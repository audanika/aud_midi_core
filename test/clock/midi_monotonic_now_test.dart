// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

@TestOn('vm')
library;

import 'dart:developer';

import 'package:aud_midi_core/src/clock/midi_monotonic_now.dart';
import 'package:test/test.dart';

void main() {
  group('midiMonotonicNow()', () {
    test('reads Timeline.now', () {
      final before = Timeline.now;
      final now = midiMonotonicNow();
      final after = Timeline.now;
      expect(now, inInclusiveRange(before, after));
    });
  });
}
