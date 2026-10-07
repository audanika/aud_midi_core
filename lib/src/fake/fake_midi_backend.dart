// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../backend/midi_backend.dart';
import '../backend/midi_backend_host.dart';
import '../clock/midi_timer_factory.dart';
import '../error/midi_exception.dart';
import 'midi_fake_bluetooth_backend.dart';
import 'midi_fake_network_backend.dart';
import 'midi_fake_virtual_ports_backend.dart';

// #############################################################################
/// A packet a [FakeMidiBackend] was asked to send: the [port], the
/// [packet] with its due time, and the time [sentAt] on the host clock the
/// backend got it.
typedef MidiFakeSentPacket = ({
  MidiPortId port,
  MidiPacket packet,
  MidiTime sentAt,
});

// #############################################################################
/// An in-memory backend for the tests of every package of the family.
///
/// It proves the Dart side of the contract, never a native binding:
///
/// - Ports are configured with [addPort], [portInfo], [removePort] and
///   [changePort]; while the backend runs, every change reaches the host
///   as a port event, like hotplug.
/// - [connectLoopback] wires an output to an input of the same raw form:
///   what is sent to the output arrives at the input when it is open, at
///   the due time of a future packet or at once.
/// - [inject] delivers packets as if a device sent them, [reportDiagnostic]
///   reports a loss.
/// - [sent] records every packet sent, [calls] every call of the
///   [MidiBackend] contract in order, e.g. `openPort fake:in`.
/// - [failWith] makes calls throw, [holdCalls] keeps them pending.
/// - [virtualPorts], [bluetooth] and [network] are in-memory sub-APIs whose
///   ports appear on this backend.
final class FakeMidiBackend implements MidiBackend {
  /// Creates a fake backend.
  ///
  /// - [name] the backend name and port id prefix.
  /// - [ports] the ports present from the start.
  /// - [capabilities] what the backend reports; by default dynamic virtual
  ///   ports, BLE scanning, AppleMIDI and UMP as far as the sub-APIs exist,
  ///   scheduled in software.
  /// - [hasVirtualPorts], [hasBluetooth] and [hasNetwork] whether the
  ///   sub-APIs exist.
  /// - [timerFactory] creates the timers of BLE scan timeouts.
  FakeMidiBackend({
    this.name = 'fake',
    Iterable<MidiPortInfo> ports = const [],
    MidiCapabilities? capabilities,
    bool hasVirtualPorts = true,
    bool hasBluetooth = true,
    bool hasNetwork = true,
    this.timerFactory = Timer.new,
  }) : capabilities =
           capabilities ??
           MidiCapabilities(
             virtualPorts: hasVirtualPorts
                 ? MidiVirtualPortSupport.dynamicPorts
                 : MidiVirtualPortSupport.none,
             bleScan: hasBluetooth,
             network: {if (hasNetwork) MidiNetworkSupport.appleMidi},
             ump: true,
           ),
       _hasVirtualPorts = hasVirtualPorts,
       _hasBluetooth = hasBluetooth,
       _hasNetwork = hasNetwork {
    for (final port in ports) {
      _ports[port.id] = port;
    }
  }

  // ...........................................................................
  /// Starts the backend; throws a [StateError] when it runs already.
  @override
  Future<void> start(MidiBackendHost host) async {
    _call('start');
    _throwIf(_failures.start);
    if (_host != null) throw StateError('The backend runs already');
    _host = host;
    await _gate?.future;
  }

  @override
  Future<void> stop() async {
    _call('stop');
    _throwIf(_failures.stop);
    _host = null;
    _openPorts.clear();
    await _gate?.future;
  }

  // ...........................................................................
  /// Opens [port]; throws a [MidiPortGone] for an unknown port.
  @override
  Future<void> openPort(MidiPortId port) async {
    _call('openPort $port');
    _throwIf(_failures.openPort);
    _require(port);
    _openPorts.add(port);
    await _gate?.future;
  }

  /// Closes [port]; does nothing for a port that is unknown or not open.
  @override
  Future<void> closePort(MidiPortId port) async {
    _call('closePort $port');
    _throwIf(_failures.closePort);
    _openPorts.remove(port);
    await _gate?.future;
  }

