// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:developer';

// #############################################################################
/// Returns the monotonic clock of the Dart VM in microseconds.
///
/// It reads `Timeline.now`, which all isolates of a process share. In the
/// browser `MidiSystemClock` uses `midi_monotonic_now_web.dart` instead,
/// because `Timeline.now` is the wall clock in milliseconds there.
int midiMonotonicNow() => Timeline.now;
