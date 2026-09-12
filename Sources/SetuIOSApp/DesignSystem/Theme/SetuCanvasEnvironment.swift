import SwiftUI

private struct SetuCanvasLayoutKey: EnvironmentKey {
    static var defaultValue: SetuCanvasLayout { SetuCanvasLayout(size: .zero) }
}

extension EnvironmentValues {
    var setuCanvas: SetuCanvasLayout {
        get { self[SetuCanvasLayoutKey.self] }
        set { self[SetuCanvasLayoutKey.self] = newValue }
    }
}

extension View {
    func setuCanvas(_ canvas: SetuCanvasLayout) -> some View {
        environment(\.setuCanvas, canvas)
    }

    func setuReadableContent() -> some View {
        modifier(SetuReadableContentModifier())
    }
}

private struct SetuReadableContentModifier: ViewModifier {
    @Environment(\.setuCanvas) private var canvas

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: canvas.readableMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
