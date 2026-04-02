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
- [ ] Lower the app deployment target from the template default to `watchOS 10+`.
- [ ] Confirm the app remains standalone with no companion iPhone target or `WatchConnectivity` dependency.
- [ ] Define the app folder structure for views, models, services, persistence, and tests.
- [ ] Add any required capabilities and entitlements for networking, media playback, and background-friendly download behavior that are appropriate for watchOS.
- [ ] Add Info.plist keys and transport security configuration needed for HTTPS by default and opt-in insecure/self-signed server support.
- [ ] Replace the template `Hello, world!` entry screen with a placeholder root navigation shell for `Artists`, `Albums`, and `Settings`.

### Phase 1: Core Domain Models and Persistence
- [ ] Define shared domain models for artist, album, track, cover art reference, download status, storage policy, and playback history.
- [ ] Define a stable identifier strategy for artists, albums, tracks, and download records using Subsonic ids.
- [ ] Choose and implement the local persistence approach for:
- [ ] server settings
- [ ] album and track metadata cache
- [ ] download records
- [ ] pin state
- [ ] playback history
- [ ] size cap
- [ ] offline-only preference
- [ ] Create repository-facing types for album sort mode, local availability state, and download progress.
- [ ] Add disk path conventions for album and track storage in an app-owned library directory.
- [ ] Add storage utilities to calculate saved bytes from real files on disk.

### Phase 2: Server Connection and Authentication
- [ ] Implement `SettingsStore` for server URL, username, password, bitrate/transcode preference, insecure-server toggle, size cap, and offline-only toggle.
- [ ] Store credentials securely using Keychain-backed storage.
- [ ] Implement Subsonic request signing with `u`, `t`, and `s` auth parameters.
- [ ] Implement common request building with API version `1.16.1`, JSON output, and client id `wristonic`.
- [ ] Implement a `ping`-based connection test flow from Settings.
- [ ] Add clear error handling for invalid credentials, unreachable servers, malformed URLs, TLS failures, and unsupported responses.
- [ ] Add logic to scope insecure/self-signed exceptions to the configured host only.
- [ ] Validate compatibility against Navidrome-oriented response samples and assumptions.

### Phase 3: Subsonic API Integration
- [ ] Implement `SubsonicClient` support for:
- [ ] `ping`
- [ ] `getArtists` or `getIndexes`
- [ ] `getArtist`
- [ ] `getAlbum`
- [ ] `getAlbumList2`
- [ ] `getCoverArt`
- [ ] `stream`
- [ ] Add decoders for artist, album, and track payloads that tolerate Subsonic-compatible server variations where practical.
- [ ] Implement album list requests for `Name`, `Random`, and `Recently Added`.
- [ ] Implement cover art loading and caching strategy suitable for watch memory constraints.
- [ ] Implement stream URL building with preferred transcoding parameters.
- [ ] Add fallback behavior for servers that do not transcode or ignore transcode parameters.

### Phase 4: Browse Experience and Navigation
- [ ] Build the root navigation screen with `Artists`, `Albums`, and `Settings`.
- [ ] Build the `Artists` list screen with lightweight loading, empty state, and error state handling.
- [ ] Show a blue dot next to artist names when any album for that artist is downloaded locally.
- [ ] Build artist detail screens that show the artist’s albums and each album’s local/download state.
- [ ] Build the `Albums` browse screen with sorting/filtering for `Name`, `Random`, and `Recently Added`.
- [ ] Show a blue dot next to album names when the album is fully downloaded or contains any downloaded tracks.
- [ ] Build album detail screens with cover art, track list, local/download state, and actions.
- [ ] Add pull-to-refresh or explicit reload behavior where appropriate for watch-friendly server refreshes.
- [ ] Ensure browse screens degrade gracefully when the app is in offline-only mode.

### Phase 5: Playback
- [ ] Choose the playback stack for watchOS local and remote audio playback.
- [ ] Implement `PlaybackCoordinator` to manage Now Playing state, queue progression, and local-vs-remote source selection.
- [ ] Support starting playback from an album.
- [ ] Support starting playback from an individual track.
- [ ] Prefer local files when a track has been downloaded.
- [ ] Fall back to remote streaming when local media is unavailable and offline-only mode is disabled.
- [ ] Disable remote playback fallback when offline-only mode is enabled.
- [ ] Add basic queue progression within the selected album.
- [ ] Expose playback metadata needed for a watch-friendly Now Playing experience.
- [ ] Record meaningful playback history only after a listen threshold is met.

