# TestFlight Prep

## Project

- [ ] In Xcode, set your Apple Developer team for `wristonic` and `wristonic Watch App`
- [ ] Confirm the bundle IDs are correct for your account:
  - `com.andyklimczak.wristonic`
  - `com.andyklimczak.wristonic.watchkitapp`
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` before each upload
- [ ] Verify the watch app icon is present in [AppIcon.appiconset](/Users/andy/Dev/wristonic/wristonic%20Watch%20App/Assets.xcassets/AppIcon.appiconset)

## Real Device

- [ ] Install on a real watch paired to your iPhone
- [ ] Set up a Navidrome/Subsonic server from the watch
- [ ] Download two albums on Wi-Fi
- [ ] Start album one on Wi-Fi, leave the phone and Wi-Fi behind, then switch to album two
- [ ] Finish an album fully offline and confirm playback stays local
- [ ] Return to Wi-Fi and confirm queued scrobbles flush to Navidrome/Last.fm
- [ ] Start a download, switch to another app, and verify the download continues

## Release

- [ ] Select an iPhone + Apple Watch destination that matches your real hardware or `Any iOS Device (arm64)` for archive
- [ ] Run `Product > Archive`
- [ ] In Organizer, validate the archive and upload it to App Store Connect
- [ ] Add release notes in TestFlight describing offline playback, downloads, and known limitations

## Known Risk

- `NSAllowsArbitraryLoads` is still enabled in [WatchAppInfo.plist](/Users/andy/Dev/wristonic/WatchAppInfo.plist) to support user-configured insecure/self-hosted Subsonic servers. This is convenient for testing, but it may need a tighter ATS story before App Store review.
