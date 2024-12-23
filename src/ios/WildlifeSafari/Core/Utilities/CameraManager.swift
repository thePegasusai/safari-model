//
// CameraManager.swift
// WildlifeSafari
//
// Advanced camera management system for wildlife detection and fossil scanning
// with performance optimization and thermal management capabilities.
//

import AVFoundation // Latest - Camera capture and configuration
import UIKit // Latest - UI integration and image handling
import CoreImage // Latest - Image processing capabilities
import os.signpost // Latest - Performance monitoring

// MARK: - Global Constants

private enum Constants {
    static let kDefaultResolution = AVCaptureSession.Preset.hd1920x1080
    static let kProcessingQueueLabel = "com.wildlifesafari.camera.processing"
    static let kFrameRate: Int32 = 30
    static let kThermalThrottleThreshold: Float = 0.8
    static let kMaxFrameDropRate: Float = 0.2
    static let kTargetImageSize = CGSize(width: 640, height: 640)
}

// MARK: - Detection Mode Enum

public enum DetectionMode {
    case wildlife
    case fossil
}

// MARK: - Error Types

public enum CameraError: Error {
    case setupFailed
    case notAuthorized
    case configurationFailed
    case captureError
    case thermalThrottling
    
    var localizedDescription: String {
        switch self {
        case .setupFailed:
            return "Failed to setup camera capture session"
        case .notAuthorized:
            return "Camera access not authorized"
        case .configurationFailed:
            return "Failed to configure camera settings"
        case .captureError:
            return "Error during frame capture"
        case .thermalThrottling:
            return "Camera throttled due to thermal state"
        }
    }
}

// MARK: - Camera Manager Class

@available(iOS 14.0, *)
public final class CameraManager {
    
    // MARK: - Private Properties
    
    private let captureSession = AVCaptureSession()
    private var captureDevice: AVCaptureDevice?
    private let imageProcessor: ImageProcessor
    private let lnnExecutor: LNNExecutor
    private let processingQueue: DispatchQueue
    private var isRunning = false
    private var currentMode: DetectionMode
    private var thermalState: ProcessInfo.ThermalState = .nominal
    private let signposter = OSSignposter()
    
    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameDropCounter = 0
    private var totalFrameCounter = 0
    private var lastFrameTimestamp: TimeInterval = 0
    
    // MARK: - Public Properties
    
    public var isCapturing: Bool {
        captureSession.isRunning
    }
    
    public var currentThermalState: ProcessInfo.ThermalState {
        thermalState
    }
    
    // MARK: - Initialization
    
    public init(processor: ImageProcessor, executor: LNNExecutor, initialMode: DetectionMode) {
        self.imageProcessor = processor
        self.lnnExecutor = executor
        self.currentMode = initialMode
        self.processingQueue = DispatchQueue(
            label: Constants.kProcessingQueueLabel,
            qos: .userInteractive,
            attributes: [],
            autoreleaseFrequency: .workItem
        )
        
        setupThermalStateMonitoring()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Sets up and configures the camera capture session
    public func setupCamera() async throws {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("Camera Setup", id: signpostID)
        
        defer {
            signposter.endInterval("Camera Setup", state)
        }
        
        // Check authorization status
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            throw CameraError.notAuthorized
        }
        
        do {
            // Configure capture session
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }
            
            // Set quality level
            captureSession.sessionPreset = Constants.kDefaultResolution
            
            // Setup capture device
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back) else {
                throw CameraError.setupFailed
            }
            
            captureDevice = device
            
            // Configure device settings
            try configureDeviceSettings(device)
            
            // Setup input
            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else {
                throw CameraError.setupFailed
            }
            captureSession.addInput(input)
            
