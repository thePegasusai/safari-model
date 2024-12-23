//
// SpeciesDetailView.swift
// WildlifeSafari
//
// A comprehensive SwiftUI view for displaying detailed species information
// with accessibility support, offline capabilities, and 3D model visualization.
//

import SwiftUI
import Combine

/// A detailed view displaying comprehensive species information with accessibility support
public struct SpeciesDetailView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: SpeciesViewModel
    @State private var showingGallery = false
    @State private var showingMap = false
    @State private var isSharing = false
    @State private var isShowingError = false
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    private let species: Species
    private let hapticEngine = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - Initialization
    
    /// Initializes the species detail view
    /// - Parameter species: The species to display
    public init(species: Species) {
        self.species = species
        _viewModel = StateObject(wrappedValue: SpeciesViewModel())
    }
    
    // MARK: - Body
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Species Image Header
                speciesImageHeader
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Species image of \(species.commonName)")
                
                // Species Names Section
                speciesNamesSection
                    .padding(.horizontal)
                
                // Conservation Status
                conservationStatusSection
                    .padding(.horizontal)
                
                // Taxonomic Information
                taxonomySection
                    .padding(.horizontal)
                
                // Action Buttons
                actionButtonsSection
                    .padding(.horizontal)
                
                // 3D Model View (if available)
                if species.has3DModel {
                    modelViewSection
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareButton
            }
        }
        .loadingOverlay(isLoading: viewModel.isLoading)
        .alert("Error", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An error occurred")
        }
        .onAppear {
            configureAccessibility()
            hapticEngine.prepare()
            viewModel.refreshSpecies()
        }
        .onChange(of: viewModel.error) { error in
            isShowingError = error != nil
        }
    }
    
    // MARK: - View Components
    
    private var speciesImageHeader: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: species.imageURL) { phase in
                switch phase {
                case .empty:
                    Color.gray.opacity(0.3)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Color.gray.opacity(0.3)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                @unknown default:
                    Color.gray.opacity(0.3)
                }
            }
            .frame(height: 300)
            .clipped()
            
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.5)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
        }
    }
    
    private var speciesNamesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(species.commonName)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
            
            Text(species.scientificName)
                .font(.title3)
                .italic()
                .foregroundColor(.secondary)
                .accessibilityLabel("Scientific name: \(species.scientificName)")
        }
    }
    
    private var conservationStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conservation Status")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(conservationStatusColor)
                    .frame(width: 4)
                
                Text(species.conservationStatus)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .standardElevation()
            .accessibilityLabel("Conservation status: \(species.conservationStatus)")
        }
    }
    
    private var taxonomySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Taxonomy")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            ForEach(species.taxonomy.components(separatedBy: "||"), id: \.self) { rank in
                HStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    
                    Text(rank)
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Taxonomic rank: \(rank)")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .standardElevation()
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            CustomButton("Add to Collection", style: .primary) {
                hapticEngine.impactOccurred()
                // Add to collection action
            }
            
            CustomButton("Show on Map", style: .outline) {
                hapticEngine.impactOccurred()
                showingMap = true
            }
        }
    }
    
    private var modelViewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3D Model")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            // 3D model viewer implementation would go here
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 200)
                .overlay(
                    Text("3D Model Viewer")
                        .foregroundColor(.secondary)
                )
                .cornerRadius(8)
                .accessibilityLabel("Interactive 3D model of \(species.commonName)")
        }
    }
    
    private var shareButton: some View {
        Button {
            hapticEngine.impactOccurred()
            isSharing = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .accessibilityLabel("Share species information")
        }
        .sheet(isPresented: $isSharing) {
            // Share sheet implementation
        }
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
        default:
            return .green
        }
    }
    
    private func configureAccessibility() {
        UIAccessibility.post(
            notification: .announcement,
            argument: "Showing details for \(species.commonName)"
        )
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SpeciesDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SpeciesDetailView(species: Species())
        }
    }
}
#endif