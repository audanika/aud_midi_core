// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_clock.dart';

// #############################################################################
/// A clock that only moves when told to, for tests.
final class MidiFakeClock implements MidiClock {
  /// Creates a clock that starts at [start].
  MidiFakeClock({MidiTime start = MidiTime.zero}) : _now = start;

  // ...........................................................................
  @override
  MidiTime now() => _now;

  // ...........................................................................
  /// Moves the clock forward by [duration].
  void advance(Duration duration) => _now = _now + duration;

  /// Moves the clock to [time].
  void jumpTo(MidiTime time) => _now = time;

  // ...........................................................................
  MidiTime _now;
}
