import SetuIOSCore
import SwiftUI

// Content 域的导航 destination。新增页面：在 AppRoute 加 case 后，把视图挂到对应域的此处——
// 无需再改 RootAppView（其 destination 会自动聚合各域解析器）。
extension RootAppView {

    @ViewBuilder
    func contentDestination(for route: AppRoute) -> some View {
        switch route {
        case .favorites:
            FavoriteListView(environment: environment)
        case .imageDeleteRequests:
            ImageDeleteRequestsView(environment: environment)
        case .imageDeleteRequestDetail(let id):
            ImageDeleteRequestDetailView(environment: environment, requestID: id)
        case .collections:
            CollectionListView(environment: environment)
        case .collectionDetail(let id):
            CollectionDetailView(environment: environment, collectionID: id)
        case .collectionSquare:
            CollectionSquareView(environment: environment)
        case .publicCollectionDetail(let id):
            PublicCollectionDetailView(environment: environment, collectionID: id)
        case .publicUserProfile(let userID):
            PublicUserProfileView(environment: environment, userID: userID)
        case .galleryUploads:
            GalleryUploadBatchesView(environment: environment)
        case .galleryUploadDetail(let id):
            GalleryUploadDetailView(environment: environment, batchID: id)
        case .imageSwipe:
            RandomImageSwipeView(environment: environment)
        default:
            EmptyView()
        }
    }
}
