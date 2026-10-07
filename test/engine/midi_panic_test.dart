// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  // Returns the controller message [controller] with value 0 on [channel].
  MidiControlChange cc(int channel, int controller) =>
      MidiControlChange(channel: channel, controller: controller, value: 0);

  group('MidiPanic', () {
    group('MidiPanic()', () {
      test('uses every message on all channels', () {
        const panic = MidiPanic();
        expect([
          panic.noteOffs,
          panic.allSoundOff,
          panic.resetAllControllers,
          panic.allNotesOff,
          panic.cancelPending,
        ], everyElement(isTrue));
        expect(panic.channels, equals(List.generate(16, (i) => i)));
        expect(MidiPanic.allChannels, hasLength(16));
      });
    });

    group('messages({activeNotes})', () {
      test('silences every channel with the three controllers', () {
        final messages = const MidiPanic().messages();
        expect(messages, hasLength(48));
        expect(messages.take(3), equals([cc(0, 120), cc(0, 121), cc(0, 123)]));
        expect(messages.last, cc(15, 123));
      });

      test('turns the active notes of each channel off first', () {
        const panic = MidiPanic(channels: [2, 5]);
        final messages = panic.messages(
          activeNotes: const [
            (channel: 5, note: 64),
            (channel: 2, note: 62),
            (channel: 2, note: 60),
            (channel: 9, note: 36),
          ],
        );
        expect(
          messages,
          equals([
            const MidiNoteOff(channel: 2, note: 60),
            const MidiNoteOff(channel: 2, note: 62),
            cc(2, 120),
            cc(2, 121),
            cc(2, 123),
            const MidiNoteOff(channel: 5, note: 64),
            cc(5, 120),
            cc(5, 121),
            cc(5, 123),
          ]),
        );
      });

      for (final (name, panic, expected) in [
        (
          'only note offs',
          const MidiPanic(
            allSoundOff: false,
            resetAllControllers: false,
            allNotesOff: false,
          ),
          [const MidiNoteOff(channel: 0, note: 60)],
        ),
        (
          'only all notes off',
          const MidiPanic(
            noteOffs: false,
            allSoundOff: false,
            resetAllControllers: false,
          ),
          [cc(0, 123)],
        ),
      ]) {
        test('sends $name when configured', () {
          final messages = panic
              .copyWith(channels: [0])
              .messages(activeNotes: const [(channel: 0, note: 60)]);
          expect(messages, equals(expected));
        });
      }
    });

    group('copyWith(...)', () {
      test('replaces the given fields', () {
        const panic = MidiPanic();
        expect(panic.copyWith(), panic);
        final changed = panic.copyWith(
          noteOffs: false,
          allSoundOff: false,
          resetAllControllers: false,
          allNotesOff: false,
          channels: [1],
          cancelPending: false,
        );
        expect(
          changed,
          const MidiPanic(
            noteOffs: false,
            allSoundOff: false,
            resetAllControllers: false,
            allNotesOff: false,
            channels: [1],
            cancelPending: false,
          ),
        );
      });
    });

    group('==, hashCode', () {
      test('compare all fields', () {
        const panic = MidiPanic(channels: [1, 2]);
        expect(panic, MidiPanic(channels: [1, 2].toList()));
        expect(panic.hashCode, MidiPanic(channels: [1, 2].toList()).hashCode);
        for (final other in [
          const MidiPanic(channels: [1, 3]),
          const MidiPanic(channels: [1]),
          const MidiPanic(channels: [1, 2], noteOffs: false),
          const MidiPanic(channels: [1, 2], allSoundOff: false),
          const MidiPanic(channels: [1, 2], resetAllControllers: false),
          const MidiPanic(channels: [1, 2], allNotesOff: false),
          const MidiPanic(channels: [1, 2], cancelPending: false),
        ]) {
          expect(panic, isNot(other));
        }
        expect(panic == panic, isTrue);
        expect(panic, isNot(Object()));
      });
    });

    group('toString()', () {
      test('lists the fields', () {
        expect(
          const MidiPanic(channels: [0]).toString(),
          'MidiPanic(noteOffs: true, allSoundOff: true, '
          'resetAllControllers: true, allNotesOff: true, channels: [0], '
          'cancelPending: true)',
        );
      });
    });
  });
}
