// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'midi_input_options.dart';

// #############################################################################
/// The settings of a `MidiEngine`.
final class MidiEngineOptions {
  /// Creates engine options.
  ///
  /// - [input] the options of input sessions opened without options of
  ///   their own.
  /// - [lateThreshold] how late the software scheduler may send a packet
  ///   before it reports `MidiDiagnosticKind.schedulerLate`.
  /// - [flushDataEntryMsb] whether outputs that translate MIDI 1.0 to MIDI
  ///   2.0 also send a Data Entry MSB without LSB, see
  ///   `MidiTranslator1To2`.
  /// - [lookahead] how long before their time packets reach outputs that
  ///   schedule in the operating system but cannot discard what they hold:
  ///   `MidiPortCapabilities.scheduledSend` without
  ///   `MidiPortCapabilities.cancelPending`, e.g. Web MIDI without
  ///   `MIDIOutput.clear()` or CoreMIDI virtual destinations, which
  ///   `MIDIFlushOutput` would send a System Reset.
  ///
  /// The [lookahead] trades cancellation against robustness:
  ///
  /// - null, the default, hands such packets over at once. The operating
  ///   system times them precisely even while the engine's isolate is
  ///   busy or throttled, e.g. in a background browser tab, but cancelling
  ///   leaves them in place; a panic repeats itself after the last of them.
  /// - A positive duration, e.g. 100 ms, keeps them in the software
  ///   scheduler until that long before their time. They stay cancellable
  ///   until then and still get the operating system's timing, as long as
  ///   the isolate is never blocked for longer than the lookahead.
  /// - [Duration.zero] schedules such ports in software only.
  const MidiEngineOptions({
    this.input = const MidiInputOptions(),
    this.lateThreshold = const Duration(milliseconds: 5),
    this.flushDataEntryMsb = false,
    this.lookahead,
  });

  // ...........................................................................
  /// Returns a copy with the given fields replaced.
  ///
  /// - [clearLookahead] sets [lookahead] to null; it wins over a given
  ///   duration.
  MidiEngineOptions copyWith({
    MidiInputOptions? input,
    Duration? lateThreshold,
    bool? flushDataEntryMsb,
    Duration? lookahead,
    bool clearLookahead = false,
  }) => MidiEngineOptions(
    input: input ?? this.input,
    lateThreshold: lateThreshold ?? this.lateThreshold,
    flushDataEntryMsb: flushDataEntryMsb ?? this.flushDataEntryMsb,
    lookahead: clearLookahead ? null : lookahead ?? this.lookahead,
  );

  // ...........................................................................
  /// The options of input sessions opened without options of their own.
  final MidiInputOptions input;

  /// How late the software scheduler may send a packet without a
  /// diagnostic.
  final Duration lateThreshold;

  /// Whether outputs translating to MIDI 2.0 send a Data Entry MSB without
  /// LSB.
  final bool flushDataEntryMsb;

  /// How long before their time packets reach outputs that schedule but
  /// cannot discard; null hands them over at once.
  final Duration? lookahead;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiEngineOptions &&
          other.input == input &&
          other.lateThreshold == lateThreshold &&
          other.flushDataEntryMsb == flushDataEntryMsb &&
          other.lookahead == lookahead;

  @override
  int get hashCode =>
      Object.hash(input, lateThreshold, flushDataEntryMsb, lookahead);

  @override
  String toString() =>
      'MidiEngineOptions(input: $input, lateThreshold: $lateThreshold, '
      'flushDataEntryMsb: $flushDataEntryMsb, lookahead: $lookahead)';
}
