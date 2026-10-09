# SpaceStateKit

The Swift package behind the SpaceState apps. It reads [SpaceAPI](https://spaceapi.io) data and Mainframe Oldenburg's additional room states.

## Products

| Product | Purpose |
| --- | --- |
| `SpaceAPI` | Generic SpaceAPI models, directory decoding and an asynchronous HTTP client |
| `MainframeStatus` | Optional Mainframe room and state support, built on `SpaceAPI` |

Both products use Foundation and have no SwiftUI, AppKit or UIKit dependencies. Their models and HTTP client can form a shared core for Apple and Linux applications. Desktop interfaces, notifications and platform-specific integration belong in the consuming applications.

## Requirements and tests

- Swift 6.2 or later, as declared in [Package.swift](Package.swift).
- The package currently declares minimum Apple deployment versions of iOS 26 and macOS 26. These declarations do not exclude Linux.
- Linux support is planned; a successful Linux build and test run is still required before claiming compatibility.

From this directory:

```sh
swift build
swift test
```

## Linux support plan

Swift and Swift Package Manager officially support Linux. Foundation provides the data and JSON types used here; networking types such as `URLSession`, `URLRequest` and `HTTPURLResponse` are provided through `FoundationNetworking` on Linux. See [Swift platform support](https://www.swift.org/platform-support/) and the [Foundation project](https://github.com/swiftlang/swift-corelibs-foundation#project-navigator).

The current code review identifies the following work before Linux support can be advertised:

1. Add a conditional networking import in `Sources/SpaceAPI/StatusClient.swift`, `Tests/SpaceAPITests/StatusClientTests.swift` and `Tests/MainframeStatusTests/MainframeTests.swift`:

   ```swift
   #if canImport(FoundationNetworking)
   import FoundationNetworking
   #endif
   ```

2. Run `swift build` and `swift test` on Linux and macOS in CI using a compatible Swift toolchain. The existing Swift Testing tests and SwiftPM fixture resources can be reused.
3. Exercise the real HTTP implementation against a local test server, covering successful requests, HTTP errors, timeouts and cancellation. The existing HTTP tests use injected loaders.
4. Check directory sorting with numbers, umlauts and different locale settings. `localizedStandardCompare` may produce platform-dependent ordering.

These are the changes identified by static inspection; Linux builds may reveal further differences. The networking imports and Linux CI have not yet been added.

## Extraction and Linux applications

Once its public API is stable, `SpaceAPI` is intended to be published as an independent Swift package with Linux verification in CI. Mainframe-specific behavior stays in the separate `MainframeStatus` module so other spaces can use the generic client directly.

The first Linux consumer is planned as a small command-line tool that can find spaces and query their status, with human-readable and JSON output. JSON output makes it usable from scripts and applications written in other languages, including status-bar integrations and displays in a hackerspace. Linux binaries should be distributed with the runtime dependencies needed for their target environment.

A Linux desktop application can later reuse the same core. It needs its own interface and adapters for desktop notifications and status-bar integration; the existing SwiftUI interface belongs to the Apple apps.

## License

MIT, see [LICENSE.MD](../LICENSE.MD).
