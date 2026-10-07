// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A host that records what a backend reports.
final class _RecordingHost implements MidiBackendHost {
  final events = <MidiPortEvent>[];
  final packets = <(MidiPortId, MidiPacket)>[];
  final diagnostics = <MidiDiagnostic>[];

  @override
  final MidiClock clock = MidiFakeClock(start: const MidiTime(5));

  @override
  void portsChanged(List<MidiPortEvent> events) => this.events.addAll(events);

  @override
  void received(MidiPortId port, MidiPacket packet) =>
      packets.add((port, packet));

  @override
  void diagnostic(MidiDiagnostic diagnostic) => diagnostics.add(diagnostic);
}

void main() {
  group('MidiBackendHost', () {
    test('takes the reports of a backend', () async {
      final recording = _RecordingHost();
      final MidiBackendHost host = recording;
      final backend = FakeMidiBackend();
      await backend.start(host);
      final input = backend.addPort(
        backend.portInfo('in', direction: MidiDirection.input),
      );
      await backend.openPort(input.id);
      final packet = MidiBytesPacket(
        bytes: MidiBytes([0xFE]),
        time: host.clock.now(),
      );
      backend.inject(input.id, packet);
      final diagnostic = MidiDiagnostic(
        kind: MidiDiagnosticKind.queueOverflow,
        port: input.id,
        cause: 'full',
        time: host.clock.now(),
      );
      backend.reportDiagnostic(diagnostic);

      expect(recording.events, equals([MidiPortAdded(port: input)]));
      expect(recording.packets, equals([(input.id, packet)]));
      expect(recording.diagnostics, equals([diagnostic]));
      expect(host.clock.now(), const MidiTime(5));
    });

    test('is what an engine gives its backend', () async {
      final backend = FakeMidiBackend();
      final engine = MidiEngine(backend: backend);
      await engine.open();
      expect(backend.host, isA<MidiBackendHost>());
      expect(backend.host!.clock, same(engine.clock));
      await engine.close();
    });
  });
}
