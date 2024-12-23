//
// CameraView.swift
// WildlifeSafari
//
// Main camera interface view providing real-time wildlife detection and fossil scanning
// with advanced thermal management and performance optimization.
//

import SwiftUI // Latest - UI framework for view implementation
import Combine // Latest - Reactive updates handling

// MARK: - Constants

private enum Constants {
    static let ANIMATION_DURATION: Double = 0.3
    static let FRAME_PROCESSING_THRESHOLD: Int = 100
    static let BATCH_SIZE: Int = 5
    static let THERMAL_CHECK_INTERVAL: TimeInterval = 1.0
    static let MEMORY_WARNING_THRESHOLD: Float = 0.8
}

// MARK: - Camera View

/// Main view component for camera interface and species detection
@available(iOS 14.0, *)
public struct CameraView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: CameraViewModel
    
    @State private var isShowingGallery: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var currentThermalState: ProcessInfo.ThermalState = .nominal
    @State private var detectionMode: DetectionMode = .wildlife
    @State private var flashMode: FlashMode = .auto
    @State private var isCapturing: Bool = false
    
    // Performance monitoring
    @State private var metrics = PerformanceMetrics(
        frameRate: 0,
        processingTime: 0,
        thermalState: .nominal,
        memoryUsage: 0,
        frameDropRate: 0
    )
    
    // Environment values for accessibility
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // MARK: - Initialization
    
    public init() {
        let viewModel = CameraViewModel(
            cameraManager: CameraManager(),
            speciesClassifier: SpeciesClassifier()
        )
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(
                cameraManager: viewModel.cameraManager,
                overlayView: DetectionOverlayView(
                    detections: viewModel.currentPrediction.map { [$0] } ?? [],
                    previewSize: UIScreen.main.bounds.size,
                    isProcessing: viewModel.isProcessing
                )
            )
            .edgesIgnoringSafeArea(.all)
            
            // Camera Controls
            CameraControlsView(
                detectionMode: $detectionMode,
                flashMode: $flashMode,
                isCapturing: $isCapturing
            )
            .onChange(of: detectionMode) { newMode in
                Task {
                    await viewModel.switchDetectionMode(newMode)
                }
            }
            
            // Error Alert
            if let error = viewModel.error {
                ErrorAlertView(error: error) {
                    viewModel.error = nil
                }
            }
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            cleanupCamera()
        }
        .onChange(of: currentThermalState) { newState in
            handleThermalStateChange(newState)
        }
        .sheet(isPresented: $isShowingGallery) {
            // Gallery view implementation
        }
        .sheet(isPresented: $isShowingSettings) {
            // Settings view implementation
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wildlife Detection Camera")
        .accessibilityHint("Point camera at wildlife or fossils for detection")
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        Task {
            do {
                try await viewModel.setupCamera()
                await viewModel.startDetection()
                setupThermalMonitoring()
                setupPerformanceMonitoring()
            } catch {
                handleCameraError(error)
            }
        }
    }
    
    private func cleanupCamera() {
        viewModel.stopDetection()
        NotificationCenter.default.removeObserver(
            self,
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    private func setupThermalMonitoring() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.currentThermalState = ProcessInfo.processInfo.thermalState
        }
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: Constants.THERMAL_CHECK_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updatePerformanceMetrics()
            }
    }
    
    private func handleThermalStateChange(_ newState: ProcessInfo.ThermalState) {
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
        viewModel.setFrameProcessingThreshold(Constants.FRAME_PROCESSING_THRESHOLD)
        viewModel.setBatchSize(Constants.BATCH_SIZE)
    }
    
    private func adjustForThermalThrottling() {
        viewModel.setFrameProcessingThreshold(Constants.FRAME_PROCESSING_THRESHOLD * 2)
        viewModel.setBatchSize(Constants.BATCH_SIZE / 2)
    }
    
    private func handleCriticalThermalState() {
        viewModel.stopDetection()
        showThermalWarning()
    }
    
    private func updatePerformanceMetrics() {
        metrics = PerformanceMetrics(
            frameRate: viewModel.currentFrameRate,
            processingTime: viewModel.averageProcessingTime,
            thermalState: currentThermalState,
            memoryUsage: viewModel.memoryUsage,
            frameDropRate: viewModel.frameDropRate
        )
    }
    
    private func handleCameraError(_ error: Error) {
        viewModel.error = error as? CameraError ?? .processingError
    }
    
    private func showThermalWarning() {
        // Implementation for thermal warning UI
    }
}

// MARK: - Error Alert View

private struct ErrorAlertView: View {
    let error: CameraError
    let dismissAction: () -> Void
    
    var body: some View {
        VStack {
            Text("Error")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.body)
            Button("Dismiss") {
                dismissAction()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

// MARK: - Preview Provider

#if DEBUG
@available(iOS 14.0, *)
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}
#endif