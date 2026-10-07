// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../clock/midi_clock.dart';

// #############################################################################
/// The connection of a backend to the engine that hosts it.
///
/// The engine passes its host to [MidiBackend.start]. Backends report
/// everything that happens on their own — hotplug, received data, losses —
/// through these methods, always from the isolate that hosts the engine.
abstract interface class MidiBackendHost {
  // ...........................................................................
  /// The package clock; every [MidiTime] the backend reports uses it.
  MidiClock get clock;

  // ...........................................................................
  /// Reports ports that appeared, disappeared or changed.
  ///
  /// A port that disappears while it is open counts as closed.
  void portsChanged(List<MidiPortEvent> events);

  // ...........................................................................
  /// Reports a [packet] received on the input [port]; the packet's time is
  /// the operating system's receive time on the package clock.
  void received(MidiPortId port, MidiPacket packet);

  // ...........................................................................
  /// Reports a loss or fault, e.g. a dropped buffer or a failed OS call.
  ///
  /// A diagnostic of kind [MidiDiagnosticKind.queueOverflow] or
  /// [MidiDiagnosticKind.networkLoss] for an input port marks a gap in its
  /// stream: the engine drops the partial messages of the port.
  void diagnostic(MidiDiagnostic diagnostic);
}
