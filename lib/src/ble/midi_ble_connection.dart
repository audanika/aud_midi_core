// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

// #############################################################################
/// An open connection to the MIDI I/O characteristic of one BLE-MIDI
/// peripheral.
abstract interface class MidiBleConnection {
  // ...........................................................................
  /// Writes one BLE-MIDI [packet] without response.
  Future<void> write(Uint8List packet);

  /// Disconnects the peripheral.
  Future<void> disconnect();

  // ...........................................................................
  /// The id of the connected peripheral.
  String get peripheralId;

  /// The notifications of the characteristic, one BLE-MIDI packet each.
  Stream<Uint8List> get notifications;

  /// The largest packet that fits, the negotiated ATT MTU minus 3.
  int get maxPacketLength;

  /// Completes when the connection ends, for whatever reason.
  Future<void> get done;
}
