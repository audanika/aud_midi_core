// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_clock.dart';
import 'midi_monotonic_now.dart'
    if (dart.library.js_interop) 'midi_monotonic_now_web.dart';

// #############################################################################
/// The process-wide monotonic clock of the Dart runtime.
///
/// On the VM it reads `Timeline.now` from `dart:developer`, the monotonic
/// clock in microseconds that all isolates of a process share. In the
/// browser `Timeline.now` is the wall clock in milliseconds, so the clock
/// reads `performance.now()` instead, the monotonic clock of the page with
/// the precision the browser grants.
final class MidiSystemClock implements MidiClock {
  /// Creates the system clock.
  const MidiSystemClock();

  // ...........................................................................
  @override
  MidiTime now() => MidiTime(midiMonotonicNow());
}
