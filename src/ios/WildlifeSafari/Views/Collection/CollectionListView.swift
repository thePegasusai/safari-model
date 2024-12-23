//
// CollectionListView.swift
// WildlifeSafari
//
// SwiftUI view that displays a list of user's wildlife and fossil collections
// with comprehensive sorting, filtering, and offline capabilities.
//

import SwiftUI

// MARK: - Constants

private let kListSpacing: CGFloat = 16.0
private let kMinimumSearchLength: Int = 2
private let kSearchDebounceTime: TimeInterval = 0.3
private let kMaxThumbnailSize: CGFloat = 60.0
private let kDeleteConfirmationDuration: TimeInterval = 1.5

// MARK: - View Layout Enum

private enum ViewLayout {
    case list
    case grid
}

// MARK: - Sort Options

private enum SortOption: String, CaseIterable {
    case nameAscending = "Name (A-Z)"
    case nameDescending = "Name (Z-A)"
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case discoveryCount = "Most Discoveries"
}

// MARK: - Collection List View

struct CollectionListView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: CollectionViewModel
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var selectedCollection: Collection?
    @State private var currentLayout: ViewLayout = .list
    @State private var showingSortOptions = false
    @State private var currentSortOption: SortOption = .dateNewest
    @State private var showingDeleteConfirmation = false
    @State private var collectionToDelete: Collection?
    @State private var isOfflineMode = false
    
    // MARK: - Initialization
    
    init(viewModel: CollectionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main Content
                VStack(spacing: 0) {
                    // Layout Toggle and Sort Button
                    HStack {
                        Picker("View", selection: $currentLayout) {
                            Image(systemName: "list.bullet")
                                .tag(ViewLayout.list)
                            Image(systemName: "square.grid.2x2")
                                .tag(ViewLayout.grid)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 100)
                        
                        Spacer()
                        
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button(action: { currentSortOption = option }) {
                                    Label(
                                        option.rawValue,
                                        systemImage: currentSortOption == option ? "checkmark" : ""
                                    )
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    .standardPadding()
                    
                    // Collection List/Grid
                    if viewModel.collections.isEmpty {
                        EmptyStateView(
                            title: "No Collections",
                            message: "Start your wildlife adventure by creating a new collection.",
                            imageName: "square.stack.3d.up.fill",
                            actionTitle: "Create Collection",
                            action: { /* Handle create action */ }
                        )
                    } else {
                        collectionList
                            .refreshable {
                                await viewModel.fetchCollections()
                            }
                    }
                }
                
                // Loading Overlay
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
                
                // Offline Mode Banner
                if isOfflineMode {
                    VStack {
                        HStack {
                            Image(systemName: "wifi.slash")
                            Text("Offline Mode")
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .standardPadding()
                        .background(Color.orange)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarItems(trailing: addButton)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer,
                prompt: "Search collections"
            )
            .onChange(of: searchText) { _ in
                isSearchActive = !searchText.isEmpty
            }
            .alert(
                "Delete Collection",
                isPresented: $showingDeleteConfirmation,
                presenting: collectionToDelete
            ) { collection in
                Button("Delete", role: .destructive) {
                    deleteCollection(collection)
                }
                Button("Cancel", role: .cancel) {}
            } message: { collection in
                Text("Are you sure you want to delete '\(collection.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            checkNetworkStatus()
        }
    }
    
    // MARK: - Subviews
    
    private var collectionList: some View {
        let filteredCollections = filterCollections(
            viewModel.collections,
            searchText: searchText,
            sortOption: currentSortOption
        )
        
        return Group {
            switch currentLayout {
            case .list:
                List {
                    ForEach(filteredCollections, id: \.collectionId) { collection in
                        CollectionRow(collection: collection)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    collectionToDelete = collection
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: kListSpacing) {
                        ForEach(filteredCollections, id: \.collectionId) { collection in
                            CollectionGridItem(collection: collection)
                                .onTapGesture {
                                    selectedCollection = collection
                                }
                        }
                    }
                    .standardPadding()
                }
            }
        }
    }
    
    private var addButton: some View {
        Button(action: { /* Handle add action */ }) {
            Image(systemName: "plus")
        }
        .accessibleTouchTarget()
    }
    
    // MARK: - Helper Functions
    
    private func filterCollections(
        _ collections: [Collection],
        searchText: String,
        sortOption: SortOption
    ) -> [Collection] {
        var filtered = collections
        
        // Apply search filter
        if !searchText.isEmpty && searchText.count >= kMinimumSearchLength {
            filtered = filtered.filter { collection in
                collection.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        filtered.sort { first, second in
            switch sortOption {
            case .nameAscending:
                return first.name < second.name
            case .nameDescending:
                return first.name > second.name
            case .dateNewest:
                return first.lastSyncDate ?? Date() > second.lastSyncDate ?? Date()
            case .dateOldest:
                return first.lastSyncDate ?? Date() < second.lastSyncDate ?? Date()
            case .discoveryCount:
                return first.discoveries.count > second.discoveries.count
            }
        }
        
        return filtered
    }
    
    private func deleteCollection(_ collection: Collection) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        Task {
            do {
                try await viewModel.deleteCollection(collection)
                generator.notificationOccurred(.success)
            } catch {
                generator.notificationOccurred(.error)
            }
        }
    }
    
    private func checkNetworkStatus() {
        // Implementation would check network status
        // and update isOfflineMode accordingly
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CollectionListView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionListView(viewModel: CollectionViewModel(
            collectionService: CollectionService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
                syncService: SyncService(
                    apiClient: APIClient(),
                    coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
                )
            )
        ))
    }
}
#endif