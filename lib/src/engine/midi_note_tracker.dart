// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Follows which notes an output turned on and did not turn off yet, per
/// group and channel, so that a panic can send explicit Note Offs.
///
/// Note On turns a note on — in MIDI 1.0 only with a velocity above 0.
/// Note Off and MIDI 1.0 Note On with velocity 0 turn it off. All Sound
/// Off (controller 120), All Notes Off (123) and the mode messages Omni
/// Off, Omni On, Mono On and Poly On (124 to 127) turn all notes of their
/// channel off, System Reset all notes of its group.
final class MidiNoteTracker {
  /// Creates a tracker without active notes.
  MidiNoteTracker();

  // ...........................................................................
  /// Updates the state with [message] sent on [group].
  void track(MidiMessage message, {int group = 0}) {
    switch (message) {
      case MidiNoteOn(:final channel, :final note, :final velocity):
        velocity == 0 ? _off(group, channel, note) : _on(group, channel, note);
      case MidiNoteOn2(:final channel, :final note):
        _on(group, channel, note);
      case MidiNoteOff(:final channel, :final note) ||
          MidiNoteOff2(:final channel, :final note):
        _off(group, channel, note);
      case MidiControlChange(:final channel, :final controller) ||
              MidiControlChange2(:final channel, :final controller)
          when _silences(controller):
        _channelOff(group, channel);
      case MidiSystemReset():
        _notes.remove(group);
      default:
        break;
    }
  }

  /// Forgets all active notes.
  void clear() => _notes.clear();

  // ...........................................................................
  /// Returns the active notes of [group], ordered by channel and note.
  List<({int channel, int note})> notesOf(int group) {
    final keys = [...?_notes[group]]..sort();
    return [for (final key in keys) (channel: key >> 7, note: key & 0x7F)];
  }

  /// The groups with active notes, in ascending order.
  List<int> get groups => [..._notes.keys]..sort();

  /// Whether no note is active.
  bool get isEmpty => _notes.isEmpty;

  // ...........................................................................
  /// The active notes per group as `channel << 7 | note`.
  final _notes = <int, Set<int>>{};

  /// Turns [note] of [channel] in [group] on.
  void _on(int group, int channel, int note) =>
      _notes.putIfAbsent(group, () => {}).add(channel << 7 | note);

  /// Turns [note] of [channel] in [group] off.
  void _off(int group, int channel, int note) =>
      _update(group, (notes) => notes.remove(channel << 7 | note));

  /// Turns all notes of [channel] in [group] off.
  void _channelOff(int group, int channel) => _update(
    group,
    (notes) => notes.removeWhere((key) => key >> 7 == channel),
  );

  /// Applies [change] to the notes of [group] and drops an empty group.
  void _update(int group, void Function(Set<int> notes) change) {
    final notes = _notes[group];
    if (notes == null) return;
    change(notes);
    if (notes.isEmpty) _notes.remove(group);
  }

  /// Whether the channel mode [controller] turns all notes off.
  static bool _silences(int controller) =>
      controller == MidiControllers.allSoundOff ||
      controller >= MidiControllers.allNotesOff;
}
