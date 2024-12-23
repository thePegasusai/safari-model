//
// EmptyStateView.swift
// WildlifeSafari
//
// A reusable SwiftUI view component for displaying empty states with customizable
// content, animations, and accessibility support.
//
// Version: 1.0
// SwiftUI version: Latest
//

import SwiftUI

/// A customizable empty state view that displays an image, title, message, and optional action button.
/// Implements design system standards and accessibility requirements.
public struct EmptyStateView: View {
    // MARK: - Properties
    
    private let title: String
    private let message: String
    private let imageName: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    
    private let transitionAnimation: Animation
    private let feedbackGenerator: UIImpactFeedbackGenerator
    
    // MARK: - Initialization
    
    /// Creates a new empty state view with the specified content.
    /// - Parameters:
    ///   - title: The main title text to display
    ///   - message: The descriptive message text
    ///   - imageName: Optional SF Symbol or asset name for the illustration
    ///   - actionTitle: Optional text for the action button
    ///   - action: Optional closure to execute when the action button is tapped
    public init(
        title: String,
        message: String,
        imageName: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.imageName = imageName
        self.actionTitle = actionTitle
        self.action = action
        
        // Initialize animation with natural easing
        self.transitionAnimation = .easeInOut(duration: 0.3)
        
        // Initialize haptic feedback generator
        self.feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        self.feedbackGenerator.prepare()
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(alignment: .center, spacing: 16) {
            // Optional image
            if let imageName = imageName {
                Image(systemName: imageName)
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                    .imageScale(.large)
                    .padding(.bottom, 8)
                    .accessibility(hidden: true)
            }
            
            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            
            // Message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            // Optional action button
            if let actionTitle = actionTitle, let action = action {
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    action()
                }) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                .accessibleTouchTarget()
                .padding(.top, 8)
            }
        }
        .standardPadding(multiplier: 3) // Apply 24pt padding (8 * 3)
        .cardStyle(elevation: 1) // Apply subtle elevation
        .animation(transitionAnimation, value: imageName)
        .animation(transitionAnimation, value: title)
        .animation(transitionAnimation, value: message)
        
        // Configure accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityHint(actionTitle != nil ? "Double tap to \(actionTitle!.lowercased())" : nil)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct EmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Basic empty state
            EmptyStateView(
                title: "No Wildlife Spotted",
                message: "Point your camera at wildlife to start detecting species.",
                imageName: "camera.fill"
            )
            
            // Empty state with action
            EmptyStateView(
                title: "Collection Empty",
                message: "Start exploring to add species to your collection.",
                imageName: "square.stack.3d.up",
                actionTitle: "Start Exploring",
                action: { }
            )
            .preferredColorScheme(.dark)
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif