// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Runs a network MIDI session: an operating system session such as
/// `MIDINetworkSession` or a session of the package's own protocols.
///
/// Every connection of the session appears as an input and an output
/// port.
abstract interface class MidiNetworkBackend {
  // ...........................................................................
  /// Enables the session under [name] on [port] (null for the protocol's
  /// default) and advertises it.
  Future<MidiNetworkSessionInfo> enable({
    required String name,
    int? port,
    MidiNetworkConnectionPolicy policy = MidiNetworkConnectionPolicy.anyone,
  });

  /// Disables the session; all connections end.
  Future<void> disable();

  // ...........................................................................
  /// Connects to [host] and returns the connection once established.
  Future<MidiNetworkConnectionInfo> connect(MidiNetworkHostInfo host);

  /// Ends the connection to [host].
  Future<void> disconnect(MidiNetworkHostInfo host);

  // ...........................................................................
  /// Browses the local network for sessions and reports the current list
  /// of hosts after every change.
  Stream<List<MidiNetworkHostInfo>> browse();

  // ...........................................................................
  /// The current state of the session.
  MidiNetworkSessionInfo get session;

  /// Reports every change of [session].
  Stream<MidiNetworkSessionInfo> get sessionChanges;
}
