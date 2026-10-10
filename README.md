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
.package(url: "https://github.com/kerker00/SpaceStateKit.git", exact: "0.1.0")
```

Import only the products your application needs:

```swift
import Foundation
import SpaceAPI

let info = try await StatusClient().space(at: URL(string: "https://status.mainframe.io/api/spaceInfo")!)
print(info.name, info.status.rawValue)
```

## HTTP behavior

The default transport streams through `URLSessionDataDelegate` on both platforms. It rejects oversized declared lengths and cancels as soon as received chunks exceed the limit; it does not first download the full response. Space documents and extra endpoints are limited to 256 KiB; directories to 16 MiB. SpacePush uses the same bounded transport. Injected loaders remain available for consumers and tests; returned bodies are also checked.

Requests have a 15-second timeout, including a total resource deadline. Swift task cancellation stops the HTTP task. HTTP(S) redirects are followed with URLSession's redirect limit; HTTPS-to-HTTP downgrades are refused. Directory names use numeric, case-insensitive comparison in a fixed `en_US_POSIX` locale, with endpoint ordering as a tie breaker.

## Development and verification

```sh
swift build -c release
swift test
python3 IntegrationTests/run.py
```

The Python runner starts a temporary local HTTP server and exercises the actual networking implementation: success, HTTP errors, redirects, advertised and chunked oversized bodies, directory-sized bodies, timeout, and cancellation. These tests do not require access to production services. Regular unit tests cover the models and all three products.

## Maintenance

Changes belong in this repository. Open a branch and pull request, run both CI jobs, and publish a new semantic version tag after successful checks. Consumers use an exact release until they deliberately update it. Changes to public models, limits, behavior and supported platforms are recorded in [CHANGELOG.md](CHANGELOG.md). During the `0.x` series, incompatible public API changes require a new minor version; compatible fixes use a patch version.

The sibling workspace can develop SpaceStateCLI against this checkout with `SPACESTATEKIT_PATH=../SpaceStateKit`. Do not copy sources back into the Apple application.

MIT; see [LICENSE.MD](LICENSE.MD).
