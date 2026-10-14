# SpaceStateKit

Shared Swift package for [SpaceState](https://github.com/kerker00/SpaceState) and [SpaceStateCLI](https://github.com/kerker00/SpaceStateCLI), extracted with its original Git history.

| Product | Purpose |
| --- | --- |
| `SpaceAPI` | SpaceAPI models, tolerant directory decoding and bounded HTTP client |
| `MainframeStatus` | Optional Mainframe Oldenburg room states |
| `SpacePushClient` | SpacePush reads, direct-read fallback, active-period reporting and APNs registration |

The package has no UI dependencies. APNs registration remains an Apple-specific service operation; Linux consumers can use `SpaceAPI` independently. `SpacePushClient` retains its Mainframe dependency to preserve the existing Apple API.

## Requirements

Swift 6.2+, iOS 26+ or macOS 26+ on Apple platforms. CI targets Ubuntu 24.04 x86_64 with Swift 6.2, plus macOS. Linux support is verified by the repository's CI, rather than inferred from conditional imports. ARM64 Linux and static binaries are not yet part of the release acceptance.

```swift
.package(url: "https://github.com/kerker00/SpaceStateKit.git", exact: "0.3.2")
```

Import only the products your application needs:

```swift
import Foundation
import SpaceAPI

let info = try await StatusClient().space(at: URL(string: "https://status.mainframe.io/api/spaceInfo")!)
print(info.name, info.status.rawValue)
```

## What `SpaceInfo` covers

`SpaceInfo` follows SpaceAPI schema v15 and also reads older layouts (flat v0.12 fields, `api`, top-level `icon`, `jabber`):

- name, logo, website, state (open, last change, message, trigger person, open/closed icons)
- location (address, coordinates, timezone, country code, access hint)
- contacts, including XMPP, Mumble, SIP, issue mail, Gopher and keymasters
- feeds (blog, wiki, calendar, Flickr), projects, links and linked spaces
- `api_compatibility` and the older `api` version

Not modelled yet: sensors, membership plans, webcams, areas, SpaceFED, events and `ext_*` fields.

Decoding is tolerant because many endpoints do not follow the schema exactly. A malformed optional field becomes `nil` or is left out of its array without affecting the rest of the document; only a missing `space` name fails. Every link must be an absolute `http` or `https` URL with a host; other schemes such as `javascript:` or `file:` are dropped. Both icons must pass this check, or the icon pair is dropped.

## Android

`Android/` builds `spacestatekit-android`, an AAR for the [SpaceState Android app](https://github.com/kerker00/SpaceState-Android). A small Swift facade (`SpaceStateKitAndroid`) exposes the three products with types swift-java bridges cleanly; `SpaceStateClient` wraps it for Kotlin with data classes and suspend functions. The AAR contains the generated bindings, swift-java's `SwiftKitCore` runtime (not yet on Maven Central), the Swift runtime for arm64-v8a and x86_64, and R8 rules.

Requirements: the Swift 6.4 SDK for Android (`swift sdk install`, then its `setup-android-sdk.sh`), Android NDK r30 and JDK 17+.

```sh
cd Android
./gradlew assembleRelease      # build/outputs/aar/spacestatekit-android-release.aar
```

The first build compiles swift-syntax for swift-java's code generator and takes several minutes. To run the package tests on an emulator, build with `swift build --swift-sdk swift-6.4.0-RELEASE_android --triple x86_64-unknown-linux-android28 --build-tests` (without `--static-swift-stdlib`), push the test runners, fixture bundles and the SDK's runtime libraries with `adb`, and run each `*-test-runner` with `LD_LIBRARY_PATH=.`.

## HTTP behavior

`SpaceEndpoint.parse` validates a raw endpoint string and `SpaceEndpoint.validate`
checks a constructed URL. Endpoints must be absolute HTTP(S) URLs with a nonempty
host and, when specified, a port from 1 to 65535. Embedded credentials and literal
or percent-encoded control characters are rejected before loading, including with
an injected loader. Local hosts remain supported; these checks do not restrict
access to particular networks. Directory decoding drops invalid endpoint entries
individually. The Android facade uses the same contract and reports invalid
endpoints or proxy configuration as `SpaceStateException.InvalidEndpoint`; an
invalid configured proxy no longer silently selects direct reads.

Endpoint validation is available starting with 0.3.1 and is not present in the
0.2.0 or 0.3.0 tags. Consumers need to adopt 0.3.1 or a later release.

The default transport streams through `URLSessionDataDelegate` on both platforms. It rejects oversized declared lengths and cancels as soon as received chunks exceed the limit; it does not first download the full response. Space documents and extra endpoints are limited to 256 KiB; directories to 16 MiB. SpacePush uses the same bounded transport. Injected loaders remain available for consumers and tests; returned bodies are also checked.

Requests have a 15-second timeout, including a total resource deadline. Swift task cancellation stops the HTTP task. HTTP(S) redirects are followed with URLSession's redirect limit; invalid endpoint redirects and HTTPS-to-HTTP downgrades are refused. Directory names use numeric, case-insensitive comparison in a fixed `en_US_POSIX` locale, with endpoint ordering as a tie breaker.

## Observation age (0.3.2)

Version 0.3.2 adds `spaceObservation(at:)`, `mainframeRoomsObservation()`
and `directoryObservations()` to the appropriate clients and `StatusService`.
They return `StatusObservation<Value>` with `ObservationTiming`. These APIs are
available starting with 0.3.2 and are not in earlier tags. Consumers must
deliberately adopt the published source release to receive the new APIs.

```swift
let observation = try await StatusClient().spaceObservation(at: endpoint)
let status = observation.timing.currentStatus(observation.value.status)
```

Keep the value for a labelled last known view, but evaluate `freshness(at:)` or
`currentStatus(_:at:)` again whenever displaying it. A retained successful read
expires without another request; stale or unknown timing cannot provide a current
open/closed state. Unknown reported states remain unknown even with current timing.
The caller tracks its own last attempt and errors separately; failures return no
successful observation.

- `observedAt` is the proxy's last successful endpoint fetch, an entry's original
  directory `lastSeen`, or the successful receipt time for a direct endpoint read.
- `receivedAt` is the client's successful receipt. Fetching a cached proxy answer
  or a directory list does not replace older or missing observation times.
- `source` identifies the read path (`direct`, `aggregator`, `spacePush`), not a
  physical measurement source. SpaceAPI `state.lastchange` and room `since` remain
  state-change times, independent of observation age.
- `expiresAt` is the observation plus its age limit, shortened by an advertised
  proxy expiry when present. Expiry is exclusive. Missing, nonfinite, invalid or
  future-at-receipt timing, explicit failed directory reachability, and a backwards
  client clock provide unknown freshness. The value and original times remain
  available. Broken optional directory validation fields do not discard entries.

Proxy reads preserve `X-SpacePush-Fetched-At`, `X-SpacePush-Max-Data-Age` and
`X-SpacePush-Expires-At`. Older servers with only the original fetch header use a
conservative 900-second default. A missing fetch header or a malformed present
policy/expiry never becomes a newly observed current value. `StatusService` tries
its direct HTTPS fallback for a stale or unproven proxy space/room observation;
cancellation does not start a fallback. Per-entry unknown directory states stay
listed and do not force the whole directory onto the fallback path.

Direct reads use a 900-second default retention limit, with clock and policy
injection available through the new initializer. Successful HTTP receipt proves
a usable answer was received, not that the upstream physically measured its state
at that moment. Existing value-only APIs and loader initializers remain available;
they do not themselves expire locally retained data. Consumer adoption is separate
from publishing this SDK; consumers must use observation APIs to expire retained values.

## Android observations (unreleased)

The Android Swift facade adds `spaceObservation(endpoint:)`,
`mainframeRoomsObservation()` and `directoryObservations()`. `ObservedSpace`,
`ObservedRooms` and `ObservedDirectoryItem` retain reported values alongside
JNI-compatible `ReadTiming`: read-path source, original observation, successful
client receipt and conservative expiry. The room document keeps timing even if
its decoded list is empty; directory observations keep each entry's own evidence.
Optional dates outside the portable 1970–9999 range are omitted, never replaced
with the client's current time.

The Kotlin client exposes the corresponding suspend methods as
`StatusObservation<T>`. Use `observation.timing.currentStatus(reported, now)` or
`freshness(now)` again when displaying retained data. Expiry is exclusive, a
backwards clock is unknown, and missing, future or explicitly unreachable
observations cannot provide a current opening. Receipt and state-change timestamps
are independent. Failed attempts belong to the app's state; they must not overwrite
successful observation times. Existing value-only methods remain available.

These Android additions are **not in tag 0.3.2**. Host Swift builds/tests compile
the production facade without JNI. Generated Java bindings, Kotlin compilation,
both native ABIs, optimized AAR/app launch and lifecycle behavior still require
validation on the configured Linux Android toolchain. Host tests do not establish
native build or runtime compatibility. No AAR publication or new release is
implied by this source change.

## Development and verification

```sh
swift build -c release
swift test
python3 IntegrationTests/run.py
```

The Python runner starts a temporary local HTTP server and exercises the actual networking implementation: success, HTTP errors, redirects, advertised and chunked oversized bodies, directory-sized bodies, timeout, and cancellation. These tests do not require access to production services. Regular unit tests cover the models and all three products.

## Maintenance

In the local multi-repository SpaceState workspace, the shared roadmap is `../Plan.md`. It is a workspace file, not part of this public repository.

Changes belong in this repository. Open a branch and pull request, run both CI jobs, and publish a new semantic version tag after successful checks. Consumers use an exact release until they deliberately update it. Changes to public models, limits, behavior and supported platforms are recorded in [CHANGELOG.md](CHANGELOG.md). During the `0.x` series, incompatible public API changes require a new minor version; compatible fixes use a patch version.

The sibling workspace can develop SpaceStateCLI against this checkout with `SPACESTATEKIT_PATH=../SpaceStateKit`. Do not copy sources back into the Apple application.

MIT; see [LICENSE.MD](LICENSE.MD).