### Phase 6: Downloads, Storage Cap, and Eviction
- [ ] Implement `DownloadManager` with a serial or tightly limited concurrent queue suitable for watch battery and networking constraints.
- [ ] Add album-level download requests from album detail screens.
- [ ] Download each track for an album into the library directory using stable file naming.
- [ ] Track queued, active, completed, and failed download states.
- [ ] Resume or recover in-progress downloads safely after app relaunch when possible.
- [ ] Mark local availability at the track and album level based on actual downloaded files.
- [ ] Add delete-downloaded-album behavior on album detail screens.
- [ ] Ensure deleting an album removes files, updates metadata, and refreshes blue-dot indicators.
- [ ] Enforce the user’s size cap before completing a new album download.
- [ ] Re-check the size cap after download completion as a safety pass.
- [ ] Implement pinning so pinned albums are never auto-evicted.
- [ ] Implement least-played eviction ordering using:
- [ ] `playCount ascending`
- [ ] `lastPlayedAt ascending`
- [ ] `downloadedAt ascending`
- [ ] Evict whole albums until storage falls back under the configured cap.
- [ ] Block additional downloads when pinned albums alone exceed the cap and show a clear explanation.
- [ ] Keep the saved-size display based on actual file sizes on disk rather than server metadata estimates.

### Phase 7: Settings and Download Management UI
- [ ] Build the main Settings screen with server credentials, connection test, insecure-server toggle, transcode preference, size cap, saved-size summary, and offline-only toggle.
- [ ] Add validation and friendly error messaging for server setup inputs.
- [ ] Add a `Downloads` or `Downloaded` screen reachable from Settings.
- [ ] Show queued downloads on that screen.
- [ ] Show active download progress on that screen.
- [ ] Show completed saved albums on that screen.
- [ ] Add delete actions for downloaded albums on that screen.
- [ ] Surface pinned state and storage usage in download-management views where helpful.
- [ ] Ensure settings changes take effect immediately where safe, and on next request/playback where immediate change is not practical.

### Phase 8: Offline-Only Mode and Local Library Behavior
- [ ] Implement the persistent `Offline Only` setting.
- [ ] Filter artist browsing to only artists with downloaded albums when offline-only mode is enabled.
- [ ] Filter album browsing to only albums with downloaded content when offline-only mode is enabled.
- [ ] Ensure artist blue dots and album blue dots remain correct while toggling offline-only mode.
- [ ] Prevent any remote streaming or remote metadata dependency for already-cached downloaded views when offline-only mode is enabled.
- [ ] Define and implement the empty states for offline-only mode when no music has been downloaded yet.

### Phase 9: Polish, Accessibility, and Watch UX
- [ ] Review list density, tap target size, and hierarchy depth against watchOS best practices.
- [ ] Add loading, empty, and failure states for all major screens.
- [ ] Ensure all major actions are reachable with minimal taps on the watch.
- [ ] Add accessibility labels and values for download indicators, playback controls, and settings.
- [ ] Check color usage so the blue download dot remains visible and understandable.
- [ ] Review battery, network, and storage behavior for watch-appropriate defaults.
- [ ] Add lightweight instrumentation or debug logging for networking, downloads, eviction, and playback failures.

### Phase 10: Testing and Validation
- [ ] Add unit tests for Subsonic auth token and signature generation.
- [ ] Add unit tests for request construction and album sort mode mapping.
- [ ] Add unit tests for decoding representative Subsonic and Navidrome artist, album, and track payloads.
- [ ] Add unit tests for transcode-preferred stream selection and original-file fallback.
- [ ] Add unit tests for local size accounting from real files on disk.
- [ ] Add unit tests for download state transitions and album availability aggregation.
- [ ] Add unit tests for eviction ordering, pin protection, and pinned-albums-exceed-cap handling.
- [ ] Add unit tests for offline-only filtering at the artist and album levels.
- [ ] Add integration-style tests with mocked API responses for successful login, invalid credentials, server without transcoding, and browse flows.
- [ ] Add integration-style tests for download persistence and recovery after app relaunch.
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
