// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Finds and connects Bluetooth LE MIDI peripherals as central.
abstract interface class MidiBluetoothBackend {
  // ...........................................................................
  /// Scans for peripherals that advertise the BLE-MIDI service and reports
  /// each finding; the stream ends after [timeout] or [stopScan].
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout});

  /// Stops a running scan.
  Future<void> stopScan();

  // ...........................................................................
  /// Connects the peripheral [peripheralId] and returns the ports it
  /// provides.
  ///
  /// Throws a `MidiException` when the connection does not succeed within
  /// [timeout].
  Future<List<MidiPortInfo>> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  });

  /// Disconnects the peripheral [peripheralId]; its ports disappear.
  Future<void> disconnect(String peripheralId);
}
