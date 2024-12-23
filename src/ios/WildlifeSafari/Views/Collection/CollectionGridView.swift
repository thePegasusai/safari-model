//
// CollectionGridView.swift
// WildlifeSafari
//
// A responsive grid view for displaying wildlife and fossil collections with
// comprehensive accessibility support and offline capabilities.
//

import SwiftUI

// MARK: - Constants

private enum Constants {
    static let gridSpacing: CGFloat = 16.0
    static let cornerRadius: CGFloat = 12.0
    static let minimumItemSize: CGFloat = 160.0
    static let placeholderImage = "collection-placeholder"
    static let offlineIndicatorSize: CGFloat = 16.0
    static let maxGridColumns = 3
}

// MARK: - Collection Grid View

@MainActor
public struct CollectionGridView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: CollectionViewModel
    @Binding private var isPresented: Bool
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingError = false
    @State private var isRefreshing = false
    
    private let columns: [GridItem]
    
    // MARK: - Initialization
    
    public init(viewModel: CollectionViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
        
        // Create adaptive grid layout
        let screenWidth = UIScreen.main.bounds.width
        let columnCount = screenWidth > 768 ? Constants.maxGridColumns : 2
        columns = Array(repeating: GridItem(.flexible(), spacing: Constants.gridSpacing), count: columnCount)
    }
    
    // MARK: - Body
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.collections.isEmpty {
                    LoadingView(message: "Loading collections...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: Constants.gridSpacing) {
                        ForEach(viewModel.collections, id: \.collectionId) { collection in
                            makeGridItem(collection)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, Constants.gridSpacing)
                }
            }
            .refreshable {
                isRefreshing = true
                await viewModel.loadCollections(forceRefresh: true)
                isRefreshing = false
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close collections")
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("Retry") {
                    Task {
                        await viewModel.loadCollections(forceRefresh: true)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An error occurred")
            }
        }
        .task {
            await viewModel.loadCollections()
        }
    }
    
    // MARK: - Grid Item View
    
    private func makeGridItem(_ collection: Collection) -> some View {
        NavigationLink(value: collection) {
            VStack(alignment: .leading, spacing: 8) {
                // Collection thumbnail
                AsyncImage(url: collection.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Image(Constants.placeholderImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(Constants.placeholderImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: Constants.minimumItemSize)
                .clipped()
                
                // Collection info
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(collection.discoveries.count) discoveries")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                
                // Offline indicator if needed
                if !collection.isSynced {
                    HStack {
                        Image(systemName: "cloud.slash")
                            .foregroundColor(.secondary)
                            .frame(width: Constants.offlineIndicatorSize, height: Constants.offlineIndicatorSize)
                        Text("Not synced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(Constants.cornerRadius)
            .standardElevation()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(collection.name), \(collection.discoveries.count) discoveries")
            .accessibilityHint(collection.isSynced ? "" : "Not synced")
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CollectionGridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = CollectionViewModel(
            collectionService: CollectionService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
                syncService: SyncService(apiClient: APIClient(), coreDataStack: CoreDataStack(modelName: "WildlifeSafari"))
            )
        )
        
        CollectionGridView(
            viewModel: mockViewModel,
            isPresented: .constant(true)
        )
    }
}
#endif