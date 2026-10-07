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
  const other = MidiPortId('fake:other');

  // Returns a snapshot with two kinds, one of them on [port].
  MidiDiagnosticsSnapshot snapshot({int late = 2}) => MidiDiagnosticsSnapshot(
    byKind: {
      MidiDiagnosticKind.queueOverflow: 3,
      MidiDiagnosticKind.schedulerLate: late,
    },
    byPort: {
      port: {MidiDiagnosticKind.queueOverflow: 3},
    },
  );

  group('MidiDiagnosticsSnapshot', () {
    group('MidiDiagnosticsSnapshot({byKind, byPort})', () {
      test('is empty by default', () {
        final empty = MidiDiagnosticsSnapshot();
        expect(empty.byKind, isEmpty);
        expect(empty.byPort, isEmpty);
        expect(empty.total, 0);
      });

      test('keeps unmodifiable copies', () {
        final counters = {MidiDiagnosticKind.parserReset: 1};
        final perPort = {port: counters};
        final copy = MidiDiagnosticsSnapshot(byKind: counters, byPort: perPort);
        counters[MidiDiagnosticKind.parserReset] = 5;
        perPort.clear();
        expect(copy.byKind, equals({MidiDiagnosticKind.parserReset: 1}));
        expect(
          copy.byPort,
          equals({
            port: {MidiDiagnosticKind.parserReset: 1},
          }),
        );
        expect(
          () => copy.byKind[MidiDiagnosticKind.nativeError] = 1,
          throwsUnsupportedError,
        );
        final withPort = MidiDiagnosticsSnapshot(byPort: {port: counters});
        expect(
          () => withPort.byPort[port]![MidiDiagnosticKind.nativeError] = 1,
          throwsUnsupportedError,
        );
      });
    });

    group('count(kind, {port})', () {
      test('returns the counter over all ports or of one port', () {
        final counts = snapshot();
        expect([
          counts.count(MidiDiagnosticKind.queueOverflow),
          counts.count(MidiDiagnosticKind.schedulerLate),
          counts.count(MidiDiagnosticKind.queueOverflow, port: port),
          counts.count(MidiDiagnosticKind.schedulerLate, port: port),
          counts.count(MidiDiagnosticKind.queueOverflow, port: other),
          counts.count(MidiDiagnosticKind.nativeError),
        ], equals([3, 2, 3, 0, 0, 0]));
      });
    });

    group('total', () {
      test('sums the counters per kind', () {
        expect(snapshot().total, 5);
      });
    });

    group('==, hashCode', () {
      test('compare the counters', () {
        expect(snapshot(), snapshot());
        expect(snapshot().hashCode, snapshot().hashCode);
        expect(snapshot(), isNot(snapshot(late: 3)));
        final otherPort = MidiDiagnosticsSnapshot(
          byKind: snapshot().byKind,
          byPort: {
            other: {MidiDiagnosticKind.queueOverflow: 3},
          },
        );
        expect(snapshot(), isNot(otherPort));
        final morePorts = MidiDiagnosticsSnapshot(
          byKind: snapshot().byKind,
          byPort: {...snapshot().byPort, other: const {}},
        );
        expect(snapshot(), isNot(morePorts));
        final fewerKinds = MidiDiagnosticsSnapshot(
          byKind: {MidiDiagnosticKind.queueOverflow: 3},
          byPort: snapshot().byPort,
        );
        expect(snapshot(), isNot(fewerKinds));
        final counts = snapshot();
        expect(counts == counts, isTrue);
        expect(counts, isNot(Object()));
      });
    });

    group('toString()', () {
      test('lists the counters', () {
        expect(
          snapshot().toString(),
          'MidiDiagnosticsSnapshot(byKind: {queueOverflow: 3, '
          'schedulerLate: 2}, byPort: {fake:in: {queueOverflow: 3}})',
        );
      });
    });
  });
}
