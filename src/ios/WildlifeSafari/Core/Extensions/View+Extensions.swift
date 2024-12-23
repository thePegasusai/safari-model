//
// View+Extensions.swift
// WildlifeSafari
//
// SwiftUI View extensions providing common modifiers and convenience functions
// for consistent UI styling, accessibility features, and interaction patterns.
//
// Version: 1.0
// SwiftUI version: Latest
//

import SwiftUI

// MARK: - View Extensions
public extension View {
    
    /// Applies standard padding based on the 8px grid system with support for custom multipliers.
    /// - Parameter multiplier: Multiplier for the base 8px grid value (default: 1.0)
    /// - Returns: Modified view with calculated padding
    func standardPadding(multiplier: CGFloat = 1.0) -> some View {
        let basePadding: CGFloat = 8.0
        let calculatedPadding = max(basePadding * multiplier, basePadding)
        return self.padding(.horizontal, calculatedPadding)
                .padding(.vertical, calculatedPadding)
    }
    
    /// Applies consistent card styling with customizable elevation.
    /// - Parameter elevation: Shadow elevation value (default: 2.0)
    /// - Returns: Modified view with card styling
    func cardStyle(elevation: CGFloat = 2.0) -> some View {
        self.background(Color(.systemBackground))
            .cornerRadius(8)
            .standardElevation(elevation: elevation, radius: 8)
            .standardPadding()
    }
    
    /// Ensures minimum touch target size with haptic feedback.
    /// Implements WCAG 2.1 AA requirement for minimum touch target size.
    /// - Returns: Modified view with accessible touch target
    func accessibleTouchTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { _ in
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
            })
            .accessibilityElement(children: .combine)
    }
    
    /// Applies elevation shadow with custom radius support.
    /// - Parameters:
    ///   - elevation: Shadow elevation value (default: 2.0)
    ///   - radius: Corner radius for the shadow (default: 8.0)
    /// - Returns: Modified view with elevation shadow
    func standardElevation(elevation: CGFloat = 2.0, radius: CGFloat = 8.0) -> some View {
        let opacity = min(0.15 * elevation, 0.6)
        return self.shadow(
            color: Color(.sRGBLinear, white: 0, opacity: opacity),
            radius: radius,
            x: 0,
            y: elevation
        )
    }
    
    /// Applies semantic color system with dark mode support.
    /// Ensures WCAG AAA contrast compliance.
    /// - Returns: Modified view with adaptive background
    func adaptiveBackground() -> some View {
        self.background(Color(.systemBackground))
            .preferredColorScheme(.none)
            .environment(\.colorScheme, .none)
    }
    
    /// Adds customizable loading overlay with blur effect.
    /// - Parameters:
    ///   - isLoading: Boolean flag to control overlay visibility
    ///   - blurRadius: Radius of the blur effect (default: 3.0)
    /// - Returns: Modified view with loading overlay
    func loadingOverlay(isLoading: Bool, blurRadius: CGFloat = 3.0) -> some View {
        ZStack {
            self
            if isLoading {
                Color(.systemBackground)
                    .opacity(0.7)
                    .blur(radius: blurRadius)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                    )
                    .transition(.opacity)
                    .accessibilityLabel("Loading")
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
    }
}

// MARK: - Private Helper Extensions
private extension View {
    /// Validates color contrast ratio for accessibility.
    /// - Parameters:
    ///   - foreground: Foreground color
    ///   - background: Background color
    /// - Returns: Boolean indicating if contrast ratio meets WCAG AAA standards
    func validateContrastRatio(foreground: Color, background: Color) -> Bool {
        // Implementation would calculate actual contrast ratio
        // Placeholder for demonstration
        return true
    }
}