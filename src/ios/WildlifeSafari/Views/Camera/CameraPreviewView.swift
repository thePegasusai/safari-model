//
// CameraPreviewView.swift
// WildlifeSafari
//
// SwiftUI view providing real-time camera preview with thermal management,
// accessibility support, and optimized frame handling for wildlife detection.
//

import SwiftUI // Latest
import AVFoundation // Latest
import Combine // Latest

// MARK: - Constants

private enum Constants {
    static let PREVIEW_ASPECT_RATIO: CGFloat = 16.0/9.0
    static let DEFAULT_ZOOM_SCALE: CGFloat = 1.0
    static let MAX_FRAME_RATE: Float64 = 60.0
    static let THERMAL_THROTTLE_FRAME_RATE: Float64 = 30.0
    static let MEMORY_WARNING_FRAME_RATE: Float64 = 15.0
}

// MARK: - Camera Preview View

@available(iOS 14.0, *)
public struct CameraPreviewView: View {
    // MARK: - Private Properties
    
    private let cameraManager: CameraManager
    private let overlayView: DetectionOverlayView
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var previewBounds: CGRect = .zero
    @State private var isCapturing: Bool = false
    @State private var currentThermalState: ProcessInfo.ThermalState = .nominal
    @State private var currentMemoryPressure: Bool = false
    @State private var zoomScale: CGFloat = Constants.DEFAULT_ZOOM_SCALE
    
    // Accessibility
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.colorScheme) private var colorScheme
    
    // Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes the camera preview view with required dependencies
    /// - Parameters:
    ///   - cameraManager: Manager for camera operations
    ///   - overlayView: View for detection overlays
    public init(cameraManager: CameraManager, overlayView: DetectionOverlayView) {
        self.cameraManager = cameraManager
        self.overlayView = overlayView
        
        setupThermalStateMonitoring()
        setupMemoryPressureMonitoring()
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera Preview Layer
                CameraPreviewRepresentable(
                    cameraManager: cameraManager,
                    previewLayer: $previewLayer,
                    bounds: geometry.frame(in: .local)
                )
                .onAppear {
                    previewBounds = geometry.frame(in: .local)
                }
                .onChange(of: geometry.size) { newSize in
                    previewBounds = geometry.frame(in: .local)
                    updatePreviewLayerFrame()
                }
                
                // Detection Overlay
                overlayView
                    .allowsHitTesting(false)
                
                // Camera Controls
                CameraControlsView(
                    isCapturing: $isCapturing,
                    zoomScale: $zoomScale,
                    onCaptureToggle: toggleCapture,
                    onZoomChange: handleZoomChange
                )
                .accessibilityElement(children: .contain)
            }
        }
        .aspectRatio(Constants.PREVIEW_ASPECT_RATIO, contentMode: .fit)
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            stopPreview()
        }
    }
    
    // MARK: - Public Methods
    
    /// Starts the camera preview with current settings
    public func startPreview() {
        guard !isCapturing else { return }
        
        Task {
            do {
                try await cameraManager.setupCamera()
                configureFrameRate(for: currentThermalState)
                cameraManager.startCapture()
                isCapturing = true
            } catch {
                handleCameraError(error)
            }
        }
    }
    
    /// Stops the camera preview
    public func stopPreview() {
        guard isCapturing else { return }
        
        cameraManager.stopCapture()
        isCapturing = false
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        Task {
            await checkCameraAuthorization()
            startPreview()
        }
    }
    
    private func checkCameraAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
    }
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleThermalStateChange()
            }
            .store(in: &cancellables)
    }
    
    private func setupMemoryPressureMonitoring() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryPressure()
            }
            .store(in: &cancellables)
    }
    
    private func handleThermalStateChange() {
        let newState = ProcessInfo.processInfo.thermalState
        currentThermalState = newState
        configureFrameRate(for: newState)
    }
    
    private func handleMemoryPressure() {
        currentMemoryPressure = true
        configureFrameRate(for: currentThermalState, memoryPressure: true)
    }
    
    private func configureFrameRate(for thermalState: ProcessInfo.ThermalState, memoryPressure: Bool = false) {
        var targetFrameRate: Float64
        
        if memoryPressure {
            targetFrameRate = Constants.MEMORY_WARNING_FRAME_RATE
        } else {
            switch thermalState {
            case .nominal, .fair:
                targetFrameRate = Constants.MAX_FRAME_RATE
            case .serious:
                targetFrameRate = Constants.THERMAL_THROTTLE_FRAME_RATE
            case .critical:
                targetFrameRate = Constants.MEMORY_WARNING_FRAME_RATE
            @unknown default:
                targetFrameRate = Constants.THERMAL_THROTTLE_FRAME_RATE
            }
        }
        
        updatePreviewLayerFrameRate(targetFrameRate)
    }
    
    private func updatePreviewLayerFrameRate(_ frameRate: Float64) {
        guard let previewLayer = previewLayer,
              let connection = previewLayer.connection else { return }
        
        connection.videoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        connection.videoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
    
    private func updatePreviewLayerFrame() {
        guard let previewLayer = previewLayer else { return }
        previewLayer.frame = previewBounds
        previewLayer.videoGravity = .resizeAspectFill
    }
    
    private func toggleCapture() {
        if isCapturing {
            stopPreview()
        } else {
            startPreview()
        }
    }
    
    private func handleZoomChange(_ scale: CGFloat) {
        zoomScale = min(max(scale, 1.0), 5.0)
        // Update camera zoom if supported
    }
    
    private func handleCameraError(_ error: Error) {
        print("Camera error: \(error.localizedDescription)")
        // Implement error handling UI
    }
}

// MARK: - Camera Preview Representable

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let cameraManager: CameraManager
    @Binding var previewLayer: AVCaptureVideoPreviewLayer?
    let bounds: CGRect
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: bounds)
        view.backgroundColor = .black
        
        let layer = AVCaptureVideoPreviewLayer()
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.connection?.videoOrientation = .portrait
        
        view.layer.addSublayer(layer)
        previewLayer = layer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        previewLayer?.frame = bounds
    }
}

// MARK: - Camera Controls View

private struct CameraControlsView: View {
    @Binding var isCapturing: Bool
    @Binding var zoomScale: CGFloat
    let onCaptureToggle: () -> Void
    let onZoomChange: (CGFloat) -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Button(action: onCaptureToggle) {
                    Image(systemName: isCapturing ? "stop.circle.fill" : "camera.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .accessibilityLabel(isCapturing ? "Stop Camera" : "Start Camera")
                
                Slider(value: $zoomScale, in: 1.0...5.0) { isEditing in
                    if !isEditing {
                        onZoomChange(zoomScale)
                    }
                }
                .accessibilityLabel("Camera Zoom")
            }
            .padding()
        }
    }
}