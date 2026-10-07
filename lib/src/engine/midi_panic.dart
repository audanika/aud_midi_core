// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Describes how an output is silenced and builds the messages for it.
///
/// Per channel of [channels] the panic sends, each when enabled: Note Off
/// for every note the output still has on ([noteOffs]), All Sound Off
/// (controller 120), Reset All Controllers (121) and All Notes Off (123).
/// Reset All Controllers releases the sustain pedal, so notes held by it
/// stop as well.
final class MidiPanic {
  /// Creates a panic description; by default it uses every message on all
  /// channels and discards the messages scheduled for later first.
  const MidiPanic({
    this.noteOffs = true,
    this.allSoundOff = true,
    this.resetAllControllers = true,
    this.allNotesOff = true,
    this.channels = allChannels,
    this.cancelPending = true,
  });

  // ...........................................................................
  /// Returns the panic messages, channel by channel in the order of
  /// [channels].
  ///
  /// - [activeNotes] the notes still on, as tracked by a
  ///   `MidiNoteTracker`; each gets a Note Off when [noteOffs] is set.
  List<MidiMessage> messages({
    Iterable<({int channel, int note})> activeNotes = const [],
  }) {
    final result = <MidiMessage>[];
    for (final channel in channels) {
      if (noteOffs) {
        final notes = [
          for (final active in activeNotes)
            if (active.channel == channel) active.note,
        ]..sort();
        for (final note in notes) {
          result.add(MidiNoteOff(channel: channel, note: note));
        }
      }
      if (allSoundOff) {
        result.add(_controlChange(channel, MidiControllers.allSoundOff));
      }
      if (resetAllControllers) {
        result.add(
          _controlChange(channel, MidiControllers.resetAllControllers),
        );
      }
      if (allNotesOff) {
        result.add(_controlChange(channel, MidiControllers.allNotesOff));
      }
    }
    return result;
  }

  /// Returns a copy with the given fields replaced.
  MidiPanic copyWith({
    bool? noteOffs,
    bool? allSoundOff,
    bool? resetAllControllers,
    bool? allNotesOff,
    List<int>? channels,
    bool? cancelPending,
  }) => MidiPanic(
    noteOffs: noteOffs ?? this.noteOffs,
    allSoundOff: allSoundOff ?? this.allSoundOff,
    resetAllControllers: resetAllControllers ?? this.resetAllControllers,
    allNotesOff: allNotesOff ?? this.allNotesOff,
    channels: channels ?? this.channels,
    cancelPending: cancelPending ?? this.cancelPending,
  );

  // ...........................................................................
  /// Whether every note the output still has on gets a Note Off.
  final bool noteOffs;

  /// Whether All Sound Off (controller 120) is sent.
  final bool allSoundOff;

  /// Whether Reset All Controllers (controller 121) is sent.
  final bool resetAllControllers;

  /// Whether All Notes Off (controller 123) is sent.
  final bool allNotesOff;

  /// The channels to silence, 0 to 15.
  final List<int> channels;

  /// Whether the messages scheduled for later are discarded before the
  /// panic messages are sent.
  final bool cancelPending;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiPanic &&
          other.noteOffs == noteOffs &&
          other.allSoundOff == allSoundOff &&
          other.resetAllControllers == resetAllControllers &&
          other.allNotesOff == allNotesOff &&
          _sameChannels(other.channels, channels) &&
          other.cancelPending == cancelPending;

  @override
  int get hashCode => Object.hash(
    noteOffs,
    allSoundOff,
    resetAllControllers,
    allNotesOff,
    Object.hashAll(channels),
    cancelPending,
  );

  @override
  String toString() =>
      'MidiPanic(noteOffs: $noteOffs, allSoundOff: $allSoundOff, '
      'resetAllControllers: $resetAllControllers, '
      'allNotesOff: $allNotesOff, channels: $channels, '
      'cancelPending: $cancelPending)';

  // ...........................................................................
  /// All sixteen channels.
  static const List<int> allChannels = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
  ];

  // ...........................................................................
  /// Whether [a] and [b] hold the same channels in the same order.
  static bool _sameChannels(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Returns the channel mode message [controller] with value 0.
  static MidiControlChange _controlChange(int channel, int controller) =>
      MidiControlChange(channel: channel, controller: controller, value: 0);
}
