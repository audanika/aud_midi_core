// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A clock that always shows the same time.
final class _StoppedClock implements MidiClock {
  _StoppedClock(this.time);

  final MidiTime time;

  @override
  MidiTime now() => time;
}

void main() {
  group('MidiClock', () {
    test('is implemented by the clocks of the package', () {
      expect(const MidiSystemClock(), isA<MidiClock>());
      expect(MidiFakeClock(), isA<MidiClock>());
    });

    group('now()', () {
      test('returns the time of the implementation', () {
        final MidiClock clock = _StoppedClock(const MidiTime(42));
        expect(clock.now(), const MidiTime(42));
      });
    });
  });
}
