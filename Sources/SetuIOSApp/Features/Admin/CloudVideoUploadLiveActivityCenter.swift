import Foundation
import SetuIOSCore

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

#if os(iOS)
import UIKit
#endif

@MainActor
enum CloudVideoUploadLiveActivityCenter {
    static func sync(store: CloudVideoUploadStore) async {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = store.running
        #endif
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if !store.busy {
            for activity in Activity<CloudVideoUploadActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let state = CloudVideoUploadActivityAttributes.ContentState(
            title: store.activeItem?.title ?? "云视频上传",
            detail: store.summary,
            percent: store.activeItem?.percent ?? 0,
            queuedCount: store.queuedCount
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(6 * 60 * 60))
        if let existing = Activity<CloudVideoUploadActivityAttributes>.activities.first {
            await existing.update(content)
        } else {
            _ = try? Activity.request(
                attributes: CloudVideoUploadActivityAttributes(),
                content: content,
                pushType: nil
            )
        }
        #endif
    }
}
