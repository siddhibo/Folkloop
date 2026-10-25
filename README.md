# Folkloop

**A privacy-conscious iOS app for sharing arrivals and exits with the people in your circle.**

Folkloop lets small groups of friends, families, or teammates create shared places and receive updates when a member arrives at or leaves one of those places. Instead of continuously sharing someone's live location, Folkloop records specific geofence events and makes those events available to the group.

The project was built with SwiftUI and Kotlin Multiplatform, with Firebase handling authentication and cloud data.

## What it does

- Create tracking groups and invite members using a six-character join code.
- Add named places to a group and configure their geofence radius.
- Detect arrivals and exits using iOS Core Location.
- Record events in Cloud Firestore and make them available to other group members.
- Review recent activity and each member's last recorded movement.
- Pause event sharing on a device when privacy is needed.

## Features

### Groups and membership

- **Multiple members per group:** Create a group for the people who need to share place-based updates.
- **Join codes:** Members must enter the group's six-character code to join. They are not added automatically.
- **Shareable invitations:** Send an invitation through the iOS share sheet.
- **Membership management:** Members can leave a group, while the owner can remove individual members.
- **Clear group activity:** View member information and recorded arrival or exit activity from the group screen.

These features make the app useful for actual groups rather than limiting it to a single-user geofencing demonstration.

### Geofence management

- **Configurable circular geofences:** Set a radius between 100 and 2,000 metres.
- **Place search:** Search for locations using Apple MapKit.
- **Map-based selection:** Choose a location by tapping the map or using the current location.
- **Editing and deletion:** The geofence creator or group owner can manage geofences.
- **Multiple monitored places:** The app supports monitoring up to 20 geofences, subject to the iOS monitoring limit.

The map editor provides different ways to choose a place, while adjustable radii allow groups to use smaller or larger areas depending on the location.

### Arrival and exit tracking

Folkloop uses Core Location to monitor configured regions and record boundary-crossing events.

- Records both arrivals and exits.
- Uses stable event IDs to prevent repeated location callbacks from creating duplicate event records.
- Associates events with the member and geofence involved.
- Uses Firestore server timestamps for event records.
- Shows a success message only after the event has been accepted by Firestore.
- Provides in-app alerts and local notifications for group activity while the app is running.

The focus is on useful events, such as someone leaving a familiar place, rather than collecting a continuous trail of coordinates.

### Presence and last recorded activity

The group screen provides a summary of members' last recorded arrivals and exits, along with per-geofence presence labels:

- **Inside**
- **Outside**
- **Unknown**
- **Stale**

These labels are inferred from recorded events, not from continuous live location tracking. Older records are marked stale so that an outdated event is not presented as a reliable picture of someone's current location.

This gives the group useful context while making the limits of the information clear.

### Activity dashboard

The dashboard turns individual events into a more useful activity history.

It includes:

- Exit counts for today and over seven- and thirty-day periods.
- Daily exit trends using Swift Charts.
- Activity filtered by group.
- Frequently triggered geofences.
- A chronological activity feed.
- Sync status to help distinguish recorded events from events that have not synced successfully.

The dashboard was added to make activity easier to review over time, rather than requiring members to rely on individual notifications.

### Pause and resume sharing

The **Share My Exits** control lets a member pause monitoring and sharing on their device.

- Pausing stops monitoring and sharing from that device.
- The setting persists across app restarts.
- Other group members are not notified when the setting is changed.

This gives users control over when their device participates in event sharing without requiring them to leave the group.

## Additional features and design decisions

Beyond the core requirement of detecting a geofence exit and notifying other group members, Folkloop includes several features intended to make the app more practical and reliable.

