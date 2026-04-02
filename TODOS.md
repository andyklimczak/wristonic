# wristonic Project TODOs

## Summary
- Build `wristonic` as a standalone `watchOS 10+` app that connects directly to Subsonic-compatible servers, with Navidrome as a primary compatibility target.
- V1 supports live browsing plus playback from the server, album-level offline downloads to the watch, pinned albums, and automatic storage enforcement under a user-defined size cap.
- Follow watch UI best practices: simple list-driven navigation, large touch targets, shallow hierarchy, fast access to Now Playing, and no phone companion flows.

## Product and UX
- Replace the template screen with a root navigation list containing `Artists`, `Albums`, and `Settings`.
- `Artists` flow: indexed artist list from the server, then artist detail showing that artist’s albums.
- Show a blue dot next to an artist name when any album for that artist is downloaded locally.
- `Albums` flow: segmented or picker-based sort/filter for `Name`, `Random`, and `Recently Added`.
- Show a blue dot next to an album name when the album is fully downloaded or contains any downloaded tracks.
- Album detail screen: cover art, track list, stream/play actions, download action, delete-downloaded-album action, pin/unpin state, and local/offline status.
- Persistent mini-entry to `Now Playing` from browse/detail screens using standard watch playback patterns.
- `Settings` screen: server URL, username, password, connect/test action, insecure-server toggle, preferred bitrate/transcode quality, size cap, current saved size, and an `Offline Only` toggle.
- Add a `Downloads` or `Downloaded` screen reachable from `Settings` that shows active download progress, queued items, completed saved albums, and per-album delete actions.
- When `Offline Only` is enabled, artist and album browsing should show only items with downloaded content and playback should resolve to local files only.

## Networking and Server Compatibility
- Add a `SubsonicClient` layer that speaks the Subsonic REST API with Navidrome-compatible defaults.
- Use API version `1.16.1`, JSON responses, client id `wristonic`.
- Store `serverURL`, `username`, and `password` in Keychain-backed settings.
- Derive token auth per request using Subsonic `u/t/s` signing rather than sending the raw password on every request.
- Implement the minimum endpoint set for V1:
  - `ping`
  - `getArtists` or `getIndexes`
  - `getArtist`
  - `getAlbum`
  - `getAlbumList2` for alphabetical, random, and newest/recently-added views
  - `getCoverArt`
  - `stream`
- Streaming and downloads both prefer server transcoding to a watch-friendly lossy format and configured bitrate.
- If the server does not transcode or ignores the transcode parameters, fall back to the original media URL and play/download only if watchOS can handle the format.
- Default security posture is HTTPS; add an advanced opt-in for insecure server setups.
- When enabled, allow HTTP or self-signed setups only for the configured host rather than treating insecurity as the default app mode.

## Local Storage, Downloads, and Playback
- Use a local persistence layer for:
  - server settings
  - album/track metadata cache
  - download records
  - playback history
  - pin state
  - storage cap
  - offline-only preference
- Store downloaded audio files on disk in an app-owned library directory, grouped by album and track id.
- Manage downloads at the album level only in V1.
- Use a serial download queue with resumable tasks where possible.
- The app may queue multiple albums, but only a small number should download concurrently to preserve battery and network stability.
- Enforce the size cap before finalizing a queued download and again after completion as a safety check.
- Eviction policy:
  - pinned albums are never auto-evicted
  - eligible albums are sorted by `playCount ascending`, then `lastPlayedAt ascending`, then `downloadedAt ascending`
  - evict whole albums until projected usage is at or below the cap
  - if the cap still cannot be met because pinned albums already exceed it, block further downloads and show a clear message
- Track saved size from actual file sizes on disk, not metadata estimates.
- Playback should support:
  - starting from an album or a track
  - standard queue progression within the selected album
  - local playback preferred when a track is already downloaded
  - remote streaming otherwise
- When `Offline Only` is enabled, hide non-downloaded artists/albums from browse views and prevent remote streaming fallbacks.
- Update playback history only after a meaningful listen threshold so accidental starts do not distort least-played eviction.

