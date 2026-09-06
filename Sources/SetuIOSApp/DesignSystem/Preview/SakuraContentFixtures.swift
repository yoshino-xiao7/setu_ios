#if DEBUG
import Foundation
import SetuIOSCore

/// Synthetic read-only transport payloads. No remote artwork, media or credentials.
enum SakuraContentFixtures {
    struct Entry {
        let path: String
        let typeName: String
        let loaded: String
        let empty: String
        let validate: (Data) throws -> Void
    }
    private static func entry<T: Decodable>(_ path: String, _ type: T.Type, loaded: String, empty: String) -> Entry {
        Entry(path: path, typeName: String(describing: type), loaded: loaded, empty: empty) {
            _ = try JSONDecoder().decode(type, from: $0)
        }
    }
    static let entries: [Entry] = [
        entry("/ai/generations", PageResult<AiGenerationJob>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":9700501,"userId":42,"source":"IOS","promptCn":"樱潮测试作品","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"COMPLETED","reviewStatus":"APPROVED","publicCategory":"GENERAL","publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":2,"favoriteCount":1,"likedByMe":false,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"2026-09-01T08:30:00+08:00","updatedAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/ai/generations/9700501", AiGenerationJob.self,
              loaded: #"{"id":9700501,"userId":42,"source":"IOS","promptCn":"樱潮测试作品","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"COMPLETED","reviewStatus":"APPROVED","publicCategory":"GENERAL","publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":2,"favoriteCount":1,"likedByMe":false,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"2026-09-01T08:30:00+08:00","updatedAt":"2026-09-01T08:30:00+08:00"}"#,
              empty: #"{"id":9700501,"userId":42,"source":"IOS","promptCn":"樱潮测试作品","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"COMPLETED","reviewStatus":"APPROVED","publicCategory":"GENERAL","publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":2,"favoriteCount":1,"likedByMe":false,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"2026-09-01T08:30:00+08:00","updatedAt":"2026-09-01T08:30:00+08:00"}"#),
        entry("/ai/generations/9700501/image-url", AiImageURL.self,
              loaded: #"{"jobId":9700501,"url":"","expiresInSeconds":0}"#,
              empty: #"{"jobId":9700501,"url":"","expiresInSeconds":0}"#),
        entry("/ai/square", PageResult<AiPublicWork>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":9700501,"userId":42,"source":"IOS","promptCn":"樱潮测试作品","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"COMPLETED","reviewStatus":"APPROVED","publicCategory":"GENERAL","publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":2,"favoriteCount":1,"likedByMe":false,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"2026-09-01T08:30:00+08:00","updatedAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/ai/square/9700501", AiPublicWork.self,
              loaded: #"{"id":9700501,"userId":42,"source":"IOS","promptCn":"樱潮测试作品","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"COMPLETED","reviewStatus":"APPROVED","publicCategory":"GENERAL","publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":2,"favoriteCount":1,"likedByMe":false,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"2026-09-01T08:30:00+08:00","updatedAt":"2026-09-01T08:30:00+08:00"}"#,
              empty: #"{"id":9700501,"userId":42,"source":"IOS","promptCn":"樱潮测试作品","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"COMPLETED","reviewStatus":"APPROVED","publicCategory":"GENERAL","publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":2,"favoriteCount":1,"likedByMe":false,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"2026-09-01T08:30:00+08:00","updatedAt":"2026-09-01T08:30:00+08:00"}"#),
        entry("/ai/capabilities", AiCapabilityResponse.self,
              loaded: #"{"checkpoints":[{"workerId":"preview-worker","type":"CHECKPOINT","name":"soft-pink-v1.safetensors","displayName":"柔光插画"}],"loras":[{"workerId":"preview-worker","type":"LORA","name":"cinematic-light.safetensors","displayName":"电影感光影"}],"vaes":[],"characters":[{"workerId":"preview-worker","type":"CHARACTER","name":"silver-hair-girl","displayName":"银发少女"}],"promptPresets":[],"workers":[{"workerId":"preview-worker","nodeName":"离线预览节点","status":"ONLINE","message":"可用"}]}"#,
              empty: #"{"checkpoints":[],"loras":[],"vaes":[],"characters":[],"promptPresets":[],"workers":[]}"#),
        entry("/favorite/list", FavoritePage.self,
              loaded: #"{"total":1,"page":1,"size":20,"items":[{"favoriteId":901,"imageId":901,"pid":901,"p":0,"favoritedAt":"2026-09-01T08:30:00+08:00","image":{"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"tags":["樱花"],"id":901}}]}"#,
              empty: #"{"total":0,"page":1,"size":20,"items":[]}"#),
        entry("/collections/mine", [CollectionInfo].self,
              loaded: #"[{"id":1,"userId":42,"name":"樱潮测试收藏夹","description":"收藏日常的温柔光影与创作灵感","visibility":1,"isDefault":false,"itemCount":1}]"#,
              empty: #"[]"#),
        entry("/collections/1", CollectionInfo.self,
              loaded: #"{"id":1,"userId":42,"name":"樱潮测试收藏夹","description":"收藏日常的温柔光影与创作灵感","visibility":1,"isDefault":false,"itemCount":1}"#,
              empty: #"{"id":1,"userId":42,"name":"樱潮测试收藏夹","description":"收藏日常的温柔光影与创作灵感","visibility":1,"isDefault":false,"itemCount":0}"#),
        entry("/collections/1/items", CollectionItemPage.self,
              loaded: #"{"total":1,"page":1,"size":20,"items":[{"itemId":1,"pid":901,"p":0,"addedAt":"2026-09-01T08:30:00+08:00","image":{"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"tags":["樱花"],"id":901}}]}"#,
              empty: #"{"total":0,"page":1,"size":20,"items":[]}"#),
        entry("/square/collections", PageResult<CollectionInfo>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"userId":42,"name":"樱潮测试收藏夹","description":"收藏日常的温柔光影与创作灵感","visibility":1,"isDefault":false,"itemCount":1}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/square/collections/1", CollectionInfo.self,
              loaded: #"{"id":1,"userId":42,"name":"樱潮测试收藏夹","description":"收藏日常的温柔光影与创作灵感","visibility":1,"isDefault":false,"itemCount":1}"#,
              empty: #"{"id":1,"userId":42,"name":"樱潮测试收藏夹","description":"收藏日常的温柔光影与创作灵感","visibility":1,"isDefault":false,"itemCount":0}"#),
        entry("/square/users/42", PublicUserProfile.self,
              loaded: #"{"id":42,"nickname":"樱潮测试用户","publicCollectionCount":1,"publicAiWorkCount":1}"#,
              empty: #"{"id":42,"nickname":"樱潮测试用户","publicCollectionCount":0,"publicAiWorkCount":0}"#),
        entry("/gallery/uploads/batches", PageResult<GalleryUploadBatchSummary>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"batchId":1,"userId":42,"pidMode":"MULTI_PID_P0","status":"WAITING_MANUAL_REVIEW","title":"樱潮测试投稿","author":"测试画师","itemCount":1,"uploadedCount":1,"approvedCount":0,"rejectedCount":0,"publishedCount":0,"createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/gallery/uploads/batches/1", GalleryUploadBatchDetail.self,
              loaded: #"{"batchId":1,"userId":42,"pidMode":"MULTI_PID_P0","status":"WAITING_MANUAL_REVIEW","title":"樱潮测试投稿","author":"测试画师","itemCount":1,"uploadedCount":1,"approvedCount":0,"rejectedCount":0,"publishedCount":0,"createdAt":"2026-09-01T08:30:00+08:00","items":[{"submissionId":1,"status":"WAITING_MANUAL_REVIEW","title":"樱潮测试插画","width":768,"height":1024}]}"#,
              empty: #"{"batchId":1,"userId":42,"pidMode":"MULTI_PID_P0","status":"WAITING_MANUAL_REVIEW","title":"樱潮测试投稿","author":"测试画师","itemCount":1,"uploadedCount":1,"approvedCount":0,"rejectedCount":0,"publishedCount":0,"createdAt":"2026-09-01T08:30:00+08:00","items":[]}"#),
        entry("/image-delete/my", PageResult<ImageDeleteRequestItem>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"userId":42,"userEmail":"qa@example.invalid","userNickname":"樱潮测试用户","pid":901,"p":0,"reason":"樱潮测试删除申请","status":0,"statusText":"待审核","createdAt":"2026-09-01T08:30:00+08:00","imageTitle":"樱潮测试插画"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/image-delete/my/1", ImageDeleteRequestDetail.self,
              loaded: #"{"id":1,"userId":42,"userEmail":"qa@example.invalid","userNickname":"樱潮测试用户","pid":901,"p":0,"reason":"樱潮测试删除申请","status":0,"statusText":"待审核","createdAt":"2026-09-01T08:30:00+08:00","imageTitle":"樱潮测试插画","title":"樱潮测试插画","author":"测试画师"}"#,
              empty: #"{"id":1,"userId":42,"userEmail":"qa@example.invalid","userNickname":"樱潮测试用户","pid":901,"p":0,"reason":"樱潮测试删除申请","status":0,"statusText":"待审核","createdAt":"2026-09-01T08:30:00+08:00","imageTitle":"樱潮测试插画","title":"樱潮测试插画","author":"测试画师"}"#),
        entry("/ai/delete-requests", PageResult<AiGenerationDeleteRequest>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"jobId":701,"userId":42,"status":"WAITING","reason":"樱潮测试删除原因","job":{"id":701,"userId":42,"promptCn":"樱潮测试作品","width":768,"height":1024,"steps":24,"cfg":7,"status":"COMPLETED","reviewStatus":"WAITING","createdAt":"2026-09-01T08:30:00+08:00"}}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/points/logs", PointsLogPage.self,
              loaded: #"{"total":1,"page":1,"size":20,"items":[{"id":1,"delta":10,"bizType":"SIGN_IN","endpoint":"樱潮测试积分记录","createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"size":20,"items":[]}"#),
        entry("/api-key/list", ApiKeyListResponse.self,
              loaded: #"{"items":[{"id":1,"name":"樱潮测试 Key","status":1,"dailyQuota":100,"totalQuota":1000,"callsToday":1,"totalCalls":4,"createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"items":[]}"#),
        entry("/points/me", PointsBalance.self,
              loaded: #"{"points":86}"#,
              empty: #"{"points":0}"#),
        entry("/setu/v2", [SetuImageItem].self,
              loaded: #"[{"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"tags":["樱花"]}]"#,
              empty: #"[]"#),
        entry("/favorite/exists/901/0", Bool.self,
              loaded: #"false"#,
              empty: #"false"#),
        entry("/blog/setu", [SetuImageItem].self,
              loaded: #"[{"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"tags":["樱花"]}]"#,
              empty: #"[]"#),
        entry("/user/playlists", [UserMusicPlaylist].self,
              loaded: #"[{"id":7401,"userId":42,"name":"我的专注时刻","description":"工作与阅读","coverUrl":null,"isPublic":0,"playMode":"sequence","songCount":18,"playCount":46,"createdAt":"2026-06-20T12:00:00+08:00","updatedAt":"2026-07-10T09:00:00+08:00"},{"id":7402,"userId":42,"name":"夜晚散步","description":"轻松、安静、有一点风","coverUrl":null,"isPublic":0,"playMode":"loop","songCount":12,"playCount":31,"createdAt":"2026-06-25T12:00:00+08:00","updatedAt":"2026-07-09T21:00:00+08:00"}]"#,
              empty: #"[]"#),
        entry("/user/playlists/7401", UserMusicPlaylistDetail.self,
              loaded: #"{"id":7401,"name":"我的专注时刻","songCount":1,"playMode":"sequence","songs":[{"id":8101,"songId":7101,"songName":"夏夜微风","artistName":"雪涼乐队"}]}"#,
              empty: #"{"id":7401,"name":"我的专注时刻","songCount":0,"playMode":"sequence","songs":[]}"#),
        entry("/user/music/history", [MusicHistoryRecord].self,
              loaded: #"[{"id":7301,"userId":42,"songId":7101,"songName":"夏夜微风","artistName":"雪涼乐队","albumName":"粉色云层","coverUrl":null,"duration":238000,"playTime":"2026-07-10T09:40:00+08:00"},{"id":7302,"userId":42,"songId":7102,"songName":"沿着星光回家","artistName":"林间回声","albumName":"夜航","coverUrl":null,"duration":205000,"playTime":"2026-07-09T22:10:00+08:00"}]"#,
              empty: #"[]"#),
        entry("/user/music/history/count", Int.self,
              loaded: #"2"#,
              empty: #"0"#),
        entry("/user/music/search", MusicSearchResult.self,
              loaded: #"{"result":{"songs":[{"id":7101,"name":"夏夜微风","artists":[{"id":1,"name":"雪涼乐队"}],"album":{"id":11,"name":"粉色云层","picUrl":null},"duration":238000,"mv":0},{"id":7102,"name":"沿着星光回家","artists":[{"id":2,"name":"林间回声"}],"album":{"id":12,"name":"夜航","picUrl":null},"duration":205000,"mv":0},{"id":7103,"name":"Quiet Focus / 深度工作","artists":[{"id":3,"name":"Luna Studio"}],"album":{"id":13,"name":"Soft Hours","picUrl":null},"duration":264000,"mv":0}],"songCount":3}}"#,
              empty: #"{"result":{"songs":[],"songCount":0}}"#),
        entry("/user/music/search/hot", MusicHotSearchResponse.self,
              loaded: #"{"code":200,"result":{"hots":[{"first":"夏夜微风","second":100,"iconType":1},{"first":"深度工作","second":96,"iconType":1},{"first":"雨天咖啡店","second":92,"iconType":1},{"first":"City Pop","second":88,"iconType":0},{"first":"轻音乐","second":84,"iconType":0}]}}"#,
              empty: #"{"code":200,"result":{"hots":[]}}"#),
        entry("/user/music/mv/detail", MusicMvDetailResponse.self,
              loaded: #"{"data":{"id":99,"name":"樱潮测试 MV","brs":[{"br":480}]}}"#,
              empty: #"{"data":{"id":99,"name":"樱潮测试 MV","brs":[{"br":480}]}}"#),
        entry("/user/music/mv/url", MusicMvUrlResponse.self,
              loaded: #"{"data":null}"#,
              empty: #"{"data":null}"#),
        entry("/user/info", UserProfile.self,
              loaded: #"{"id":42,"email":"qa@example.invalid","nickname":"樱潮测试用户","role":0,"createdAt":"2026-09-01T08:30:00+08:00"}"#,
              empty: #"{"id":42,"email":"qa@example.invalid","nickname":"樱潮测试用户","role":0,"createdAt":"2026-09-01T08:30:00+08:00"}"#),
        entry("/user/qq-binding", QqBinding.self,
              loaded: #"{"qqNumber":"10000001","enabled":true,"updatedAt":"2026-09-01T08:30:00+08:00"}"#,
              empty: #"{"qqNumber":null,"enabled":false}"#),
        entry("/user/apple", AppleBindingStatus.self,
              loaded: #"{"linked":true,"email":"qa@example.invalid"}"#,
              empty: #"{"linked":false}"#),
        entry("/user/passkeys", PasskeyListResponse.self,
              loaded: #"[{"id":1,"nickname":"樱潮测试通行密钥","createdAt":"2026-09-01T08:30:00+08:00"}]"#,
              empty: #"[]"#),
        entry("/auth/captcha", CaptchaResponse.self,
              loaded: #"{"uuid":"sakura-content-captcha","img":""}"#,
              empty: #"{"uuid":"sakura-content-captcha","img":""}"#),
        entry("/notifications", UserNotificationPage.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"type":"SYSTEM","title":"樱潮测试通知","content":"这是一条用于离线布局验收的通知。","read":true,"createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/notifications/unread-count", UnreadNotificationCount.self,
              loaded: #"{"count":0}"#,
              empty: #"{"count":0}"#),
        entry("/status/overview", StatusOverview.self,
              loaded: #"{"status":{"status":"UP","availability":99.98,"avgLatencyMs":82,"callsToday":214},"health":{"status":"UP","healthy":true,"code":"OK","checkedAt":"2026-09-01T08:30:00+08:00"}}"#,
              empty: #"{"status":{"status":"UP","availability":99.98,"avgLatencyMs":82,"callsToday":214},"health":{"status":"UP","healthy":true,"code":"OK","checkedAt":"2026-09-01T08:30:00+08:00"}}"#),
        entry("/status/image-count", Int.self,
              loaded: #"24"#,
              empty: #"24"#),
    ]
    static func decode<T: Decodable>(_ type: T.Type, path: String) -> T {
        guard let entry = entries.first(where: { $0.path == path }) else { preconditionFailure("Missing fixture: \(path)") }
        do { return try JSONDecoder().decode(type, from: Data(entry.loaded.utf8)) }
        catch { preconditionFailure("Invalid fixture: \(path): \(error)") }
    }
    static func validateAll() throws -> String {
        try entries.map { entry in
            try entry.validate(Data(entry.loaded.utf8))
            try entry.validate(Data(entry.empty.utf8))
            return "\(entry.path): \(entry.typeName) loaded/empty decoded"
        }.joined(separator: "\n")
    }
}
#endif
