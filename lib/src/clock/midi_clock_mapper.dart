// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_clock.dart';

// #############################################################################
/// Maps a native monotonic clock of an operating system to the package
/// clock.
///
/// Backends receive timestamps in their native clock, e.g. mach ticks or
/// `CLOCK_MONOTONIC`, converted to microseconds. The mapper measures the
/// offset between both clocks by sampling them back to back and keeps the
/// sample with the smallest gap. Call [resync] from time to time, because
/// some native clocks stop while the system sleeps.
final class MidiClockMapper {
  /// Creates a mapper between [clock] and the native clock read by
  /// [nativeNow] in microseconds; [samples] pairs are taken per [resync].
  MidiClockMapper({
    required this.clock,
    required this.nativeNow,
    this.samples = 5,
  }) : assert(samples > 0) {
    resync();
  }

  // ...........................................................................
  /// Measures the offset between the native clock and the package clock
  /// again.
  void resync() {
    var bestGap = -1;
    for (var i = 0; i < samples; i++) {
      final before = clock.now().microseconds;
      final native = nativeNow();
      final after = clock.now().microseconds;
      final gap = after - before;
      if (bestGap < 0 || gap < bestGap) {
        bestGap = gap;
        _offset = before + gap ~/ 2 - native;
      }
    }
  }

  // ...........................................................................
  /// Converts the native time [nativeMicros] to the package clock.
  MidiTime toPackage(int nativeMicros) => MidiTime(nativeMicros + _offset);

  /// Converts the package time [time] to the native clock in microseconds.
  int toNative(MidiTime time) => time.microseconds - _offset;

  // ...........................................................................
  /// The package clock.
  final MidiClock clock;

  /// Reads the native clock in microseconds.
  final int Function() nativeNow;

  /// The number of sample pairs taken per [resync].
  final int samples;

  /// The package time minus the native time, in microseconds.
  int get offset => _offset;

  // ...........................................................................
  int _offset = 0;
}
