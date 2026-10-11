# Changelog

## 0.2.0 — unreleased

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
