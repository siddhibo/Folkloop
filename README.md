# Folkloop

Folkloop is an iOS app for small groups (family, friends, teams) that share named places ("geofences").
When a member arrives at or leaves one of the group's geofences, the event is recorded and the rest of the
group is told. It shares **recorded arrivals and exits only** — never live or precise location.

The repository and Xcode project are still named `GeoCircle`; the app's display name is Folkloop.

## Features

- Email/password accounts (Firebase Authentication).
- Groups with a 6-character join code. Nobody is added until they enter the code; members can share an
  invitation with the system share sheet. Members can leave; the owner can remove members.
- Circular geofences (100–2,000 m) per group: place search (Apple MapKit), "Use My Location", or tap the
  map. The editor starts on India when nothing is selected. Geofences can be edited and deleted by their
  creator or the group owner.
- Core Location (`CLMonitor`) watches up to 20 geofences (the iOS limit) and records **arrivals and exits**
  with stable event IDs, so repeated callbacks don't create duplicates.
- "Share My Exits" pauses monitoring and sharing on this device (it persists across restarts; other
  members are not told).
- Live in-app alerts and local notifications for other members' arrivals and exits while the app is
  running.
- Group screen: each member's last recorded arrival/exit and per-geofence presence (inside / outside /
  unknown or stale), clearly labelled as recorded events.
- Activity dashboard (Swift Charts): exits today and over 7/30 days, exits per day, by group, top
  geofences, and a feed with honest sync status.
- Firestore security rules: members-only access, events only about yourself with server timestamps,
  creator/owner edit rights, one-member-at-a-time removal, owner-only device tokens.

## Tech stack

SwiftUI, MapKit, Core Location, Swift Charts · Kotlin Multiplatform shared logic (`shared/`) ·
Firebase Authentication, Cloud Firestore, Cloud Functions + Cloud Messaging (`backend/`).

## Requirements

- Xcode 26, Java 21, Node.js 22
- Firebase CLI: `npm install -g firebase-tools`

## Run locally (Firebase Emulator Suite, no Firebase project needed)

**Debug** builds always use the local emulators (project `demo-geocircle`).

```sh
cd backend
npm install
npm run emulators        # Auth on :9099, Firestore on :8080
```

Then open `iosApp/iosApp.xcodeproj` and run the `iosApp` scheme on an iOS Simulator. Emulator data is
wiped when the emulators stop; sign out and create a new account after restarting them.

## Tests

```sh
./gradlew :shared:iosSimulatorArm64Test     # Kotlin shared logic
cd backend && npm test                      # Firestore security rules (starts its own emulator)
cd backend/functions && npm install && npm test   # push-notification processor (no network needed)

# iOS UI tests: start the emulators first (see above), then
cd iosApp && xcodebuild -project iosApp.xcodeproj -scheme iosApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

UI tests reinstall the Debug (emulator) build on the simulator they run on. `PlaceSearchUITests` needs
network access to Apple Maps.

## Using the cloud Firebase project

**Release** builds always use the cloud project and refuse to start without a matching
`GoogleService-Info.plist` — they never fall back to the emulators.

1. In the Firebase console, enable Email/Password sign-in and create the `(default)` Firestore database.
2. Download the iOS app's `GoogleService-Info.plist` (bundle ID `com.geocircle.app`) into
   `iosApp/iosApp/`. It is git-ignored. It holds client configuration, not server credentials.
3. Set the expected project ID in `FirebaseSetup.cloudProjectID` if you use a different project.
4. Build Release for the simulator:
   `xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' ONLY_ACTIVE_ARCH=YES build`
5. Deploy the rules: `cd backend && firebase deploy --only firestore:rules --project <project-id>`.

## Remote push notifications (code complete, not yet configured)

Implemented: a Cloud Function (`backend/functions`) that runs when an event is created, re-validates it
against the group, member and geofence, notifies every other current member's registered devices, never
the sender, sends no location data, processes each event at most once, and removes unregistered tokens.
The app registers its FCM token under `users/{uid}/devices/{deviceId}` (Release builds only) and removes
it on sign-out. While the app is open, the live in-app alert is shown instead of the push.

Still required, none of which is in this repository:

1. A paid Apple Developer Program team set on the `iosApp` target, and the **Push Notifications**
   capability added in Xcode (this creates the `aps-environment` entitlement).
2. An APNs authentication key (`.p8`) uploaded in Firebase console → Project settings → Cloud Messaging.
3. The Firebase **Blaze** plan, then `cd backend && firebase deploy --only functions --project <project-id>`.
4. Testing on a physical iPhone; delivery to a closed app has not been verified.

## Known limitations

- iOS decides when region events arrive; delivery is not guaranteed or instant, and background delivery
  needs "Always" location access.
- Without push configured, other members see events only while Folkloop is running on their device.
- Presence and member status come from recorded events in the last 30 days; records older than 12 hours
  are shown as stale.
- Group ownership transfer and group deletion are not implemented; the owner cannot leave.
- Exactly-once delivery is not guaranteed; duplicates are prevented by stable event IDs and server-side
  delivery records.

No server credentials, service-account keys or APNs keys are stored in the app or the repository.
