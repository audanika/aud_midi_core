// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  late MidiFakeClock clock;
  late MidiFakeTimers timers;
  late List<String> log;

  // Creates a timer that logs [name] with the clock time it fires at.
  void timer(String name, int milliseconds) => timers.create(
    Duration(milliseconds: milliseconds),
    () => log.add('$name@${clock.now().microseconds}'),
  );

  setUp(() {
    clock = MidiFakeClock();
    timers = MidiFakeTimers(clock: clock);
    log = [];
  });

  group('MidiFakeTimers', () {
    group('MidiFakeTimers({clock})', () {
      test('drives the timers with clock', () {
        expect(timers.clock, same(clock));
        expect(timers.pending, 0);
      });
    });

    group('create(duration, callback)', () {
      test('returns an active timer that fires once', () {
        final created = timers.create(const Duration(milliseconds: 1), () {});
        expect([created.isActive, created.tick], equals([true, 0]));
        timers.advance(const Duration(milliseconds: 1));
        expect([created.isActive, created.tick], equals([false, 1]));
      });

      test('treats a negative duration as zero', () {
        timer('a', -5);
        timers.flush();
        expect(log, equals(['a@0']));
      });
    });

    group('advance(duration)', () {
      test('fires due timers in order, at their due time', () {
        timer('late', 3);
        timer('early', 1);
        timer('tie', 3);
        timer('beyond', 10);
        timers.advance(const Duration(milliseconds: 5));
        expect(log, equals(['early@1000', 'late@3000', 'tie@3000']));
        expect(clock.now(), const MidiTime(5000));
        expect(timers.pending, 1);
      });

      test('fires timers created by callbacks when they are due', () {
        timers.create(const Duration(milliseconds: 1), () => timer('inner', 1));
        timers.advance(const Duration(milliseconds: 2));
        expect(log, equals(['inner@2000']));
      });

      test('does not move the clock back for overdue timers', () {
        timer('a', 1);
        clock.advance(const Duration(milliseconds: 4));
        timers.advance(const Duration(milliseconds: 1));
        expect(log, equals(['a@4000']));
        expect(clock.now(), const MidiTime(5000));
      });

      test('skips cancelled timers', () {
        timers.create(const Duration(milliseconds: 1), () {}).cancel();
        timer('kept', 2);
        expect(timers.pending, 1);
        timers.advance(const Duration(milliseconds: 2));
        expect(log, equals(['kept@2000']));
      });

      test('skips a timer cancelled by an earlier callback', () {
        late final Timer second;
        timers.create(const Duration(milliseconds: 1), () => second.cancel());
        second = timers.create(
          const Duration(milliseconds: 1),
          () => log.add('second'),
        );
        timers.advance(const Duration(milliseconds: 1));
        expect(log, isEmpty);
      });

      test('rejects negative durations', () {
        expect(
          () => timers.advance(const Duration(microseconds: -1)),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('flush()', () {
      test('fires the due timers without moving the clock', () {
        timer('now', 0);
        timer('later', 1);
        timers.flush();
        expect(log, equals(['now@0']));
        expect(clock.now(), MidiTime.zero);
      });
    });
  });
}
