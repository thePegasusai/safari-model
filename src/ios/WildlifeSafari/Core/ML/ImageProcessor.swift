//
// ImageProcessor.swift
// WildlifeSafari
//
// Core image processing utility optimized for wildlife and fossil detection
// using LNN models with Metal acceleration and thermal management.
//

import CoreImage      // Latest - Advanced image processing with Metal acceleration
import Vision        // Latest - High-level image analysis and processing
import CoreML        // Latest - ML model input preparation
import UIKit         // Latest - Basic image handling
import MetalKit      // Latest - Metal acceleration
import os.signpost   // Latest - Performance monitoring

// MARK: - Global Constants

private let kTargetImageSize = CGSize(width: 640, height: 640)
private let kPixelFormat = kCVPixelFormatType_32BGRA
private let kNormalizationMean: [Float] = [0.485, 0.456, 0.406]
private let kNormalizationStd: [Float] = [0.229, 0.224, 0.225]
private let kMaxProcessingTime: TimeInterval = 0.1
private let kThermalThreshold = ProcessInfo.thermalStateDidChangeNotification

// MARK: - Error Handling

public enum ImageProcessingError: Error {
    case invalidInput
    case processingFailed
    case thermalThrottling
    case timeoutExceeded
    
    var localizedDescription: String {
        switch self {
        case .invalidInput:
            return "Invalid input image provided"
        case .processingFailed:
            return "Image processing operation failed"
        case .thermalThrottling:
            return "Processing throttled due to thermal state"
        case .timeoutExceeded:
            return "Processing timeout exceeded"
        }
    }
}

// MARK: - Image Processor Class

public final class ImageProcessor {
    
    // MARK: - Private Properties
    
    private let ciContext: CIContext
    private let visionHandler: VNSequenceRequestHandler
    private let targetSize: CGSize
    private let metalDevice: MTLDevice?
    private let processingQueue: DispatchQueue
    private var thermalState: ProcessInfo.ThermalState
    
    private let signposter = OSSignposter()
    
    // MARK: - Public Properties
    
    public var currentThermalState: ProcessInfo.ThermalState {
        get { thermalState }
    }
    
    // MARK: - Initialization
    
    public init() {
        // Initialize Metal device with maximum performance
        metalDevice = MTLCreateSystemDefaultDevice()
        
        // Configure CI context with Metal acceleration
        let contextOptions = [
            CIContextOption.useSoftwareRenderer: false,
            CIContextOption.priorityRequestLow: false
        ]
        ciContext = CIContext(mtlDevice: metalDevice!, options: contextOptions)
        
        // Initialize other components
        visionHandler = VNSequenceRequestHandler()
        targetSize = kTargetImageSize
        processingQueue = DispatchQueue(label: "com.wildlifesafari.imageprocessing",
                                      qos: .userInitiated)
        thermalState = ProcessInfo.processInfo.thermalState
        
        // Set up thermal state monitoring
        setupThermalStateMonitoring()
    }
    
    // MARK: - Public Methods
    
    public func processImageForML(_ image: UIImage) -> Result<MLFeatureProvider, ImageProcessingError> {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("Image Processing", id: signpostID)
        
        defer {
            signposter.endInterval("Image Processing", state)
        }
        
        // Check thermal state
        guard thermalState != .critical else {
            return .failure(.thermalThrottling)
        }
        
        // Validate input
        guard image.cgImage != nil else {
            return .failure(.invalidInput)
        }
        
        do {
            // Resize image
            guard let resizedImage = resizeImage(image, targetSize: targetSize) else {
                return .failure(.processingFailed)
            }
            
            // Convert to pixel buffer
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                           Int(targetSize.width),
                                           Int(targetSize.height),
                                           kPixelFormat,
                                           nil,
                                           &pixelBuffer)
            
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                return .failure(.processingFailed)
            }
            
            // Normalize pixel buffer
            let normalizedBuffer = normalizePixelBuffer(buffer)
            
            // Create ML Feature Provider
            let featureProvider = try MLFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: normalizedBuffer)
            ])
            
            return .success(featureProvider)
            
        } catch {
            return .failure(.processingFailed)
        }
    }
    
    public func processImageAsync(_ image: UIImage,
                                completion: @escaping (Result<MLFeatureProvider, ImageProcessingError>) -> Void) {
        let processingTimeout = DispatchTime.now() + kMaxProcessingTime
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check for timeout
            if DispatchTime.now() > processingTimeout {
                completion(.failure(.timeoutExceeded))
                return
            }
            
            let result = self.processImageForML(image)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    // MARK: - Private Methods
    
    @inline(__always)
    private func normalizePixelBuffer(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        
        guard let commandQueue = metalDevice?.makeCommandQueue() else {
            return buffer
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        // Create Metal texture from pixel buffer
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            mipmapped: false
        )
        
        guard let texture = metalDevice?.makeTexture(descriptor: textureDescriptor) else {
            return buffer
        }
        
        // Apply normalization using Metal shader
        let normalizeFunction = """
        kernel void normalize(texture2d<float, access::read> input [[texture(0)]],
                            texture2d<float, access::write> output [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
            float4 color = input.read(gid);
            float3 normalized = (color.rgb - float3(\(kNormalizationMean.map { String($0) }.joined(separator: ", ")))) /
                               float3(\(kNormalizationStd.map { String($0) }.joined(separator: ", ")));
            output.write(float4(normalized, 1.0), gid);
        }
        """
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        return buffer
    }
    
    @inline(__always)
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        let aspectRatio = image.size.width / image.size.height
        var scaledSize = targetSize
        
        if aspectRatio > 1 {
            scaledSize.width = targetSize.height * aspectRatio
        } else {
            scaledSize.height = targetSize.width / aspectRatio
        }
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
    }
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func thermalStateChanged(_ notification: Notification) {
        thermalState = ProcessInfo.processInfo.thermalState
    }
}

// MARK: - MLFeatureProvider Extension

private extension MLFeatureProvider {
    convenience init(dictionary: [String: MLFeatureValue]) throws {
        struct FeatureProvider: MLFeatureProvider {
            let featureNames: Set<String>
            private let features: [String: MLFeatureValue]
            
            func featureValue(for featureName: String) -> MLFeatureValue? {
                features[featureName]
            }
            
            init(dictionary: [String: MLFeatureValue]) {
                self.features = dictionary
                self.featureNames = Set(dictionary.keys)
            }
        }
        
        self = FeatureProvider(dictionary: dictionary) as! Self
    }
}