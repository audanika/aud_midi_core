// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// The source of the monotonic package clock.
///
/// Every timestamp of the aud_midi family is a [MidiTime] on this clock:
/// backends convert native receive times to it, and outputs schedule
/// against it.
abstract interface class MidiClock {
  // ...........................................................................
  /// Returns the current time.
  MidiTime now();
}
