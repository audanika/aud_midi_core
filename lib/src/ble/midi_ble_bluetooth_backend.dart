// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:typed_data';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../backend/midi_backend.dart';
import '../backend/midi_backend_host.dart';
import '../backend/midi_bluetooth_backend.dart';
import '../backend/midi_network_backend.dart';
import '../backend/midi_virtual_ports_backend.dart';
import '../error/midi_exception.dart';
import 'midi_ble_connection.dart';
import 'midi_ble_transport.dart';

// #############################################################################
/// A backend for BLE-MIDI peripherals reached through a GATT client, for
/// platforms whose operating system does not expose them as MIDI ports
/// (Specification for MIDI over Bluetooth Low Energy, BLE-MIDI 1.0).
///
/// It is its own [bluetooth] sub-API. [connect] opens a connection through
/// the [transport] and adds one input and one output byte port for the
/// peripheral, with the ids `'<name>:<peripheralId>/input'` and `'…/output'`
/// and the transport [MidiTransport.bluetoothLe].
///
/// - Notifications of the open input go through a [MidiBleDecoder]; every
///   decoded message becomes a bytes packet with its reconstructed time.
/// - Sends are parsed into messages, encoded with a [MidiBleEncoder] sized
///   to the connection's packet length and written in order.
/// - A connection that ends, for whatever reason, removes its ports.
final class MidiBleBluetoothBackend
    implements MidiBackend, MidiBluetoothBackend {
  /// Creates a backend on [transport].
  ///
  /// - [name] the backend name and port id prefix.
  /// - [maxSysExLength] the largest System Exclusive the decoder accepts,
  ///   in data bytes.
  MidiBleBluetoothBackend({
    required this.transport,
    this.name = 'ble',
    this.maxSysExLength = 1 << 20,
  });

  // ...........................................................................
  /// Starts the backend; throws a [StateError] when it runs already.
  @override
  Future<void> start(MidiBackendHost host) async {
    if (_host != null) throw StateError('The backend runs already');
    _host = host;
  }

  /// Disconnects all peripherals without reporting their ports as removed.
  @override
  Future<void> stop() async {
    _host = null;
    final peripherals = [..._peripherals.values];
    _peripherals.clear();
    for (final peripheral in peripherals) {
      await peripheral.subscription.cancel();
      await peripheral.connection.disconnect();
    }
  }

  // ...........................................................................
  /// Opens [port]: an input starts to deliver, with a fresh decoder.
  ///
  /// Throws a [MidiPortGone] for an unknown port.
  @override
  Future<void> openPort(MidiPortId port) async {
    final peripheral = _peripheralOf(port);
    if (port != peripheral.input.id) return;
    peripheral.decoder.reset();
    peripheral.isInputOpen = true;
  }

  /// Closes [port]: an input stops delivering. Does nothing for an unknown
  /// port.
  @override
  Future<void> closePort(MidiPortId port) async {
    for (final peripheral in _peripherals.values) {
      if (port == peripheral.input.id) peripheral.isInputOpen = false;
    }
  }

  // ...........................................................................
  /// Writes the bytes [packet] to the output [port] at once, after the
  /// writes sent before; the packet time is not used, BLE-MIDI timestamps
  /// carry the send time.
  ///
  /// Throws a [MidiPortGone] for an unknown port, an [ArgumentError] for an
  /// input port and a [MidiUnsupported] for a UMP packet.
  @override
  Future<void> send(MidiPortId port, MidiPacket packet) async {
    final peripheral = _outputOf(port);
    if (packet is! MidiBytesPacket) {
      throw MidiUnsupported('UMP packets on the BLE-MIDI port $port');
    }
    final time = _requireHost().clock.now();
    final messages = peripheral.parser.add(packet.bytes.bytes, time: time);
    final encoder = MidiBleEncoder(
      maxPacketLength: peripheral.connection.maxPacketLength,
    );
    await peripheral.write(encoder.encode(messages));
  }

  /// Does nothing, BLE-MIDI holds no packets for later; throws a
  /// [MidiPortGone] for an unknown port and an [ArgumentError] for an
  /// input port.
  @override
  Future<void> cancelPending(MidiPortId port) async => _outputOf(port);

  // ...........................................................................
  /// Scans through the [transport] and remembers the names of the found
  /// peripherals for their ports.
  @override
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout}) =>
      transport.scan(timeout: timeout).map((peripheral) {
        if (peripheral.name.isNotEmpty) {
          _names[peripheral.id] = peripheral.name;
        }
        return peripheral;
      });

  @override
  Future<void> stopScan() => transport.stopScan();

  // ...........................................................................
  /// Connects [peripheralId] and returns its ports, the existing ones when
  /// it is connected already.
  ///
  /// Throws a [StateError] before [start] and what the transport throws.
  @override
  Future<List<MidiPortInfo>> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final existing = _peripherals[peripheralId];
    if (existing != null) return Future.value(existing.ports);
    // A block body: returning the removed future would make whenComplete
    // wait for the very future it completes.
    return _connecting[peripheralId] ??= _connect(peripheralId, timeout)
        .whenComplete(() {
          _connecting.remove(peripheralId);
        });
  }

  /// Disconnects [peripheralId] and removes its ports; does nothing for a
  /// peripheral that is not connected.
  @override
  Future<void> disconnect(String peripheralId) async {
    final peripheral = _peripherals[peripheralId];
    if (peripheral == null) return;
    _lost(peripheral);
    await peripheral.connection.disconnect();
  }

  // ...........................................................................
  /// The GATT client.
  final MidiBleTransport transport;

  @override
  final String name;

  /// The largest System Exclusive the decoder accepts, in data bytes.
  final int maxSysExLength;

  @override
  final MidiCapabilities capabilities = MidiCapabilities(bleScan: true);

  /// The ports of the connected peripherals.
  @override
  List<MidiPortInfo> get ports => [
    for (final peripheral in _peripherals.values) ...peripheral.ports,
  ];

  @override
  MidiVirtualPortsBackend? get virtualPorts => null;

  @override
  MidiBluetoothBackend get bluetooth => this;

  @override
  MidiNetworkBackend? get network => null;

  // ...........................................................................
  MidiBackendHost? _host;
  final _peripherals = <String, _BlePeripheral>{};
  final _connecting = <String, Future<List<MidiPortInfo>>>{};
  final _names = <String, String>{};

  /// Opens the connection to [peripheralId] and adds its ports.
  Future<List<MidiPortInfo>> _connect(
    String peripheralId,
    Duration timeout,
  ) async {
    _requireHost();
    final connection = await transport.connect(peripheralId, timeout: timeout);
    final host = _host;
    if (host == null) {
      await connection.disconnect();
      throw StateError('The backend stopped while connecting');
    }
    final input = _port(peripheralId, MidiDirection.input);
    final peripheral = _BlePeripheral(
      id: peripheralId,
      connection: connection,
      input: input,
      output: _port(peripheralId, MidiDirection.output),
      decoder: MidiBleDecoder(
        maxSysExLength: maxSysExLength,
        onIssue: (kind, cause) => _issue(input.id, kind, cause),
      ),
    );
    _peripherals[peripheralId] = peripheral;
    peripheral.subscription = connection.notifications.listen(
      (data) => _notified(peripheral, data),
    );
    unawaited(
      connection.done.then(
        (_) => _lost(peripheral),
        onError: (Object _) => _lost(peripheral),
      ),
    );
    host.portsChanged([
      for (final port in peripheral.ports) MidiPortAdded(port: port),
    ]);
    return peripheral.ports;
  }

  /// Delivers the messages of the notification [data] of [peripheral].
  void _notified(_BlePeripheral peripheral, Uint8List data) {
    final host = _host;
    if (host == null || !peripheral.isInputOpen) return;
    final decoded = peripheral.decoder.decode(data, time: host.clock.now());
    for (final (:message, :time) in decoded) {
      final bytes = MidiByteEncoder.encodeAll([message]);
      if (bytes.isEmpty) continue;
      host.received(
        peripheral.input.id,
        MidiBytesPacket(bytes: bytes, time: time),
      );
    }
  }

  /// Forgets [peripheral] and reports its ports as removed, once.
  void _lost(_BlePeripheral peripheral) {
    if (!identical(_peripherals[peripheral.id], peripheral)) return;
    _peripherals.remove(peripheral.id);
    unawaited(peripheral.subscription.cancel());
    _host?.portsChanged([
      for (final port in peripheral.ports) MidiPortRemoved(port: port),
    ]);
  }

  /// Reports an issue of [kind] with [cause] for [port].
  void _issue(MidiPortId port, MidiDiagnosticKind kind, String cause) {
    final host = _host;
    if (host == null) return;
    host.diagnostic(
      MidiDiagnostic(
        kind: kind,
        port: port,
        cause: cause,
        time: host.clock.now(),
      ),
    );
  }

  /// Returns the connected peripheral that owns [port], or throws a
  /// [MidiPortGone].
  _BlePeripheral _peripheralOf(MidiPortId port) {
    for (final peripheral in _peripherals.values) {
      if (peripheral.input.id == port || peripheral.output.id == port) {
        return peripheral;
      }
    }
    throw MidiPortGone(port);
  }

  /// Returns the peripheral whose output is [port], or throws.
  _BlePeripheral _outputOf(MidiPortId port) {
    final peripheral = _peripheralOf(port);
    if (port != peripheral.output.id) {
      throw ArgumentError.value(port, 'port', 'Not an output');
    }
    return peripheral;
  }

  /// Returns the host, or throws a [StateError] before [start].
  MidiBackendHost _requireHost() =>
      _host ?? (throw StateError('The backend is not started'));

  /// Returns the port of [peripheralId] in [direction].
  MidiPortInfo _port(String peripheralId, MidiDirection direction) =>
      MidiPortInfo(
        id: MidiPortId.of(
          backend: name,
          nativeId: '$peripheralId/${direction.name}',
        ),
        deviceId: MidiDeviceId.of(backend: name, nativeId: peripheralId),
        name: _names[peripheralId] ?? peripheralId,
        direction: direction,
        transport: MidiTransport.bluetoothLe,
        capabilities: const MidiPortCapabilities(timestampsIn: true),
        serialNumber: peripheralId,
      );
}

// #############################################################################
/// A connected peripheral of [MidiBleBluetoothBackend].
final class _BlePeripheral {
  _BlePeripheral({
    required this.id,
    required this.connection,
    required this.input,
    required this.output,
    required this.decoder,
  });

  // ...........................................................................
  /// Writes [packets] after all writes queued before.
  Future<void> write(List<Uint8List> packets) {
    final written = _writes.then((_) async {
      for (final packet in packets) {
        await connection.write(packet);
      }
    });
    _writes = written.then((_) {}, onError: (Object _) {});
    return written;
  }

  // ...........................................................................
  /// The id the peripheral was connected with.
  final String id;

  /// The open connection.
  final MidiBleConnection connection;

  /// The input port.
  final MidiPortInfo input;

  /// The output port.
  final MidiPortInfo output;

  /// Decodes the notifications.
  final MidiBleDecoder decoder;

  /// Splits the sent bytes into messages.
  final parser = MidiByteParser();

  /// The subscription to the notifications.
  late final StreamSubscription<Uint8List> subscription;

  /// Whether the input port is open.
  bool isInputOpen = false;

  /// Both ports.
  List<MidiPortInfo> get ports => [input, output];

  // ...........................................................................
  Future<void> _writes = Future.value();
}
