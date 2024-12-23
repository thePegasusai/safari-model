//
// Image+Extensions.swift
// WildlifeSafari
//
// High-performance image processing extensions optimized for wildlife detection
// and ML model input preparation with sub-100ms processing requirement.
//

import UIKit          // Latest - Base UIImage functionality
import CoreImage      // Latest - High-performance image processing
import CoreML        // Latest - ML-specific image preparation
import Vision        // Latest - Image analysis utilities

// MARK: - Constants

private enum Constants {
    static let defaultImageSize = CGSize(width: 640, height: 640)
    static let pixelNormalizationScale: Float = 1.0 / 255.0
    static let maxImageDimension: CGFloat = 4096
    static let defaultImageQuality: CGFloat = 0.8
    static let minImageDimension: CGFloat = 224
    
    static let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .highQualityDownsample: true,
        .useSoftwareRenderer: false
    ])
}

// MARK: - Detection Enhancement Options

public struct DetectionEnhancementOptions {
    let noiseReductionLevel: Float
    let contrastAdjustment: Float
    let sharpnessLevel: Float
    
    public static let `default` = DetectionEnhancementOptions(
        noiseReductionLevel: 0.5,
        contrastAdjustment: 1.1,
        sharpnessLevel: 0.7
    )
}

// MARK: - UIImage Extension

public extension UIImage {
    
    /// Normalizes image pixel values for ML model input with optimized performance
    /// - Parameter useGPU: Whether to use GPU acceleration for processing
    /// - Returns: Normalized pixel buffer optimized for ML processing
    @inlinable
    func normalizeForML(useGPU: Bool = true) -> CVPixelBuffer? {
        guard let cgImage = self.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Validate dimensions
        guard width > 0 && height > 0 &&
              width <= Int(Constants.maxImageDimension) &&
              height <= Int(Constants.maxImageDimension) else {
            return nil
        }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .init(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0)) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Apply normalization using vImage for optimal performance
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let buffer = UnsafeMutableBufferPointer<UInt8>(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: height * bytesPerRow
            )
            
            // Vectorized normalization
            DispatchQueue.concurrentPerform(iterations: height) { row in
                var pixel = buffer.baseAddress! + row * bytesPerRow
                for _ in 0..<width {
                    pixel[0] = UInt8(Float(pixel[0]) * Constants.pixelNormalizationScale)
                    pixel[1] = UInt8(Float(pixel[1]) * Constants.pixelNormalizationScale)
                    pixel[2] = UInt8(Float(pixel[2]) * Constants.pixelNormalizationScale)
                    pixel += 4
                }
            }
        }
        
        return pixelBuffer
    }
    
    /// Resizes image to target size while maintaining aspect ratio using Core Image
    /// - Parameters:
    ///   - targetSize: Desired output size
    ///   - maintainAspectRatio: Whether to preserve aspect ratio
    /// - Returns: Resized image optimized for ML processing
    @inlinable
    func resize(to targetSize: CGSize = Constants.defaultImageSize,
                maintainAspectRatio: Bool = true) -> UIImage {
        guard size != targetSize else { return self }
        
        let targetWidth = min(targetSize.width, Constants.maxImageDimension)
        let targetHeight = min(targetSize.height, Constants.maxImageDimension)
        
        var newSize = CGSize(width: targetWidth, height: targetHeight)
        
        if maintainAspectRatio {
            let widthRatio = targetWidth / size.width
            let heightRatio = targetHeight / size.height
            let ratio = min(widthRatio, heightRatio)
            
            newSize = CGSize(
                width: size.width * ratio,
                height: size.height * ratio
            )
        }
        
        guard let ciImage = CIImage(image: self) else { return self }
        
        let scaleTransform = CGAffineTransform(
            scaleX: newSize.width / size.width,
            y: newSize.height / size.height
        )
        
        let scaledImage = ciImage.transformed(by: scaleTransform)
        
        guard let cgImage = Constants.ciContext.createCGImage(
            scaledImage,
            from: scaledImage.extent,
            format: .BGRA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            return self
        }
        
        return UIImage(
            cgImage: cgImage,
            scale: scale,
            orientation: imageOrientation
        )
    }
    
    /// Enhances image quality for better species detection
    /// - Parameter options: Enhancement configuration options
    /// - Returns: Enhanced image optimized for detection
    @inlinable
    func enhanceForDetection(options: DetectionEnhancementOptions = .default) -> UIImage {
        guard let ciImage = CIImage(image: self) else { return self }
        
        // Create filter chain
        let filters: [(CIFilter?, [String: Any])] = [
            (CIFilter(name: "CINoiseReduction"), [
                kCIInputImageKey: ciImage,
                "inputNoiseLevel": options.noiseReductionLevel,
                "inputSharpness": options.sharpnessLevel
            ]),
            (CIFilter(name: "CIColorControls"), [
                "inputContrast": options.contrastAdjustment
            ])
        ]
        
        // Apply filters
        var processedImage = ciImage
        for (filter, parameters) in filters {
            guard let filter = filter else { continue }
            
            filter.setDefaults()
            parameters.forEach { filter.setValue($1, forKey: $0) }
            
            if let outputImage = filter.outputImage {
                processedImage = outputImage
            }
        }
        
        // Create final image
        guard let cgImage = Constants.ciContext.createCGImage(
            processedImage,
            from: processedImage.extent
        ) else {
            return self
        }
        
        return UIImage(
            cgImage: cgImage,
            scale: scale,
            orientation: imageOrientation
        )
    }
    
    /// Converts UIImage to CVPixelBuffer format with optimal memory management
    /// - Returns: Memory-efficient pixel buffer
    @inlinable
    func toCVPixelBuffer() -> CVPixelBuffer? {
        guard let cgImage = cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}

// MARK: - CIImage Extension

public extension CIImage {
    
    /// Normalizes CIImage for ML processing with optimal performance
    /// - Returns: Normalized pixel buffer for ML input
    @inlinable
    func normalizeForML() -> CVPixelBuffer? {
        let extent = self.extent
        guard extent.size.width > 0 && extent.size.height > 0 else { return nil }
        
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(extent.width),
            Int(extent.height),
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        Constants.ciContext.render(
            self,
            to: pixelBuffer,
            bounds: extent,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        return pixelBuffer
    }
    
    /// Resizes CIImage using high-performance Core Image operations
    /// - Parameter targetSize: Desired output size
    /// - Returns: Resized CIImage
    @inlinable
    func resize(to targetSize: CGSize = Constants.defaultImageSize) -> CIImage {
        let scale = CGAffineTransform(
            scaleX: targetSize.width / extent.width,
            y: targetSize.height / extent.height
        )
        return transformed(by: scale)
    }
}