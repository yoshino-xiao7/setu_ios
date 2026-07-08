import SwiftUI

enum SetuAppAppearance {
    static func configure() {
        #if os(iOS)
        let tint = UIColor(named: "brand/pink") ?? UIColor.systemPink
        let textPrimary = UIColor(named: "text/primary") ?? UIColor.label
        let textTertiary = UIColor(named: "text/tertiary") ?? UIColor.tertiaryLabel
        let background = UIColor(named: "bg/base") ?? UIColor.systemGroupedBackground

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = tint
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: tint]
        tabAppearance.stackedLayoutAppearance.normal.iconColor = textTertiary
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: textTertiary]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = tint

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = background.withAlphaComponent(0.72)
        navAppearance.titleTextAttributes = [.foregroundColor: textPrimary]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: textPrimary]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = tint
        #endif
    }
}