| Additional feature | Why it matters |
| --- | --- |
| Arrival events | Records both directions of movement across a boundary, not just exits. |
| Stable event IDs | Prevents repeated location callbacks from creating duplicate event records. |
| Presence summaries | Makes recent recorded activity easier to understand at a glance. |
| Stale-status indicators | Avoids presenting old activity as current information. |
| Activity analytics | Helps users review patterns across days, groups, and places. |
| Place search and map selection | Makes geofence setup more convenient than entering coordinates manually. |
| Adjustable geofence radius | Supports different types of places and desired boundary sizes. |
| Join codes and shareable invitations | Gives groups a straightforward way to manage membership. |
| Leave and member-removal controls | Supports changes in group membership over time. |
| Pause and resume sharing | Gives each member control over participation from their device. |
| Honest sync feedback | Avoids treating an event as successfully shared before the cloud write succeeds. |
| Local emulator support | Allows development and testing without depending on production Firebase data. |
| Firestore rules tests | Helps verify that access restrictions behave as intended. |
| Push-notification processor | Provides a server-side implementation for future remote notifications once deployment requirements are met. |

## Privacy and security

Privacy is a central design consideration in Folkloop. Location information can be sensitive, so the app is designed around sharing recorded events rather than a continuous location feed.

### Location privacy

- Folkloop shares recorded arrivals and exits, not continuous or precise location coordinates.
- Presence labels are derived from event history.
- The app does not provide a live location map of group members.
- Members can pause monitoring and sharing on their device.
- Older activity is marked stale instead of being presented as fresh information.

Geofencing still requires location permissions and location monitoring by iOS. Background event delivery depends on operating-system behaviour and the permissions granted by the user.

### Firestore access controls

The Firestore security rules enforce restrictions including:

- Access to group data for authorised members.
- Event creation only for the authenticated member's own activity.
- Server-generated timestamps for event records.
- Editing permissions for geofences based on creator or group-owner privileges.
- Restrictions on membership changes, including one-member-at-a-time removal.
- Owner-only access for device-token operations.

These rules provide a server-side access-control layer in addition to the app's interface. Hiding an action in the UI is not treated as a substitute for checking permissions in Firestore.

### Credential handling

- The iOS Firebase configuration file is excluded from Git.
- No service-account private keys or APNs authentication keys are included in the repository.
- Local development uses a separate Firebase emulator project.
- Release builds validate the expected Firebase project configuration and do not silently fall back to local emulators.

Firebase client configuration is distinct from private server credentials. Production API keys should still have appropriate restrictions configured in Google Cloud.

### Event and notification handling

The push-notification processor revalidates events against group membership and geofence data before processing them. Its implementation is designed to avoid notifying the sender, prevent repeated processing of the same event, and remove unregistered device tokens.

The processor's presence in the codebase does not mean remote push delivery is currently operational. See [Remote push notifications](#remote-push-notifications).

## Tech stack

| Area | Technologies |
| --- | --- |
| iOS interface | SwiftUI |
| Maps and place search | MapKit |
| Location monitoring | Core Location |
| Charts | Swift Charts |
| Shared logic | Kotlin Multiplatform |
| Authentication | Firebase Authentication |
| Cloud database | Cloud Firestore |
| Backend notifications | Cloud Functions and Firebase Cloud Messaging |
| Testing | Kotlin tests, Firestore rules tests, backend tests, and iOS UI tests |

The repository and Xcode project retain the name `GeoCircle`, while the app's display name is Folkloop.

## Project structure

```text
Folkloop/
├── shared/                 # Kotlin Multiplatform shared logic
├── iosApp/
│   ├── iosApp/             # SwiftUI application
│   └── iosApp.xcodeproj/   # Xcode project
├── backend/
│   ├── firestore.rules     # Firestore access rules
│   ├── tests/              # Firestore rules tests
│   └── functions/          # Push-notification processor
└── README.md
```

## Requirements

- macOS with Xcode 26
- Java 21
- Node.js 22
- Firebase CLI

Install the Firebase CLI if needed:

```bash
npm install -g firebase-tools
```

## Running locally

Local development uses the Firebase Emulator Suite, so you can work without connecting the app to production Firebase data.

### 1. Start the emulators

From the repository root:

```bash
cd backend
npm install
npm run emulators
```