  // ...........................................................................
  /// Records [packet] and passes it on to the open inputs looped back to
  /// [port].
  ///
  /// Throws a [MidiPortGone] for an unknown port, an [ArgumentError] for an
  /// input port, a [MidiUnsupported] for a packet of the other raw form and
  /// a [StateError] when the port is not open or the backend does not run.
  @override
  Future<void> send(MidiPortId port, MidiPacket packet) async {
    _call('send $port');
    _throwIf(_failures.send);
    final info = _requireOutput(port);
    if ((packet is MidiUmpPacket) != info.capabilities.ump) {
      throw MidiUnsupported('${packet.runtimeType} on $port');
    }
    final host = _host;
    if (host == null || !_openPorts.contains(port)) {
      throw StateError('$port is not open');
    }
    final now = host.clock.now();
    _sent.add((port: port, packet: packet, sentAt: now));
    final arrival = packet.copyWith(
      time: packet.time.isAfter(now) ? packet.time : now,
    );
    for (final input in [...?_loopbacks[port]]) {
      if (_openPorts.contains(input)) host.received(input, arrival);
    }
    await _gate?.future;
  }

  /// Records the call; throws a [MidiPortGone] for an unknown port and an
  /// [ArgumentError] for an input port.
  @override
  Future<void> cancelPending(MidiPortId port) async {
    _call('cancelPending $port');
    _throwIf(_failures.cancelPending);
    _requireOutput(port);
    await _gate?.future;
  }

  // ...........................................................................
  /// Returns the description of a port of this backend with [nativeId],
  /// without adding it.
  MidiPortInfo portInfo(
    String nativeId, {
    required MidiDirection direction,
    String? name,
    String manufacturer = 'Audanika',
    int index = 0,
    MidiTransport transport = MidiTransport.software,
    MidiProtocol protocol = MidiProtocol.midi1,
    int group = 0,
    MidiPortCapabilities capabilities = const MidiPortCapabilities(),
    MidiDeviceId? deviceId,
    String serialNumber = '',
  }) => MidiPortInfo(
    id: MidiPortId.of(backend: this.name, nativeId: nativeId),
    deviceId: deviceId,
    name: name ?? nativeId,
    manufacturer: manufacturer,
    direction: direction,
    index: index,
    transport: transport,
    protocol: protocol,
    group: group,
    capabilities: capabilities,
    serialNumber: serialNumber,
  );

  /// Adds [port], or replaces the port with its id, reports it while the
  /// backend runs and returns it.
  MidiPortInfo addPort(MidiPortInfo port) {
    final previous = _ports[port.id];
    _ports[port.id] = port;
    _portsChanged(
      previous == null
          ? MidiPortAdded(port: port)
          : MidiPortChanged(port: port, previous: previous),
    );
    return port;
  }

  /// Removes the port [id] with its loopbacks and reports it while the
  /// backend runs; throws a [MidiPortGone] for an unknown port.
  void removePort(MidiPortId id) {
    final port = _require(id);
    _ports.remove(id);
    _openPorts.remove(id);
    _loopbacks.remove(id);
    for (final inputs in _loopbacks.values) {
      inputs.remove(id);
    }
    _portsChanged(MidiPortRemoved(port: port));
  }

  /// Replaces the port with the id of [port], reports the change while the
  /// backend runs and returns [port]; throws a [MidiPortGone] for an
  /// unknown port.
  MidiPortInfo changePort(MidiPortInfo port) {
    final previous = _require(port.id);
    _ports[port.id] = port;
    _portsChanged(MidiPortChanged(port: port, previous: previous));
    return port;
  }

  /// Returns the port [id], or null when it is unknown.
  MidiPortInfo? port(MidiPortId id) => _ports[id];

  // ...........................................................................
  /// Wires the [output] to the [input] port.
  ///
  /// Throws a [MidiPortGone] for an unknown port and an [ArgumentError]
  /// when the directions or the raw forms do not match.
  void connectLoopback(MidiPortId output, MidiPortId input) {
    final from = _require(output);
    final to = _require(input);
    if (!from.isOutput || !to.isInput) {
      throw ArgumentError('A loopback runs from an output to an input');
    }
    if (from.capabilities.ump != to.capabilities.ump) {
      throw ArgumentError('A loopback needs ports of the same raw form');
    }
    _loopbacks.putIfAbsent(output, () => {}).add(input);
  }

  /// Removes the wire from [output] to [input].
  void disconnectLoopback(MidiPortId output, MidiPortId input) =>
      _loopbacks[output]?.remove(input);

