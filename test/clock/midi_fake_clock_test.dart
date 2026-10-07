// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiFakeClock', () {
    group('MidiFakeClock({start})', () {
      test('starts at zero by default', () {
        expect(MidiFakeClock().now(), MidiTime.zero);
      });

      test('starts at start', () {
        expect(
          MidiFakeClock(start: const MidiTime(7)).now(),
          const MidiTime(7),
        );
      });
    });

    group('now()', () {
      test('stays until the clock is moved', () {
        final clock = MidiFakeClock(start: const MidiTime(3));
        expect([
          clock.now(),
          clock.now(),
        ], equals([const MidiTime(3), const MidiTime(3)]));
      });
    });

    group('advance(duration)', () {
      test('moves the clock forward', () {
        final clock = MidiFakeClock()
          ..advance(const Duration(milliseconds: 2))
          ..advance(const Duration(microseconds: 5));
        expect(clock.now(), const MidiTime(2005));
      });
    });

    group('jumpTo(time)', () {
      test('sets the clock, also backwards', () {
        final clock = MidiFakeClock()..jumpTo(const MidiTime(100));
        expect(clock.now(), const MidiTime(100));
        clock.jumpTo(const MidiTime(10));
        expect(clock.now(), const MidiTime(10));
      });
    });
  });
}
