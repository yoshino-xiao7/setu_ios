import SwiftUI

#if os(iOS)
import UIKit
#endif

struct SetuPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var cornerRadius: CGFloat = SetuRadius.md
    var pressedOpacity: Double = 0.72
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? SetuColor.brandSoft.opacity(0.18) : .clear)
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.16, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

private struct SetuTapFeedbackModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.simultaneousGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
            }
        )
        #else
        content
        #endif
    }
}

extension View {
    @ViewBuilder
    func setuButtonFeedback(cornerRadius: CGFloat = SetuRadius.md, haptic: Bool = false) -> some View {
        if haptic {
            buttonStyle(SetuPressableButtonStyle(cornerRadius: cornerRadius))
                .modifier(SetuTapFeedbackModifier())
        } else {
            buttonStyle(SetuPressableButtonStyle(cornerRadius: cornerRadius))
        }
    }
}
