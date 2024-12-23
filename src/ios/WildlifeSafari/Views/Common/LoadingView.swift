//
// LoadingView.swift
// WildlifeSafari
//
// A reusable SwiftUI loading indicator component with accessibility support
// and design system compliance.
//
// Version: 1.0
// SwiftUI version: Latest
//

import SwiftUI

/// A customizable loading indicator view that provides visual feedback during async operations
/// with enhanced accessibility support and design system compliance.
public struct LoadingView: View {
    
    // MARK: - Properties
    
    /// Optional message to display below the loading spinner
    private let message: String?
    
    /// Color of the loading spinner
    private let spinnerColor: Color
    
    /// Size of the loading spinner
    private let size: CGFloat
    
    /// Controls the animation state of the spinner
    @State private var isAnimating: Bool = true
    
    /// Controls the fade-in animation of the view
    @State private var opacity: Double = 0.0
    
    // MARK: - Initialization
    
    /// Creates a new loading view with customizable appearance.
    /// - Parameters:
    ///   - message: Optional text to display below the spinner
    ///   - spinnerColor: Color of the loading spinner (defaults to accent color)
    ///   - size: Size of the loading spinner (defaults to 44.0 for accessibility)
    public init(
        message: String? = nil,
        spinnerColor: Color = .accentColor,
        size: CGFloat = 44.0
    ) {
        self.message = message
        self.spinnerColor = spinnerColor
        self.size = size
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // Loading spinner
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: spinnerColor))
                .scaleEffect(1.2)
                .frame(width: size, height: size)
            
            // Optional message
            if let message = message {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .dynamicTypeSize(.large...(.accessibility3))
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .adaptiveBackground()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1.0
            }
        }
        .makeAccessible()
        .standardPadding(multiplier: 1.5)
    }
    
    // MARK: - Accessibility
    
    /// Applies accessibility configurations to the loading view
    private func makeAccessible() -> some View {
        let accessibilityLabel = message ?? "Loading"
        
        return self
            .accessibilityLabel(accessibilityLabel)
            .accessibilityTraits(.updatesFrequently)
            .accessibilityAddTraits(.isStatusElement)
            .accessibilityIdentifier("LoadingView")
            .accessibilityAnnouncement("Loading in progress")
    }
}

// MARK: - View Modifier

public extension View {
    /// Adds a loading message overlay to any view
    /// - Parameter message: The message to display in the loading view
    /// - Returns: A modified view with a loading overlay
    func withLoadingMessage(_ message: String) -> some View {
        ZStack {
            self
            LoadingView(message: message)
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Basic loading view
            LoadingView()
                .previewDisplayName("Default Loading")
            
            // Loading view with message
            LoadingView(message: "Identifying species...")
                .previewDisplayName("With Message")
            
            // Loading view with custom color
            LoadingView(
                message: "Processing image...",
                spinnerColor: .green,
                size: 60
            )
            .previewDisplayName("Custom Style")
            
            // Dark mode preview
            LoadingView(message: "Loading...")
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
#endif