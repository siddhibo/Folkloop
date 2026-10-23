import SwiftUI

struct JoinGroupView: View {
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isJoining = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Join code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Ask a group member for the 6-character code shown on their group screen.")
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", action: join)
                        .disabled(isJoining)
                }
            }
        }
    }

    private func join() {
        isJoining = true
        Task {
            do {
                try await store.joinGroup(code: code)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }
}
