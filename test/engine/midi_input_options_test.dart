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
  const changed = MidiInputOptions(
    deliverAs: MidiProtocol.midi2,
    noteOnZeroAsNoteOff: true,
    flushDataEntryMsb: true,
    maxSysExLength: 10,
    maxSysExDuration: Duration(seconds: 1),
    queueCapacity: 2,
  );

  group('MidiInputOptions', () {
    group('MidiInputOptions()', () {
      test('delivers as received with 1 MiB System Exclusive', () {
        const options = MidiInputOptions();
        expect([
          options.deliverAs,
          options.noteOnZeroAsNoteOff,
          options.flushDataEntryMsb,
          options.maxSysExLength,
          options.maxSysExDuration,
          options.queueCapacity,
        ], equals([null, false, false, 1 << 20, null, 4096]));
      });

      for (final (name, create) in [
        (
          'a positive System Exclusive length',
          () => MidiInputOptions(maxSysExLength: [0].first),
        ),
        (
          'a positive queue capacity',
          () => MidiInputOptions(queueCapacity: [0].first),
        ),
      ]) {
        test('needs $name', () {
          expect(create, throwsA(isA<AssertionError>()));
        });
      }
    });

    group('copyWith(...)', () {
      test('replaces the given fields', () {
        const options = MidiInputOptions();
        expect(options.copyWith(), options);
        expect(
          options.copyWith(
            deliverAs: MidiProtocol.midi2,
            noteOnZeroAsNoteOff: true,
            flushDataEntryMsb: true,
            maxSysExLength: 10,
            maxSysExDuration: const Duration(seconds: 1),
            queueCapacity: 2,
          ),
          changed,
        );
      });

      test('clears the nullable fields', () {
        expect(
          changed.copyWith(clearDeliverAs: true, clearMaxSysExDuration: true),
          changed.copyWith(
            deliverAs: MidiProtocol.midi1,
            clearDeliverAs: true,
            clearMaxSysExDuration: true,
          ),
        );
        final cleared = changed.copyWith(
          clearDeliverAs: true,
          clearMaxSysExDuration: true,
        );
        expect([
          cleared.deliverAs,
          cleared.maxSysExDuration,
        ], equals([null, null]));
      });
    });

    group('==, hashCode', () {
      test('compare all fields', () {
        expect(changed, changed.copyWith());
        expect(changed.hashCode, changed.copyWith().hashCode);
        for (final other in [
          changed.copyWith(deliverAs: MidiProtocol.midi1),
          changed.copyWith(noteOnZeroAsNoteOff: false),
          changed.copyWith(flushDataEntryMsb: false),
          changed.copyWith(maxSysExLength: 11),
          changed.copyWith(maxSysExDuration: Duration.zero),
          changed.copyWith(queueCapacity: 3),
        ]) {
          expect(changed, isNot(other));
        }
        expect(changed, isNot(Object()));
      });
    });

    group('toString()', () {
      test('lists the fields', () {
        expect(
          changed.toString(),
          'MidiInputOptions(deliverAs: midi2, noteOnZeroAsNoteOff: true, '
          'flushDataEntryMsb: true, maxSysExLength: 10, '
          'maxSysExDuration: 0:00:01.000000, queueCapacity: 2)',
        );
      });
    });
  });
}
