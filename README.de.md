# aud_midi_core

Laufzeit-Verträge der aud_midi-Familie: Backend-Interfaces, Fake-Backend, Software-Scheduler, Port-Registry und Diagnose.

Teil der aud_midi-Familie, siehe [aud_midi](https://github.com/audanika/aud_midi).

## Ziele

- MidiBackend-, Advertiser- und BLE-Transport-Interfaces
- FakeMidiBackend für Tests
- Software-Scheduler mit dem Send-Vertrag
- Port-Registry und Diagnose-Bus
- Kein dart:io, dart:ffi oder dart:isolate

## Stand

Nur Boilerplate. Die Implementierung folgt in späteren Tickets, siehe den Plan in [aud_midi](https://github.com/audanika/aud_midi/blob/main/blog/2026/10/01_plan_the_package_implementation.md).

## Installation

```bash
dart pub add aud_midi_core
```

## Mitwirken

Siehe [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
