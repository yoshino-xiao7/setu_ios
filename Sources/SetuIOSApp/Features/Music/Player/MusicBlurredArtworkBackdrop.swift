import SetuIOSCore
import SwiftUI

struct MusicBlurredArtworkBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let coverURLString: String?
    let accentColor: Color?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 1. Ambient fallback base
                LinearGradient(
                    colors: [
                        (accentColor ?? SetuColor.brandSoft).opacity(colorScheme == .dark ? 0.35 : 0.5),
                        SetuColor.bgBase,
                        (accentColor ?? SetuColor.brandPink).opacity(colorScheme == .dark ? 0.2 : 0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 2. High-blur Album Artwork Layer
                if let coverURLString, !coverURLString.isEmpty {
                    MusicArtworkView(
                        urlString: coverURLString,
                        width: proxy.size.width * 1.3,
                        height: proxy.size.height * 1.3,
                        cornerRadius: 0,
                        artworkSize: .lockScreen
                    )
                    .blur(radius: 68)
                    .scaleEffect(1.25)
                    .clipped()
                }

                // 3. Dark atmospheric tint overlay (NetEase signature deep contrast)
                Color.black.opacity(colorScheme == .dark ? 0.52 : 0.4)

                // 4. Subtle top and bottom vignette gradients
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        Color.clear,
                        Color.black.opacity(0.48)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}
