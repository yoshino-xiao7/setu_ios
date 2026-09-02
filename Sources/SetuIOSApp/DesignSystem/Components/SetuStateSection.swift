import SetuIOSCore
import SwiftUI

/// Shared loading/empty/error section. Error metadata survives the entire render path.
struct SetuStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false
    var actionTitle: String?
    var action: (() -> Void)?
    var error: UserFacingError?

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    if let error {
                        SetuEmptyState(error: error, retry: action)
                    } else {
                        SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading, actionTitle: actionTitle, action: action)
                    }
                }
            }
            .setuListRow()
        }
    }
}

extension SetuStateSection {
    init(title: String, stateTitle: String, message: UserFacingError, systemImage: String, isLoading: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.init(title: title, stateTitle: stateTitle, systemImage: systemImage, isLoading: isLoading, actionTitle: actionTitle, action: action, error: message)
    }
}
