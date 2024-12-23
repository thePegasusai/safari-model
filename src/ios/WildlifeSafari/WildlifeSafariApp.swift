//
// WildlifeSafariApp.swift
// WildlifeSafari
//
// Main entry point for the Wildlife Detection Safari Pokédex iOS application
// with comprehensive lifecycle management and state handling.
//

import SwiftUI // Latest - UI framework for app implementation

// MARK: - App Entry Point

@main
struct WildlifeSafariApp: App {
    // MARK: - Environment Objects
    
    @StateObject private var coreDataStack: CoreDataStack
    @StateObject private var collectionViewModel: CollectionViewModel
    @StateObject private var networkMonitor = NetworkMonitor()
    
    // MARK: - State Properties
    
    @State private var isFirstLaunch = true
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    @State private var appState = AppState()
    
    // MARK: - Constants
    
    private let APP_NAME = "Wildlife Safari Pokédex"
    private let APP_VERSION = "1.0.0"
    private let BACKGROUND_TASK_IDENTIFIER = "com.wildlifesafari.backgroundSync"
    
    // MARK: - Initialization
    
    init() {
        // Initialize CoreDataStack
        let coreDataStack = CoreDataStack(
            modelName: "WildlifeSafari",
            configuration: .default
        )
        _coreDataStack = StateObject(wrappedValue: coreDataStack)
        
        // Initialize CollectionViewModel
        let apiClient = APIClient()
        let syncService = SyncService(
            apiClient: apiClient,
            coreDataStack: coreDataStack
        )
        let collectionService = CollectionService(
            apiClient: apiClient,
            coreDataStack: coreDataStack,
            syncService: syncService
        )
        let viewModel = CollectionViewModel(collectionService: collectionService)
        _collectionViewModel = StateObject(wrappedValue: viewModel)
        
        // Configure appearance
        configureAppearance()
        
        // Register background tasks
        registerBackgroundTasks()
    }
    
    // MARK: - App Scene
    
    var body: some Scene {
        WindowGroup {
            TabView {
                // Camera View
                CameraView()
                    .environmentObject(coreDataStack)
                    .tabItem {
                        Label("Detect", systemImage: "camera.fill")
                    }
                    .onChange(of: thermalState) { newState in
                        handleThermalStateChange(newState)
                    }
                
                // Collection View
                CollectionView(viewModel: collectionViewModel)
                    .environmentObject(coreDataStack)
                    .tabItem {
                        Label("Collections", systemImage: "square.stack.3d.up.fill")
                    }
            }
            .environmentObject(networkMonitor)
            .onAppear {
                handleAppLaunch()
            }
            .onChange(of: networkMonitor.isConnected) { isConnected in
                handleConnectivityChange(isConnected)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func configureAppearance() {
        // Configure navigation bar appearance
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        
        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BACKGROUND_TASK_IDENTIFIER,
            using: nil
        ) { task in
            handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        // Schedule next background task
        scheduleBackgroundTask()
        
        // Create task group for background operations
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                // Perform sync operations
                try await collectionViewModel.syncCollections()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: BACKGROUND_TASK_IDENTIFIER)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    private func handleAppLaunch() {
        if isFirstLaunch {
            // Perform first launch setup
            isFirstLaunch = false
            UIAccessibility.post(
                notification: .announcement,
                argument: "Welcome to \(APP_NAME)"
            )
        }
        
        // Schedule initial background task
        scheduleBackgroundTask()
    }
    
    private func handleThermalStateChange(_ newState: ProcessInfo.ThermalState) {
        switch newState {
        case .nominal, .fair:
            // Normal operation
            break
        case .serious:
            // Reduce processing
            appState.reduceProcessingLoad = true
        case .critical:
            // Minimal operation
            appState.reduceProcessingLoad = true
            appState.disableMLProcessing = true
        @unknown default:
            break
        }
    }
    
    private func handleConnectivityChange(_ isConnected: Bool) {
        if isConnected {
            // Trigger sync when coming online
            Task {
                await collectionViewModel.syncCollections()
            }
        }
    }
}

// MARK: - Supporting Types

private class AppState: ObservableObject {
    @Published var reduceProcessingLoad = false
    @Published var disableMLProcessing = false
}

private class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true
}