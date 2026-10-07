// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  const port = MidiPortId('fake:in');
  late MidiDiagnosticsBus bus;

  // Returns a diagnostic of [kind] with [count] on [onPort].
  MidiDiagnostic diagnostic(
    MidiDiagnosticKind kind, {
    MidiPortId? onPort,
    int count = 1,
  }) => MidiDiagnostic(
    kind: kind,
    port: onPort,
    count: count,
    cause: kind.name,
    time: MidiTime.zero,
  );

  setUp(() => bus = MidiDiagnosticsBus());

  group('MidiDiagnosticsBus', () {
    group('report(diagnostic)', () {
      test('publishes and counts per kind and port', () async {
        final published = bus.diagnostics.toList();
        final reports = [
          diagnostic(MidiDiagnosticKind.queueOverflow, onPort: port, count: 4),
          diagnostic(MidiDiagnosticKind.queueOverflow),
          diagnostic(MidiDiagnosticKind.nativeError, onPort: port),
        ];
        reports.forEach(bus.report);
        await bus.close();
        expect(await published, equals(reports));
        expect(
          bus.snapshot(),
          MidiDiagnosticsSnapshot(
            byKind: {
              MidiDiagnosticKind.queueOverflow: 5,
              MidiDiagnosticKind.nativeError: 1,
            },
            byPort: {
              port: {
                MidiDiagnosticKind.queueOverflow: 4,
                MidiDiagnosticKind.nativeError: 1,
              },
            },
          ),
        );
      });

      test('counts without listeners', () {
        bus.report(diagnostic(MidiDiagnosticKind.parserReset));
        expect(bus.snapshot().total, 1);
      });

      test('ignores reports after close', () async {
        await bus.close();
        bus.report(diagnostic(MidiDiagnosticKind.parserReset));
        expect([bus.isClosed, bus.snapshot().total], equals([true, 0]));
      });
    });

    group('resetCounters()', () {
      test('sets all counters to zero', () {
        bus
          ..report(diagnostic(MidiDiagnosticKind.schedulerLate, onPort: port))
          ..resetCounters();
        expect(bus.snapshot(), MidiDiagnosticsSnapshot());
      });
    });

    group('diagnostics', () {
      test('is a broadcast stream', () {
        expect(bus.diagnostics.isBroadcast, isTrue);
      });
    });
  });
}
