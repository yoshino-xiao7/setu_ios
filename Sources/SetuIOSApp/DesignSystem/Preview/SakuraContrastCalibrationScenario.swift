#if DEBUG
import SwiftUI

/// Offline calibration only. Compare background construction and the actual
/// primary button without changing production colors, modifiers, or audit rules.
struct SakuraContrastCalibrationScenario: View {
    @State private var index = 0
    private let sample = "对比度 Aa 123"
    private let names = ["A-black-white", "B-solid-plum", "C-identical-gradient",
                         "D-hero-gradient", "E-primary-button", "F-primary-in-dock", "N-negative-control"]
    private let plum = Color(red: 122.0 / 255, green: 51.0 / 255, blue: 85.0 / 255)
    private var isDark: Bool { ProcessInfo.processInfo.arguments.contains("Dark") }

    var body: some View {
        VStack(spacing: 0) {
            Text(names[index])
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("sakura.contrast.current")
                .dynamicTypeSize(.large)
            Spacer(minLength: 24)
            probe
                .id(index)
                .accessibilityIdentifier("sakura.contrast.probe")
                .padding(.horizontal, SetuSpacing.lg)
            Spacer(minLength: 24)
            Button { index = (index + 1) % names.count } label: {
                Text("下一项")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sakura.contrast.next")
                .dynamicTypeSize(.large)
                .padding(16)
        }
        // Harness labels stay at a known 21:1. The tested probe overrides these
        // foreground/background colors and uses the requested AX1 text size.
        .foregroundStyle(isDark ? Color.white : Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color.black : Color.white)
        .dynamicTypeSize(.accessibility1)
        .preferredColorScheme(isDark ? .dark : .light)
    }

    @ViewBuilder private var probe: some View {
        switch index {
        case 0:
            label.background(Color.black, in: Capsule())
        case 1:
            label.background(plum, in: Capsule())
        case 2:
            label.background(LinearGradient(colors: [plum, plum], startPoint: .topLeading,
                                            endPoint: .bottomTrailing), in: Capsule())
        case 3:
            label.background(SetuColor.heroGradient, in: Capsule())
        case 4:
            SetuPrimaryButton(action: {}) { Text(sample) }
        case 5:
            SetuActionDock {
                SetuPrimaryButton(action: {}) { Text(sample) }
            }
        default:
            label.background(Color(red: 221.0 / 255, green: 221.0 / 255, blue: 221.0 / 255), in: Capsule())
        }
    }

    private var label: some View {
        Text(sample)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, SetuSpacing.lg)
    }
}
#endif
