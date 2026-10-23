import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var isCreatingAccount = true
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $isCreatingAccount) {
                    Text("Create Account").tag(true)
                    Text("Sign In").tag(false)
                }
                .pickerStyle(.segmented)

                Section {
                    if isCreatingAccount {
                        TextField("Display name", text: $displayName)
                    }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    if FirebaseSetup.usesEmulator {
                        Text("Using the local Firebase Emulator Suite. Accounts here are test data.")
                    }
                }

                Button("Continue", action: submit)
                    .disabled(isWorking)
            }
            .navigationTitle("GeoCircle")
        }
    }

    private func submit() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                if isCreatingAccount {
                    try await session.createAccount(displayName: displayName, email: email, password: password)
                } else {
                    try await session.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