## App Structure and Interfaces
- Introduce core modules and services:
  - `SubsonicClient` for API/auth/request building
  - `LibraryRepository` for server-backed browse models
  - `DownloadManager` for queueing, file persistence, size accounting, and eviction
  - `PlaybackCoordinator` for local-vs-remote playback and Now Playing state
  - `SettingsStore` for server config, cap, and playback/download preferences
- Introduce shared domain types:
  - `ArtistSummary`
  - `AlbumSummary`
  - `AlbumDetail`
  - `Track`
  - `AlbumSortMode = .alphabeticalByName | .random | .recentlyAdded`
  - `DownloadState = .notDownloaded | .queued | .downloading(progress) | .downloaded | .failed`
  - `StoragePolicy` with `capBytes`, `savedBytes`, `pinnedBytes`, and eviction rules
- Keep the watch app standalone: no `WatchConnectivity`, no iPhone sync, no phone-owned library model.

## Test Plan
- Unit tests for:
  - Subsonic token/signature generation
  - decoding of artist, album, and track payloads from representative Subsonic/Navidrome responses
  - album sort mode request mapping
  - transcode URL selection and original-file fallback
  - size accounting from on-disk files
  - eviction ordering with pinning and tie-breakers
  - pinned albums exceed cap blocking behavior
  - local-file preference over streaming during playback resolution
- Integration-style tests around repository and service boundaries with mocked API responses for:
  - successful server login
  - invalid credentials
  - server reachable but missing transcode support
  - recently-added/random/name album browsing
  - album download and restore from persisted state after app relaunch
- UI tests for:
  - first-run server setup
  - browse by artist
  - browse albums by each supported sort mode
  - download an album and see it appear in `Downloads`
  - change size cap and verify storage screen updates
  - pin an album and verify it is protected from automatic eviction

## Assumptions and Defaults
- Minimum platform target is `watchOS 10+`; the template’s current `watchOS 26.4` setting should be lowered.
- V1 scope excludes playlists, search, scrobbling, ratings, podcasts, lyrics, multi-account support, and background sync with any companion app.
- Offline saving is album-only.
- The saved library is surfaced through artist/album browse screens and `Offline Only` filtering rather than a dedicated `Downloads` top-level destination.
- Default storage cap is `8 GB`, adjustable in `1 GB` increments up to available free space.
- Default transcode preference is a watch-friendly lossy stream at a conservative bitrate; the user can adjust this in settings later without changing the overall architecture.
- Server metadata browsing is live from the server, with lightweight local caching for responsiveness and offline display of already-downloaded albums.

## Detailed Todo Checklist

### Phase 0: Project Setup and Baseline
- [x] Lower the app deployment target from the template default to `watchOS 10+`.
- [x] Confirm the app remains standalone with no companion iPhone target or `WatchConnectivity` dependency.
- [x] Define the app folder structure for views, models, services, persistence, and tests.
- [x] Add any required capabilities and entitlements for networking, media playback, and background-friendly download behavior that are appropriate for watchOS.
- [x] Add Info.plist keys and transport security configuration needed for HTTPS by default and opt-in insecure/self-signed server support.
- [x] Replace the template `Hello, world!` entry screen with a placeholder root navigation shell for `Artists`, `Albums`, and `Settings`.

### Phase 1: Core Domain Models and Persistence
- [x] Define shared domain models for artist, album, track, cover art reference, download status, storage policy, and playback history.
- [x] Define a stable identifier strategy for artists, albums, tracks, and download records using Subsonic ids.
- [ ] Choose and implement the local persistence approach for:
- [x] server settings
- [x] album and track metadata cache
- [x] download records
- [x] pin state
- [x] playback history
- [x] size cap
- [x] offline-only preference
- [x] Create repository-facing types for album sort mode, local availability state, and download progress.
- [x] Add disk path conventions for album and track storage in an app-owned library directory.
- [x] Add storage utilities to calculate saved bytes from real files on disk.

