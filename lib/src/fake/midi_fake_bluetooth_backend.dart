// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../backend/midi_bluetooth_backend.dart';
import '../error/midi_exception.dart';
import 'fake_midi_backend.dart';

// #############################################################################
/// The in-memory BLE-MIDI central of a [FakeMidiBackend].
///
/// Peripherals become discoverable with [addPeripheral]. A connection
/// succeeds at once and adds an input and an output byte port per
/// peripheral to the backend, with the ids
/// `'<backend>:<peripheralId>/input'` and `'…/output'`.
final class MidiFakeBluetoothBackend implements MidiBluetoothBackend {
  /// Creates the BLE central of [backend].
  MidiFakeBluetoothBackend({required this.backend});

  // ...........................................................................
  /// Makes [peripheral] discoverable; running scans report it at once.
  void addPeripheral(MidiBlePeripheralInfo peripheral) {
    _peripherals[peripheral.id] = peripheral;
    for (final scan in [..._scans.keys]) {
      scan.add(peripheral);
    }
  }

  // ...........................................................................
  /// Reports the discoverable peripherals and those added later, until
  /// [timeout] passed on the backend's timers or [stopScan] is called.
  @override
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout}) {
    late final StreamController<MidiBlePeripheralInfo> scan;
    scan = StreamController(
      onListen: () {
        _scans[scan] = timeout == null
            ? null
            : backend.timerFactory(timeout, () => _end(scan));
        _peripherals.values.forEach(scan.add);
      },
      onCancel: () => _end(scan),
    );
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    for (final scan in [..._scans.keys]) {
      _end(scan);
    }
  }

  // ...........................................................................
  /// Connects the discoverable [peripheralId] at once and returns its
  /// ports, the existing ones when it is connected already.
  ///
  /// Throws a [MidiPortGone] for a peripheral that was never added.
  @override
  Future<List<MidiPortInfo>> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final peripheral =
        _peripherals[peripheralId] ??
        (throw MidiPortGone(
          MidiPortId.of(backend: backend.name, nativeId: peripheralId),
        ));
    final existing = _connections[peripheralId];
    if (existing != null) return existing;
    final ports = List<MidiPortInfo>.unmodifiable([
      backend.addPort(_port(peripheral, MidiDirection.input)),
      backend.addPort(_port(peripheral, MidiDirection.output)),
    ]);
    _connections[peripheralId] = ports;
    _peripherals[peripheralId] = peripheral.copyWith(
      state: MidiBlePeripheralState.connected,
      portIds: [for (final port in ports) port.id],
    );
    return ports;
  }

  /// Disconnects [peripheralId] and removes its ports; does nothing for a
  /// peripheral that is not connected.
  @override
  Future<void> disconnect(String peripheralId) async {
    final ports = _connections.remove(peripheralId);
    if (ports == null) return;
    for (final port in ports) {
      if (backend.port(port.id) != null) backend.removePort(port.id);
    }
    _peripherals[peripheralId] = _peripherals[peripheralId]!.copyWith(
      state: MidiBlePeripheralState.disconnected,
      portIds: const [],
    );
  }

  // ...........................................................................
  /// The backend the ports appear on.
  final FakeMidiBackend backend;

  /// The discoverable peripherals with their current state; cannot be
  /// modified.
  List<MidiBlePeripheralInfo> get peripherals =>
      List.unmodifiable(_peripherals.values);

  /// Whether a scan is running.
  bool get isScanning => _scans.isNotEmpty;

  // ...........................................................................
  final _peripherals = <String, MidiBlePeripheralInfo>{};
  final _connections = <String, List<MidiPortInfo>>{};
  final _scans = <StreamController<MidiBlePeripheralInfo>, Timer?>{};

  /// Ends the running [scan].
  void _end(StreamController<MidiBlePeripheralInfo> scan) {
    if (!_scans.containsKey(scan)) return;
    _scans.remove(scan)?.cancel();
    unawaited(scan.close());
  }

  /// Returns the port of [peripheral] in [direction].
  MidiPortInfo _port(
    MidiBlePeripheralInfo peripheral,
    MidiDirection direction,
  ) => MidiPortInfo(
    id: MidiPortId.of(
      backend: backend.name,
      nativeId: '${peripheral.id}/${direction.name}',
    ),
    deviceId: MidiDeviceId.of(backend: backend.name, nativeId: peripheral.id),
    name: peripheral.name.isEmpty ? peripheral.id : peripheral.name,
    direction: direction,
    transport: MidiTransport.bluetoothLe,
    capabilities: const MidiPortCapabilities(timestampsIn: true),
    serialNumber: peripheral.id,
  );
}
