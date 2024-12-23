//
// FossilCard.swift
// WildlifeSafari
//
// A reusable SwiftUI card component for displaying fossil information with
// interactive 3D preview capabilities, enhanced accessibility features,
// and optimized memory management for 3D model visualization.
//

import SwiftUI // Latest
import SceneKit // Latest

/// A SwiftUI view that displays fossil information in a card format with 3D preview
public struct FossilCard: View {
    // MARK: - Properties
    
    private let fossil: Fossil
    @State private var isExpanded: Bool = false
    @State private var showingDetails: Bool = false
    @State private var sceneView: SCNView?
    @State private var isLoadingModel: Bool = false
    @State private var hasLoadError: Bool = false
    
    // Cache for 3D models to optimize memory usage
    private let modelCache = NSCache<NSString, SCNScene>()
    
    // MARK: - Initialization
    
    /// Creates a new FossilCard instance
    /// - Parameter fossil: The fossil to display
    public init(fossil: Fossil) {
        self.fossil = fossil
        
        // Configure model cache limits
        modelCache.countLimit = AppConstants.Storage.maxCacheEntries
        modelCache.totalCostLimit = AppConstants.Storage.cacheSizeLimit
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 8) {
            // Header Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fossil.commonName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Text(fossil.scientificName)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .italic()
                }
                
                Spacer()
                
                CustomButton(
                    isExpanded ? "Less" : "More",
                    style: .outline
                ) {
                    withAnimation(.spring()) {
                        toggleExpanded()
                    }
                }
                .accessibilityLabel(isExpanded ? "Show less details" : "Show more details")
            }
            .padding(.horizontal, 16)
            
            // 3D Model Preview Section
            if isExpanded {
                VStack {
                    if isLoadingModel {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                            .padding()
                            .accessibilityLabel("Loading 3D model")
                    } else if hasLoadError {
                        Text("Failed to load 3D model")
                            .foregroundColor(.error)
                            .padding()
                    } else if let sceneView = sceneView {
                        SceneView(scene: sceneView.scene)
                            .frame(height: 200)
                            .cornerRadius(8)
                            .accessibilityLabel("3D fossil model viewer")
                            .accessibilityHint("Double tap to interact with the 3D model")
                    }
                }
                .transition(.opacity)
                
                // Fossil Details Section
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("Period: \(fossil.period)")
                        Text("Estimated Age: \(String(format: "%.1f", fossil.estimatedAge)) million years")
                    }
                    .font(.body)
                    .foregroundColor(.text)
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
            }
        }
        .cardStyle(elevation: isExpanded ? 4 : 2)
        .accessibleTouchTarget()
        .onTapGesture {
            withAnimation(.spring()) {
                toggleExpanded()
            }
        }
        .onChange(of: isExpanded) { expanded in
            if expanded && sceneView == nil {
                loadModel()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Toggles the expanded state of the card
    private func toggleExpanded() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        isExpanded.toggle()
    }
    
    /// Loads and configures the 3D model with memory optimization
    private func loadModel() {
        guard !isLoadingModel else { return }
        
        isLoadingModel = true
        hasLoadError = false
        
        // Check cache first
        if let cachedScene = modelCache.object(forKey: fossil.id.uuidString as NSString) {
            setupSceneView(with: cachedScene)
            isLoadingModel = false
            return
        }
        
        Task {
            do {
                let result = await fossil.load3DModel(lowMemoryMode: true)
                
                await MainActor.run {
                    switch result {
                    case .success(let node):
                        let scene = SCNScene()
                        scene.rootNode.addChildNode(node)
                        
                        // Cache the scene
                        modelCache.setObject(scene, forKey: fossil.id.uuidString as NSString)
                        
                        setupSceneView(with: scene)
                        isLoadingModel = false
                        
                    case .failure:
                        hasLoadError = true
                        isLoadingModel = false
                    }
                }
            }
        }
    }
    
    /// Configures the SceneKit view with proper lighting and camera
    private func setupSceneView(with scene: SCNScene) {
        let view = SCNView(frame: .zero)
        view.scene = scene
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        
        // Configure camera
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        scene.rootNode.addChildNode(cameraNode)
        
        // Memory optimization
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling2X
        view.rendersContinuously = false
        
        self.sceneView = view
    }
}

// MARK: - Preview Provider

#if DEBUG
struct FossilCard_Previews: PreviewProvider {
    static var previews: some View {
        let location = CLLocation(latitude: 0, longitude: 0)
        let fossil = Fossil(
            id: UUID(),
            scientificName: "Tyrannosaurus Rex",
            commonName: "T-Rex",
            period: "Late Cretaceous",
            estimatedAge: 66.0,
            discoveryLocation: location
        )
        
        return Group {
            FossilCard(fossil: fossil)
                .padding()
                .previewLayout(.sizeThatFits)
                .preferredColorScheme(.light)
            
            FossilCard(fossil: fossil)
                .padding()
                .previewLayout(.sizeThatFits)
                .preferredColorScheme(.dark)
        }
    }
}
#endif