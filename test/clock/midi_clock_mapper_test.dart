// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  late MidiFakeClock clock;
  late List<int> gaps;
  late int reads;

  // A native clock 500 µs behind the start of the package clock that moves
  // in steps of 10 µs per read; each read takes the next of [gaps] on the
  // package clock.
  int nativeNow() {
    final native = 500 + reads * 10;
    clock.advance(Duration(microseconds: gaps[reads % gaps.length]));
    reads++;
    return native;
  }

  setUp(() {
    clock = MidiFakeClock(start: const MidiTime(1000));
    gaps = [5, 2, 7];
    reads = 0;
  });

  group('MidiClockMapper', () {
    group('MidiClockMapper({clock, nativeNow, samples})', () {
      test('takes five samples by default', () {
        final mapper = MidiClockMapper(clock: clock, nativeNow: nativeNow);
        expect(mapper.samples, 5);
        expect(reads, 5);
        expect(mapper.clock, same(clock));
      });

      test('needs at least one sample', () {
        expect(
          () => MidiClockMapper(clock: clock, nativeNow: nativeNow, samples: 0),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('resync()', () {
      test('keeps the sample with the smallest gap', () {
        final mapper = MidiClockMapper(
          clock: clock,
          nativeNow: nativeNow,
          samples: 3,
        );
        // Sample 2: before 1005, native 510, gap 2: 1005 + 1 - 510.
        expect(mapper.offset, 496);
      });

      test('measures again', () {
        final mapper = MidiClockMapper(
          clock: clock,
          nativeNow: nativeNow,
          samples: 1,
        );
        expect(mapper.offset, 1000 + 2 - 500);
        mapper.resync();
        // Before 1005, native 510, gap 2.
        expect(mapper.offset, 1005 + 1 - 510);
      });
    });

    group('toPackage(nativeMicros), toNative(time)', () {
      test('convert with the offset', () {
        final mapper = MidiClockMapper(
          clock: clock,
          nativeNow: nativeNow,
          samples: 3,
        );
        expect(mapper.toPackage(1000), const MidiTime(1496));
        expect(mapper.toNative(const MidiTime(1496)), 1000);
        expect(mapper.nativeNow, same(nativeNow));
      });
    });
  });
}
