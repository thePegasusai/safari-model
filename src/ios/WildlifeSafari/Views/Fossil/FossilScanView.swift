//
// FossilScanView.swift
// WildlifeSafari
//
// SwiftUI view component implementing the fossil scanning interface with
// real-time feedback, AR visualization, thermal management, and progressive scanning.
//

import SwiftUI
import ARKit

// MARK: - Constants

private let kScanningInstructionsText = "Position the fossil within the frame and hold steady"
private let kProcessingText = "Processing scan..."
private let kScanButtonSize: CGFloat = 60.0
private let kMinimumMemoryRequired: Float = 512.0
private let kMaxThermalState: Int = 2

// MARK: - FossilScanView

public struct FossilScanView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: FossilViewModel
    @State private var showingInstructions: Bool = true
    @State private var showingScanResult: Bool = false
    @State private var currentThermalState: ProcessInfo.ThermalState = .nominal
    @State private var memoryPressure: Double = 0.0
    
    // MARK: - Initialization
    
    public init(viewModel: FossilViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack {
            // AR Camera View
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
                .overlay(scanningOverlay())
            
            // Controls
            VStack {
                Spacer()
                controlButtons()
                    .padding(.bottom)
            }
            
            // Loading Indicator
            if viewModel.isProcessing {
                LoadingView(
                    message: kProcessingText,
                    spinnerColor: .accentColor,
                    size: 50
                )
                .transition(.opacity)
            }
            
            // Scan Result
            if showingScanResult {
                scanResultView()
            }
        }
        .onChange(of: viewModel.thermalState) { newState in
            handleThermalStateChange(newState)
        }
        .onChange(of: viewModel.memoryPressure) { newPressure in
            handleMemoryPressureChange(newPressure)
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    // MARK: - Private Views
    
    @ViewBuilder
    private func scanningOverlay() -> some View {
        VStack {
            // Scanning Frame Guide
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    viewModel.isScanning ? Color.green : Color.white,
                    style: StrokeStyle(lineWidth: 2, dash: [10])
                )
                .frame(width: 300, height: 300)
                .overlay(
                    Text(kScanningInstructionsText)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .opacity(showingInstructions ? 1 : 0)
                )
            
            // Progress Indicator
            if viewModel.isScanning {
                ProgressView(value: viewModel.scanProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .padding()
                    .accessibilityLabel("Scanning progress")
                    .accessibilityValue("\(Int(viewModel.scanProgress * 100))%")
            }
        }
        .animation(.easeInOut, value: viewModel.isScanning)
    }
    
    @ViewBuilder
    private func controlButtons() -> some View {
        HStack(spacing: 20) {
            // Cancel Button
            Button(action: cancelScan) {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Cancel scan")
            
            // Scan Button
            Button(action: toggleScan) {
                Circle()
                    .fill(viewModel.isScanning ? .red : .white)
                    .frame(width: kScanButtonSize, height: kScanButtonSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                    )
            }
            .disabled(viewModel.thermalState == .critical)
            .accessibilityLabel(viewModel.isScanning ? "Stop scanning" : "Start scanning")
            
            // Settings Button
            Button(action: showSettings) {
                Image(systemName: "gear.circle.fill")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Scan settings")
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
    
    @ViewBuilder
    private func scanResultView() -> some View {
        if let fossil = viewModel.currentFossil {
            Fossil3DView(viewModel: viewModel)
                .transition(.move(edge: .bottom))
                .overlay(
                    VStack {
                        if viewModel.scanError != nil {
                            Text("Scan failed. Please try again.")
                                .foregroundColor(.red)
                                .padding()
                        }
                        
                        HStack {
                            Button("Rescan") {
                                resetScan()
                            }
                            Button("Save") {
                                saveScan()
                            }
                        }
                        .padding()
                    }
                )
        }
    }
    
    // MARK: - Private Methods
    
    private func setupInitialState() {
        // Configure initial state
        currentThermalState = ProcessInfo.processInfo.thermalState
        showingInstructions = true
        
        // Setup accessibility
        UIAccessibility.post(
            notification: .announcement,
            argument: "Ready to scan. Position fossil within frame."
        )
    }
    
    private func toggleScan() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if viewModel.isScanning {
            viewModel.stopScanning()
        } else {
            viewModel.startScanning()
            showingInstructions = false
        }
    }
    
    private func cancelScan() {
        viewModel.stopScanning()
        showingScanResult = false
        showingInstructions = true
    }
    
    private func resetScan() {
        showingScanResult = false
        showingInstructions = true
        viewModel.stopScanning()
    }
    
    private func saveScan() {
        // Implementation for saving scan
        showingScanResult = false
        showingInstructions = true
    }
    
    private func showSettings() {
        // Implementation for showing settings
    }
    
    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        currentThermalState = state
        
        switch state {
        case .serious:
            viewModel.adjustScanQuality(isLowQuality: true)
        case .critical:
            viewModel.stopScanning()
            UIAccessibility.post(
                notification: .announcement,
                argument: "Device temperature too high. Scanning paused."
            )
        default:
            viewModel.adjustScanQuality(isLowQuality: false)
        }
    }
    
    private func handleMemoryPressureChange(_ pressure: Double) {
        memoryPressure = pressure
        if pressure > 0.8 {
            viewModel.adjustScanQuality(isLowQuality: true)
        }
    }
}

// MARK: - ARViewContainer

private struct ARViewContainer: UIViewRepresentable {
    let viewModel: FossilViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.frameSemantics = .sceneDepth
        
        arView.session.run(configuration)
        arView.delegate = context.coordinator
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Update AR view if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        let viewModel: FossilViewModel
        
        init(viewModel: FossilViewModel) {
            self.viewModel = viewModel
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            // Handle AR session errors
        }
    }
}

#if DEBUG
struct FossilScanView_Previews: PreviewProvider {
    static var previews: some View {
        FossilScanView(viewModel: FossilViewModel(
            detectionService: try! DetectionService(),
            fossilDetector: try! FossilDetector(configuration: MLModelConfiguration()),
            thermalStateMonitor: ThermalStateMonitor(),
            memoryPressureHandler: MemoryPressureHandler(),
            performanceMonitor: PerformanceMonitor()
        ))
    }
}
#endif