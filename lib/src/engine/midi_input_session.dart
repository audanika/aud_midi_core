// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_input_options.dart';

// #############################################################################
/// A handle on an open input port, created by `MidiEngine.openInput`.
///
/// Several sessions on one port share one open of the native port; each
/// session has its own [options] and its own queues.
///
/// - [events] delivers the parsed messages: byte ports go through a MIDI
///   1.0 parser and get the port's group, UMP ports through a UMP decoder.
///   JR Timestamps set the [MidiEvent.senderTime] of the events after them
///   (M2-104-UM 7.2.2.2); they, JR Clocks and NOOPs are not delivered.
/// - [packets] delivers the raw packets exactly as the backend received
///   them.
///
/// A stream starts to collect when it is read for the first time. Each
/// stream keeps at most [MidiInputOptions.queueCapacity] undelivered
/// values, e.g. while its subscription is paused; newer values are dropped
/// and reported as a `MidiDiagnosticKind.queueOverflow` diagnostic with the
/// number of dropped values. The streams never error; they complete when
/// the session closes, also when the port disappears.
abstract interface class MidiInputSession {
  // ...........................................................................
  /// Closes the session: its streams complete at once and undelivered
  /// values are discarded. Closing the last session of a port closes the
  /// native port. Closing twice does nothing.
  Future<void> close();

  // ...........................................................................
  /// The port of the session as it is now.
  MidiPortInfo get port;

  /// The options of the session.
  MidiInputOptions get options;

  /// The events of the port, collected from the first read on.
  Stream<MidiEvent> get events;

  /// The raw packets of the port, collected from the first read on.
  Stream<MidiPacket> get packets;

  /// Whether the session is closed, by [close], by the removal of its port
  /// or by the engine.
  bool get isClosed;

  /// Completes when the session is closed.
  ///
  /// When the port disappeared, the streams still deliver the values they
  /// queued before they complete.
  Future<void> get done;
}
