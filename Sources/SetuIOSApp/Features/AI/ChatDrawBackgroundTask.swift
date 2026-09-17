import UIKit

/// Keeps the app briefly awake so an in-flight chat SSE is less likely to die when the user backgrounds.
@MainActor
final class ChatDrawBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin(name: String = "ai.chat.draw.stream") -> ChatDrawBackgroundTask {
        let task = ChatDrawBackgroundTask()
        task.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            task.end()
        }
        return task
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    deinit {
        // end() is MainActor-isolated; schedule safely if deallocated off-main.
        let identifier = identifier
        guard identifier != .invalid else { return }
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}
