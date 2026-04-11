# Release Checklist

This app ships as an iOS app container plus a standalone watch app:

- iOS container bundle ID: `com.andyklimczak.wristonic`
- watch app bundle ID: `com.andyklimczak.wristonic.watchkitapp`
- current version/build in project: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`

## Repo-Side Readiness

- [ ] In Xcode, confirm your Apple Developer team is set for `wristonic` and `wristonic Watch App`
- [ ] Confirm the bundle IDs above are the ones you want to keep in App Store Connect
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` before every upload
- [ ] Verify the watch icon asset exists in [AppIcon.appiconset](/Users/andy/Dev/wristonic/wristonic%20Watch%20App/Assets.xcassets/AppIcon.appiconset)
- [ ] Run the local release build/test flow you trust before archiving
- [ ] Decide whether to keep Internet Radio visible for v1 or hide it before submission if server compatibility is still uncertain

## App Review Risk

- [ ] Revisit ATS before App Review: [WatchAppInfo.plist](/Users/andy/Dev/wristonic/WatchAppInfo.plist) currently sets `NSAllowsArbitraryLoads = true`
- [ ] Keep App Review notes ready explaining that the app connects to user-specified Subsonic/Navidrome servers, including self-hosted and HTTP setups
- [ ] Verify your final release build still connects correctly to the production servers you care about

## Real Device Validation

- [ ] Install on a real watch paired to your iPhone
- [ ] Set up a Navidrome/Subsonic server from the watch
- [ ] Download two albums on Wi-Fi
- [ ] Start album one on Wi-Fi, leave the phone and Wi-Fi behind, then switch to album two
- [ ] Finish an album fully offline and confirm playback stays local
- [ ] Return to Wi-Fi and confirm queued scrobbles flush
- [ ] Start a download, switch to another app, and verify the download continues
- [ ] Verify album-start haptic and album-end double haptic on device
- [ ] Verify repeat-album state and album sort survive app relaunch

## App Store Connect Setup

- [ ] Ensure the Account Holder has accepted the latest Apple agreements
- [ ] Create the app record in App Store Connect before the first upload
- [ ] Use the iOS platform app record, then add Apple Watch screenshots under the Apple Watch tab
- [ ] Choose app name, primary language, SKU, category, and age rating
- [ ] Add a Support URL
- [ ] Add a publicly reachable Privacy Policy URL
- [ ] Fill in App Privacy answers in App Store Connect
- [ ] Prepare App Review notes, including test credentials or a demo server path if review needs one

## TestFlight

- [ ] Archive from Xcode
- [ ] Validate and upload the archive in Organizer
- [ ] Wait for processing to complete in App Store Connect
- [ ] Add internal testers first
- [ ] Fill in TestFlight test information:
  - beta description
  - feedback email
  - what to test
- [ ] If you want external testers, create an internal group first, then an external group
- [ ] Add release notes describing downloads, offline playback, supported server expectations, and any known limitations

## App Store Submission

- [ ] Create the first iOS version record in App Store Connect
- [ ] Upload at least one Apple Watch screenshot set
- [ ] Add subtitle, description, keywords, support URL, marketing URL if you have one, and copyright
- [ ] Add App Review contact details and notes
- [ ] Select the processed build
- [ ] Complete export compliance questions
- [ ] Submit for review

## Notes

- The project targets `watchOS 10.0`.
- CI exists in [.github/workflows/ci.yml](/Users/andy/Dev/wristonic/.github/workflows/ci.yml) and should be green before upload.
