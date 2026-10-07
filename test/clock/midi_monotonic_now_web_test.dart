// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// Runs in the browser only: dart test -p chrome test/clock

@TestOn('browser')
library;

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_core/src/clock/midi_monotonic_now_web.dart';
import 'package:test/test.dart';

void main() {
  group('midiMonotonicNow()', () {
    test('counts microseconds of the page clock', () async {
      final before = midiMonotonicNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final elapsed = midiMonotonicNow() - before;
      // Microseconds, not the milliseconds of Timeline.now in the browser.
      expect(elapsed, inInclusiveRange(15000, 2000000));
    });

    test('never goes back', () {
      var previous = midiMonotonicNow();
      for (var i = 0; i < 1000; i++) {
        final now = midiMonotonicNow();
        expect(now, greaterThanOrEqualTo(previous));
        previous = now;
      }
    });

    test('drives MidiSystemClock in the browser', () {
      final before = midiMonotonicNow();
      final now = const MidiSystemClock().now().microseconds;
      expect(now, inInclusiveRange(before, midiMonotonicNow()));
    });
  });
}
