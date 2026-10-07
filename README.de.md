# aud_midi_core

Laufzeit-Verträge der aud_midi-Familie: Backend-Interfaces, Fake-Backend, Software-Scheduler, Port-Registry und Diagnose.

Teil der aud_midi-Familie, siehe [aud_midi](https://github.com/audmidi/aud_midi).

## Ziele

- MidiBackend-, Advertiser- und BLE-Transport-Interfaces
- FakeMidiBackend für Tests
- Software-Scheduler mit dem Send-Vertrag
- Port-Registry und Diagnose-Bus
- Kein dart:io, dart:ffi oder dart:isolate

## Stand

Implementiert; jede Datei ist auf der Dart VM zu 100 % durch ihre eigenen Tests abgedeckt, die reinen Dart-Tests laufen auch in Chrome (`dart test -p chrome test/clock test/engine test/fake test/backend test/ble test/error`).

- Verträge: `MidiBackend` mit den Unter-APIs für virtuelle Ports, Bluetooth und Netzwerk, `MidiBackendHost`, `MidiServiceAdvertiser`, `MidiBleTransport`, `MidiException`.
- Uhr: `MidiSystemClock` (`Timeline.now` auf der VM, `performance.now()` im Browser), `MidiClockMapper` sowie `MidiFakeClock` mit `MidiFakeTimers` für Tests.
- `MidiEngine` betreibt ein Backend im aktuellen Isolate: je Eingang ein MIDI-1.0-Parser oder UMP-Decoder, JR-Timestamps als Senderzeit, optionale Übersetzung, begrenzte Warteschlangen mit Überlauf-Diagnosen; je Ausgang Übersetzung ins Protokoll des Ports, Kodierung, Planung durch das Betriebssystem oder den Software-Scheduler (mit Vorlauf für Ports, die nicht verwerfen können), `cancelPending` und Panic; Port-Registry mit Re-Plug-Kandidaten und Geräten; Diagnose-Bus; eine feste Reihenfolge beim Herunterfahren.
- `MidiCompositeBackend` kombiniert Backends, `MidiBleBluetoothBackend` betreibt BLE-MIDI über einen GATT-Client.
- `FakeMidiBackend` mit Loopback, Hotplug, Fehlern sowie virtuellen Ports, BLE- und Netzwerk-Sessions im Speicher. Die Vertragstests laufen dagegen: Sie belegen die Dart-Abstraktion, keine native Anbindung.

Siehe den Plan in [aud_midi_pm](https://github.com/audmidi/aud_midi_pm/blob/main/doc/2026-Q4/tickets/2026-10-06-aud_midi_01-initial-midi-implementation.md).

## Installation

```bash
dart pub add aud_midi_core
```

## Mitwirken

Siehe [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
