import SwiftUI
#if os(iOS)
import AVKit

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor(SetuColor.brandInk)
        view.activeTintColor = UIColor(SetuColor.brandPink)
        view.accessibilityLabel = "AirPlay 音频输出"
        view.accessibilityIdentifier = "music.airplay"
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
struct AirPlayRouteButton: View {
    var body: some View { EmptyView() }
}
#endif
