//
// ErrorView.swift
// WildlifeSafari
//
// A reusable SwiftUI view component for displaying error states with 
// comprehensive accessibility support and haptic feedback.
//
// Version: 1.0
// SwiftUI version: Latest
//

import SwiftUI // Latest

/// A view component for displaying error states with retry functionality
public struct ErrorView: View {
    // MARK: - Properties
    
    private let message: String
    private let retryAction: (() -> Void)?
    private let enableHaptics: Bool
    private let feedbackGenerator: UIImpactFeedbackGenerator
    
    // MARK: - Animation Properties
    private let animation = Animation.easeInOut(duration: 0.3)
    private let transition = AnyTransition.opacity.combined(with: .scale(scale: 0.95))
    
    // MARK: - Initialization
    
    /// Creates a new ErrorView instance
    /// - Parameters:
    ///   - message: The error message to display
    ///   - retryAction: Optional closure to execute when retry is tapped
    ///   - enableHaptics: Whether to enable haptic feedback (default: true)
    public init(
        message: String,
        retryAction: (() -> Void)? = nil,
        enableHaptics: Bool = true
    ) {
        self.message = message
        self.retryAction = retryAction
        self.enableHaptics = enableHaptics
        self.feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        
        // Prepare haptic feedback generator
        if enableHaptics {
            feedbackGenerator.prepare()
        }
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 16) {
            // Error Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.error)
                .accessibility(hidden: true)
            
            // Error Message
            Text(message)
                .font(.body)
                .foregroundColor(.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            
            // Retry Button
            if let retryAction = retryAction {
                CustomButton(
                    "Try Again",
                    style: .primary
                ) {
                    triggerHapticFeedback()
                    retryAction()
                }
                .padding(.top, 8)
            }
        }
        .standardPadding(multiplier: 2)
        .cardStyle(elevation: 4)
        .transition(transition)
        .animation(animation, value: message)
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error")
        .accessibilityValue(message)
        .accessibilityAddTraits(.isAlert)
        .accessibilityAction(named: "Try Again") {
            if let retryAction = retryAction {
                triggerHapticFeedback()
                retryAction()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Triggers haptic feedback if enabled
    private func triggerHapticFeedback() {
        guard enableHaptics else { return }
        feedbackGenerator.impactOccurred()
    }
}

// MARK: - Preview Provider

#if DEBUG
struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Basic error without retry
            ErrorView(message: "Unable to connect to the server")
                .previewDisplayName("Basic Error")
            
            // Error with retry action
            ErrorView(
                message: "Species detection failed. Please try again.",
                retryAction: { print("Retry tapped") }
            )
            .previewDisplayName("Error with Retry")
            
            // Dark mode preview
            ErrorView(
                message: "Network connection lost",
                retryAction: { print("Retry tapped") }
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif