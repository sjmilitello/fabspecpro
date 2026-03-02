import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Theme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.05, blue: 0.06),
            Color(red: 0.08, green: 0.09, blue: 0.11)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let panel = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let surface = Color(red: 0.13, green: 0.15, blue: 0.18)
    static let accent = Color(red: 0.12, green: 0.55, blue: 0.95)
    static let brandBlue = Color(red: 0.20, green: 0.58, blue: 0.96)
    static let brandGreenStart = Color(red: 0.67, green: 0.92, blue: 0.23)
    static let brandGreenEnd = Color(red: 0.20, green: 0.80, blue: 0.45)
    static let primaryText = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let secondaryText = Color(red: 0.62, green: 0.68, blue: 0.75)
    static let divider = Color(red: 0.23, green: 0.26, blue: 0.31)
}

struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
            content
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }
}

struct PillButtonStyle: ButtonStyle {
    var isProminent = false
    var textColor: Color? = nil
    var backgroundColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let resolvedBackground = backgroundColor ?? (isProminent ? Theme.accent : Theme.surface)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(textColor ?? (isProminent ? Theme.primaryText : Theme.accent))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(resolvedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.divider, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct LogoHeaderView: View {
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Theme.brandGreenStart, Theme.brandGreenEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("F")
                        .foregroundStyle(gradient)
                    Text("ab")
                        .foregroundStyle(Theme.brandBlue)
                    Text("S")
                        .foregroundStyle(gradient)
                    Text("pecPro")
                        .foregroundStyle(Theme.brandBlue)
                }
                .font(.system(size: 22, weight: .bold))
                Text("Cut List Builder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Keyboard Dismissal

#if canImport(UIKit)
extension View {
    /// Configures ScrollView to dismiss keyboard when scrolling
    func dismissKeyboardOnSwipe() -> some View {
        self.scrollDismissesKeyboard(.interactively)
    }
    
    /// Dismisses keyboard when tapping outside text fields
    func dismissKeyboardOnTap() -> some View {
        self.contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
    }
    
    /// Applies tap-to-dismiss keyboard to the entire view hierarchy
    func dismissKeyboardOnTapOutside() -> some View {
        self.onAppear {
            setupKeyboardDismissGesture()
        }
    }
}

/// Sets up a global tap gesture to dismiss keyboard when tapping outside text fields
private func setupKeyboardDismissGesture() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first else { return }
    
    // Check if we already added the gesture
    let gestureTag = 999
    if window.gestureRecognizers?.contains(where: { $0.view?.tag == gestureTag }) == true {
        return
    }
    
    let tapGesture = UITapGestureRecognizer(target: window, action: nil)
    tapGesture.requiresExclusiveTouchType = false
    tapGesture.cancelsTouchesInView = false
    tapGesture.delegate = KeyboardDismissGestureDelegate.shared
    window.addGestureRecognizer(tapGesture)
}

/// Gesture delegate that dismisses keyboard on any tap
class KeyboardDismissGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGestureDelegate()
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Dismiss keyboard on any touch
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        return false // Don't consume the touch
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
#else
extension View {
    func dismissKeyboardOnSwipe() -> some View {
        self // No-op on macOS
    }
    
    func dismissKeyboardOnTap() -> some View {
        self // No-op on macOS
    }
    
    func dismissKeyboardOnTapOutside() -> some View {
        self // No-op on macOS
    }
}
#endif
