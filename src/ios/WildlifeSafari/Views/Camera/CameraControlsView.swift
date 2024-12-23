//
// CameraControlsView.swift
// WildlifeSafari
//
// Accessible camera control interface with real-time mode switching,
// flash control, capture functionality, and gallery access.
//

import SwiftUI // Latest - UI framework for view implementation

// MARK: - Constants

private enum Constants {
    static let buttonSize: CGFloat = 60
    static let iconSize: CGFloat = 24
    static let animationDuration: CGFloat = 0.3
    static let hapticIntensity: CGFloat = 0.5
    static let spacing: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let buttonOpacity: CGFloat = 0.8
    static let captureButtonScale: CGFloat = 1.2
}

// MARK: - Camera Controls View

@available(iOS 14.0, *)
@MainActor
public struct CameraControlsView: View {
    // MARK: - Properties
    
    @Binding private var detectionMode: DetectionMode
    @Binding private var flashMode: FlashMode
    @Binding private var isCapturing: Bool
    
    @State private var isProcessing: Bool = false
    @State private var buttonScale: CGFloat = 1.0
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - Initialization
    
    public init(
        detectionMode: Binding<DetectionMode>,
        flashMode: Binding<FlashMode>,
        isCapturing: Binding<Bool>
    ) {
        self._detectionMode = detectionMode
        self._flashMode = flashMode
        self._isCapturing = isCapturing
        
        // Initialize haptic feedback
        feedbackGenerator.prepare()
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: Constants.spacing) {
            // Mode Selection Buttons
            HStack(spacing: Constants.spacing) {
                modeSelectionButton(mode: .wildlife)
                modeSelectionButton(mode: .fossil)
            }
            .padding(.top)
            
            Spacer()
            
            // Bottom Control Bar
            HStack(spacing: Constants.spacing * 2) {
                // Gallery Button
                Button {
                    // Gallery access implementation
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Constants.iconSize, height: Constants.iconSize)
                }
                .accessibilityLabel("Open Gallery")
                .accessibilityHint("View captured photos")
                
                // Capture Button
                captureButton
                
                // Flash Mode Button
                flashButton
            }
            .padding(.bottom, Constants.spacing * 2)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Subviews
    
    private var captureButton: some View {
        Button {
            handleCapture()
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: Constants.buttonSize - 8, height: Constants.buttonSize - 8)
                )
                .overlay(
                    Group {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        }
                    }
                )
        }
        .scaleEffect(buttonScale)
        .animation(.spring(response: 0.3), value: buttonScale)
        .accessibilityLabel("Capture Photo")
        .accessibilityHint(isProcessing ? "Processing capture" : "Take a photo")
        .disabled(isProcessing)
    }
    
    private var flashButton: some View {
        Button {
            cycleFlashMode()
        } label: {
            Image(systemName: flashModeIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundColor(.white)
        }
        .accessibilityLabel("Flash Mode")
        .accessibilityValue(flashModeLabel)
        .accessibilityHint("Cycle through flash modes")
    }
    
    private func modeSelectionButton(mode: DetectionMode) -> some View {
        Button {
            switchDetectionMode(to: mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: modeIcon(for: mode))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                
                Text(modeName(for: mode))
                    .font(.caption)
            }
            .foregroundColor(detectionMode == mode ? .white : .white.opacity(0.6))
            .padding(.horizontal, Constants.spacing)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(detectionMode == mode ? Color.white.opacity(0.3) : Color.clear)
            )
        }
        .accessibilityLabel("\(modeName(for: mode)) Mode")
        .accessibilityValue(detectionMode == mode ? "Selected" : "")
        .accessibilityHint("Switch to \(modeName(for: mode)) detection")
    }
    
    // MARK: - Helper Methods
    
    private func handleCapture() {
        guard !isProcessing else { return }
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred(intensity: Constants.hapticIntensity)
        
        // Animate button
        withAnimation(.spring(response: 0.2)) {
            buttonScale = Constants.captureButtonScale
        }
        
        // Reset scale after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2)) {
                buttonScale = 1.0
            }
        }
        
        // Trigger capture
        isCapturing = true
        isProcessing = true
        
        // Reset processing state after delay (actual implementation would be based on capture completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isProcessing = false
            isCapturing = false
        }
    }
    
    private func switchDetectionMode(to mode: DetectionMode) {
        guard detectionMode != mode else { return }
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred(intensity: Constants.hapticIntensity)
        
        withAnimation(.easeInOut(duration: Constants.animationDuration)) {
            detectionMode = mode
        }
    }
    
    private func cycleFlashMode() {
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred(intensity: Constants.hapticIntensity)
        
        // Cycle through flash modes
        withAnimation {
            switch flashMode {
            case .auto:
                flashMode = .on
            case .on:
                flashMode = .off
            case .off:
                flashMode = .auto
            }
        }
    }
    
    private func modeIcon(for mode: DetectionMode) -> String {
        switch mode {
        case .wildlife:
            return "camera.metering.center.weighted"
        case .fossil:
            return "camera.metering.spot"
        }
    }
    
    private func modeName(for mode: DetectionMode) -> String {
        switch mode {
        case .wildlife:
            return "Wildlife"
        case .fossil:
            return "Fossil"
        }
    }
    
    private var flashModeIcon: String {
        switch flashMode {
        case .auto:
            return "bolt.badge.a"
        case .on:
            return "bolt.fill"
        case .off:
            return "bolt.slash.fill"
        }
    }
    
    private var flashModeLabel: String {
        switch flashMode {
        case .auto:
            return "Flash Auto"
        case .on:
            return "Flash On"
        case .off:
            return "Flash Off"
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
@available(iOS 14.0, *)
struct CameraControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            CameraControlsView(
                detectionMode: .constant(.wildlife),
                flashMode: .constant(.auto),
                isCapturing: .constant(false)
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
#endif