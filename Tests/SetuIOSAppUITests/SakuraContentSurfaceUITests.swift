import XCTest

/// Each method covers one real page and its applicable states. Device width and
/// appearance are separate measured runs, not inferred from a fixture marker.
final class SakuraContentSurfaceUITests: XCTestCase {
    private struct Case { let state: String; let expected: [String] }
    private struct Page { let name: String; let start: Int; let cases: [Case] }
    private let pages: [Page] = [
        .init(name: "AiHistoryView", start: 0, cases: [
            .init(state: "loading", expected: ["正在加载 AI 绘画历史"]),
            .init(state: "empty", expected: ["暂无 AI 绘画记录"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试作品"]),
        ]),
        .init(name: "AiSquareView", start: 4, cases: [
            .init(state: "loading", expected: ["正在加载 AI 绘画广场"]),
            .init(state: "empty", expected: ["暂无公开 AI 作品"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试作品"]),
        ]),
        .init(name: "AiAssetBrowserView", start: 8, cases: [
            .init(state: "loading", expected: ["正在加载风格与角色"]),
            .init(state: "empty", expected: ["暂无可用选项"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["电影感光影"]),
        ]),
        .init(name: "FavoriteListView", start: 12, cases: [
            .init(state: "loading", expected: ["正在加载收藏"]),
            .init(state: "empty", expected: ["暂无默认收藏"]),
            .init(state: "failed", expected: ["加载失败"]),
            .init(state: "loaded", expected: ["樱潮测试插画"]),
        ]),
        .init(name: "CollectionListView", start: 16, cases: [
            .init(state: "loading", expected: ["正在加载"]),
            .init(state: "empty", expected: ["暂无收藏夹"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试收藏夹"]),
        ]),
        .init(name: "CollectionDetailView", start: 20, cases: [
            .init(state: "loading", expected: ["正在加载收藏夹"]),
            .init(state: "empty-items", expected: ["暂无图片"]),
            .init(state: "metadata-failed", expected: ["网络似乎断开了"]),
            .init(state: "items-failed", expected: ["樱潮测试收藏夹", "网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试插画"]),
        ]),
        .init(name: "CollectionSquareView", start: 25, cases: [
            .init(state: "loading", expected: ["正在加载收藏夹广场"]),
            .init(state: "empty", expected: ["暂无公开收藏夹"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试收藏夹"]),
        ]),
        .init(name: "PublicCollectionDetailView", start: 29, cases: [
            .init(state: "loading", expected: ["正在加载公开收藏夹"]),
            .init(state: "empty-items", expected: ["暂无图片"]),
            .init(state: "metadata-failed", expected: ["网络似乎断开了"]),
            .init(state: "items-failed", expected: ["樱潮测试收藏夹", "网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试插画"]),
        ]),
        .init(name: "PublicUserProfileView", start: 34, cases: [
            .init(state: "loading", expected: ["正在加载用户主页"]),
            .init(state: "empty-public-content", expected: ["暂无公开 AI 作品", "暂无公开收藏夹"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试用户"]),
        ]),
        .init(name: "GalleryUploadBatchesView", start: 38, cases: [
            .init(state: "loading", expected: ["正在加载投稿记录"]),
            .init(state: "empty", expected: ["暂无投稿记录"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试投稿"]),
        ]),
        .init(name: "GalleryUploadDetailView", start: 42, cases: [
            .init(state: "loading", expected: ["正在加载投稿详情"]),
            .init(state: "empty-items", expected: ["图片 0"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试插画"]),
        ]),
        .init(name: "ImageDeleteRequestsView", start: 46, cases: [
            .init(state: "loading", expected: ["正在加载删除申请"]),
            .init(state: "empty", expected: ["暂无删除申请"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试删除申请"]),
        ]),
        .init(name: "ImageDeleteRequestDetailView", start: 50, cases: [
            .init(state: "loading", expected: ["正在加载申请详情"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试删除申请"]),
        ]),
        .init(name: "AiDeleteRequestsView", start: 53, cases: [
            .init(state: "loading", expected: ["正在加载 AI 删除申请"]),
            .init(state: "empty", expected: ["暂无 AI 删除申请"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试删除原因"]),
        ]),
        .init(name: "PointsLogsView", start: 57, cases: [
            .init(state: "loading", expected: ["正在加载"]),
            .init(state: "empty", expected: ["暂无积分明细"]),
            .init(state: "failed", expected: ["加载失败"]),
            .init(state: "loaded", expected: ["积分获得"]),
        ]),
        .init(name: "ApiKeyListView", start: 61, cases: [
            .init(state: "loading", expected: ["正在加载"]),
            .init(state: "empty", expected: ["暂无 API Key"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试 Key"]),
        ]),
        .init(name: "PointsCallView", start: 65, cases: [
            .init(state: "loading", expected: ["正在加载积分"]),
            .init(state: "zero-balance", expected: ["当前积分"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["当前积分"]),
            .init(state: "results-loading", expected: ["正在寻找图片"]),
            .init(state: "results-empty", expected: ["当前筛选条件没有匹配图片"]),
            .init(state: "results-failed", expected: ["网络似乎断开了"]),
            .init(state: "results-loaded", expected: ["已获取 1 张图片"]),
        ]),
        .init(name: "AiGenerationDetailView", start: 73, cases: [
            .init(state: "loading", expected: ["正在加载作品"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["作品状态"]),
        ]),
        .init(name: "PublicAiWorkDetailView", start: 76, cases: [
            .init(state: "snapshot-pending", expected: ["樱潮初始作品快照"]),
            .init(state: "snapshot-failed", expected: ["暂时无法确认作品的最新公开状态"]),
            .init(state: "unavailable", expected: ["作品已下架"]),
            .init(state: "loaded", expected: ["樱潮测试作品"]),
        ]),
        .init(name: "MusicPlaylistDetailView", start: 80, cases: [
            .init(state: "loading", expected: ["正在加载"]),
            .init(state: "empty-items", expected: ["暂无歌曲"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["夏夜微风"]),
        ]),
        .init(name: "MusicHistoryView", start: 84, cases: [
            .init(state: "loading", expected: ["正在加载播放历史"]),
            .init(state: "empty", expected: ["暂无播放历史"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["夏夜微风"]),
        ]),
        .init(name: "MusicSearchView", start: 88, cases: [
            .init(state: "loading", expected: ["正在搜索"]),
            .init(state: "empty", expected: ["没有找到音乐"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["夏夜微风"]),
        ]),
        .init(name: "MusicPlaylistsView", start: 92, cases: [
            .init(state: "loading", expected: ["正在加载"]),
            .init(state: "empty", expected: ["暂无歌单"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["我的专注时刻"]),
        ]),
        .init(name: "PlaylistSelectionSheet", start: 96, cases: [
            .init(state: "loading", expected: ["正在加载歌单"]),
            .init(state: "empty", expected: ["暂无歌单"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["我的专注时刻"]),
        ]),
        .init(name: "MusicMvSheet", start: 100, cases: [
            .init(state: "loading", expected: ["正在加载 MV 详情"]),
            .init(state: "no-mv", expected: ["暂无 MV"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "detail-media-unavailable", expected: ["樱潮测试 MV"]),
        ]),
        .init(name: "CollectionEditorSheet", start: 104, cases: [
            .init(state: "create-empty", expected: ["收藏夹信息"]),
            .init(state: "edit-filled", expected: ["樱潮测试收藏夹"]),
        ]),
        .init(name: "AccountView", start: 106, cases: [
            .init(state: "loading", expected: ["正在同步当前状态"]),
            .init(state: "unbound", expected: ["尚未绑定 QQ"]),
            .init(state: "failed", expected: ["状态暂未同步，进入详情查看"]),
            .init(state: "loaded", expected: ["已绑定 QQ"]),
            .init(state: "auth-landing", expected: ["把灵感变成作品"]),
            .init(state: "auth-login", expected: ["欢迎回来"]),
            .init(state: "auth-register", expected: ["创建账号"]),
            .init(state: "auth-recovery", expected: ["验证邮箱后发送重置邮件"]),
            .init(state: "auth-password-reset", expected: ["输入邮件里的重置码和新密码"]),
        ]),
        .init(name: "ProfileView", start: 115, cases: [
            .init(state: "loading", expected: ["正在加载资料"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试用户"]),
        ]),
        .init(name: "SecuritySettingsView", start: 118, cases: [
            .init(state: "loading", expected: ["正在检查 Apple 绑定状态"]),
            .init(state: "unbound", expected: ["绑定 Apple 账号"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["解除 Apple 绑定"]),
        ]),
        .init(name: "PasskeyListView", start: 122, cases: [
            .init(state: "loading", expected: ["正在加载通行密钥"]),
            .init(state: "empty", expected: ["未开通通行密钥"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试通行密钥"]),
        ]),
        .init(name: "QqBindingView", start: 126, cases: [
            .init(state: "loading", expected: ["正在加载 QQ 绑定"]),
            .init(state: "unbound", expected: ["尚未绑定"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["10000001"]),
        ]),
        .init(name: "NotificationsView", start: 130, cases: [
            .init(state: "loading", expected: ["正在加载通知"]),
            .init(state: "empty", expected: ["暂无通知"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试通知"]),
        ]),
        .init(name: "SystemStatusView", start: 134, cases: [
            .init(state: "loading", expected: ["正在加载系统状态"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["图库数量"]),
        ]),
        .init(name: "StaticInfoView", start: 137, cases: [
            .init(state: "loading", expected: ["正在加载示例图"]),
            .init(state: "empty", expected: ["暂无示例图"]),
            .init(state: "failed", expected: ["网络似乎断开了"]),
            .init(state: "loaded", expected: ["樱潮测试插画"]),
            .init(state: "about", expected: ["雪涼云的定位"]),
            .init(state: "privacy", expected: ["了解个人数据"]),
            .init(state: "terms", expected: ["了解服务范围"]),
        ]),
    ]
    func testAiHistoryViewLightDefault() { run(page: 0, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testAiHistoryViewLightAX1() { run(page: 0, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiHistoryViewLightAX5() { run(page: 0, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiHistoryViewDarkDefault() { run(page: 0, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testAiHistoryViewDarkAX1() { run(page: 0, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiHistoryViewDarkAX5() { run(page: 0, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiSquareViewLightDefault() { run(page: 1, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testAiSquareViewLightAX1() { run(page: 1, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiSquareViewLightAX5() { run(page: 1, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiSquareViewDarkDefault() { run(page: 1, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testAiSquareViewDarkAX1() { run(page: 1, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiSquareViewDarkAX5() { run(page: 1, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiAssetBrowserViewLightDefault() { run(page: 2, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testAiAssetBrowserViewLightAX1() { run(page: 2, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiAssetBrowserViewLightAX5() { run(page: 2, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiAssetBrowserViewDarkDefault() { run(page: 2, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testAiAssetBrowserViewDarkAX1() { run(page: 2, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiAssetBrowserViewDarkAX5() { run(page: 2, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testFavoriteListViewLightDefault() { run(page: 3, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testFavoriteListViewLightAX1() { run(page: 3, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testFavoriteListViewLightAX5() { run(page: 3, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testFavoriteListViewDarkDefault() { run(page: 3, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testFavoriteListViewDarkAX1() { run(page: 3, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testFavoriteListViewDarkAX5() { run(page: 3, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionListViewLightDefault() { run(page: 4, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testCollectionListViewLightAX1() { run(page: 4, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionListViewLightAX5() { run(page: 4, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionListViewDarkDefault() { run(page: 4, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testCollectionListViewDarkAX1() { run(page: 4, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionListViewDarkAX5() { run(page: 4, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionDetailViewLightDefault() { run(page: 5, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testCollectionDetailViewLightAX1() { run(page: 5, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionDetailViewLightAX5() { run(page: 5, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionDetailViewDarkDefault() { run(page: 5, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testCollectionDetailViewDarkAX1() { run(page: 5, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionDetailViewDarkAX5() { run(page: 5, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionSquareViewLightDefault() { run(page: 6, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testCollectionSquareViewLightAX1() { run(page: 6, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionSquareViewLightAX5() { run(page: 6, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionSquareViewDarkDefault() { run(page: 6, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testCollectionSquareViewDarkAX1() { run(page: 6, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionSquareViewDarkAX5() { run(page: 6, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPublicCollectionDetailViewLightDefault() { run(page: 7, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPublicCollectionDetailViewLightAX1() { run(page: 7, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPublicCollectionDetailViewLightAX5() { run(page: 7, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPublicCollectionDetailViewDarkDefault() { run(page: 7, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPublicCollectionDetailViewDarkAX1() { run(page: 7, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPublicCollectionDetailViewDarkAX5() { run(page: 7, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPublicUserProfileViewLightDefault() { run(page: 8, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPublicUserProfileViewLightAX1() { run(page: 8, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPublicUserProfileViewLightAX5() { run(page: 8, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPublicUserProfileViewDarkDefault() { run(page: 8, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPublicUserProfileViewDarkAX1() { run(page: 8, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPublicUserProfileViewDarkAX5() { run(page: 8, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testGalleryUploadBatchesViewLightDefault() { run(page: 9, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testGalleryUploadBatchesViewLightAX1() { run(page: 9, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testGalleryUploadBatchesViewLightAX5() { run(page: 9, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testGalleryUploadBatchesViewDarkDefault() { run(page: 9, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testGalleryUploadBatchesViewDarkAX1() { run(page: 9, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testGalleryUploadBatchesViewDarkAX5() { run(page: 9, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testGalleryUploadDetailViewLightDefault() { run(page: 10, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testGalleryUploadDetailViewLightAX1() { run(page: 10, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testGalleryUploadDetailViewLightAX5() { run(page: 10, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testGalleryUploadDetailViewDarkDefault() { run(page: 10, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testGalleryUploadDetailViewDarkAX1() { run(page: 10, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testGalleryUploadDetailViewDarkAX5() { run(page: 10, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testImageDeleteRequestsViewLightDefault() { run(page: 11, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testImageDeleteRequestsViewLightAX1() { run(page: 11, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testImageDeleteRequestsViewLightAX5() { run(page: 11, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testImageDeleteRequestsViewDarkDefault() { run(page: 11, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testImageDeleteRequestsViewDarkAX1() { run(page: 11, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testImageDeleteRequestsViewDarkAX5() { run(page: 11, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testImageDeleteRequestDetailViewLightDefault() { run(page: 12, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testImageDeleteRequestDetailViewLightAX1() { run(page: 12, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testImageDeleteRequestDetailViewLightAX5() { run(page: 12, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testImageDeleteRequestDetailViewDarkDefault() { run(page: 12, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testImageDeleteRequestDetailViewDarkAX1() { run(page: 12, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testImageDeleteRequestDetailViewDarkAX5() { run(page: 12, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiDeleteRequestsViewLightDefault() { run(page: 13, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testAiDeleteRequestsViewLightAX1() { run(page: 13, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiDeleteRequestsViewLightAX5() { run(page: 13, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiDeleteRequestsViewDarkDefault() { run(page: 13, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testAiDeleteRequestsViewDarkAX1() { run(page: 13, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiDeleteRequestsViewDarkAX5() { run(page: 13, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPointsLogsViewLightDefault() { run(page: 14, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPointsLogsViewLightAX1() { run(page: 14, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPointsLogsViewLightAX5() { run(page: 14, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPointsLogsViewDarkDefault() { run(page: 14, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPointsLogsViewDarkAX1() { run(page: 14, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPointsLogsViewDarkAX5() { run(page: 14, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testApiKeyListViewLightDefault() { run(page: 15, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testApiKeyListViewLightAX1() { run(page: 15, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testApiKeyListViewLightAX5() { run(page: 15, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testApiKeyListViewDarkDefault() { run(page: 15, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testApiKeyListViewDarkAX1() { run(page: 15, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testApiKeyListViewDarkAX5() { run(page: 15, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPointsCallViewLightDefault() { run(page: 16, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPointsCallViewLightAX1() { run(page: 16, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPointsCallViewLightAX5() { run(page: 16, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPointsCallViewDarkDefault() { run(page: 16, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPointsCallViewDarkAX1() { run(page: 16, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPointsCallViewDarkAX5() { run(page: 16, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiGenerationDetailViewLightDefault() { run(page: 17, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testAiGenerationDetailViewLightAX1() { run(page: 17, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiGenerationDetailViewLightAX5() { run(page: 17, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAiGenerationDetailViewDarkDefault() { run(page: 17, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testAiGenerationDetailViewDarkAX1() { run(page: 17, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAiGenerationDetailViewDarkAX5() { run(page: 17, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPublicAiWorkDetailViewLightDefault() { run(page: 18, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPublicAiWorkDetailViewLightAX1() { run(page: 18, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPublicAiWorkDetailViewLightAX5() { run(page: 18, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPublicAiWorkDetailViewDarkDefault() { run(page: 18, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPublicAiWorkDetailViewDarkAX1() { run(page: 18, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPublicAiWorkDetailViewDarkAX5() { run(page: 18, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicPlaylistDetailViewLightDefault() { run(page: 19, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testMusicPlaylistDetailViewLightAX1() { run(page: 19, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicPlaylistDetailViewLightAX5() { run(page: 19, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicPlaylistDetailViewDarkDefault() { run(page: 19, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testMusicPlaylistDetailViewDarkAX1() { run(page: 19, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicPlaylistDetailViewDarkAX5() { run(page: 19, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicHistoryViewLightDefault() { run(page: 20, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testMusicHistoryViewLightAX1() { run(page: 20, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicHistoryViewLightAX5() { run(page: 20, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicHistoryViewDarkDefault() { run(page: 20, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testMusicHistoryViewDarkAX1() { run(page: 20, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicHistoryViewDarkAX5() { run(page: 20, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicSearchViewLightDefault() { run(page: 21, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testMusicSearchViewLightAX1() { run(page: 21, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicSearchViewLightAX5() { run(page: 21, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicSearchViewDarkDefault() { run(page: 21, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testMusicSearchViewDarkAX1() { run(page: 21, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicSearchViewDarkAX5() { run(page: 21, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicPlaylistsViewLightDefault() { run(page: 22, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testMusicPlaylistsViewLightAX1() { run(page: 22, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicPlaylistsViewLightAX5() { run(page: 22, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicPlaylistsViewDarkDefault() { run(page: 22, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testMusicPlaylistsViewDarkAX1() { run(page: 22, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicPlaylistsViewDarkAX5() { run(page: 22, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPlaylistSelectionSheetLightDefault() { run(page: 23, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPlaylistSelectionSheetLightAX1() { run(page: 23, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPlaylistSelectionSheetLightAX5() { run(page: 23, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPlaylistSelectionSheetDarkDefault() { run(page: 23, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPlaylistSelectionSheetDarkAX1() { run(page: 23, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPlaylistSelectionSheetDarkAX5() { run(page: 23, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicMvSheetLightDefault() { run(page: 24, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testMusicMvSheetLightAX1() { run(page: 24, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicMvSheetLightAX5() { run(page: 24, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testMusicMvSheetDarkDefault() { run(page: 24, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testMusicMvSheetDarkAX1() { run(page: 24, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testMusicMvSheetDarkAX5() { run(page: 24, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionEditorSheetLightDefault() { run(page: 25, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testCollectionEditorSheetLightAX1() { run(page: 25, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionEditorSheetLightAX5() { run(page: 25, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCollectionEditorSheetDarkDefault() { run(page: 25, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testCollectionEditorSheetDarkAX1() { run(page: 25, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testCollectionEditorSheetDarkAX5() { run(page: 25, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAccountViewLightDefault() { run(page: 26, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testAccountViewLightAX1() { run(page: 26, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAccountViewLightAX5() { run(page: 26, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAccountViewDarkDefault() { run(page: 26, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testAccountViewDarkAX1() { run(page: 26, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testAccountViewDarkAX5() { run(page: 26, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testProfileViewLightDefault() { run(page: 27, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testProfileViewLightAX1() { run(page: 27, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testProfileViewLightAX5() { run(page: 27, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testProfileViewDarkDefault() { run(page: 27, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testProfileViewDarkAX1() { run(page: 27, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testProfileViewDarkAX5() { run(page: 27, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testSecuritySettingsViewLightDefault() { run(page: 28, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testSecuritySettingsViewLightAX1() { run(page: 28, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testSecuritySettingsViewLightAX5() { run(page: 28, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testSecuritySettingsViewDarkDefault() { run(page: 28, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testSecuritySettingsViewDarkAX1() { run(page: 28, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testSecuritySettingsViewDarkAX5() { run(page: 28, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPasskeyListViewLightDefault() { run(page: 29, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testPasskeyListViewLightAX1() { run(page: 29, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPasskeyListViewLightAX5() { run(page: 29, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testPasskeyListViewDarkDefault() { run(page: 29, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testPasskeyListViewDarkAX1() { run(page: 29, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testPasskeyListViewDarkAX5() { run(page: 29, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testQqBindingViewLightDefault() { run(page: 30, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testQqBindingViewLightAX1() { run(page: 30, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testQqBindingViewLightAX5() { run(page: 30, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testQqBindingViewDarkDefault() { run(page: 30, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testQqBindingViewDarkAX1() { run(page: 30, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testQqBindingViewDarkAX5() { run(page: 30, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testNotificationsViewLightDefault() { run(page: 31, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testNotificationsViewLightAX1() { run(page: 31, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testNotificationsViewLightAX5() { run(page: 31, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testNotificationsViewDarkDefault() { run(page: 31, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testNotificationsViewDarkAX1() { run(page: 31, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testNotificationsViewDarkAX5() { run(page: 31, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testSystemStatusViewLightDefault() { run(page: 32, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testSystemStatusViewLightAX1() { run(page: 32, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testSystemStatusViewLightAX5() { run(page: 32, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testSystemStatusViewDarkDefault() { run(page: 32, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testSystemStatusViewDarkAX1() { run(page: 32, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testSystemStatusViewDarkAX5() { run(page: 32, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testStaticInfoViewLightDefault() { run(page: 33, mode: "Light", size: "UICTContentSizeCategoryL") }
    func testStaticInfoViewLightAX1() { run(page: 33, mode: "Light", size: "UICTContentSizeCategoryAccessibilityM") }
    func testStaticInfoViewLightAX5() { run(page: 33, mode: "Light", size: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testStaticInfoViewDarkDefault() { run(page: 33, mode: "Dark", size: "UICTContentSizeCategoryL") }
    func testStaticInfoViewDarkAX1() { run(page: 33, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityM") }
    func testStaticInfoViewDarkAX5() { run(page: 33, mode: "Dark", size: "UICTContentSizeCategoryAccessibilityXXXL") }

    private func run(page index: Int, mode: String, size: String) {
        continueAfterFailure = false
        let page = pages[index]
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-sakura-content", "-sakura-content-start", String(page.start),
                               "-UIPreferredContentSizeCategoryName", size, mode]
        app.launch()
        defer { app.terminate() }
        for scenario in page.cases {
            let name = "content-\(page.name)-\(scenario.state)-\(mode)-\(size)"
            XCTContext.runActivity(named: name) { _ in
                let current = app.staticTexts["sakura.content.current"]
                let selection = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == true AND label == %@", "\(page.name) / \(scenario.state)"), object: current)
                guard XCTWaiter.wait(for: [selection], timeout: 10) == .completed else {
                    fail(app, name: name, reason: "Gallery did not switch to the requested case")
                    return
                }
                if scenario.state.hasPrefix("results-") {
                    // This is an explicit GET to the isolated session, never a live points call.
                    let call = app.buttons["points.call"]
                    guard reveal(call, app: app), call.isEnabled else {
                        fail(app, name: name, reason: "Offline points call never became enabled")
                        return
                    }
                    call.tap()
                }
                for expected in scenario.expected {
                    let target = app.descendants(matching: .any).matching(
                        NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected)).firstMatch
                    guard reveal(target, app: app) else {
                        fail(app, name: name, reason: "Missing actual page state: \(expected)")
                        return
                    }
                    do { try SakuraSurfaceAudit.perform(in: app, test: self, name: name, target: target) }
                    catch { fail(app, name: name, reason: "Accessibility audit exception: \(error)") }
                }
                capture(app, name: "\(name)-state")
                if scenario.state == "zero-balance" {
                    XCTAssertTrue(app.staticTexts["0"].firstMatch.exists,
                                  "Zero balance is a loaded numeric value, not empty results")
                }
                if page.name == "CollectionEditorSheet" {
                    let save = app.buttons[scenario.state == "create-empty" ? "创建" : "保存"].firstMatch
                    XCTAssertTrue(reveal(save, app: app))
                    XCTAssertEqual(save.isEnabled, scenario.state == "edit-filled", "Real form validation must control save")
                }
                let manifest = app.descendants(matching: .any)["sakura.content.dtoEvidence"].firstMatch
                if manifest.exists { keep(XCTAttachment(string: manifest.label), name: "\(name)-dto-decoding") }
                // Record all visible regions until content stops moving twice.
                // No fixed four-swipe shortcut: AX5 forms can be much taller.
                captureWholePage(app, name: name)
                if page.name == "AccountView", scenario.state.hasPrefix("auth-"), scenario.state != "auth-landing" {
                    captureFilledAuthForm(app, state: scenario.state, name: name)
                }
                app.buttons["sakura.content.next"].tap()
            }
        }
    }

    private func reveal(_ target: XCUIElement, app: XCUIApplication) -> Bool {
        // Let async production state settle before the first scroll (Admin regression).
        _ = target.waitForExistence(timeout: 8)
        for _ in 0..<48 {
            if visible(target, app: app) { return true }
            guard app.scrollViews.firstMatch.exists else { return false }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        }
        return visible(target, app: app)
    }

    private func visible(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let f = element.frame
        let window = app.windows.firstMatch.frame
        // Exclude the 44pt harness strip and retain complete controls/text.
        let clip = CGRect(x: window.minX, y: app.staticTexts["sakura.content.current"].frame.maxY,
                          width: window.width, height: window.maxY - app.staticTexts["sakura.content.current"].frame.maxY)
        let intersection = f.intersection(clip)
        return !intersection.isNull && f.width > 0 && f.height > 0
            && intersection.width * intersection.height / (f.width * f.height) >= 0.9
    }

    private func fingerprint(_ app: XCUIApplication) -> String {
        app.scrollViews.firstMatch.descendants(matching: .any).allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && !$0.label.isEmpty && $0.elementType != .progressIndicator }
            .map { "\($0.label)|\(Int($0.frame.minY.rounded()))|\(Int($0.frame.height.rounded()))" }
            .joined(separator: "\n")
    }

    private func captureWholePage(_ app: XCUIApplication, name: String) {
        guard app.scrollViews.firstMatch.exists else { capture(app, name: "\(name)-non-scrolling"); return }
        let board = app.scrollViews.firstMatch
        // Return to top with the same stability criterion before walking downward.
        for direction in ["top", "bottom"] {
            var previous = fingerprint(app)
            var stable = 0
            var reached = false
            for step in 0..<48 {
                if direction == "top" { board.swipeDown() } else { board.swipeUp() }
                let current = fingerprint(app)
                if direction == "bottom" { capture(app, name: "\(name)-scroll-\(step)") }
                stable = !current.isEmpty && current == previous ? stable + 1 : 0
                previous = current
                if stable >= 2 { reached = true; break }
            }
            capture(app, name: "\(name)-\(direction)")
            do { try SakuraSurfaceAudit.perform(in: app, test: self, name: "\(name)-\(direction)") }
            catch { fail(app, name: name, reason: "Accessibility audit exception: \(error)") }
            guard reached else {
                fail(app, name: name, reason: "Scroll limit reached before stable \(direction); coverage incomplete")
                return
            }
        }
    }

    private func captureFilledAuthForm(_ app: XCUIApplication, state: String, name: String) {
        // Local editing only. Never submit authentication, send email or open credentials UI.
        let fieldID = state == "auth-login" ? "auth.login.email" : state == "auth-register" ? "auth.register.email" :
            state == "auth-recovery" ? "auth.recovery.email" : "auth.reset.token"
        let field = app.textFields[fieldID]
        for _ in 0..<48 { if visible(field, app: app) { break }; app.scrollViews.firstMatch.swipeDown() }
        guard visible(field, app: app) else { fail(app, name: name, reason: "Authentication input missing"); return }
        field.tap()
        field.typeText(state == "auth-password-reset" ? "SYNTHETIC-RESET-CODE" : "qa@example.invalid")
        capture(app, name: "\(name)-local-edit-keyboard")
        app.scrollViews.firstMatch.swipeUp() // Actual screen dismisses the keyboard interactively.
        let submitTitle = state == "auth-login" ? "登录" : state == "auth-register" ? "注册" :
            state == "auth-recovery" ? "发送重置邮件" : "重置密码"
        let submit = app.buttons[submitTitle].firstMatch
        XCTAssertTrue(reveal(submit, app: app))
        XCTAssertFalse(submit.isEnabled, "Incomplete local form must not permit submission")
        capture(app, name: "\(name)-incomplete-form-disabled")
        do { try SakuraSurfaceAudit.perform(in: app, test: self, name: "\(name)-edited-form", target: submit) }
        catch { fail(app, name: name, reason: "Accessibility audit exception: \(error)") }
    }

    private func fail(_ app: XCUIApplication, name: String, reason: String) {
        capture(app, name: "\(name)-failure")
        keep(XCTAttachment(string: app.debugDescription), name: "\(name)-failure-hierarchy")
        XCTFail(reason)
    }
    private func capture(_ app: XCUIApplication, name: String) {
        keep(XCTAttachment(screenshot: app.screenshot()), name: name)
    }
    private func keep(_ attachment: XCTAttachment, name: String) {
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
