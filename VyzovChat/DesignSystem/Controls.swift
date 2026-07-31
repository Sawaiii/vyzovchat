import SwiftUI

// MARK: - Основная кнопка

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: Spacing.xs) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    if let icon { Image(systemName: icon) }
                    Text(title)
                }
            }
            .font(Typography.button)
            .foregroundStyle(Theme.textOnAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.accentGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(0.45), radius: 16, y: 8)
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isLoading)
        .opacity((!isEnabled || isLoading) ? 0.55 : 1)
    }
}

// MARK: - Вторичная (стеклянная) кнопка

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: Spacing.xs) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(Typography.button)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .glass(cornerRadius: 27, elevated: false)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Эффект «нажатия» — лёгкое сжатие для тактильной обратной связи.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

// MARK: - Стеклянное текстовое поле

struct GlassField: View {
    let placeholder: String
    var icon: String? = nil
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var textContentType: UITextContentType? = nil
    @Binding var text: String

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(focused ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22)
            }

            Group {
                if isSecure && !revealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(textContentType)
            .focused($focused)
            .font(Typography.body)

            if isSecure {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: 54)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.8) : .white.opacity(0.08),
                              lineWidth: focused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}
