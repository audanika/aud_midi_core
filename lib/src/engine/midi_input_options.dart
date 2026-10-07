// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// How an input session turns the data of its port into events.
final class MidiInputOptions {
  /// Creates input options.
  ///
  /// - [deliverAs] the protocol of the delivered channel voice messages:
  ///   null keeps them as received, [MidiProtocol.midi1] translates MIDI
  ///   2.0 messages down and drops those without a MIDI 1.0 equivalent,
  ///   [MidiProtocol.midi2] translates MIDI 1.0 messages up with the
  ///   context of the port's stream.
  /// - [noteOnZeroAsNoteOff] delivers a MIDI 1.0 Note On with velocity 0
  ///   as Note Off with velocity 64.
  /// - [flushDataEntryMsb] uses the alternate translation to MIDI 2.0 that
  ///   also sends a Data Entry MSB without LSB, see `MidiTranslator1To2`.
  /// - [maxSysExLength] the largest System Exclusive or other reassembled
  ///   message accepted, in data bytes.
  /// - [maxSysExDuration] the longest time such a message may stay
  ///   incomplete; null for no limit.
  /// - [queueCapacity] how many undelivered events, and separately
  ///   packets, a session keeps; newer ones are dropped beyond it.
  const MidiInputOptions({
    this.deliverAs,
    this.noteOnZeroAsNoteOff = false,
    this.flushDataEntryMsb = false,
    this.maxSysExLength = 1 << 20,
    this.maxSysExDuration,
    this.queueCapacity = 4096,
  }) : assert(maxSysExLength > 0),
       assert(queueCapacity > 0);

  // ...........................................................................
  /// Returns a copy with the given fields replaced.
  ///
  /// - [clearDeliverAs] sets [deliverAs] to null; it wins over a given
  ///   protocol.
  /// - [clearMaxSysExDuration] sets [maxSysExDuration] to null; it wins
  ///   over a given duration.
  MidiInputOptions copyWith({
    MidiProtocol? deliverAs,
    bool clearDeliverAs = false,
    bool? noteOnZeroAsNoteOff,
    bool? flushDataEntryMsb,
    int? maxSysExLength,
    Duration? maxSysExDuration,
    bool clearMaxSysExDuration = false,
    int? queueCapacity,
  }) => MidiInputOptions(
    deliverAs: clearDeliverAs ? null : deliverAs ?? this.deliverAs,
    noteOnZeroAsNoteOff: noteOnZeroAsNoteOff ?? this.noteOnZeroAsNoteOff,
    flushDataEntryMsb: flushDataEntryMsb ?? this.flushDataEntryMsb,
    maxSysExLength: maxSysExLength ?? this.maxSysExLength,
    maxSysExDuration: clearMaxSysExDuration
        ? null
        : maxSysExDuration ?? this.maxSysExDuration,
    queueCapacity: queueCapacity ?? this.queueCapacity,
  );

  // ...........................................................................
  /// The protocol of the delivered channel voice messages, or null to keep
  /// them as received.
  final MidiProtocol? deliverAs;

  /// Whether a MIDI 1.0 Note On with velocity 0 becomes a Note Off.
  final bool noteOnZeroAsNoteOff;

  /// Whether the translation to MIDI 2.0 also sends a Data Entry MSB
  /// without LSB.
  final bool flushDataEntryMsb;

  /// The largest reassembled message accepted, in data bytes.
  final int maxSysExLength;

  /// The longest time a reassembled message may stay incomplete.
  final Duration? maxSysExDuration;

  /// How many undelivered events, and separately packets, a session keeps.
  final int queueCapacity;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiInputOptions &&
          other.deliverAs == deliverAs &&
          other.noteOnZeroAsNoteOff == noteOnZeroAsNoteOff &&
          other.flushDataEntryMsb == flushDataEntryMsb &&
          other.maxSysExLength == maxSysExLength &&
          other.maxSysExDuration == maxSysExDuration &&
          other.queueCapacity == queueCapacity;

  @override
  int get hashCode => Object.hash(
    deliverAs,
    noteOnZeroAsNoteOff,
    flushDataEntryMsb,
    maxSysExLength,
    maxSysExDuration,
    queueCapacity,
  );

  @override
  String toString() =>
      'MidiInputOptions(deliverAs: ${deliverAs?.name}, '
      'noteOnZeroAsNoteOff: $noteOnZeroAsNoteOff, '
      'flushDataEntryMsb: $flushDataEntryMsb, '
      'maxSysExLength: $maxSysExLength, '
      'maxSysExDuration: $maxSysExDuration, queueCapacity: $queueCapacity)';
}
