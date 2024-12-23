//
// CollectionDetailView.swift
// WildlifeSafari
//
// A SwiftUI view that displays detailed information about a specific collection,
// including its discoveries, statistics, and management options with enhanced
// security, accessibility, and offline support.
//

import SwiftUI
import Combine

// MARK: - Constants

private enum Constants {
    static let gridSpacing: CGFloat = 12
    static let headerHeight: CGFloat = 60
    static let minTouchSize: CGFloat = 44
    static let maxNameLength = 100
    static let animationDuration: Double = 0.3
    static let gridColumns = 2
}

// MARK: - Collection Detail View

struct CollectionDetailView: View {
    // MARK: - Properties
    
    @ObservedObject private var viewModel: CollectionViewModel
    private let collection: Collection
    
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showingDeleteAlert = false
    @State private var showingEncryptionStatus = false
    @State private var gridItemSize: CGFloat = 0
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    // MARK: - Initialization
    
    init(viewModel: CollectionViewModel, collection: Collection) {
        self.viewModel = viewModel
        self.collection = collection
        self._editedName = State(initialValue: collection.name)
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Collection Header
                collectionHeader
                    .accessibleTouchTarget()
                
                // Statistics Section
                statisticsSection
                    .cardStyle()
                
                // Discoveries Grid
                discoveriesGrid
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Collection Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Collection Options")
                }
            }
        }
        .loadingOverlay(isLoading: viewModel.isLoading)
        .alert("Delete Collection?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteCollection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Collection Header
    
    private var collectionHeader: some View {
        HStack(spacing: 12) {
            if isEditingName {
                TextField("Collection Name", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(updateCollectionName)
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Edit Collection Name")
            } else {
                Text(collection.name)
                    .font(.title2.bold())
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                isEditingName.toggle()
            } label: {
                Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil.circle")
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel(isEditingName ? "Save Name" : "Edit Name")
        }
        .padding(.horizontal)
        .frame(height: Constants.headerHeight)
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)
            
            HStack {
                StatisticItem(
                    title: "Discoveries",
                    value: "\(collection.discoveries.count)",
                    icon: "camera.fill"
                )
                
                Divider()
                
                StatisticItem(
                    title: "Last Updated",
                    value: collection.lastSyncTimestamp?.formatted() ?? "Never",
                    icon: "clock.fill"
                )
            }
            
            if !collection.isSynced {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Changes pending sync")
                        .font(.caption)
                }
                .padding(.top, 4)
            }
        }
        .padding()
    }
    
    // MARK: - Discoveries Grid
    
    private var discoveriesGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Constants.gridSpacing),
            GridItem(.flexible(), spacing: Constants.gridSpacing)
        ]
        
        return LazyVGrid(columns: columns, spacing: Constants.gridSpacing) {
            ForEach(Array(collection.discoveries as? Set<Discovery> ?? []), id: \.discoveryId) { discovery in
                DiscoveryGridItem(discovery: discovery)
                    .aspectRatio(1, contentMode: .fill)
                    .cornerRadius(8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Discovery of \(discovery.species?.commonName ?? "Unknown Species")")
            }
        }
    }
    
    // MARK: - Supporting Views
    
    private struct StatisticItem: View {
        let title: String
        let value: String
        let icon: String
        
        var body: some View {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(value)")
        }
    }
    
    private struct DiscoveryGridItem: View {
        let discovery: Discovery
        
        var body: some View {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                
                VStack(alignment: .leading) {
                    Text(discovery.species?.commonName ?? "Unknown Species")
                        .font(.caption.bold())
                        .lineLimit(2)
                    
                    Text(discovery.timestamp.formatted())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(.ultraThinMaterial)
            }
        }
    }
    
    // MARK: - Actions
    
    private func updateCollectionName() {
        guard !editedName.isEmpty,
              editedName != collection.name,
              editedName.count <= Constants.maxNameLength else {
            editedName = collection.name
            isEditingName = false
            return
        }
        
        viewModel.updateCollection(collection) { collection in
            collection.name = editedName
        }
        .sink(
            receiveCompletion: { _ in
                isEditingName = false
            },
            receiveValue: { _ in }
        )
        .store(in: &Set<AnyCancellable>())
    }
    
    private func deleteCollection() {
        viewModel.deleteCollection(collection)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in }
            )
            .store(in: &Set<AnyCancellable>())
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CollectionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CollectionDetailView(
                viewModel: CollectionViewModel(
                    collectionService: CollectionService(
                        apiClient: APIClient(),
                        coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
                        syncService: SyncService(
                            apiClient: APIClient(),
                            coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
                        )
                    )
                ),
                collection: Collection()
            )
        }
    }
}
#endif