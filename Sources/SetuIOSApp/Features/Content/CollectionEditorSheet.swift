import SetuIOSCore
import SwiftUI

enum CollectionEditorContext: Identifiable {
    case create
    case edit(CollectionInfo)

    var id: String {
        switch self {
        case .create:
            "create"
        case .edit(let collection):
            "edit-\(collection.id)"
        }
    }
}

struct CollectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let context: CollectionEditorContext
    let onSaved: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var visibility: CollectionVisibility
    @State private var feedback: SetuFeedback?

    init(environment: AppEnvironment, context: CollectionEditorContext, onSaved: @escaping () -> Void) {
        self.environment = environment
        self.context = context
        self.onSaved = onSaved

        switch context {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _visibility = State(initialValue: .private)
        case .edit(let collection):
            _name = State(initialValue: collection.name)
            _description = State(initialValue: collection.description ?? "")
            _visibility = State(initialValue: collection.visibility)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "收藏夹信息", subtitle: visibility.title)
                    TextField("名称", text: $name)
                            .textFieldStyle(.roundedBorder)
                    TextField("描述", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                    Picker("可见性", selection: $visibility) {
                        ForEach(CollectionVisibility.allCases, id: \.self) { value in
                            Label(value.title, systemImage: value == .publicVisible ? "eye" : "lock")
                                .tag(value)
                        }
                    }
                        .pickerStyle(.segmented)
                }
                }
                .setuListRow()

                if let feedback {
                    SetuFeedbackBanner(feedback: feedback)
                    .setuListRow()
                }
            }
            .listStyle(.plain)
            .setuBackground()
        .setuFeedbackPresentation($feedback)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        Task { await save() }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch context {
        case .create:
            "新建收藏夹"
        case .edit:
            "编辑收藏夹"
        }
    }

    private var saveTitle: String {
        switch context {
        case .create:
            "创建"
        case .edit:
            "保存"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String? {
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func save() async {
        guard !trimmedName.isEmpty else { return }
        feedback = nil
        do {
            switch context {
            case .create:
                _ = try await environment.collectionClient.create(
                    name: trimmedName,
                    description: trimmedDescription,
                    visibility: visibility
                )
            case .edit(let collection):
                try await environment.collectionClient.update(
                    collectionID: collection.id,
                    name: trimmedName,
                    description: trimmedDescription,
                    visibility: visibility
                )
            }
            onSaved()
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
