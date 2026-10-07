// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_panic.dart';

// #############################################################################
/// A handle on an open output port, created by `MidiEngine.openOutput`.
///
/// Several sessions on one port share one open of the native port and one
/// send queue, so the order of all sends to a port is kept.
///
/// Messages are translated to what the port takes: a byte port gets MIDI
/// 1.0 bytes, MIDI 2.0 messages translated down; a UMP port gets Universal
/// MIDI Packets in the port's protocol. Messages that cannot be expressed
/// there are dropped and reported as `MidiDiagnosticKind.untranslatable`.
///
/// A send with a past or absent `at` leaves at once. A future `at` goes to
/// the operating system when the port has
/// [MidiPortCapabilities.scheduledSend], otherwise to the engine's
/// software scheduler. The returned future completes when the port's queue
/// accepted the message, not when it left the device; a failure after
/// that point becomes a `MidiDiagnosticKind.nativeError` diagnostic.
///
/// Every method throws a `MidiPortGone` once the port disappeared and a
/// [StateError] after [close].
abstract interface class MidiOutputSession {
  // ...........................................................................
  /// Sends [message] at [at] on [group].
  ///
  /// - [at] the due time on the package clock; null or a past time sends
  ///   at once.
  /// - [group] the group of a UMP port, 0 to 15; null for the port's
  ///   group. Byte ports ignore it.
  Future<void> send(MidiMessage message, {MidiTime? at, int? group});

  /// Sends [messages] together in one packet at [at] on [group], like
  /// [send].
  Future<void> sendAll(
    Iterable<MidiMessage> messages, {
    MidiTime? at,
    int? group,
  });

  /// Sends the raw [packet] at its [MidiPacket.time].
  ///
  /// A packet of the port's raw form goes out unchanged. Otherwise it is
  /// decoded and sent like messages; it must then hold complete messages.
  Future<void> sendPacket(MidiPacket packet);

  // ...........................................................................
  /// Discards the messages of the port that wait for their due time, in
  /// the software scheduler and, where the port supports it
  /// ([MidiPortCapabilities.cancelPending]), in the operating system.
  ///
  /// Returns the number of packets that still leave: a port that
  /// schedules in the operating system but cannot discard keeps the
  /// packets it was handed and sends them at their due time. With
  /// `MidiEngineOptions.lookahead` such packets reach the operating system
  /// only shortly before their time, so that only those stay.
  Future<int> cancelPending();

  /// Silences the port as [panic] describes: it discards pending messages
  /// first when told to, then sends the panic messages at once on the
  /// port's group and on every group with notes still on.
  ///
  /// When the operating system keeps packets it cannot discard, the panic
  /// messages are sent once more, one millisecond after the last of them.
  Future<void> panic({MidiPanic panic = const MidiPanic()});

  // ...........................................................................
  /// Closes the session; closing the last session of a port discards the
  /// messages scheduled on it and closes the native port. Closing twice
  /// does nothing.
  Future<void> close();

  // ...........................................................................
  /// The port of the session as it is now.
  MidiPortInfo get port;

  /// Whether the session is closed, by [close], by the removal of its port
  /// or by the engine.
  bool get isClosed;

  /// Completes when the session is closed.
  Future<void> get done;
}
