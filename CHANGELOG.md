# Changelog

## 0.1.0 — 2026-10-10

- Extract all three products, tests and fixtures from SpaceState, retaining package Git history.
- Add Linux networking imports and a bounded delegate-based streaming transport.
- Apply separate 256 KiB document and 16 MiB directory limits to direct and SpacePush reads.
- Preserve custom loader injection and existing public products.
- Make directory ordering independent of the machine's locale.
- Add macOS/Linux CI and real HTTP tests for size limits, errors, redirects, timeout and cancellation.
