# wristonic

> music, but from your wrist.

`wristonic` is a watchOS app for Subsonic-compatible servers such as Navidrome. It is built for quick library browsing, playback control, offline downloads, and lightweight settings directly on Apple Watch.

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/us/app/wristonic/id6762027816)

If you use the app, App Store reviews are appreciated.

## Features

- Connect to a Subsonic-compatible server from Apple Watch
- Browse artists and albums
- View album details and start playback
- See now playing state and playback progress
- Download albums for offline listening
- Set a storage cap and offline-only playback mode
- Optionally show internet radio stations

## Screenshots

| Main | Artists |
| --- | --- |
| ![Main](<screenshots/main.png>) | ![Artists](<screenshots/artists.png>) |
| Albums | Album Detail |
| ![Albums](<screenshots/albums.png>) | ![Album Detail](<screenshots/album detail.png>) |
| Currently Playing |  |
| ![Currently Playing](<screenshots/currently playing.png>) |  |

## Development

Open `wristonic.xcodeproj` in Xcode, select the `wristonic Watch App` scheme, and run it on a watchOS simulator or device.

## Tests

Run the watch unit tests with:

```sh
xcodebuild \
  -project wristonic.xcodeproj \
  -scheme "wristonic Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch SE (40mm) (2nd generation)' \
  -only-testing:'wristonic Watch AppTests' \
  test
```

## License

MIT. See [LICENSE](LICENSE).

## Privacy

See [PRIVACY.md](PRIVACY.md).
