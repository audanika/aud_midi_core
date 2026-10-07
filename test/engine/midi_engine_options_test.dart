// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  // Options with every field changed.
  const changed = MidiEngineOptions(
    input: MidiInputOptions(deliverAs: MidiProtocol.midi2),
    lateThreshold: Duration(milliseconds: 1),
    flushDataEntryMsb: true,
    lookahead: Duration(milliseconds: 100),
  );

  group('MidiEngineOptions', () {
    group('MidiEngineOptions()', () {
      test('uses default input options and a 5 ms threshold', () {
        const options = MidiEngineOptions();
        expect(options.input, const MidiInputOptions());
        expect(options.lateThreshold, const Duration(milliseconds: 5));
        expect(options.flushDataEntryMsb, isFalse);
        expect(options.lookahead, isNull);
      });
    });

    group('copyWith(...)', () {
      test('replaces the given fields', () {
        const options = MidiEngineOptions();
        expect(options.copyWith(), options);
        expect(
          options.copyWith(
            input: const MidiInputOptions(deliverAs: MidiProtocol.midi2),
            lateThreshold: const Duration(milliseconds: 1),
            flushDataEntryMsb: true,
            lookahead: const Duration(milliseconds: 100),
          ),
          changed,
        );
      });

      test('clears the lookahead', () {
        expect(changed.copyWith(clearLookahead: true).lookahead, isNull);
        expect(
          changed
              .copyWith(lookahead: Duration.zero, clearLookahead: true)
              .lookahead,
          isNull,
        );
      });
    });

    group('==, hashCode', () {
      test('compare all fields', () {
        expect(changed, changed.copyWith());
        expect(changed.hashCode, changed.copyWith().hashCode);
        for (final other in [
          changed.copyWith(input: const MidiInputOptions()),
          changed.copyWith(lateThreshold: Duration.zero),
          changed.copyWith(flushDataEntryMsb: false),
          changed.copyWith(lookahead: Duration.zero),
        ]) {
          expect(changed, isNot(other));
        }
        expect(changed, isNot(Object()));
      });
    });

    group('toString()', () {
      test('lists the fields', () {
        expect(
          const MidiEngineOptions().toString(),
          'MidiEngineOptions(input: ${const MidiInputOptions()}, '
          'lateThreshold: 0:00:00.005000, flushDataEntryMsb: false, '
          'lookahead: null)',
        );
      });
    });
  });
}