            // Setup output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            guard captureSession.canAddOutput(videoOutput) else {
                throw CameraError.setupFailed
            }
            captureSession.addOutput(videoOutput)
            self.videoOutput = videoOutput
            
            // Configure connection
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isEnabled = true
            }
            
        } catch {
            throw CameraError.setupFailed
        }
    }
    
    /// Starts the camera capture session
    public func startCapture() {
        guard !isRunning else { return }
        
        captureSession.startRunning()
        isRunning = true
    }
    
    /// Stops the camera capture session
    public func stopCapture() {
        guard isRunning else { return }
        
        captureSession.stopRunning()
        isRunning = false
    }
    
    /// Switches between wildlife and fossil detection modes
    public func switchDetectionMode(_ newMode: DetectionMode) async throws {
        guard currentMode != newMode else { return }
        
        do {
            // Reconfigure camera settings for new mode
            captureSession.beginConfiguration()
            
            // Update device settings based on mode
            if let device = captureDevice {
                try configureDeviceSettings(device, for: newMode)
            }
            
            // Update LNN executor configuration
            try await lnnExecutor.configureForMode(newMode)
            
            currentMode = newMode
            captureSession.commitConfiguration()
            
        } catch {
            throw CameraError.configurationFailed
        }
    }
    
    // MARK: - Private Methods
    
    private func configureDeviceSettings(_ device: AVCaptureDevice, for mode: DetectionMode? = nil) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Configure frame rate
        let targetFrameRate = mode == .fossil ? Constants.kFrameRate / 2 : Constants.kFrameRate
        let frameDuration = CMTime(value: 1, timescale: targetFrameRate)
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        
        // Configure focus and exposure
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        
        // Configure stabilization if available
        if device.isVideoStabilizationSupported(.cinematic) {
            device.activeVideoStabilizationMode = .cinematic
        }
    }
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    private func setupPerformanceMonitoring() {
        // Reset performance counters periodically
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    @objc private func handleThermalStateChange(_ notification: Notification) {
        let newState = ProcessInfo.processInfo.thermalState
        thermalState = newState
        
        switch newState {
        case .nominal, .fair:
            adjustForNormalOperation()
        case .serious:
            adjustForThermalThrottling()
        case .critical:
            handleCriticalThermalState()
        @unknown default:
            adjustForNormalOperation()
        }
    }
    
    private func adjustForNormalOperation() {
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        if let device = captureDevice {
            try? configureDeviceSettings(device)
        }
    }
    
    private func adjustForThermalThrottling() {
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        frameDropCounter = 0
        
        if let device = captureDevice {
            try? device.lockForConfiguration()
            let reducedFrameRate = Constants.kFrameRate / 2
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: reducedFrameRate)
            device.unlockForConfiguration()
        }
    }
    
    private func handleCriticalThermalState() {
        stopCapture()
        NotificationCenter.default.post(
            name: NSNotification.Name("CameraThermalShutdown"),
            object: nil
        )
    }
    
    private func updatePerformanceMetrics() {
        let frameDropRate = Float(frameDropCounter) / Float(max(1, totalFrameCounter))
        frameDropCounter = 0
        totalFrameCounter = 0
        
        if frameDropRate > Constants.kMaxFrameDropRate {
            adjustForThermalThrottling()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                            didOutput sampleBuffer: CMSampleBuffer,
                            from connection: AVCaptureConnection) {
        totalFrameCounter += 1
        
        // Check thermal state
        guard thermalState != .critical else {
            frameDropCounter += 1
            return
        }
        
        // Check frame timing
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp - lastFrameTimestamp >= (1.0 / Double(Constants.kFrameRate)) else {
            frameDropCounter += 1
            return
        }
        lastFrameTimestamp = timestamp
        
        // Process frame
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("Frame Processing", id: signpostID)
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Convert sample buffer to image
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    self.frameDropCounter += 1
                    return
                }
                
                // Process image for ML
                let processedImage = try self.imageProcessor.processImageForML(imageBuffer)
                
                // Execute ML inference
                _ = try await self.lnnExecutor.processImage(processedImage)
                
                self.signposter.endInterval("Frame Processing", state)
                
            } catch {
                self.frameDropCounter += 1
                print("Frame processing error: \(error)")
            }
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput,
                            didDrop sampleBuffer: CMSampleBuffer,
                            from connection: AVCaptureConnection) {
        frameDropCounter += 1
    }
}