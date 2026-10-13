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
.package(url: "https://github.com/kerker00/SpaceStateKit.git", exact: "0.3.0")
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

This endpoint validation is unreleased and is not present in the existing 0.2.0 or
0.3.0 tags. Consumers need to adopt a release containing these changes.

The default transport streams through `URLSessionDataDelegate` on both platforms. It rejects oversized declared lengths and cancels as soon as received chunks exceed the limit; it does not first download the full response. Space documents and extra endpoints are limited to 256 KiB; directories to 16 MiB. SpacePush uses the same bounded transport. Injected loaders remain available for consumers and tests; returned bodies are also checked.

Requests have a 15-second timeout, including a total resource deadline. Swift task cancellation stops the HTTP task. HTTP(S) redirects are followed with URLSession's redirect limit; invalid endpoint redirects and HTTPS-to-HTTP downgrades are refused. Directory names use numeric, case-insensitive comparison in a fixed `en_US_POSIX` locale, with endpoint ordering as a tie breaker.

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
