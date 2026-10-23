import Foundation

/// Acts as a second member's device by calling the local Firebase emulators' REST APIs.
/// Requests carry that user's own ID token, so the Firestore security rules apply exactly as they do to the app.
@MainActor
struct EmulatorClient {
    struct User {
        let uid: String
        let idToken: String
    }

    struct RequestError: Error, CustomStringConvertible {
        let description: String
    }

    static let testPassword = "password123"

    static func uniqueEmail(for name: String) -> String {
        "\(name.lowercased())-\(UUID().uuidString.prefix(8).lowercased())@example.com"
    }

    private let documentsName = "projects/demo-geocircle/databases/(default)/documents"
    private var documentsURL: String { "http://127.0.0.1:8080/v1/\(documentsName)" }

    func signUp(as name: String) async throws -> User {
        let json = try await send(
            "POST",
            "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key",
            body: ["email": Self.uniqueEmail(for: name), "password": Self.testPassword, "returnSecureToken": true]
        )
        guard let uid = json["localId"] as? String, let token = json["idToken"] as? String else {
            throw RequestError(description: "Unexpected sign-up response: \(json)")
        }
        return User(uid: uid, idToken: token)
    }

    /// Joins the way the app does: a member document carrying the code, plus adding the user's id, in one commit.
    func join(code: String, as user: User, displayName: String) async throws -> String {
        let lookup = try await send("GET", "\(documentsURL)/joinCodes/\(code)", token: user.idToken)
        guard let groupID = Self.string("groupId", in: lookup) else {
            throw RequestError(description: "Join code not found: \(lookup)")
        }
        try await commit([
            [
                "update": [
                    "name": "\(documentsName)/groups/\(groupID)/members/\(user.uid)",
                    "fields": [
                        "displayName": ["stringValue": displayName],
                        "status": ["stringValue": "MEMBER"],
                        "joinCode": ["stringValue": code],
                    ],
                ],
                "updateTransforms": [["fieldPath": "joinedAt", "setToServerValue": "REQUEST_TIME"]],
                "currentDocument": ["exists": false],
            ],
            [
                "transform": [
                    "document": "\(documentsName)/groups/\(groupID)",
                    "fieldTransforms": [[
                        "fieldPath": "memberIds",
                        "appendMissingElements": ["values": [["stringValue": user.uid]]],
                    ]],
                ],
            ],
        ], token: user.idToken)
        return groupID
    }

    func geofenceID(named name: String, inGroup groupID: String, as user: User) async throws -> String {
        let json = try await send("GET", "\(documentsURL)/groups/\(groupID)/geofences", token: user.idToken)
        let documents = json["documents"] as? [[String: Any]] ?? []
        guard let match = documents.first(where: { Self.string("name", in: $0) == name }),
              let path = match["name"] as? String
        else { throw RequestError(description: "Geofence \(name) not found") }
        return String(path.split(separator: "/").last!)
    }

    func reportExit(groupID: String, geofenceID: String, geofenceName: String, memberName: String, as user: User) async throws {
        try await commit([[
            "update": [
                "name": "\(documentsName)/groups/\(groupID)/exitEvents/\(UUID().uuidString)",
                "fields": [
                    "memberId": ["stringValue": user.uid],
                    "memberName": ["stringValue": memberName],
                    "geofenceId": ["stringValue": geofenceID],
                    "geofenceName": ["stringValue": geofenceName],
                ],
            ],
            "updateTransforms": [["fieldPath": "occurredAt", "setToServerValue": "REQUEST_TIME"]],
            "currentDocument": ["exists": false],
        ]], token: user.idToken)
    }

    /// Reads a collection as an emulator admin, bypassing security rules, to check what the app wrote.
    func adminList(_ collectionPath: String) async throws -> [[String: Any]] {
        let json = try await send("GET", "\(documentsURL)/\(collectionPath)", token: "owner")
        return json["documents"] as? [[String: Any]] ?? []
    }

    static func string(_ field: String, in document: [String: Any]) -> String? {
        let fields = document["fields"] as? [String: Any]
        return (fields?[field] as? [String: Any])?["stringValue"] as? String
    }

    private func commit(_ writes: [[String: Any]], token: String) async throws {
        _ = try await send("POST", "\(documentsURL):commit", token: token, body: ["writes": writes])
    }

    private func send(_ method: String, _ url: String, token: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RequestError(description: "\(method) \(url) failed (\(status)): \(String(decoding: data, as: UTF8.self))")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
