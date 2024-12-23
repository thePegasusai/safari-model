//
// ProfileView.swift
// WildlifeSafari
//
// A comprehensive user profile interface with offline support, secure data handling,
// and statistics visualization.
//

import SwiftUI // latest

@available(iOS 14.0, *)
@MainActor
struct ProfileView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: ProfileViewModel
    @State private var refreshing: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var showingOfflineAlert: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastSyncTimestamp") private var lastSync: Double = 0
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Offline Mode Banner
                        if viewModel.isOffline {
                            offlineBanner
                        }
                        
                        // Profile Header
                        profileHeader
                            .padding(.horizontal)
                        
                        // Statistics Summary
                        statisticsSummary
                            .padding(.horizontal)
                        
                        // Recent Discoveries
                        recentDiscoveries
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await refreshData()
                }
                
                // Loading State
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                        Image(systemName: "gear")
                            .imageScale(.large)
                    }
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred")
            }
            .alert("Offline Mode", isPresented: $showingOfflineAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Some features may be limited while offline")
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await refreshData()
                }
            }
        }
    }
    
    // MARK: - Components
    
    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("Offline Mode")
            Spacer()
            Text("Last synced: \(formatDate(Date(timeIntervalSince1970: lastSync)))")
                .font(.caption)
        }
        .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile Image
            if let user = viewModel.user {
                AsyncImage(url: user.avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                
                // User Info
                VStack(spacing: 8) {
                    Text(user.name)
                        .font(.title2)
                        .bold()
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sync Status
            if viewModel.syncStatus != .synced {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Syncing...")
                    Spacer()
                    ProgressView()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var statisticsSummary: some View {
        NavigationLink(destination: StatisticsView(viewModel: viewModel)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Statistics")
                    .font(.headline)
                
                HStack {
                    StatisticItem(
                        title: "Discoveries",
                        value: "\(viewModel.user?.discoveries.count ?? 0)",
                        icon: "magnifyingglass"
                    )
                    
                    Divider()
                    
                    StatisticItem(
                        title: "Species",
                        value: "\(viewModel.user?.uniqueSpecies.count ?? 0)",
                        icon: "leaf"
                    )
                    
                    Divider()
                    
                    StatisticItem(
                        title: "Accuracy",
                        value: "\(viewModel.user?.averageAccuracy.formatted(.percent) ?? "0%")",
                        icon: "checkmark.circle"
                    )
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var recentDiscoveries: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Discoveries")
                .font(.headline)
            
            if let discoveries = viewModel.user?.recentDiscoveries {
                ForEach(discoveries.prefix(3)) { discovery in
                    DiscoveryRow(discovery: discovery)
                }
            } else {
                Text("No recent discoveries")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func refreshData() async {
        refreshing = true
        defer { refreshing = false }
        
        do {
            try await viewModel.refreshUserData()
            lastSync = Date().timeIntervalSince1970
        } catch {
            if viewModel.isOffline {
                showingOfflineAlert = true
            } else {
                showingErrorAlert = true
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Views

private struct StatisticItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DiscoveryRow: View {
    let discovery: Discovery
    
    var body: some View {
        HStack {
            AsyncImage(url: discovery.thumbnailURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.species?.commonName ?? "Unknown Species")
                    .font(.subheadline)
                    .bold()
                
                Text(discovery.location?.locationContext ?? "Unknown Location")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formatDate(discovery.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    ProfileView(viewModel: ProfileViewModel(
        authService: AuthenticationService(),
        collectionService: CollectionService(
            apiClient: APIClient(),
            coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
            syncService: SyncService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
            )
        ),
        secureStorage: KeychainManager.shared,
        errorHandler: ErrorHandler(),
        analyticsTracker: AnalyticsTracker()
    ))
}