//
// DetectionOverlayView.swift
// WildlifeSafari
//
// SwiftUI view component for real-time detection overlays with thermal management
// and accessibility optimizations.
//

import SwiftUI // Latest
import CoreGraphics // Latest
import MetalKit // Latest

// MARK: - Constants

private let BOUNDING_BOX_COLOR = Color("DetectionOverlay", bundle: .main)
private let CONFIDENCE_THRESHOLD: Float = 0.75
private let ANIMATION_DURATION: Double = 0.3
private let THERMAL_THROTTLE_THRESHOLD: Double = 0.8
private let MAX_CONCURRENT_RENDERS: Int = 3

// MARK: - Detection Overlay View

/// SwiftUI view that renders detection overlays with accessibility and thermal management
@available(iOS 14.0, *)
public struct DetectionOverlayView: View {
    // MARK: - Properties
    
    private let detections: [DetectionResult]
    private let previewSize: CGSize
    private let isProcessing: Bool
    @State private var currentThermalState: ProcessInfo.ThermalState = .nominal
    @State private var activeRenders: Int = 0
    
    // Accessibility
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.colorScheme) private var colorScheme
    
    // Metal rendering
    private let metalDevice = MTLCreateSystemDefaultDevice()
    private let renderSemaphore = DispatchSemaphore(value: MAX_CONCURRENT_RENDERS)
    
    // MARK: - Initialization
    
    /// Initializes the overlay view with detection results and preview size
    /// - Parameters:
    ///   - detections: Array of detection results to display
    ///   - previewSize: Size of the camera preview
    ///   - isProcessing: Whether detection is currently processing
    public init(
        detections: [DetectionResult],
        previewSize: CGSize,
        isProcessing: Bool
    ) {
        self.detections = detections
        self.previewSize = previewSize
        self.isProcessing = isProcessing
        
        setupThermalMonitoring()
        configureAccessibility()
    }
    
    // MARK: - View Body
    
    public var body: some View {
        ZStack {
            // Detection overlays
            ForEach(filteredDetections, id: \.boundingBox) { detection in
                DetectionBox(
                    detection: detection,
                    previewSize: previewSize,
                    thermalState: currentThermalState
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: detection))
                .accessibilityValue(accessibilityValue(for: detection))
            }
            
            // Processing indicator
            if isProcessing {
                ProcessingIndicator()
                    .accessibilityLabel("Processing wildlife detection")
            }
        }
        .onChange(of: currentThermalState) { newState in
            adjustRenderingQuality(for: newState)
        }
    }
    
    // MARK: - Private Methods
    
    /// Calculates the path for drawing detection bounding boxes
    private func calculateBoundingBoxPath(bounds: CGRect, cornerRadius: CGFloat) -> Path {
        let thermalAdjustedRadius = adjustCornerRadius(cornerRadius, for: currentThermalState)
        
        return Path { path in
            path.addRoundedRect(
                in: bounds,
                cornerSize: CGSize(width: thermalAdjustedRadius, height: thermalAdjustedRadius)
            )
        }
    }
    
    /// Monitors device thermal state and adjusts rendering
    private func monitorThermalState() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.currentThermalState = ProcessInfo.processInfo.thermalState
        }
    }
    
    /// Filters detections based on confidence and thermal state
    private var filteredDetections: [DetectionResult] {
        detections.filter { detection in
            let thermalAdjustedThreshold = adjustConfidenceThreshold(for: currentThermalState)
            return detection.confidence >= thermalAdjustedThreshold
        }
    }
    
    /// Adjusts rendering quality based on thermal state
    private func adjustRenderingQuality(for thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal:
            activeRenders = MAX_CONCURRENT_RENDERS
        case .fair:
            activeRenders = MAX_CONCURRENT_RENDERS / 2
        case .serious:
            activeRenders = MAX_CONCURRENT_RENDERS / 4
        case .critical:
            activeRenders = 1
        @unknown default:
            activeRenders = MAX_CONCURRENT_RENDERS / 2
        }
    }
    
    /// Adjusts confidence threshold based on thermal state
    private func adjustConfidenceThreshold(for thermalState: ProcessInfo.ThermalState) -> Float {
        switch thermalState {
        case .nominal:
            return CONFIDENCE_THRESHOLD
        case .fair:
            return CONFIDENCE_THRESHOLD + 0.05
        case .serious:
            return CONFIDENCE_THRESHOLD + 0.1
        case .critical:
            return CONFIDENCE_THRESHOLD + 0.15
        @unknown default:
            return CONFIDENCE_THRESHOLD
        }
    }
    
    /// Generates accessibility label for detection
    private func accessibilityLabel(for detection: DetectionResult) -> String {
        "Detected \(detection.className)"
    }
    
    /// Generates accessibility value for detection
    private func accessibilityValue(for detection: DetectionResult) -> String {
        "Confidence: \(Int(detection.confidence * 100))%"
    }
    
    /// Configures view accessibility
    private func configureAccessibility() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
    
    /// Sets up thermal state monitoring
    private func setupThermalMonitoring() {
        monitorThermalState()
    }
    
    /// Adjusts corner radius based on thermal state
    private func adjustCornerRadius(_ radius: CGFloat, for thermalState: ProcessInfo.ThermalState) -> CGFloat {
        switch thermalState {
        case .nominal:
            return radius
        case .fair:
            return max(radius - 2, 0)
        case .serious:
            return max(radius - 4, 0)
        case .critical:
            return 0
        @unknown default:
            return radius
        }
    }
}

// MARK: - Supporting Views

/// Detection bounding box view
private struct DetectionBox: View {
    let detection: DetectionResult
    let previewSize: CGSize
    let thermalState: ProcessInfo.ThermalState
    
    var body: some View {
        calculateBoundingBoxPath(bounds: detection.boundingBox, cornerRadius: 8)
            .stroke(BOUNDING_BOX_COLOR, lineWidth: lineWidth)
            .animation(.easeInOut(duration: ANIMATION_DURATION))
    }
    
    private var lineWidth: CGFloat {
        switch thermalState {
        case .nominal:
            return 2
        case .fair:
            return 1.5
        case .serious:
            return 1
        case .critical:
            return 0.5
        @unknown default:
            return 1.5
        }
    }
}

/// Processing indicator view
private struct ProcessingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .stroke(BOUNDING_BOX_COLOR.opacity(0.5), lineWidth: 2)
            .frame(width: 30, height: 30)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                Animation.linear(duration: 1)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}