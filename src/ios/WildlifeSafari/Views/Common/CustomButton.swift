//
// CustomButton.swift
// WildlifeSafari
//
// A reusable SwiftUI button component implementing the Wildlife Safari app's
// design system with comprehensive accessibility support and interaction patterns.
//
// Version: 1.0
// SwiftUI version: Latest
//

import SwiftUI // Latest

/// Enumeration defining available button styles with color management
public enum ButtonStyle {
    case primary
    case secondary
    case outline
    
    /// Returns the appropriate background color with dark mode support
    var backgroundColor: Color {
        switch self {
        case .primary:
            return Color.primary
        case .secondary:
            return Color.secondary
        case .outline:
            return Color.clear
        }
    }
    
    /// Returns the appropriate text color with WCAG AAA compliance
    var foregroundColor: Color {
        switch self {
        case .primary, .secondary:
            return Color.adaptiveColor(light: .white, dark: .white)
        case .outline:
            return Color.primary
        }
    }
    
    /// Returns appropriate border configuration for outline style
    var border: (width: CGFloat, color: Color)? {
        switch self {
        case .outline:
            return (width: 2, color: Color.primary)
        default:
            return nil
        }
    }
}

/// A customizable button component that follows the app's design system
public struct CustomButton: View {
    // MARK: - Properties
    
    private let title: String
    private let style: ButtonStyle
    private let isLoading: Bool
    private let action: () -> Void
    
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let minimumSize = CGSize(width: 44, height: 44) // WCAG touch target requirement
    
    // MARK: - Initialization
    
    /// Creates a new CustomButton instance with specified configuration
    /// - Parameters:
    ///   - title: Button text to display
    ///   - style: Visual style of the button (default: .primary)
    ///   - isLoading: Loading state flag (default: false)
    ///   - action: Closure to execute when button is tapped
    public init(
        _ title: String,
        style: ButtonStyle = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button(action: {
            hapticFeedback.impactOccurred()
            action()
        }) {
            ZStack {
                // Button background
                RoundedRectangle(cornerRadius: 8)
                    .fill(style.backgroundColor)
                    .if(style == .outline) { view in
                        view.strokeBorder(style.border?.color ?? .clear,
                                        lineWidth: style.border?.width ?? 0)
                    }
                
                // Button content
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                            .scaleEffect(0.8)
                    }
                    
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundColor(style.foregroundColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        .standardElevation(elevation: style == .outline ? 0 : 2)
        .opacity(isLoading ? 0.7 : 1.0)
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .combine)
        .if(isLoading) { view in
            view.accessibilityValue("Loading")
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - View Extension Helper

private extension View {
    /// Conditional modifier application
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CustomButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CustomButton("Primary Button", style: .primary) {}
            CustomButton("Secondary Button", style: .secondary) {}
            CustomButton("Outline Button", style: .outline) {}
            CustomButton("Loading Button", isLoading: true) {}
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.light)
        
        VStack(spacing: 20) {
            CustomButton("Primary Button", style: .primary) {}
            CustomButton("Secondary Button", style: .secondary) {}
            CustomButton("Outline Button", style: .outline) {}
            CustomButton("Loading Button", isLoading: true) {}
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
    }
}
#endif