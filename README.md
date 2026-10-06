# aud_midi_core

Runtime contracts of the aud_midi family: backend interfaces, a fake backend, the software scheduler, the port registry and diagnostics.

Part of the aud_midi family, see [aud_midi](https://github.com/audanika/aud_midi).

## Goals

- MidiBackend, advertiser and BLE transport interfaces
- FakeMidiBackend for tests
- Software scheduler with the send contract
- Port registry and diagnostics bus
- No dart:io, dart:ffi or dart:isolate

## State

Boilerplate only. The implementation follows in later tickets, see the plan in [aud_midi](https://github.com/audanika/aud_midi/blob/main/blog/2026/10/01_plan_the_package_implementation.md).

## Installation

```bash
dart pub add aud_midi_core
```

## Contributing

See [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
