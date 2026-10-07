// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:test/test.dart';

void main() {
  group('MidiSystemClock', () {
    group('MidiSystemClock()', () {
      test('creates a clock', () {
        const create = MidiSystemClock.new;
        expect(create(), isA<MidiClock>());
      });
    });

    group('now()', () {
      test('counts microseconds', () async {
        const clock = MidiSystemClock();
        final before = clock.now();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final elapsed = clock.now().difference(before);
        expect(
          elapsed.inMicroseconds,
          inInclusiveRange(15000, const Duration(seconds: 2).inMicroseconds),
        );
      });

      test('never goes back', () {
        const clock = MidiSystemClock();
        var previous = clock.now();
        for (var i = 0; i < 100; i++) {
          final now = clock.now();
          expect(now.isBefore(previous), isFalse);
          previous = now;
        }
      });
    });
  });
}
