// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:test/test.dart';

void main() {
  group('MidiTimerFactory', () {
    test('accepts the real timer', () async {
      const MidiTimerFactory factory = Timer.new;
      final fired = Completer<void>();
      final timer = factory(Duration.zero, fired.complete);
      await fired.future;
      expect(timer.isActive, isFalse);
    });

    test('accepts fake timers', () {
      final timers = MidiFakeTimers(clock: MidiFakeClock());
      final MidiTimerFactory factory = timers.create;
      var fired = false;
      factory(const Duration(milliseconds: 1), () => fired = true);
      timers.advance(const Duration(milliseconds: 1));
      expect(fired, isTrue);
    });
  });
}
