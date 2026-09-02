import SetuIOSCore
import SwiftUI

// Admin 域的导航 destination。新增页面：在 AppRoute 加 case 后，把视图挂到对应域的此处——
// 无需再改 RootAppView（其 destination 会自动聚合各域解析器）。
extension RootAppView {

    @ViewBuilder
    func adminDestination(for route: AppRoute) -> some View {
        switch route {
        case .admin:
            AdminOverviewView(environment: environment)
        case .adminUsers:
            AdminUsersView(environment: environment)
        case .adminUserDetail(let id):
            AdminUserDetailView(environment: environment, userID: id)
        case .adminBlacklist:
            AdminBlacklistView(environment: environment)
        case .adminSystemStatus:
            SystemStatusView(environment: environment, title: "系统监控")
        case .adminMusicTokens:
            AdminMusicTokensView(environment: environment)
        case .adminImageInfo:
            AdminImageInfoView(environment: environment)
        case .adminImageDetail(let pid, let p):
            AdminImageInfoView(environment: environment, initialPID: pid, initialPage: p)
        case .adminImageDeleteRequests:
            AdminImageDeleteRequestsView(environment: environment)
        case .adminImageDeleteRequestDetail(let id):
            AdminImageDeleteRequestDetailView(environment: environment, requestID: id)
        case .adminImageAudit:
            AdminImageAuditView(environment: environment)
        case .adminGallerySubmissions:
            AdminGallerySubmissionsView(environment: environment)
        case .adminGallerySubmissionDetail(let id):
            AdminGallerySubmissionDetailView(environment: environment, batchID: id)
        case .adminOperationLogs:
            AdminOperationLogsView(environment: environment)
        case .adminOperationLogDetail(let id):
            AdminOperationLogDetailView(environment: environment, logID: id)
        case .adminPixivCrawl:
            AdminPixivCrawlView(environment: environment)
        case .adminPixivTask(let id):
            AdminPixivTaskDetailView(environment: environment, taskID: id)
        case .adminAiGenerations:
            AdminAiGenerationsView(environment: environment)
        case .adminAiWorkers:
            AdminAiWorkersView(environment: environment)
        case .adminAiReviews:
            AdminAiReviewsView(environment: environment)
        case .adminAiDeleteRequests:
            AdminAiDeleteRequestsView(environment: environment)
        default:
            EmptyView()
        }
    }
}
