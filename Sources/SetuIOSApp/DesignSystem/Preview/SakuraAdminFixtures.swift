#if DEBUG
import Foundation
import SetuIOSCore

/// All values are synthetic. Endpoint payloads are decoded by the production DTO
/// before being served. No unknown endpoint or write request receives a success.
enum SakuraAdminFixtures {
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
        entry("/admin/blog/stats", AdminBlogStats.self,
              loaded: #"{"totalCalls":128,"aiGenerationTotal":24,"aiGenerationToday":2}"#,
              empty: #"{"totalCalls":0,"aiGenerationTotal":0,"aiGenerationToday":0}"#),
        entry("/admin/users", AdminUserListResponse.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":42,"email":"qa@example.invalid","nickname":"樱潮测试用户","role":0,"status":1}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/blacklist/ip", [AdminBlacklistIpItem].self,
              loaded: #"[{"id":1,"ip":"192.0.2.10","reason":"测试封禁记录"}]"#,
              empty: #"[]"#),
        entry("/admin/tempblock/list", [AdminTempBlockItem].self,
              loaded: #"[{"ip":"192.0.2.11","reason":"测试临时封禁"}]"#,
              empty: #"[]"#),
        entry("/status/image-count", Int.self,
              loaded: #"24"#,
              empty: #"0"#),
        entry("/admin/netease/tokens", [NeteaseToken].self,
              loaded: #"[{"id":1,"cookie":"","nickname":"樱潮测试 Token","status":1}]"#,
              empty: #"[]"#),
        entry("/admin/operation-logs", PageResult<AdminOperationLogItem>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"eventType":"IMAGE_AUDIT","status":"SUCCESS","message":"樱潮测试操作","createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/pixiv/health", PixivCrawlerHealth.self,
              loaded: #"{"status":"ok","environment":"fixture","database":"ok"}"#,
              empty: #"{"status":"ok","environment":"fixture","database":"ok"}"#),
        entry("/admin/pixiv/tasks", PixivCrawlerTaskList.self,
              loaded: #"{"total":1,"tasks":[{"task_id":"fixture-task","status":"completed","mode":"by_ids","message":"樱潮测试抓取","progress":{"total":1,"done":1,"new":1,"skipped":0,"failed":0}}]}"#,
              empty: #"{"total":0,"tasks":[]}"#),
        entry("/admin/image-audit/list", ImageAuditPageResult.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":901,"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"ext":"jpg","aiType":1,"uploadDate":1788222600000,"urlOriginal":""}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/gallery-submission-batches", PageResult<GalleryUploadBatchSummary>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"batchId":1,"userId":42,"pidMode":"SHARED","status":"SUBMITTED","title":"樱潮测试投稿","author":"测试画师","itemCount":2,"uploadedCount":2,"approvedCount":0,"rejectedCount":0,"publishedCount":0,"createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/image-delete/list", PageResult<ImageDeleteRequestItem>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"userId":42,"userEmail":"qa@example.invalid","userNickname":"测试用户","pid":901,"p":0,"reason":"樱潮测试删除申请","status":0,"statusText":"待审核","createdAt":"2026-09-01T08:30:00+08:00","imageTitle":"樱潮测试插画"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/image/info", AdminImageDetail.self,
              loaded: #"{"id":901,"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"ext":"jpg","aiType":1,"uploadDate":1788222600000}"#,
              empty: #"{"id":901,"pid":901,"p":0,"uid":42,"title":"樱潮测试插画","author":"测试画师","r18":0,"width":768,"height":1024,"ext":"jpg","aiType":1,"uploadDate":1788222600000}"#),
        entry("/admin/ai/generations", PageResult<AiGenerationJob>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":701,"userId":42,"promptCn":"樱潮测试作品","width":768,"height":1024,"steps":24,"cfg":7,"status":"COMPLETED","reviewStatus":"WAITING","createdAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/ai/reviews", PageResult<AiGenerationReview>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"jobId":701,"userId":42,"category":"GENERAL","status":"WAITING","submitNote":"樱潮测试审核","job":{"id":701,"userId":42,"promptCn":"樱潮测试作品","width":768,"height":1024,"steps":24,"cfg":7,"status":"COMPLETED","reviewStatus":"WAITING","createdAt":"2026-09-01T08:30:00+08:00"}}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/admin/ai/delete-requests", PageResult<AiGenerationDeleteRequest>.self,
              loaded: #"{"total":1,"page":1,"pageSize":20,"list":[{"id":1,"jobId":701,"userId":42,"status":"WAITING","reason":"樱潮测试删除原因","job":{"id":701,"userId":42,"promptCn":"樱潮测试作品","width":768,"height":1024,"steps":24,"cfg":7,"status":"COMPLETED","reviewStatus":"WAITING","createdAt":"2026-09-01T08:30:00+08:00"}}]}"#,
              empty: #"{"total":0,"page":1,"pageSize":20,"list":[]}"#),
        entry("/ai/status", AiServiceStatusResponse.self,
              loaded: #"{"status":"ONLINE","online":true,"openNow":true,"available":true,"workers":[{"workerId":"fixture-worker","nodeName":"樱潮测试节点","status":"ONLINE","version":"fixture","lastSeenAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"status":"OFFLINE","online":false,"openNow":true,"available":false,"workers":[]}"#),
        entry("/ai/capabilities", AiCapabilityResponse.self,
              loaded: #"{"checkpoints":[{"name":"fixture-model","displayName":"测试模型"}],"loras":[],"vaes":[],"characters":[],"promptPresets":[],"workers":[{"workerId":"fixture-worker","nodeName":"樱潮测试节点","status":"ONLINE","version":"fixture","lastSeenAt":"2026-09-01T08:30:00+08:00"}]}"#,
              empty: #"{"checkpoints":[],"loras":[],"vaes":[],"characters":[],"promptPresets":[],"workers":[]}"#),
        entry("/admin/ai/control/status", AiControlStatus.self,
              loaded: #"{"controlReady":true,"comfyReady":true,"workerRunning":true}"#,
              empty: #"{"controlReady":false,"comfyReady":false,"workerRunning":false}"#),
    ]

    static func validateAll() throws -> String {
        try entries.map { entry in
            try entry.validate(Data(entry.loaded.utf8))
            try entry.validate(Data(entry.empty.utf8))
            return "\(entry.path) → \(entry.typeName): loaded/empty decoded"
        }.joined(separator: "\n")
    }
}
#endif
