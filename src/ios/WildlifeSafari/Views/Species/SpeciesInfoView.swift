//
// SpeciesInfoView.swift
// WildlifeSafari
//
// SwiftUI view displaying detailed species information with accessibility support
// and design system compliance.
//

import SwiftUI

// MARK: - Constants

private enum Constants {
    static let headerSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let minTouchTarget: CGFloat = 44
    static let animationDuration: TimeInterval = 0.3
    static let taxonomyLevels = ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"]
}

// MARK: - SpeciesInfoView

struct SpeciesInfoView: View {
    // MARK: - Properties
    
    @ObservedObject private var viewModel: SpeciesViewModel
    private let species: Species
    
    @State private var isExpanded = false
    @State private var selectedTaxonomyLevel: Int? = nil
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    init(viewModel: SpeciesViewModel, species: Species) {
        self.viewModel = viewModel
        self.species = species
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Constants.sectionSpacing) {
                // Species Header
                speciesHeader
                    .padding(.horizontal)
                
                // Conservation Status
                conservationStatus
                    .padding(.horizontal)
                
                // Taxonomy Section
                taxonomySection
                    .padding(.horizontal)
                
                // Action Buttons
                actionButtons
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Species Information")
    }
    
    // MARK: - View Components
    
    private var speciesHeader: some View {
        VStack(alignment: .leading, spacing: Constants.headerSpacing) {
            Text(species.scientificName)
                .font(.title2.italic())
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
            
            Text(species.commonName)
                .font(.headline)
                .foregroundColor(.secondary)
                .accessibilityLabel("Common name: \(species.commonName)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var conservationStatus: some View {
        HStack(spacing: Constants.headerSpacing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(conservationStatusColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            
            Text(species.conservationStatus)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conservation status: \(species.conservationStatus)")
    }
    
    private var taxonomySection: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: Constants.headerSpacing) {
                    ForEach(species.getTaxonomyArray().enumerated().map({ $0 }), id: \.offset) { index, rank in
                        TaxonomyRow(
                            level: Constants.taxonomyLevels[index],
                            value: rank,
                            isSelected: selectedTaxonomyLevel == index
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: Constants.animationDuration)) {
                                selectedTaxonomyLevel = selectedTaxonomyLevel == index ? nil : index
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Constants.taxonomyLevels[index]): \(rank)")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.top, Constants.headerSpacing)
            },
            label: {
                Text("Taxonomy")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        )
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: Constants.headerSpacing) {
            CustomButton("Add to Collection", style: .primary) {
                // Add to collection action
            }
            
            CustomButton("Share", style: .outline) {
                // Share action
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private var conservationStatusColor: Color {
        switch species.conservationStatus.lowercased() {
        case "extinct":
            return .red
        case "endangered":
            return .orange
        case "vulnerable":
            return .yellow
        case "near threatened":
            return .blue
        default:
            return .green
        }
    }
}

// MARK: - Supporting Views

private struct TaxonomyRow: View {
    let level: String
    let value: String
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text(level)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isSelected ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
        )
        .animation(.easeInOut(duration: Constants.animationDuration), value: isSelected)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SpeciesInfoView_Previews: PreviewProvider {
    static var previews: some View {
        let mockSpecies = Species()
        let viewModel = SpeciesViewModel()
        
        Group {
            SpeciesInfoView(viewModel: viewModel, species: mockSpecies)
                .preferredColorScheme(.light)
            
            SpeciesInfoView(viewModel: viewModel, species: mockSpecies)
                .preferredColorScheme(.dark)
        }
    }
}
#endif