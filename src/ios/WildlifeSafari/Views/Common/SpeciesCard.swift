//
// SpeciesCard.swift
// WildlifeSafari
//
// A reusable SwiftUI view component that displays species information in an
// accessible card format with WCAG 2.1 AA compliance.
//

import SwiftUI // Latest - Core SwiftUI framework

// MARK: - Constants

private let kCardCornerRadius: CGFloat = 12.0
private let kCardPadding: CGFloat = 16.0
private let kImageHeight: CGFloat = 120.0
private let kMinTouchTarget: CGFloat = 44.0
private let kImageAspectRatio: CGFloat = 16/9
private let kSpacing: CGFloat = 8.0
private let kStatusPillHeight: CGFloat = 24.0

// MARK: - SpeciesCard View

/// A card-style view displaying species information with full accessibility support
public struct SpeciesCard: View {
    
    // MARK: - Properties
    
    let species: Species
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var isImageLoading = true
    @State private var hasImageLoadError = false
    var onTap: (() -> Void)?
    
    // MARK: - Initialization
    
    /// Creates a new species card view
    /// - Parameters:
    ///   - species: The species to display
    ///   - onTap: Optional closure to execute when card is tapped
    public init(species: Species, onTap: (() -> Void)? = nil) {
        self.species = species
        self.onTap = onTap
        
        // Set accessibility identifier
        #if DEBUG
        _: () = UIAccessibility.post(notification: .screenChanged,
                                   argument: "Species Card - \(species.commonName)")
        #endif
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            speciesImage()
            
            VStack(alignment: .leading, spacing: kSpacing) {
                speciesInfo()
                conservationStatus()
            }
            .padding(kCardPadding)
        }
        .background(
            RoundedRectangle(cornerRadius: kCardCornerRadius)
                .fill(colorScheme == .dark ? Color(.systemGray6) : .white)
        )
        .clipShape(RoundedRectangle(cornerRadius: kCardCornerRadius))
        .shadow(
            color: Color.black.opacity(0.1),
            radius: 8,
            x: 0,
            y: 2
        )
        .onTapGesture {
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onTap?()
        }
        // Ensure minimum touch target size
        .frame(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget)
        // Configure accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Private Views
    
    private func speciesImage() -> some View {
        Group {
            if isImageLoading {
                ProgressView()
                    .frame(height: kImageHeight)
            } else if hasImageLoadError {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.gray)
                    .frame(height: kImageHeight)
            } else {
                AsyncImage(url: species.imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(kImageAspectRatio, contentMode: .fill)
                            .frame(height: kImageHeight)
                            .clipped()
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(height: kImageHeight)
        .accessibilityLabel("Image of \(species.commonName)")
    }
    
    private func speciesInfo() -> some View {
        VStack(alignment: .leading, spacing: kSpacing / 2) {
            Text(species.commonName)
                .font(.headline)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            
            Text(species.scientificName)
                .font(.subheadline)
                .italic()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .accessibilityElement(children: .combine)
    }
    
    private func conservationStatus() -> some View {
        HStack(spacing: kSpacing / 2) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(species.conservationStatus)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.1))
        )
        .accessibilityLabel("Conservation status: \(species.conservationStatus)")
    }
    
    // MARK: - Helper Properties
    
    private var statusColor: Color {
        switch species.conservationStatus.lowercased() {
        case "extinct":
            return .red
        case "endangered":
            return .orange
        case "vulnerable":
            return .yellow
        case "least concern":
            return .green
        default:
            return .gray
        }
    }
    
    private var accessibilityLabel: String {
        """
        \(species.commonName), \
        Scientific name: \(species.scientificName), \
        Conservation status: \(species.conservationStatus)
        """
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SpeciesCard_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Light mode preview
            SpeciesCard(species: previewSpecies)
                .padding()
                .previewDisplayName("Light Mode")
            
            // Dark mode preview
            SpeciesCard(species: previewSpecies)
                .padding()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            // Dynamic type preview
            SpeciesCard(species: previewSpecies)
                .padding()
                .environment(\.sizeCategory, .accessibilityLarge)
                .previewDisplayName("Large Dynamic Type")
        }
    }
    
    private static var previewSpecies: Species {
        let species = Species(entity: Species.entity(),
                            insertInto: nil)
        species.commonName = "Red-tailed Hawk"
        species.scientificName = "Buteo jamaicensis"
        try? species.updateConservationStatus("Least Concern")
        return species
    }
}
#endif