The local configuration uses:

- Firebase Authentication: port `9099`
- Cloud Firestore: port `8080`

Keep the emulator process running while using the app.

### 2. Run the iOS app

Open `iosApp/iosApp.xcodeproj` in Xcode, select the `iosApp` scheme, and run it on an iOS Simulator.

Debug builds use the local emulator project `demo-geocircle`. Emulator data is cleared when the emulators stop, so create a new account after restarting them if necessary.

## Tests

Run the Kotlin shared-logic tests from the repository root:

```bash
./gradlew :shared:iosSimulatorArm64Test
```

Run the Firestore security rules tests:

```bash
cd backend
npm test
```

Run the push-notification processor tests:

```bash
cd backend/functions
npm install
npm test
```

Run the iOS UI tests with the Firebase emulators running:

```bash
cd iosApp
xcodebuild \
  -project iosApp.xcodeproj \
  -scheme iosApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

The place-search UI tests require network access to Apple Maps. UI tests install the Debug emulator build on the simulator used for testing.

## Using the cloud Firebase project

Release builds use the configured cloud Firebase project and require a matching `GoogleService-Info.plist`. They do not fall back to the local emulators.

To configure a separate Firebase project:

1. Enable Email/Password authentication in the Firebase console.
2. Create the default Cloud Firestore database.
3. Register the iOS app with bundle ID `com.geocircle.app`.
4. Download its `GoogleService-Info.plist` into `iosApp/iosApp/`. This file is git-ignored.
5. Update `FirebaseSetup.cloudProjectID` if the project ID differs.
6. Build the Release simulator app:

   ```bash
   xcodebuild \
     -project iosApp/iosApp.xcodeproj \
     -scheme iosApp \
     -configuration Release \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     ONLY_ACTIVE_ARCH=YES \
     build
   ```

7. Deploy the Firestore rules after reviewing them:

   ```bash
   cd backend
   firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
   ```

Use the correct Firebase project ID and ensure the Firebase CLI is authenticated before deploying.

## Remote push notifications

The Cloud Functions and Firebase Cloud Messaging integration is implemented in the repository, but remote push notifications are **not yet configured for delivery**.

The implementation is intended to:

- Process new event records on the server.
- Revalidate events against the relevant group, member, and geofence.
- Notify other current group members' registered devices, excluding the sender.
- Avoid including location coordinates in push payloads.
- Prevent repeated processing of the same event.
- Remove unregistered device tokens.

The following setup is still required:

1. A paid Apple Developer Program team with Push Notifications enabled for the iOS app target.
2. An APNs authentication key uploaded in Firebase Console under Project settings and Cloud Messaging.
3. Firebase Blaze billing enabled for Cloud Functions deployment.
4. Deployment of the Functions to the intended Firebase project.
5. Testing on a physical iPhone, including delivery when the app is closed.

Until these steps are completed, group members should not expect remote push notifications when Folkloop is not running on their device.

## Known limitations

- iOS controls when region-monitoring events are delivered. Events may be delayed or missed.
- Reliable background location monitoring depends on iOS permissions and operating-system behaviour.
- Remote push notifications are not configured for delivery.
- Presence is inferred from recorded events, not continuous live location.
- Records older than 12 hours are marked stale, and the presence model uses a limited event-history window.
- Group ownership transfer and group deletion are not implemented.
- The owner cannot leave their own group.
- Stable event IDs prevent duplicate event records, but end-to-end exactly-once notification delivery is not guaranteed.
- The app has been tested with simulator-based flows; physical-device background behaviour and remote push delivery still require validation.

## Current status

The core group, geofence, and event-recording flows are implemented. Firestore rules, shared Kotlin logic, backend processing, and iOS UI tests provide coverage for important parts of the application.

The Release app's cloud arrival and exit flow has been tested using a simulator. Remote push notifications remain a follow-up configuration and device-testing task.

---

**Folkloop** is built around a simple idea: share the events that matter without turning everyday movement into a continuous location feed.