### Phase 2: Server Connection and Authentication
- [x] Implement `SettingsStore` for server URL, username, password, bitrate/transcode preference, insecure-server toggle, size cap, and offline-only toggle.
- [x] Store credentials securely using Keychain-backed storage.
- [x] Implement Subsonic request signing with `u`, `t`, and `s` auth parameters.
- [x] Implement common request building with API version `1.16.1`, JSON output, and client id `wristonic`.
- [x] Implement a `ping`-based connection test flow from Settings.
- [x] Add clear error handling for invalid credentials, unreachable servers, malformed URLs, TLS failures, and unsupported responses.
- [x] Add logic to scope insecure/self-signed exceptions to the configured host only.
- [x] Validate compatibility against Navidrome-oriented response samples and assumptions.

### Phase 3: Subsonic API Integration
- [ ] Implement `SubsonicClient` support for:
- [x] `ping`
- [x] `getArtists` or `getIndexes`
- [x] `getArtist`
- [x] `getAlbum`
- [x] `getAlbumList2`
- [x] `getCoverArt`
- [x] `stream`
- [x] Add decoders for artist, album, and track payloads that tolerate Subsonic-compatible server variations where practical.
- [x] Implement album list requests for `Name`, `Random`, and `Recently Added`.
- [x] Implement cover art loading and caching strategy suitable for watch memory constraints.
- [x] Implement stream URL building with preferred transcoding parameters.
- [x] Add fallback behavior for servers that do not transcode or ignore transcode parameters.

### Phase 4: Browse Experience and Navigation
- [x] Build the root navigation screen with `Artists`, `Albums`, and `Settings`.
- [x] Build the `Artists` list screen with lightweight loading, empty state, and error state handling.
- [x] Show a blue dot next to artist names when any album for that artist is downloaded locally.
- [x] Build artist detail screens that show the artist’s albums and each album’s local/download state.
- [x] Build the `Albums` browse screen with sorting/filtering for `Name`, `Random`, and `Recently Added`.
- [x] Show a blue dot next to album names when the album is fully downloaded or contains any downloaded tracks.
- [x] Build album detail screens with cover art, track list, local/download state, and actions.
- [x] Add pull-to-refresh or explicit reload behavior where appropriate for watch-friendly server refreshes.
- [x] Ensure browse screens degrade gracefully when the app is in offline-only mode.

### Phase 5: Playback
- [x] Choose the playback stack for watchOS local and remote audio playback.
- [x] Implement `PlaybackCoordinator` to manage Now Playing state, queue progression, and local-vs-remote source selection.
- [x] Support starting playback from an album.
- [x] Support starting playback from an individual track.
- [x] Prefer local files when a track has been downloaded.
- [x] Fall back to remote streaming when local media is unavailable and offline-only mode is disabled.
- [x] Disable remote playback fallback when offline-only mode is enabled.
- [x] Add basic queue progression within the selected album.
- [x] Expose playback metadata needed for a watch-friendly Now Playing experience.
- [x] Record meaningful playback history only after a listen threshold is met.

### Phase 6: Downloads, Storage Cap, and Eviction
- [x] Implement `DownloadManager` with a serial or tightly limited concurrent queue suitable for watch battery and networking constraints.
- [x] Add album-level download requests from album detail screens.
- [x] Download each track for an album into the library directory using stable file naming.
- [x] Track queued, active, completed, and failed download states.
- [x] Resume or recover in-progress downloads safely after app relaunch when possible.
- [x] Mark local availability at the track and album level based on actual downloaded files.
- [x] Add delete-downloaded-album behavior on album detail screens.
- [x] Ensure deleting an album removes files, updates metadata, and refreshes blue-dot indicators.
- [x] Enforce the user’s size cap before completing a new album download.
- [x] Re-check the size cap after download completion as a safety pass.
- [x] Implement pinning so pinned albums are never auto-evicted.
- [ ] Implement least-played eviction ordering using:
- [x] `playCount ascending`
- [x] `lastPlayedAt ascending`
- [x] `downloadedAt ascending`
- [x] Evict whole albums until storage falls back under the configured cap.
- [x] Block additional downloads when pinned albums alone exceed the cap and show a clear explanation.
- [x] Keep the saved-size display based on actual file sizes on disk rather than server metadata estimates.

