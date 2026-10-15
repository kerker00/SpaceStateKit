# Changelog

## Unreleased

- Add `SpaceInfo.sensors` with typed numeric/door readings and optional unit,
  location, name, description and value-change time. Skip invalid entries
  individually and preserve other sensor kinds as generic JSON, including
  compound wind/radiation data. Visitor-name and connected-machine lists are
  omitted from typed readings. Sensor changes do not refresh observation age.
  Existing constructors default to empty sensors; consumer UI, Kotlin exports
  and a new release remain separate changes.
- Add observation reads to the Android Swift facade and Kotlin client for spaces,
  the whole Mainframe room document and individual directory entries. Preserve
  original source, successful receipt and conservative expiry without filling
  missing lastSeen or confusing state changes with observation time.
- Add JNI-compatible observation wrappers and Kotlin `ObservationTiming`,
  `ObservationFreshness`, `ObservationSource` and `StatusObservation`. Consumers
  reevaluate retained data; stale or unproven observations supply unknown current
  status. Existing value-only methods and Kotlin data constructors remain available.
- Omit nonfinite or nonportable optional dates at the facade boundary and avoid
  saturating Android timestamp conversions. These changes are not in tag 0.3.2;
  Android bindings/AAR and app adoption require a native Linux build.

## 0.3.2 — 2026-10-13

- Add `StatusObservation`, `ObservationTiming`, `ObservationSource` and
  `ObservationFreshness`, separating source observation, client receipt and expiry
  from state-change times. Retained stale or unproven values have unknown current
  status; explicit directory reachability failures preserve data without a current
  opening. `DirectoryEntry.reachable` is optional and defaults to nil.
- Add observation reads for spaces, directories and Mainframe rooms. Preserve
  SpacePush headers and per-entry lastSeen, with a 900-second default policy for
  direct reads and older proxy responses. `StatusService` falls back over HTTPS
  for stale or unproven proxy space/room observations, preserving cancellation.
- Keep the existing value-only APIs and loader initializer signatures. Add clock
  injection for deterministic observation tests. Consumer adoption remains a
  separate step; previous tags are unchanged.

## 0.3.1 — 2026-10-13

- Add `SpaceEndpoint.parse`, `SpaceEndpoint.validate` and `EndpointValidationError`.
  Require absolute HTTP(S) endpoints with a host, valid port, no embedded credentials
  and no literal or percent-encoded control characters at direct-read, SpacePush-read
  and registration boundaries. Initializer signatures and URL identities are preserved.
- Skip invalid directory endpoint entries individually; use the same validation for
  redirects while retaining HTTPS downgrade protection.
- Android facade: validate raw endpoint strings and configured proxy URLs. Invalid
  configuration fails with the existing `invalidEndpoint` code instead of selecting
  direct reads silently. Host tests compile the production Swift facade without JNI.

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
