# Changelog

## 0.3.0 — 2026-10-11

Additive: the Swift products are unchanged.

- `Android/`: Android library for the SpaceState Android app. The package is cross-compiled with the Swift SDK for Android (arm64-v8a, x86_64) and bridged to Kotlin with swift-java 0.6.0 in JNI mode. It is a separate package, so Apple and Linux consumers never resolve swift-java.
- Kotlin API `SpaceStateClient` with `space`, `mainframeRooms` and `directory` as suspend functions; push registration follows.
- Failures reach Kotlin as `SpaceStateException` (unreachable, timeout, HTTP status, response too large, invalid data), since Foundation's error descriptions on Android are raw `NSError` dumps. Kotlin calls have a 30-second deadline as a backstop: right after a network change, a request was seen to hang past the transport's 15 seconds.
- The package's tests pass on an Android 37 emulator; static linking of the standard library is not supported for `FoundationNetworking` or swift-testing, so the AAR ships the Swift runtime as shared libraries (about 23 MB compressed per ABI).

## 0.2.0 — 2026-10-11

Additive: existing properties and initialisers keep working.

- `Location.countryCode` and `Location.hint`.
- `State.icon` with open and closed pictures, also read from the top-level `icon` of older documents.
- `Contact`: `xmpp` (also from the older `jabber`), `mumble`, `sip`, `issueMail`, `gopher` and `keymasters`.
- `SpaceInfo.feeds` with blog, wiki, calendar and Flickr feeds and their types; `calendar` now reads and writes `feeds.calendar`.
- `projects`, `links` and `linkedSpaces`.
- `apiCompatibility` and `legacyAPIVersion` (the `api` field before v14).
- Arrays decode tolerantly per element; every new link is limited to `http` and `https`.
- Fixtures from real v14 and v15 documents, with personal data replaced, and a fixture of malformed fields.

## 0.1.0 — 2026-10-10

- Extract all three products, tests and fixtures from SpaceState, retaining package Git history.
- Add Linux networking imports and a bounded delegate-based streaming transport.
- Apply separate 256 KiB document and 16 MiB directory limits to direct and SpacePush reads.
- Preserve custom loader injection and existing public products.
- Make directory ordering independent of the machine's locale.
- Add macOS/Linux CI and real HTTP tests for size limits, errors, redirects, timeout and cancellation.
