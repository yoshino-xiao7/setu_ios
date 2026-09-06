import SwiftUI

struct SetuFilterBar<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        let systemImage: String?
        let badge: Int?
        var id: Value { value }

        init(value: Value, title: String, systemImage: String? = nil, badge: Int? = nil) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
            self.badge = badge
        }
    }

    @Environment(\.setuBoardInset) private var boardInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let options: [Option]
    @Binding private var selection: Value
    private let accessibilityTitle: String

    init(options: [Option], selection: Binding<Value>, accessibilityTitle: String = "筛选") {
        self.options = options
        self._selection = selection
        self.accessibilityTitle = accessibilityTitle
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SetuSpacing.sm) {
                ForEach(options) { option in
                    Button {
                        withAnimation(SetuMotion.resolved(SetuMotion.gentle, reduceMotion: reduceMotion)) {
                            selection = option.value
                        }
                    } label: {
                        Label {
                            Text(option.title)
                            if let badge = option.badge { Text("\(badge)").monospacedDigit() }
                        } icon: {
                            if let systemImage = option.systemImage { Image(systemName: systemImage) }
                        }
                        .font(SetuTypography.label)
                        .padding(.horizontal, SetuSpacing.md)
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(selection == option.value ? SetuColor.brandInk : SetuColor.textSecondary)
                        .background(selection == option.value ? SetuColor.brandSoft : SetuColor.surface,
                                    in: Capsule())
                        .overlay { Capsule().stroke(SetuColor.separator, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, boardInset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .padding(.horizontal, -boardInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}
