//
// SettingsView.swift
// WildlifeSafari
//
// A comprehensive settings management interface with security, offline capabilities,
// and user preferences management.
//

import SwiftUI // latest
import Combine // latest

@available(iOS 14.0, *)
struct SettingsView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: ProfileViewModel
    @ObservedObject private var networkMonitor: NetworkMonitor = .shared
    
    // Alert states
    @State private var showingSignOutAlert = false
    @State private var showingClearDataAlert = false
    @State private var showingBiometricAlert = false
    @State private var showingOfflineModeAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Settings states
    @State private var biometricsEnabled = false
    @State private var offlineEnabled = UserDefaults.standard.bool(forKey: "offlineMode")
    @State private var isDarkMode = false
    @State private var selectedLanguage = "English"
    
    // MARK: - Initialization
    
    init(viewModel: ProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        
        // Load initial biometric state
        biometricsEnabled = BiometricAuthManager.shared.isBiometricsEnabled()
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            Form {
                // Account Section
                Section(header: Text("Account")) {
                    if let user = viewModel.user {
                        Text(user.email)
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink(destination: ProfileEditView()) {
                        Text("Edit Profile")
                    }
                }
                
                // Security Section
                Section(header: Text("Security & Privacy")) {
                    Toggle("Biometric Authentication", isOn: $biometricsEnabled)
                        .onChange(of: biometricsEnabled) { _ in
                            toggleBiometrics()
                        }
                    
                    Toggle("Offline Mode", isOn: $offlineEnabled)
                        .onChange(of: offlineEnabled) { _ in
                            toggleOfflineMode()
                        }
                        .disabled(!networkMonitor.isConnected.value)
                }
                
                // Application Section
                Section(header: Text("Application")) {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                        .onChange(of: isDarkMode) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "darkMode")
                        }
                    
                    Picker("Language", selection: $selectedLanguage) {
                        Text("English").tag("English")
                        Text("Spanish").tag("Spanish")
                        Text("French").tag("French")
                        Text("German").tag("German")
                        Text("Chinese").tag("Chinese")
                    }
                    .onChange(of: selectedLanguage) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "appLanguage")
                    }
                }
                
                // Data Management Section
                Section(header: Text("Data Management")) {
                    Button(action: {
                        showingClearDataAlert = true
                    }) {
                        Text("Clear Local Data")
                            .foregroundColor(.red)
                    }
                    
                    if networkMonitor.isConnected.value {
                        Button(action: {
                            syncData()
                        }) {
                            Text("Sync Data")
                        }
                    }
                }
                
                // Sign Out Section
                Section {
                    Button(action: {
                        showingSignOutAlert = true
                    }) {
                        Text("Sign Out")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert(isPresented: $showingSignOutAlert) {
                Alert(
                    title: Text("Sign Out"),
                    message: Text("Are you sure you want to sign out?"),
                    primaryButton: .destructive(Text("Sign Out")) {
                        handleSignOut()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: $showingClearDataAlert) {
                Alert(
                    title: Text("Clear Local Data"),
                    message: Text("This will remove all locally stored data. This action cannot be undone."),
                    primaryButton: .destructive(Text("Clear")) {
                        clearLocalData()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: $showingBiometricAlert) {
                Alert(
                    title: Text("Biometric Authentication"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(isPresented: $showingOfflineModeAlert) {
                Alert(
                    title: Text("Offline Mode"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func toggleBiometrics() {
        if biometricsEnabled {
            switch BiometricAuthManager.shared.enableBiometrics() {
            case .success:
                break
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingBiometricAlert = true
                biometricsEnabled = false
            }
        } else {
            BiometricAuthManager.shared.disableBiometrics()
        }
    }
    
    private func toggleOfflineMode() {
        guard networkMonitor.isConnected.value else {
            errorMessage = "Cannot change offline mode without network connection"
            showingOfflineModeAlert = true
            offlineEnabled = true
            return
        }
        
        viewModel.updateOfflineMode(enabled: offlineEnabled) { result in
            switch result {
            case .success:
                UserDefaults.standard.set(offlineEnabled, forKey: "offlineMode")
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingOfflineModeAlert = true
                offlineEnabled = !offlineEnabled
            }
        }
    }
    
    private func clearLocalData() {
        viewModel.clearUserData { result in
            switch result {
            case .success:
                // Reset local settings
                biometricsEnabled = false
                offlineEnabled = false
                isDarkMode = false
                selectedLanguage = "English"
                
                // Clear UserDefaults
                let domain = Bundle.main.bundleIdentifier!
                UserDefaults.standard.removePersistentDomain(forName: domain)
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
    
    private func handleSignOut() {
        viewModel.signOut { result in
            switch result {
            case .success:
                // Additional cleanup if needed
                break
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
    
    private func syncData() {
        // Implement data synchronization
        // This would typically be handled by the SyncService
    }
}

// MARK: - Preview Provider

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ProfileViewModel(
            authService: AuthenticationService(),
            collectionService: CollectionService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
                syncService: SyncService(
                    apiClient: APIClient(),
                    coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
                )
            ),
            secureStorage: SecureStorageManager(),
            errorHandler: ErrorHandler(),
            analyticsTracker: AnalyticsTracker()
        )
        
        SettingsView(viewModel: viewModel)
    }
}