  /// Delivers [packet] as received on the input [port] and returns whether
  /// it arrived, which needs a running backend and an open port.
  bool inject(MidiPortId port, MidiPacket packet) {
    final host = _host;
    if (host == null || !_openPorts.contains(port)) return false;
    host.received(port, packet);
    return true;
  }

  /// Reports [diagnostic] to the host while the backend runs.
  void reportDiagnostic(MidiDiagnostic diagnostic) =>
      _host?.diagnostic(diagnostic);

  // ...........................................................................
  /// Holds the futures of later calls of the contract until
  /// [releaseCalls], e.g. to keep sends in flight; the calls take effect at
  /// once.
  void holdCalls() => _gate ??= Completer<void>();

  /// Completes the calls held since [holdCalls].
  void releaseCalls() {
    _gate?.complete();
    _gate = null;
  }

  /// Makes the calls of the contract throw the given errors from now on;
  /// a null error lets the call succeed. Each call replaces all errors.
  void failWith({
    Object? start,
    Object? stop,
    Object? openPort,
    Object? closePort,
    Object? send,
    Object? cancelPending,
  }) => _failures = (
    start: start,
    stop: stop,
    openPort: openPort,
    closePort: closePort,
    send: send,
    cancelPending: cancelPending,
  );

  /// Forgets the recorded [sent] packets and [calls].
  void clearRecords() {
    _sent.clear();
    _calls.clear();
  }

  // ...........................................................................
  @override
  final String name;

  @override
  final MidiCapabilities capabilities;

  /// Creates the timers of BLE scan timeouts.
  final MidiTimerFactory timerFactory;

  @override
  List<MidiPortInfo> get ports => List.unmodifiable(_ports.values);

  @override
  late final MidiFakeVirtualPortsBackend? virtualPorts = _hasVirtualPorts
      ? MidiFakeVirtualPortsBackend(backend: this)
      : null;

  @override
  late final MidiFakeBluetoothBackend? bluetooth = _hasBluetooth
      ? MidiFakeBluetoothBackend(backend: this)
      : null;

  @override
  late final MidiFakeNetworkBackend? network = _hasNetwork
      ? MidiFakeNetworkBackend(backend: this)
      : null;

  /// The host while the backend runs, otherwise null.
  MidiBackendHost? get host => _host;

  /// Whether the backend runs.
  bool get isStarted => _host != null;

  /// The open ports; cannot be modified.
  Set<MidiPortId> get openPorts => Set.unmodifiable(_openPorts);

  /// The packets sent, in order; cannot be modified.
  List<MidiFakeSentPacket> get sent => List.unmodifiable(_sent);

  /// The calls of the contract, in order, e.g. `send fake:out`; cannot be
  /// modified.
  List<String> get calls => List.unmodifiable(_calls);

  // ...........................................................................
  final bool _hasVirtualPorts;
  final bool _hasBluetooth;
  final bool _hasNetwork;
  final _ports = <MidiPortId, MidiPortInfo>{};
  final _openPorts = <MidiPortId>{};
  final _loopbacks = <MidiPortId, Set<MidiPortId>>{};
  final _sent = <MidiFakeSentPacket>[];
  final _calls = <String>[];
  MidiBackendHost? _host;
  Completer<void>? _gate;
  ({
    Object? start,
    Object? stop,
    Object? openPort,
    Object? closePort,
    Object? send,
    Object? cancelPending,
  })
  _failures = (
    start: null,
    stop: null,
    openPort: null,
    closePort: null,
    send: null,
    cancelPending: null,
  );

  /// Records the call [call].
  void _call(String call) => _calls.add(call);

  /// Throws [error] unless it is null.
  void _throwIf(Object? error) {
    if (error != null) throw error;
  }

  /// Returns the port [id] or throws a [MidiPortGone].
  MidiPortInfo _require(MidiPortId id) =>
      _ports[id] ?? (throw MidiPortGone(id));

  /// Returns the output port [id] or throws.
  MidiPortInfo _requireOutput(MidiPortId id) {
    final port = _require(id);
    if (!port.isOutput) throw ArgumentError.value(id, 'port', 'Not an output');
    return port;
  }

  /// Reports [event] while the backend runs.
  void _portsChanged(MidiPortEvent event) => _host?.portsChanged([event]);
}
