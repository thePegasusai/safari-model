//
// Fossil3DView.swift
// WildlifeSafari
//
// SwiftUI view component providing interactive 3D visualization of fossil specimens
// with advanced features including thermal management, memory optimization, and
// accessibility support.
//

import SwiftUI      // Latest - UI framework components and accessibility support
import SceneKit     // Latest - 3D rendering capabilities

// MARK: - Constants

private let kDefaultCameraDistance: Float = 2.0
private let kMinZoomScale: Float = 0.5
private let kMaxZoomScale: Float = 3.0
private let kRotationSensitivity: Float = 0.5
private let kDefaultLightIntensity: CGFloat = 1000.0
private let kAmbientLightIntensity: CGFloat = 300.0

@available(iOS 14.0, *)
public struct Fossil3DView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: FossilViewModel
    @State private var modelNode: SCNNode?
    @State private var currentScale: Float = 1.0
    @State private var currentRotation: CGPoint = .zero
    @State private var isLowMemoryMode: Bool = false
    @State private var loadingProgress: Double = 0.0
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - Initialization
    
    public init(viewModel: FossilViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        feedbackGenerator.prepare()
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack {
            // 3D SceneKit View
            SceneView(
                scene: setupScene(),
                pointOfView: setupCamera(),
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleRotation(value)
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        handleZoom(scale)
                    }
            )
            
            // Loading Overlay
            if viewModel.isProcessing {
                LoadingView(
                    message: "Loading 3D Model...",
                    spinnerColor: .accentColor,
                    size: 50
                )
            }
            
            // Thermal Warning Overlay
            if viewModel.thermalState == .serious {
                VStack {
                    Spacer()
                    Text("Device temperature high. Performance may be reduced.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .padding()
            }
            
            // Measurements Overlay
            if let fossil = viewModel.currentFossil {
                MeasurementsOverlay(measurements: fossil.measurements)
                    .padding()
            }
        }
        .onAppear {
            loadModel()
        }
        .onChange(of: viewModel.thermalState) { newState in
            handleThermalStateChange(newState)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("3D Fossil Viewer")
        .accessibilityAddTraits([.allowsDirectInteraction])
        .accessibilityHint("Use two fingers to zoom and rotate the fossil model")
    }
    
    // MARK: - Private Methods
    
    private func setupScene() -> SCNScene {
        let scene = SCNScene()
        
        // Configure lighting
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = kAmbientLightIntensity
        scene.rootNode.addChildNode(ambientLight)
        
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = kDefaultLightIntensity
        directionalLight.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(directionalLight)
        
        // Configure scene settings
        scene.background.contents = UIColor.systemBackground
        
        return scene
    }
    
    private func setupCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 60
        
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: Float(kDefaultCameraDistance))
        
        return cameraNode
    }
    
    private func loadModel() {
        guard let fossil = viewModel.currentFossil else { return }
        
        Task {
            do {
                let result = try await fossil.load3DModel(lowMemoryMode: isLowMemoryMode)
                switch result {
                case .success(let node):
                    await MainActor.run {
                        self.modelNode = node
                        self.loadingProgress = 1.0
                    }
                case .failure(let error):
                    print("Failed to load 3D model: \(error)")
                }
            } catch {
                print("Error loading 3D model: \(error)")
            }
        }
    }
    
    private func handleRotation(_ value: DragGesture.Value) {
        guard viewModel.thermalState != .critical else { return }
        
        let rotationX = Float(value.translation.width) * kRotationSensitivity
        let rotationY = Float(value.translation.height) * kRotationSensitivity
        
        modelNode?.eulerAngles.y += rotationX
        modelNode?.eulerAngles.x += rotationY
        
        feedbackGenerator.impactOccurred()
        
        // Update accessibility value
        let degrees = Int(abs(rotationX + rotationY))
        UIAccessibility.post(notification: .announcement, argument: "Rotated \(degrees) degrees")
    }
    
    private func handleZoom(_ scale: CGFloat) {
        let newScale = Float(scale)
        guard newScale >= kMinZoomScale && newScale <= kMaxZoomScale else { return }
        
        currentScale = newScale
        modelNode?.scale = SCNVector3(newScale, newScale, newScale)
        
        feedbackGenerator.impactOccurred()
        
        // Update accessibility value
        let zoomPercentage = Int(scale * 100)
        UIAccessibility.post(notification: .announcement, argument: "Zoom level \(zoomPercentage)%")
    }
    
    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .serious:
            isLowMemoryMode = true
            loadModel() // Reload with low memory mode
        case .critical:
            modelNode?.geometry?.firstMaterial?.lightingModel = .constant
        default:
            isLowMemoryMode = false
        }
    }
}

// MARK: - MeasurementsOverlay

private struct MeasurementsOverlay: View {
    let measurements: [String: Double]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(measurements.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f m", value))
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fossil Measurements")
    }
}

#if DEBUG
struct Fossil3DView_Previews: PreviewProvider {
    static var previews: some View {
        Fossil3DView(viewModel: FossilViewModel(
            detectionService: try! DetectionService(),
            fossilDetector: try! FossilDetector(configuration: MLModelConfiguration()),
            thermalStateMonitor: ThermalStateMonitor(),
            memoryPressureHandler: MemoryPressureHandler(),
            performanceMonitor: PerformanceMonitor()
        ))
    }
}
#endif