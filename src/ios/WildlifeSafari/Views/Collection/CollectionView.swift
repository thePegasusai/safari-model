//
// CollectionView.swift
// WildlifeSafari
//
// Main container view for managing and displaying wildlife and fossil collections
// with comprehensive offline support and accessibility features.
//

import SwiftUI

// MARK: - View Mode Enum

private enum ViewMode: String, CaseIterable {
    case grid = "Grid"
    case list = "List"
}

// MARK: - Sort Option Enum

private enum SortOption: String, CaseIterable {
    case date = "Date"
    case name = "Name"
    case type = "Type"
    case rarity = "Rarity"
}

// MARK: - Collection View

public struct CollectionView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: CollectionViewModel
    @State private var viewMode: ViewMode = .grid
    @State private var showAddCollection = false
    @State private var newCollectionName = ""
    @State private var sortOption: SortOption = .date
    @State private var isRefreshing = false
    @State private var showSortMenu = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // MARK: - Initialization
    
    public init(viewModel: CollectionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        
        // Load saved view mode preference
        if let savedMode = UserDefaults.standard.string(forKey: "CollectionViewMode"),
           let mode = ViewMode(rawValue: savedMode) {
            _viewMode = State(initialValue: mode)
        }
    }
    
    // MARK: - Body
    
    public var body: some View {
        NavigationView {
            ZStack {
                // Offline Mode Banner
                if viewModel.isOffline {
                    VStack {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.white)
                            Text("Offline Mode")
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Color.orange)
                        Spacer()
                    }
                    .zIndex(1)
                    .transition(.move(edge: .top))
                    .animation(.easeInOut, value: viewModel.isOffline)
                }
                
                // Sync Status Indicator
                if case .syncing = viewModel.syncStatus {
                    VStack {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        Spacer()
                    }
                    .zIndex(1)
                }
                
                // Main Content
                VStack(spacing: 0) {
                    // View Mode Toggle
                    HStack {
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Image(systemName: mode == .grid ? "square.grid.2x2" : "list.bullet")
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        
                        Spacer()
                        
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    Label(
                                        option.rawValue,
                                        systemImage: sortOption == option ? "checkmark" : ""
                                    )
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    .padding()
                    
                    // Collection Views
                    Group {
                        if viewModel.collections.isEmpty && !viewModel.isLoading {
                            EmptyStateView(
                                title: "No Collections",
                                message: "Start your wildlife adventure by creating a new collection.",
                                imageName: "square.stack.3d.up.fill",
                                actionTitle: "Create Collection",
                                action: { showAddCollection = true }
                            )
                        } else {
                            switch viewMode {
                            case .grid:
                                CollectionGridView(viewModel: viewModel)
                            case .list:
                                CollectionListView(viewModel: viewModel)
                            }
                        }
                    }
                    .refreshable {
                        await handleRefresh()
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddCollection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Collection")
                }
            }
            .sheet(isPresented: $showAddCollection) {
                NavigationView {
                    Form {
                        Section {
                            TextField("Collection Name", text: $newCollectionName)
                                .textContentType(.name)
                                .submitLabel(.done)
                        }
                    }
                    .navigationTitle("New Collection")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showAddCollection = false
                        },
                        trailing: Button("Create") {
                            addCollection()
                        }
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func toggleViewMode() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        viewMode = viewMode == .grid ? .list : .grid
        UserDefaults.standard.set(viewMode.rawValue, forKey: "CollectionViewMode")
        
        UIAccessibility.post(
            notification: .announcement,
            argument: "Switched to \(viewMode.rawValue) view"
        )
    }
    
    private func addCollection() {
        guard !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            do {
                _ = try await viewModel.createCollection(name: newCollectionName)
                newCollectionName = ""
                showAddCollection = false
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Collection created successfully"
                )
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
    
    private func handleRefresh() async {
        isRefreshing = true
        await viewModel.fetchCollections()
        isRefreshing = false
        
        UIAccessibility.post(
            notification: .announcement,
            argument: "Collections refreshed"
        )
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CollectionView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionView(viewModel: CollectionViewModel(
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