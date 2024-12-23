//
// FossilARView.swift
// WildlifeSafari
//
// SwiftUI view component providing augmented reality-based fossil scanning and visualization
// with enhanced resource management, accessibility support, and performance optimization.
//

import SwiftUI
import ARKit
import RealityKit

// MARK: - Constants

private let kMinScanDistance: Float = 0.3
private let kMaxScanDistance: Float = 2.0
private let kScanningInstructionsText = "Position camera 30-200cm from fossil"
private let kMaxFrameRate: Int = 60
private let kThermalThrottleFrameRate: Int = 30

// MARK: - FossilARView

public struct FossilARView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: FossilViewModel
    @State private var arView: ARView?
    @State private var isGuideVisible: Bool = true
    @State private var focusPoint: CGPoint = .zero
    @State private var currentThermalState: ProcessInfo.ThermalState = .nominal
    @State private var memoryWarningLevel: Float = 0.0
    
    // MARK: - Initialization
    
    public init(viewModel: FossilViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack {
            // AR View Container
            ARViewContainer(arView: $arView)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    setupARSession()
                }
            
            // Scanning Overlay
            if viewModel.isScanning {
                ScanningOverlay(
                    progress: viewModel.scanProgress,
                    distance: calculateScanningDistance(),
                    isGuideVisible: $isGuideVisible
                )
                .accessibilityLabel("Fossil scanning in progress")
                .accessibilityValue("\(Int(viewModel.scanProgress * 100))% complete")
            }
            
            // Control Buttons
            VStack {
                Spacer()
                
                HStack {
                    // Cancel Button
                    Button(action: handleCancelTapped) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 44, height: 44)
                    }
                    .accessibleTouchTarget()
                    .accessibilityLabel("Cancel scanning")
                    
                    Spacer()
                    
                    // Scan Button
                    Button(action: handleScanButtonTapped) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isScanning ? .red : .green)
                                .frame(width: 72, height: 72)
                            
                            if viewModel.isScanning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                            }
                        }
                    }
                    .disabled(currentThermalState == .critical)
                    .accessibleTouchTarget()
                    .accessibilityLabel(viewModel.isScanning ? "Stop scanning" : "Start scanning")
                    
                    Spacer()
                    
                    // Guide Toggle Button
                    Button(action: { isGuideVisible.toggle() }) {
                        Image(systemName: isGuideVisible ? "eye.fill" : "eye.slash.fill")
                            .resizable()
                            .frame(width: 44, height: 44)
                    }
                    .accessibleTouchTarget()
                    .accessibilityLabel(isGuideVisible ? "Hide scanning guide" : "Show scanning guide")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            
            // Resource Warning Overlays
            if currentThermalState == .serious {
                WarningOverlay(
                    message: "Device temperature high",
                    icon: "thermometer.high"
                )
            }
            
            if memoryWarningLevel > 0.8 {
                WarningOverlay(
                    message: "Memory pressure high",
                    icon: "exclamationmark.triangle"
                )
            }
            
            // Loading View
            if viewModel.currentFossil != nil {
                LoadingView(message: "Processing fossil scan...")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            handleThermalStateChange(ProcessInfo.processInfo.thermalState)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupARSession() {
        guard arView == nil else { return }
        
        let session = ARSession()
        let configuration = ARWorldTrackingConfiguration()
        
        // Configure tracking
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        // Set frame rate based on thermal state
        configuration.frameSemantics = currentThermalState == .serious ? 
            [.smoothedSceneDepth] : [.sceneDepth, .smoothedSceneDepth]
        
        // Initialize AR view
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.session.delegate = self
        view.session.run(configuration)
        
        // Set up debug options for development
        #if DEBUG
        view.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        #endif
        
        self.arView = view
    }
    
    private func handleScanButtonTapped() {
        guard currentThermalState != .critical else { return }
        
        if viewModel.isScanning {
            viewModel.stopScanning()
            provideFeedback(.success)
        } else {
            viewModel.startScanning()
            provideFeedback(.selection)
        }
    }
    
    private func handleCancelTapped() {
        viewModel.stopScanning()
        provideFeedback(.warning)
    }
    
    private func handleThermalStateChange(_ newState: ProcessInfo.ThermalState) {
        currentThermalState = newState
        
        if newState == .critical {
            viewModel.stopScanning()
            provideFeedback(.error)
        }
        
        // Adjust frame rate based on thermal state
        if let configuration = arView?.session.configuration as? ARWorldTrackingConfiguration {
            configuration.frameSemantics = newState == .serious ?
                [.smoothedSceneDepth] : [.sceneDepth, .smoothedSceneDepth]
            arView?.session.run(configuration)
        }
    }
    
    private func calculateScanningDistance() -> Float {
        // Implementation would calculate actual distance to scanning target
        return 0.5 // Placeholder
    }
    
    private func provideFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - ARSessionDelegate

extension FossilARView: ARSessionDelegate {
    public func session(_ session: ARSession, didFailWithError error: Error) {
        // Handle session errors
        print("AR session failed: \(error.localizedDescription)")
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        // Handle session interruption
        viewModel.stopScanning()
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        // Handle interruption end
        setupARSession()
    }
}

// MARK: - Supporting Views

private struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView?
    
    func makeUIView(context: Context) -> UIView {
        return arView ?? UIView()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
    }
}

private struct ScanningOverlay: View {
    let progress: Double
    let distance: Float
    @Binding var isGuideVisible: Bool
    
    var body: some View {
        VStack {
            if isGuideVisible {
                Text(kScanningInstructionsText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
            
            Spacer()
            
            // Progress indicator
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(8)
        }
        .padding()
    }
}

private struct WarningOverlay: View {
    let message: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(message)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding(.top)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct FossilARView_Previews: PreviewProvider {
    static var previews: some View {
        FossilARView(viewModel: FossilViewModel(
            detectionService: DetectionService(),
            fossilDetector: FossilDetector(configuration: MLModelConfiguration()),
            thermalStateMonitor: ThermalStateMonitor(),
            memoryPressureHandler: MemoryPressureHandler(),
            performanceMonitor: PerformanceMonitor()
        ))
    }
}
#endif