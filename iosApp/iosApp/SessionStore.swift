import FirebaseAuth
import Observation
import Shared

struct SignedInUser: Equatable {
    let uid: String
    let displayName: String
}

/// An error whose message can be shown to the user as-is.
struct UserFacingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Tracks who is signed in with Firebase Authentication (email and password).
@MainActor
@Observable
final class SessionStore {
    private(set) var user: SignedInUser?

    @ObservationIgnored private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            MainActor.assumeIsolated {
                self?.user = firebaseUser.map { SignedInUser(uid: $0.uid, displayName: $0.displayName ?? "") }
            }
        }
    }

    func createAccount(displayName rawName: String, email: String, password: String) async throws {
        if let error = Validation.shared.nameError(name: rawName) {
            throw UserFacingError(message: error)
        }
        let displayName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let change = result.user.createProfileChangeRequest()
        change.displayName = displayName
        try await change.commitChanges()
        // The auth listener fired before the name was saved, so publish the complete user now.
        user = SignedInUser(uid: result.user.uid, displayName: displayName)
    }

    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
