import SwiftUI

/// Transient acknowledgements disappear; errors and warnings remain recoverable.
/// SwiftUI cancels the previous task when feedback changes or the page disappears.
private struct SetuFeedbackPresenter: ViewModifier {
    @Binding var feedback: SetuFeedback?

    func body(content: Content) -> some View {
        content.task(id: feedback) {
            guard let snapshot = feedback else { return }
            switch snapshot {
            case .success, .info:
                do {
                    try await Task.sleep(for: .seconds(2.4))
                    guard !Task.isCancelled, feedback == snapshot else { return }
                    feedback = nil
                } catch {
                    // Cancellation belongs to a newer message or a dismissed page.
                }
            case .error, .failure, .warning:
                break
            }
        }
    }
}

extension View {
    func setuFeedbackPresentation(_ feedback: Binding<SetuFeedback?>) -> some View {
        modifier(SetuFeedbackPresenter(feedback: feedback))
    }
}
