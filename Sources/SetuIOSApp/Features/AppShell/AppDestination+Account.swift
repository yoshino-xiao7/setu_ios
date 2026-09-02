import SetuIOSCore
import SwiftUI

// Account 域的导航 destination。新增页面：在 AppRoute 加 case 后，把视图挂到对应域的此处——
// 无需再改 RootAppView（其 destination 会自动聚合各域解析器）。
extension RootAppView {

    @ViewBuilder
    func accountDestination(for route: AppRoute) -> some View {
        switch route {
        case .account:
            AccountView(environment: environment)
        case .profile:
            ProfileView(environment: environment)
        case .docs:
            StaticInfoView(environment: environment, kind: .docs)
        case .about:
            StaticInfoView(environment: environment, kind: .about)
        case .privacy:
            StaticInfoView(environment: environment, kind: .privacy)
        case .terms:
            StaticInfoView(environment: environment, kind: .terms)
        case .passkeys:
            PasskeyListView(environment: environment)
        case .points:
            PointsCallView(environment: environment)
        case .apiKeys:
            ApiKeyListView(environment: environment)
        case .pointsLogs:
            PointsLogsView(environment: environment)
        case .notifications:
            NotificationsView(environment: environment)
        case .qqBinding:
            QqBindingView(environment: environment)
        case .security:
            SecuritySettingsView(environment: environment)
        default:
            EmptyView()
        }
    }
}
