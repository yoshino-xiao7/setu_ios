import Foundation
import XCTest

final class ColorContrastTests: XCTestCase {
    func testHeroGradientSupportsWhiteTextInLightAndDarkAppearances() throws {
        for asset in ["brand/gradientTop", "brand/gradientBottom"] {
            let light = try color(asset: asset, dark: false)
            let dark = try color(asset: asset, dark: true)

            XCTAssertGreaterThanOrEqual(contrast(light, .white), 4.5, "\(asset) light must support white body text")
            XCTAssertGreaterThanOrEqual(contrast(dark, .white), 4.5, "\(asset) dark must support white body text")
        }
    }

    func testBrandForegroundForWhiteControlsRemainsReadableInEveryAppearance() throws {
        let light = try color(asset: "brand/onLight", dark: false)
        let dark = try color(asset: "brand/onLight", dark: true)

        XCTAssertGreaterThanOrEqual(contrast(light, .white), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(dark, .white), 4.5)
    }

    func testSemanticStateForegroundsMeetBodyTextContrast() throws {
        for name in ["successForeground", "warningForeground", "dangerForeground", "infoForeground"] {
            let light = try color(asset: "state/\(name)", dark: false)
            let dark = try color(asset: "state/\(name)", dark: true)

            XCTAssertGreaterThanOrEqual(contrast(light, .white), 4.5, "\(name) light must remain readable on light surfaces")
            XCTAssertGreaterThanOrEqual(contrast(dark, .black), 4.5, "\(name) dark must remain readable on dark surfaces")
        }
    }

    func testSupportingTextMeetsBodyTextContrastOnAppSurfaces() throws {
        for textAsset in ["text/secondary", "text/tertiary", "brand/ink"] {
            for surfaceAsset in ["bg/surface", "bg/surfaceMuted"] {
                let lightText = try color(asset: textAsset, dark: false)
                let darkText = try color(asset: textAsset, dark: true)
                let lightSurface = try color(asset: surfaceAsset, dark: false)
                let darkSurface = try color(asset: surfaceAsset, dark: true)

                XCTAssertGreaterThanOrEqual(
                    contrast(lightText, lightSurface),
                    4.5,
                    "\(textAsset) light must remain readable on \(surfaceAsset)"
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(darkText, darkSurface),
                    4.5,
                    "\(textAsset) dark must remain readable on \(surfaceAsset)"
                )
            }
        }
    }

    private func color(asset: String, dark: Bool) throws -> RGBColor {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("Sources/SetuIOSApp/Resources/Assets.xcassets")
            .appendingPathComponent("\(asset).colorset/Contents.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colors = try XCTUnwrap(root["colors"] as? [[String: Any]])
        let entry = try XCTUnwrap(colors.first { entry in
            let appearances = entry["appearances"] as? [[String: String]]
            let isDark = appearances?.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" } == true
            return isDark == dark
        })
        let color = try XCTUnwrap(entry["color"] as? [String: Any])
        let components = try XCTUnwrap(color["components"] as? [String: String])
        return RGBColor(
            red: try component("red", in: components),
            green: try component("green", in: components),
            blue: try component("blue", in: components)
        )
    }

    private func component(_ name: String, in values: [String: String]) throws -> Double {
        let value = try XCTUnwrap(values[name])
        if value.hasPrefix("0x"), let byte = Int(value.dropFirst(2), radix: 16) {
            return Double(byte) / 255
        }
        return try XCTUnwrap(Double(value))
    }

    private func contrast(_ first: RGBColor, _ second: RGBColor) -> Double {
        let values = [first.luminance, second.luminance].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}

private struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double

    static let white = RGBColor(red: 1, green: 1, blue: 1)
    static let black = RGBColor(red: 0, green: 0, blue: 0)

    var luminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
