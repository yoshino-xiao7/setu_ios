import SetuIOSCore
import SwiftUI

// AI 域的导航 destination。新增页面：在 AppRoute 加 case 后，把视图挂到对应域的此处——
// 无需再改 RootAppView（其 destination 会自动聚合各域解析器）。
extension RootAppView {

    @ViewBuilder
    func aiDestination(for route: AppRoute) -> some View {
        switch route {
        case .aiDraw:
            AiDrawView(environment: environment)
        case .aiAssets:
            AiAssetBrowserView(environment: environment)
        case .aiHistory:
            AiHistoryView(environment: environment)
        case .aiDeleteRequests:
            AiDeleteRequestsView(environment: environment)
        case .aiGenerationDetail(let id):
            AiGenerationDetailView(environment: environment, jobID: id)
        case .publicAiWork(let work):
            PublicAiWorkDetailView(environment: environment, work: work)
        case .aiSquare:
            AiSquareView(environment: environment)
        default:
            EmptyView()
        }
    }
}
