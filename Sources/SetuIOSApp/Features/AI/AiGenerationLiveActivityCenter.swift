import Foundation
import SetuIOSCore

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

#if os(iOS)
import UIKit
#endif

@MainActor
enum AiGenerationLiveActivityCenter {
    static func start(job: AiGenerationJob, mobileClient: MobileAppClient) async {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard job.shouldKeepAiLiveActivity else { return }

        if let existing = activity(for: job.id) {
            await update(existing, with: job)
            return
        }

        do {
            let activity = try Activity<AiGenerationActivityAttributes>.request(
                attributes: AiGenerationActivityAttributes(jobID: job.id, title: "AI 绘画生成"),
                content: ActivityContent(state: contentState(for: job), staleDate: Date().addingTimeInterval(30 * 60)),
                pushType: nil
            )
            observePushTokenUpdates(for: activity, mobileClient: mobileClient)
        } catch {
            #if DEBUG
            print("Live Activity start failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    static func update(job: AiGenerationJob, mobileClient: MobileAppClient) async {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activity(for: job.id) else {
            await start(job: job, mobileClient: mobileClient)
            return
        }

        if job.isAiLiveActivityTerminal {
            await end(activity, with: job, mobileClient: mobileClient)
        } else {
            await update(activity, with: job)
        }
        #endif
    }

    #if os(iOS) && canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static func activity(for jobID: Int) -> Activity<AiGenerationActivityAttributes>? {
        Activity<AiGenerationActivityAttributes>.activities.first { $0.attributes.jobID == jobID }
    }

    @available(iOS 16.1, *)
    private static func update(_ activity: Activity<AiGenerationActivityAttributes>, with job: AiGenerationJob) async {
        await activity.update(
            ActivityContent(state: contentState(for: job), staleDate: Date().addingTimeInterval(30 * 60))
        )
    }

    @available(iOS 16.1, *)
    private static func end(
        _ activity: Activity<AiGenerationActivityAttributes>,
        with job: AiGenerationJob,
        mobileClient: MobileAppClient
    ) async {
        await activity.end(
            ActivityContent(state: contentState(for: job), staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))
        )
        _ = try? await mobileClient.endLiveActivity(activityId: activity.id)
    }

    @available(iOS 16.1, *)
    private static func observePushTokenUpdates(
        for activity: Activity<AiGenerationActivityAttributes>,
        mobileClient: MobileAppClient
    ) {
        let activityID = activity.id
        let deviceID = liveActivityDeviceID()
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                let request = MobileLiveActivityTokenRequest(
                    deviceId: deviceID,
                    activityId: activityID,
                    activityType: "AI_GENERATION",
                    pushToken: token,
                    staleAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(30 * 60))
                )
                _ = try? await mobileClient.registerLiveActivity(request)
            }
        }
    }

    private static func contentState(for job: AiGenerationJob) -> AiGenerationActivityAttributes.ContentState {
        AiGenerationActivityAttributes.ContentState(
            status: job.status,
            statusTitle: job.statusTitle,
            detail: job.aiLiveActivityDetail,
            updatedAt: Date()
        )
    }
    #endif

    private static func liveActivityDeviceID() -> String {
        let key = "setu.liveActivity.deviceID"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        #if os(iOS)
        let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let generated = UUID().uuidString
        #endif
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

extension AiGenerationJob {
    var shouldKeepAiLiveActivity: Bool {
        !isAiLiveActivityTerminal
    }

    var isAiLiveActivityTerminal: Bool {
        deleted == true || status == "COMPLETED" || status == "FAILED"
    }

    var isTrackingFinished: Bool {
        isAiLiveActivityTerminal
    }

    var aiLiveActivityDetail: String {
        if let message = userErrorMessage ?? errorMessage, !message.isEmpty {
            return message
        }
        if let detail = workerDetail, !detail.isEmpty {
            return detail
        }
        if let stage = workerStage, !stage.isEmpty {
            return stage
        }
        switch status {
        case "QUEUED":
            return "任务已进入队列"
        case "CLAIMED":
            return "节点已接单"
        case "RUNNING":
            return "正在生成图片"
        case "UPLOADING":
            return "正在上传结果"
        case "COMPLETED":
            return "图片已生成"
        case "FAILED":
            return "生成失败"
        default:
            return statusTitle
        }
    }
}
