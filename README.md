# GeoCircle

iOS app (SwiftUI, MapKit, Core Location) with shared business logic in Kotlin Multiplatform (`shared/`)
and Firebase Authentication + Cloud Firestore as the backend (`backend/`).

## What works

- Email/password accounts (Firebase Authentication).
- Groups with a 6-character join code; members join by entering the code.
- Circular geofences (100–2,000 m) per group, picked on a map.
- Core Location monitors up to 20 geofences (the iOS limit) and detects exits.
- An exit is written to Firestore as an exit event. Firestore security rules only accept an event from a
  group member, about themselves, for a geofence in that group, stamped with the server time.
- Other signed-in members get a **live in-app alert** through a Firestore listener.

## Important limitation: live alerts are not push notifications

Other members only see an exit while GeoCircle is **running on their device** (open, or briefly in the
background before iOS suspends it). Nothing is delivered to a closed app. Real remote push needs Apple
Push Notification service, which requires the paid Apple Developer Program, plus a server to send it
(Cloud Functions requires Firebase's Blaze billing plan). That is not implemented.

Other limitations: iOS decides when region events arrive (not guaranteed or instant); members cannot leave
or be removed yet; geofences cannot be edited.

## Requirements

- Xcode 26, Java 21, Node.js 22
- Firebase CLI: `npm install -g firebase-tools`

## Run locally with the Firebase Emulator Suite (no Firebase project or billing needed)

```sh
cd backend
npm install
npm run emulators        # Auth on :9099, Firestore on :8080, project "demo-geocircle"
```

Then open `iosApp/iosApp.xcodeproj` and run on an iOS Simulator. Without a `GoogleService-Info.plist`
the app connects to the emulators automatically. Emulator data is wiped when the emulators stop, so sign
out and create a new account after restarting them.

## Tests

```sh
./gradlew :shared:iosSimulatorArm64Test   # Kotlin shared logic
cd backend && npm test                    # Firestore security rules (starts its own emulator)

# iOS UI tests need the emulators running:
cd backend && firebase emulators:exec --only auth,firestore --project demo-geocircle \
  "cd ../iosApp && xcodebuild -project iosApp.xcodeproj -scheme iosApp \
   -destination 'platform=iOS Simulator,name=iPhone 17' test"
```

## Using a real Firebase project (later)

1. Create a Firebase project on the free Spark plan and enable Email/Password sign-in.
2. Add an iOS app with bundle ID `com.geocircle.app` and download `GoogleService-Info.plist`.
3. Put it in `iosApp/iosApp/` (it is git-ignored; the app then uses the real project instead of the emulators).
4. Deploy the rules: `cd backend && firebase deploy --only firestore:rules --project <your-project-id>`.

No server credentials are stored in the app or the repository.
