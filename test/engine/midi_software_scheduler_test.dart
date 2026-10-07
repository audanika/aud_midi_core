// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  const a = MidiPortId('fake:a');
  const b = MidiPortId('fake:b');
  late MidiFakeClock clock;
  late MidiFakeTimers timers;
  late List<String> dispatched;
  late List<MidiDiagnostic> diagnostics;
  late MidiSoftwareScheduler scheduler;

  // Returns a one-byte packet [value] due at [milliseconds].
  MidiPacket packet(int value, num milliseconds) => MidiBytesPacket(
    bytes: MidiBytes([value]),
    time: MidiTime((milliseconds * 1000).round()),
  );

  // Records a dispatch as 'port:value@clock milliseconds'.
  void dispatch(MidiPortId port, MidiPacket packet) {
    final value = (packet as MidiBytesPacket).bytes[0];
    final now = (clock.now().microseconds / 1000).toStringAsFixed(1);
    dispatched.add('${port.nativeId}:$value@$now');
  }

  setUp(() {
    clock = MidiFakeClock();
    timers = MidiFakeTimers(clock: clock);
    dispatched = [];
    diagnostics = [];
    scheduler = MidiSoftwareScheduler(
      clock: clock,
      dispatch: dispatch,
      timerFactory: timers.create,
      lateThreshold: const Duration(milliseconds: 1),
      onDiagnostic: diagnostics.add,
    );
  });

  group('MidiSoftwareScheduler', () {
    group('MidiSoftwareScheduler(...)', () {
      test('keeps its settings', () {
        expect(scheduler.clock, same(clock));
        expect(scheduler.lateThreshold, const Duration(milliseconds: 1));
        expect(scheduler.pending(), 0);
        expect(scheduler.nextDue, isNull);
      });

      test('uses real timers and a 5 ms threshold by default', () async {
        final real = MidiSoftwareScheduler(
          clock: const MidiSystemClock(),
          dispatch: (port, packet) => dispatched.add(port.value),
        );
        expect(real.lateThreshold, const Duration(milliseconds: 5));
        expect(real.onDiagnostic, isNull);
        real.schedule(a, packet(1, 0));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(dispatched, equals(['fake:a']));
      });
    });

    group('schedule(port, packet)', () {
      test('dispatches each packet at its due time', () {
        scheduler
          ..schedule(a, packet(1, 2))
          ..schedule(a, packet(2, 5));
        expect(scheduler.nextDue, const MidiTime(2000));
        timers.advance(const Duration(milliseconds: 1));
        expect(dispatched, isEmpty);
        timers.advance(const Duration(milliseconds: 9));
        expect(dispatched, equals(['a:1@2.0', 'a:2@5.0']));
        expect(scheduler.pending(), 0);
        expect(diagnostics, isEmpty);
      });

      test('never dispatches early, waiting in whole milliseconds', () {
        scheduler.schedule(a, packet(1, 1.5));
        timers.advance(const Duration(milliseconds: 3));
        expect(dispatched, equals(['a:1@2.0']));
      });

      test('orders by due time and keeps the order of equal times', () {
        scheduler
          ..schedule(a, packet(1, 3))
          ..schedule(b, packet(2, 1))
          ..schedule(a, packet(3, 3))
          ..schedule(a, packet(4, 1))
          ..schedule(b, packet(5, 3));
        timers.advance(const Duration(milliseconds: 3));
        expect(
          dispatched,
          equals(['b:2@1.0', 'a:4@1.0', 'a:1@3.0', 'a:3@3.0', 'b:5@3.0']),
        );
      });

      test('dispatches a lead before the due time', () {
        scheduler
          ..schedule(a, packet(1, 5), lead: const Duration(milliseconds: 3))
          ..schedule(b, packet(2, 3));
        expect(scheduler.nextDue, const MidiTime(2000));
        timers.advance(const Duration(milliseconds: 3));
        expect(dispatched, equals(['a:1@2.0', 'b:2@3.0']));
      });

      test('measures lateness against the due time', () {
        scheduler.schedule(
          a,
          packet(1, 5),
          lead: const Duration(milliseconds: 3),
        );
        clock.advance(const Duration(milliseconds: 5));
        scheduler.dispatchDue();
        expect(dispatched, equals(['a:1@5.0']));
        expect(diagnostics, isEmpty);
      });

      test('throws after dispose', () {
        scheduler.dispose();
        expect(
          () => scheduler.schedule(a, packet(1, 1)),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'The scheduler is disposed',
            ),
          ),
        );
      });
    });

    group('dispatchDue({port})', () {
      test('dispatches the due packets of one port at once', () {
        scheduler
          ..schedule(a, packet(1, 1))
          ..schedule(b, packet(2, 1))
          ..schedule(a, packet(3, 4));
        clock.advance(const Duration(milliseconds: 1));
        scheduler.dispatchDue(port: a);
        expect(dispatched, equals(['a:1@1.0']));
        scheduler.dispatchDue();
        expect(dispatched, equals(['a:1@1.0', 'b:2@1.0']));
        scheduler.dispatchDue(port: const MidiPortId('fake:unknown'));
        expect(scheduler.pending(port: a), 1);
      });

      test('reports packets that leave late, per port', () {
        scheduler
          ..schedule(a, packet(1, 1))
          ..schedule(a, packet(2, 2))
          ..schedule(a, packet(3, 4))
          ..schedule(b, packet(4, 3))
          ..schedule(b, packet(5, 4.5));
        clock.advance(const Duration(milliseconds: 5));
        scheduler.dispatchDue();
        expect(
          diagnostics,
          equals([
            const MidiDiagnostic(
              kind: MidiDiagnosticKind.schedulerLate,
              port: a,
              count: 2,
              cause: '2 scheduled packet(s) left up to 4.0 ms late',
              time: MidiTime(5000),
            ),
            const MidiDiagnostic(
              kind: MidiDiagnosticKind.schedulerLate,
              port: b,
              cause: '1 scheduled packet(s) left up to 2.0 ms late',
              time: MidiTime(5000),
            ),
          ]),
        );
      });
    });

    group('cancel(port), cancelAll()', () {
      test('discard queued packets and return their number', () {
        scheduler
          ..schedule(a, packet(1, 1))
          ..schedule(a, packet(2, 2))
          ..schedule(b, packet(3, 3));
        expect(scheduler.cancel(a), 2);
        expect(scheduler.cancel(a), 0);
        expect(scheduler.pending(), 1);
        expect(scheduler.nextDue, const MidiTime(3000));
        expect(scheduler.cancelAll(), 1);
        timers.advance(const Duration(milliseconds: 5));
        expect(dispatched, isEmpty);
        expect(timers.pending, 0);
      });
    });

    group('dispose()', () {
      test('stops for good', () {
        scheduler
          ..schedule(a, packet(1, 1))
          ..dispose();
        expect([scheduler.isDisposed, scheduler.pending()], equals([true, 0]));
        timers.advance(const Duration(milliseconds: 2));
        expect(dispatched, isEmpty);
      });
    });

    group('nextDue', () {
      test('follows an earlier packet', () {
        scheduler.schedule(a, packet(1, 5));
        scheduler.schedule(b, packet(2, 2));
        expect(scheduler.nextDue, const MidiTime(2000));
        expect(timers.pending, 1);
        timers.advance(const Duration(milliseconds: 5));
        expect(dispatched, equals(['b:2@2.0', 'a:1@5.0']));
      });
    });
  });
}
