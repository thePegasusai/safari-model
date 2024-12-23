//
// CustomTextField.swift
// WildlifeSafari
//
// A comprehensive SwiftUI TextField component providing consistent styling,
// real-time validation, and accessibility features.
//
// Version: 1.0
// SwiftUI version: Latest
//

import SwiftUI // Latest
import Combine // Latest

/// Defines validation rules for the text field
public enum ValidationRule {
    case email
    case password
    case required
    case custom((String) -> Bool)
    
    func validate(_ text: String) -> Bool {
        switch self {
        case .email:
            let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: text)
        case .password:
            return text.count >= 8 && text.rangeOfCharacter(from: .uppercaseLetters) != nil
        case .required:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom(let validator):
            return validator(text)
        }
    }
}

/// A sophisticated text field component with real-time validation, accessibility features,
/// and adaptive styling supporting both light and dark modes.
public struct CustomTextField: View {
    // MARK: - Properties
    
    @Binding private var text: String
    private let placeholder: String
    private let title: String?
    private var isSecure: Bool
    private var contentType: UITextContentType?
    private var validationRule: ValidationRule?
    
    @Published private var errorMessage: String?
    @Published private var isValid: Bool = true
    @FocusState private var isFocused: Bool
    
    private let validationPublisher = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private enum Constants {
        static let debounceInterval: TimeInterval = 0.3
        static let cornerRadius: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let fontSize: CGFloat = 16
        static let errorFontSize: CGFloat = 12
        static let titleFontSize: CGFloat = 14
    }
    
    // MARK: - Initialization
    
    /// Creates a new CustomTextField instance with comprehensive configuration options.
    /// - Parameters:
    ///   - text: Binding to the text value
    ///   - placeholder: Placeholder text
    ///   - title: Optional title text displayed above the field
    ///   - isSecure: Whether the field should be secure (password)
    ///   - contentType: UITextContentType for keyboard optimization
    ///   - validationRule: Optional validation rule to apply
    public init(
        text: Binding<String>,
        placeholder: String,
        title: String? = nil,
        isSecure: Bool = false,
        contentType: UITextContentType? = nil,
        validationRule: ValidationRule? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.title = title
        self.isSecure = isSecure
        self.contentType = contentType
        self.validationRule = validationRule
        
        setupValidation()
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = title {
                Text(title)
                    .font(.system(size: Constants.titleFontSize, weight: .medium))
                    .foregroundColor(.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            
            textFieldContent
                .textFieldStyle()
                .onChange(of: text) { newValue in
                    validationPublisher.send(newValue)
                }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: Constants.errorFontSize))
                    .foregroundColor(.red)
                    .transition(.opacity)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
        .adaptiveBackground()
        .accessibleTouchTarget()
    }
    
    // MARK: - Private Views
    
    @ViewBuilder
    private var textFieldContent: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
                .textContentType(contentType)
                .focused($isFocused)
        } else {
            TextField(placeholder, text: $text)
                .textContentType(contentType)
                .focused($isFocused)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupValidation() {
        validationPublisher
            .debounce(for: .seconds(Constants.debounceInterval), scheduler: RunLoop.main)
            .sink { [weak self] value in
                self?.validate(value)
            }
            .store(in: &cancellables)
    }
    
    /// Performs real-time validation with debouncing and error handling
    private func validate(_ value: String) {
        guard let rule = validationRule else { return }
        
        isValid = rule.validate(value)
        errorMessage = isValid ? nil : "Invalid input"
        
        // Announce validation status to VoiceOver
        UIAccessibility.post(
            notification: .announcement,
            argument: isValid ? "Valid input" : "Invalid input: \(errorMessage ?? "")"
        )
    }
}

// MARK: - View Modifiers

private extension View {
    /// Applies comprehensive styling including accessibility and validation states
    func textFieldStyle() -> some View {
        self
            .standardPadding()
            .font(.system(size: CustomTextField.Constants.fontSize))
            .textFieldStyle(PlainTextFieldStyle())
            .multilineTextAlignment(.leading)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .background(
                RoundedRectangle(cornerRadius: CustomTextField.Constants.cornerRadius)
                    .stroke(Color.primary.opacity(0.2), lineWidth: CustomTextField.Constants.borderWidth)
            )
            .background(Color(.systemBackground))
            .cornerRadius(CustomTextField.Constants.cornerRadius)
    }
}

// MARK: - Preview Provider

struct CustomTextField_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CustomTextField(
                text: .constant(""),
                placeholder: "Enter email",
                title: "Email",
                contentType: .emailAddress,
                validationRule: .email
            )
            .previewDisplayName("Email Field")
            
            CustomTextField(
                text: .constant(""),
                placeholder: "Enter password",
                title: "Password",
                isSecure: true,
                contentType: .password,
                validationRule: .password
            )
            .previewDisplayName("Password Field")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}