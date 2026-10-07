// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// coverage:ignore-file
// Browser only: a JS interop call cannot run in a VM test. The browser test
// test/clock/midi_monotonic_now_web_test.dart covers it with -p chrome.

import 'dart:js_interop';

// #############################################################################
/// Returns the monotonic clock of the page in microseconds.
///
/// It reads `performance.now()`, the high resolution time of the page in
/// milliseconds; the browser decides its precision. `Timeline.now` cannot
/// serve here: dart2js, DDC and dart2wasm return the wall clock in
/// milliseconds from it.
int midiMonotonicNow() => (_performanceNow() * 1000).round();

// .............................................................................
/// The `performance.now()` of the page in milliseconds.
@JS('performance.now')
external double _performanceNow();
