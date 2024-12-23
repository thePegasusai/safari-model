//
// MapAnnotationView.swift
// WildlifeSafari
//
// A SwiftUI view component that renders custom map annotations for wildlife discoveries
// and fossil finds with comprehensive accessibility support and interactive elements.
//

import SwiftUI
import MapKit

// MARK: - Constants

private let kAnnotationSize: CGFloat = 44.0 // WCAG minimum touch target size
private let kCalloutPadding: CGFloat = 8.0 // Design system grid
private let kAnimationDuration: Double = 0.3
private let kMaxCalloutWidth: CGFloat = 300.0

// MARK: - MapAnnotationView

/// Custom map annotation view for displaying wildlife and fossil discoveries
public struct MapAnnotationView: View {
    // MARK: - Properties
    
    let discovery: Discovery
    let isSelected: Bool
    let onTap: (() -> Void)?
    
    @State private var isAnimating: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    /// Creates a new MapAnnotationView instance
    /// - Parameters:
    ///   - discovery: The discovery to display
    ///   - isSelected: Whether the annotation is selected
    ///   - onTap: Optional closure to execute when tapped
    public init(
        discovery: Discovery,
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.discovery = discovery
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Main annotation icon
            ZStack {
                Circle()
                    .fill(getAnnotationColor())
                    .frame(width: kAnnotationSize, height: kAnnotationSize)
                    .standardElevation(elevation: isSelected ? 4 : 2)
                
                Image(systemName: getAnnotationIcon())
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.easeInOut(duration: kAnimationDuration), value: isSelected)
            
            // Selection indicator
            if isSelected {
                Rectangle()
                    .fill(getAnnotationColor())
                    .frame(width: 2, height: 8)
            }
            
            // Callout view when selected
            if isSelected {
                makeCalloutView()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: kAnimationDuration)) {
                onTap?()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(getAccessibilityLabel())
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(getAccessibilityValue())
    }
    
    // MARK: - Private Methods
    
    /// Creates the expanded callout view with discovery details
    @ViewBuilder
    private func makeCalloutView() -> some View {
        VStack(alignment: .leading, spacing: kCalloutPadding) {
            // Species name and confidence
            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.species?.commonName ?? "Unknown Species")
                    .font(.headline)
                    .foregroundColor(.text)
                
                Text("Confidence: \(Int(discovery.confidence * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            
            // Action buttons
            HStack(spacing: kCalloutPadding) {
                CustomButton("View Details", style: .primary) {
                    // Handle view details action
                }
                .frame(maxWidth: .infinity)
                
                CustomButton("Share", style: .outline) {
                    // Handle share action
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(kCalloutPadding * 2)
        .background(Color.surface)
        .cornerRadius(8)
        .standardElevation(elevation: 3)
        .frame(maxWidth: kMaxCalloutWidth)
    }
    
    /// Returns the appropriate color based on discovery type
    private func getAnnotationColor() -> Color {
        switch discovery.discoveryType {
        case "wildlife":
            return Color.primary // #2E7D32
        case "fossil":
            return Color.secondary // #1565C0
        default:
            return Color.gray
        }
    }
    
    /// Returns the appropriate system icon based on discovery type
    private func getAnnotationIcon() -> String {
        switch discovery.discoveryType {
        case "wildlife":
            return "pawprint.fill"
        case "fossil":
            return "fossil.shell.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
    
    /// Generates appropriate accessibility label
    private func getAccessibilityLabel() -> String {
        let type = discovery.discoveryType.capitalized
        let species = discovery.species?.commonName ?? "Unknown Species"
        return "\(type) Discovery: \(species)"
    }
    
    /// Generates appropriate accessibility value
    private func getAccessibilityValue() -> String {
        let confidence = Int(discovery.confidence * 100)
        let status = isSelected ? "Selected" : "Not Selected"
        return "\(confidence)% Confidence, \(status)"
    }
}

// MARK: - Preview Provider

#if DEBUG
struct MapAnnotationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Wildlife annotation preview
            MapAnnotationView(
                discovery: mockWildlifeDiscovery(),
                isSelected: false
            )
            
            // Fossil annotation preview
            MapAnnotationView(
                discovery: mockFossilDiscovery(),
                isSelected: true
            )
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.background)
    }
    
    // Mock data for preview
    static func mockWildlifeDiscovery() -> Discovery {
        let discovery = Discovery()
        // Set mock properties
        return discovery
    }
    
    static func mockFossilDiscovery() -> Discovery {
        let discovery = Discovery()
        // Set mock properties
        return discovery
    }
}
#endif