### Phase 7: Settings and Download Management UI
- [x] Build the main Settings screen with server credentials, connection test, insecure-server toggle, transcode preference, size cap, saved-size summary, and offline-only toggle.
- [x] Add validation and friendly error messaging for server setup inputs.
- [x] Add a `Downloads` or `Downloaded` screen reachable from Settings.
- [x] Show queued downloads on that screen.
- [x] Show active download progress on that screen.
- [x] Show completed saved albums on that screen.
- [x] Add delete actions for downloaded albums on that screen.
- [x] Surface pinned state and storage usage in download-management views where helpful.
- [x] Ensure settings changes take effect immediately where safe, and on next request/playback where immediate change is not practical.

### Phase 8: Offline-Only Mode and Local Library Behavior
- [x] Implement the persistent `Offline Only` setting.
- [x] Filter artist browsing to only artists with downloaded albums when offline-only mode is enabled.
- [x] Filter album browsing to only albums with downloaded content when offline-only mode is enabled.
- [x] Ensure artist blue dots and album blue dots remain correct while toggling offline-only mode.
- [x] Prevent any remote streaming or remote metadata dependency for already-cached downloaded views when offline-only mode is enabled.
- [x] Define and implement the empty states for offline-only mode when no music has been downloaded yet.

### Phase 9: Polish, Accessibility, and Watch UX
- [x] Review list density, tap target size, and hierarchy depth against watchOS best practices.
- [x] Add loading, empty, and failure states for all major screens.
- [x] Ensure all major actions are reachable with minimal taps on the watch.
- [ ] Add accessibility labels and values for download indicators, playback controls, and settings.
- [x] Check color usage so the blue download dot remains visible and understandable.
- [ ] Review battery, network, and storage behavior for watch-appropriate defaults.
- [ ] Add lightweight instrumentation or debug logging for networking, downloads, eviction, and playback failures.

### Phase 10: Testing and Validation
- Remaining unchecked items in this phase require either broader test coverage or a functioning watch simulator/runtime than is available in the current environment.
- [x] Add unit tests for Subsonic auth token and signature generation.
- [x] Add unit tests for request construction and album sort mode mapping.
- [x] Add unit tests for decoding representative Subsonic and Navidrome artist, album, and track payloads.
- [x] Add unit tests for transcode-preferred stream selection and original-file fallback.
- [x] Add unit tests for local size accounting from real files on disk.
- [x] Add unit tests for download state transitions and album availability aggregation.
- [ ] Add unit tests for eviction ordering, pin protection, and pinned-albums-exceed-cap handling.
- [x] Add unit tests for offline-only filtering at the artist and album levels.
- [ ] Add integration-style tests with mocked API responses for successful login, invalid credentials, server without transcoding, and browse flows.
- [x] Add integration-style tests for download persistence and recovery after app relaunch.
- [ ] Add UI tests for first-run setup, artist browsing, album browsing by each sort mode, album download, delete-downloaded-album, offline-only mode, and settings-driven download management.
- [ ] Run the full test suite and capture any watchOS simulator or device-specific gaps that need manual validation.

### Phase 11: Manual Acceptance Pass
- [ ] Verify connection setup against a Navidrome server.
- [ ] Verify browsing by artist works end-to-end.
- [ ] Verify album browsing by name, random, and recently added works end-to-end.
- [ ] Verify streaming playback works for non-downloaded albums.
- [ ] Verify downloaded albums play locally with networking disabled.
- [ ] Verify the blue dot appears correctly on downloaded albums and artists with downloaded albums.
- [ ] Verify deleting a downloaded album removes the blue dot and frees storage.
- [ ] Verify the downloads management screen in Settings reflects queued, active, and completed downloads accurately.
- [ ] Verify the size cap is enforced and eviction respects pinning and least-played ordering.
- [ ] Verify offline-only mode hides non-downloaded content and prevents streaming fallback.
