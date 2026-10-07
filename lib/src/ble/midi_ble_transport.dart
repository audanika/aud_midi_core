// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_ble_connection.dart';

// #############################################################################
/// A Bluetooth LE GATT client that reaches BLE-MIDI peripherals, for
/// platforms where the operating system does not expose them as MIDI
/// ports, e.g. Linux with BlueZ or Web Bluetooth.
///
/// The BLE-MIDI service has the UUID [serviceUuid], its MIDI I/O
/// characteristic [characteristicUuid] (Specification for MIDI over
/// Bluetooth Low Energy, BLE-MIDI 1.0).
abstract interface class MidiBleTransport {
  // ...........................................................................
  /// Scans for peripherals advertising the BLE-MIDI service; the stream
  /// ends after [timeout] or [stopScan].
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout});

  /// Stops a running scan.
  Future<void> stopScan();

  // ...........................................................................
  /// Connects [peripheralId], subscribes to the MIDI I/O characteristic and
  /// returns the connection.
  Future<MidiBleConnection> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  });

  // ...........................................................................
  /// The UUID of the BLE-MIDI service.
  static const String serviceUuid = '03b80e5a-ede8-4b33-a751-6ce34ec4c700';

  /// The UUID of the BLE-MIDI I/O characteristic.
  static const String characteristicUuid =
      '7772e5db-3868-4112-a1a9-f2669d106bf3';
}
