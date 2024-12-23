//
// SpeciesGalleryView.swift
// WildlifeSafari
//
// A SwiftUI view that displays a grid or list of species cards with comprehensive
// accessibility support, offline capabilities, and error handling.
//

import SwiftUI // Latest - Core SwiftUI framework
import Combine // Latest - Reactive programming support

// MARK: - Constants

private enum Constants {
    static let gridColumns = 2
    static let gridSpacing: CGFloat = 16.0
    static let searchBarHeight: CGFloat = 44.0
    static let minimumTouchTarget: CGFloat = 44.0
    static let searchDebounceTime: TimeInterval = 0.3
    static let filterOptions = ["All", "Endangered", "Discovered", "Reference"]
}

// MARK: - SpeciesGalleryView

struct SpeciesGalleryView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel = SpeciesViewModel()
    @State private var searchText = ""
    @State private var isGridView = true
    @State private var selectedFilter = "All"
    @State private var isRefreshing = false
    
    private let searchDebouncer = PassthroughSubject<String, Never>()
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.gridSpacing),
        count: Constants.gridColumns
    )
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding()
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Search species")
                    
                    // View mode toggle and filter
                    HStack {
                        viewModeToggle
                        Spacer()
                        filterPicker
                    }
                    .padding(.horizontal)
                    
                    // Species content
                    if viewModel.isLoading {
                        ProgressView()
                            .accessibilityLabel("Loading species")
                    } else {
                        speciesContent
                            .refreshable {
                                await refreshData()
                            }
                    }
                }
                
                // Error overlay
                if let error = viewModel.error {
                    errorOverlay(error)
                }
            }
            .navigationTitle("Species Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    sortButton
                }
            }
        }
        .onAppear {
            setupSearchDebouncing()
            viewModel.loadSpecies()
        }
    }
    
    // MARK: - Subviews
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search species...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(height: Constants.searchBarHeight)
                .accessibilityLabel("Search species")
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .frame(width: Constants.minimumTouchTarget, height: Constants.minimumTouchTarget)
                .accessibilityLabel("Clear search")
            }
        }
    }
    
    private var viewModeToggle: some View {
        Button(action: { isGridView.toggle() }) {
            Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                .frame(width: Constants.minimumTouchTarget, height: Constants.minimumTouchTarget)
        }
        .accessibilityLabel(isGridView ? "Switch to list view" : "Switch to grid view")
    }
    
    private var filterPicker: some View {
        Picker("Filter", selection: $selectedFilter) {
            ForEach(Constants.filterOptions, id: \.self) { option in
                Text(option)
                    .tag(option)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .accessibilityLabel("Filter species")
    }
    
    private var sortButton: some View {
        Menu {
            Button("Name (A-Z)", action: { /* Sort implementation */ })
            Button("Name (Z-A)", action: { /* Sort implementation */ })
            Button("Recently Added", action: { /* Sort implementation */ })
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: Constants.minimumTouchTarget, height: Constants.minimumTouchTarget)
        }
        .accessibilityLabel("Sort options")
    }
    
    private var speciesContent: some View {
        Group {
            if isGridView {
                speciesGrid
            } else {
                speciesList
            }
        }
    }
    
    private var speciesGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Constants.gridSpacing) {
                ForEach(filteredSpecies, id: \.id) { species in
                    SpeciesCard(species: species) {
                        // Handle card tap
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding()
        }
    }
    
    private var speciesList: some View {
        List(filteredSpecies, id: \.id) { species in
            SpeciesCard(species: species) {
                // Handle card tap
            }
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 8)
        }
        .listStyle(PlainListStyle())
    }
    
    private func errorOverlay(_ error: Error) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
            Button("Retry") {
                viewModel.loadSpecies()
            }
            .padding()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.localizedDescription)")
    }
    
    // MARK: - Helper Methods
    
    private var filteredSpecies: [Species] {
        var species = viewModel.species
        
        // Apply search filter
        if !searchText.isEmpty {
            species = species.filter { species in
                species.commonName.localizedCaseInsensitiveContains(searchText) ||
                species.scientificName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply category filter
        switch selectedFilter {
        case "Endangered":
            species = species.filter { $0.conservationStatus == "Endangered" }
        case "Discovered":
            species = species.filter { !$0.discoveries.isEmpty }
        case "Reference":
            species = species.filter { $0.discoveries.isEmpty }
        default:
            break
        }
        
        return species
    }
    
    private func setupSearchDebouncing() {
        searchDebouncer
            .debounce(for: .seconds(Constants.searchDebounceTime), scheduler: RunLoop.main)
            .sink { searchText in
                // Handle debounced search
            }
            .store(in: &viewModel.cancellables)
        
        $searchText
            .sink { text in
                searchDebouncer.send(text)
            }
            .store(in: &viewModel.cancellables)
    }
    
    private func refreshData() async {
        isRefreshing = true
        await viewModel.refreshData()
        isRefreshing = false
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SpeciesGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        SpeciesGalleryView()
    }
}
#endif