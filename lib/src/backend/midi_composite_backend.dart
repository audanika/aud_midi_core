// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../error/midi_exception.dart';
import 'midi_backend.dart';
import 'midi_backend_host.dart';
import 'midi_bluetooth_backend.dart';
import 'midi_network_backend.dart';
import 'midi_virtual_ports_backend.dart';

// #############################################################################
/// Combines several backends into one, e.g. the operating system backend,
/// a network session backend and a BLE-MIDI backend.
///
/// Every backend reports to the same host, so its port ids keep its own
/// name as prefix; calls about a port go to the backend whose
/// [MidiBackend.name] is the prefix of the port id. The capabilities and
/// ports of all running backends are merged. The sub-APIs are the ones
/// given to the constructor, otherwise the first a backend offers.
final class MidiCompositeBackend implements MidiBackend {
  /// Creates a composite of [backends], which must all start, and
  /// [optionalBackends], which are left out when they fail to start; such a
  /// failure becomes a [MidiDiagnosticKind.nativeError] diagnostic.
  ///
  /// - [name] the name of the composite; port ids keep the names of the
  ///   backends.
  /// - [virtualPorts], [bluetooth] and [network] replace the sub-APIs the
  ///   backends offer.
  ///
  /// Throws an [ArgumentError] when two backends share a name.
  MidiCompositeBackend({
    required List<MidiBackend> backends,
    List<MidiBackend> optionalBackends = const [],
    this.name = 'composite',
    this._virtualPorts,
    this._bluetooth,
    this._network,
  }) : backends = List.unmodifiable(backends),
       optionalBackends = List.unmodifiable(optionalBackends) {
    final names = <String>{};
    for (final backend in [...backends, ...optionalBackends]) {
      if (!names.add(backend.name)) {
        throw ArgumentError.value(
          backend.name,
          'backends',
          'Two backends share the name',
        );
      }
    }
  }

  // ...........................................................................
  /// Starts [backends], then [optionalBackends], in their order.
  ///
  /// When a required backend fails, the backends started so far are stopped
  /// again and the error is rethrown. Throws a [StateError] when the
  /// composite runs already.
  @override
  Future<void> start(MidiBackendHost host) async {
    if (_isRunning) throw StateError('The backend runs already');
    _isRunning = true;
    _failed.clear();
    for (final backend in backends) {
      try {
        await backend.start(host);
      } on Object {
        await _stopStarted();
        rethrow;
      }
      _started.add(backend);
    }
    for (final backend in optionalBackends) {
      try {
        await backend.start(host);
        _started.add(backend);
      } on Object catch (error) {
        _failed.add(backend);
        host.diagnostic(
          MidiDiagnostic(
            kind: MidiDiagnosticKind.nativeError,
            cause: 'Backend ${backend.name} failed to start: $error',
            time: host.clock.now(),
          ),
        );
      }
    }
  }

  /// Stops the started backends in reverse order; when some fail, it
  /// rethrows the first failure after all were stopped.
  @override
  Future<void> stop() => _stopStarted();

  // ...........................................................................
  @override
  Future<void> openPort(MidiPortId port) async => _route(port).openPort(port);

  /// Closes [port]; does nothing for a port of no started backend.
  @override
  Future<void> closePort(MidiPortId port) async {
    for (final backend in _started) {
      if (backend.name == port.backend) return backend.closePort(port);
    }
  }

  // ...........................................................................
  @override
  Future<void> send(MidiPortId port, MidiPacket packet) async =>
      _route(port).send(port, packet);

  @override
  Future<void> cancelPending(MidiPortId port) async =>
      _route(port).cancelPending(port);

  // ...........................................................................
  @override
  final String name;

  /// The backends that must start.
  final List<MidiBackend> backends;

  /// The backends that are left out when they fail to start.
  final List<MidiBackend> optionalBackends;

  /// The backends taking part: all of them before [start], afterwards the
  /// ones that did not fail.
  List<MidiBackend> get activeBackends => [
    for (final backend in [...backends, ...optionalBackends])
      if (!_failed.contains(backend)) backend,
  ];

  /// The merged capabilities: the best virtual port support, BLE and UMP
  /// support when any backend has it, the union of the network flavours
  /// and missing permissions, and hardware scheduling only when every
  /// backend schedules in hardware.
  @override
  MidiCapabilities get capabilities {
    final all = [for (final backend in activeBackends) backend.capabilities];
    if (all.isEmpty) return const MidiCapabilities.none();
    return MidiCapabilities(
      virtualPorts: MidiVirtualPortSupport.values.firstWhere(
        (support) => all.any((c) => c.virtualPorts == support),
      ),
      bleScan: all.any((c) => c.bleScan),
      blePeripheral: all.any((c) => c.blePeripheral),
      network: {for (final c in all) ...c.network},
      ump: all.any((c) => c.ump),
      scheduling:
          all.every((c) => c.scheduling == MidiSchedulingSupport.hardware)
          ? MidiSchedulingSupport.hardware
          : MidiSchedulingSupport.software,
      missingPermissions: {for (final c in all) ...c.missingPermissions},
    );
  }

  /// The ports of the started backends.
  @override
  List<MidiPortInfo> get ports => [
    for (final backend in _started) ...backend.ports,
  ];

  @override
  MidiVirtualPortsBackend? get virtualPorts =>
      _virtualPorts ?? _first((backend) => backend.virtualPorts);

  @override
  MidiBluetoothBackend? get bluetooth =>
      _bluetooth ?? _first((backend) => backend.bluetooth);

  @override
  MidiNetworkBackend? get network =>
      _network ?? _first((backend) => backend.network);

  // ...........................................................................
  final MidiVirtualPortsBackend? _virtualPorts;
  final MidiBluetoothBackend? _bluetooth;
  final MidiNetworkBackend? _network;
  final _started = <MidiBackend>[];
  final _failed = <MidiBackend>{};
  bool _isRunning = false;

  /// Returns the started backend that owns [port], or throws a
  /// [MidiPortGone].
  MidiBackend _route(MidiPortId port) {
    for (final backend in _started) {
      if (backend.name == port.backend) return backend;
    }
    throw MidiPortGone(port);
  }

  /// Returns the first sub-API [of] returns for an active backend.
  T? _first<T extends Object>(T? Function(MidiBackend backend) of) {
    for (final backend in activeBackends) {
      final api = of(backend);
      if (api != null) return api;
    }
    return null;
  }

  /// Stops the started backends in reverse order and rethrows the first
  /// failure.
  Future<void> _stopStarted() async {
    _isRunning = false;
    final started = _started.reversed.toList();
    _started.clear();
    Object? firstError;
    StackTrace? firstStack;
    for (final backend in started) {
      try {
        await backend.stop();
      } on Object catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
