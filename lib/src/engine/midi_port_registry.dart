// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// The ports an engine knows right now, kept up to date from the port
/// events of its backend.
///
/// Ports are the primary entity; devices are derived from the
/// [MidiPortInfo.deviceId] of the ports. Re-plugged devices usually get new
/// port ids; [replugCandidates] finds ports with the same fingerprint, but
/// the registry never decides between several candidates.
final class MidiPortRegistry {
  /// Creates an empty registry.
  MidiPortRegistry();

  // ...........................................................................
  /// Replaces the known ports with [ports] without publishing events.
  void reset(Iterable<MidiPortInfo> ports) {
    _ports
      ..clear()
      ..addEntries(ports.map((port) => MapEntry(port.id, port)));
  }

  /// Applies the port [events] of a backend and returns the events that
  /// changed the registry; [events] publishes the same ones.
  ///
  /// The returned events are normalised against the known ports: an added
  /// port that is known already becomes a change, a changed port that is
  /// unknown an addition, a removal carries the last known description,
  /// and events that change nothing — repeated additions, removals of
  /// unknown ports, changes only of [MidiPortInfo.native] — disappear;
  /// the native extras are taken over silently.
  List<MidiPortEvent> apply(Iterable<MidiPortEvent> events) {
    final applied = [for (final event in events) ?_apply(event)];
    if (!_controller.isClosed) applied.forEach(_controller.add);
    return applied;
  }

  // ...........................................................................
  /// Returns the port with [id], or null when it is unknown.
  MidiPortInfo? port(MidiPortId id) => _ports[id];

  /// Returns the other known ports with the fingerprint of [port].
  ///
  /// A single candidate is most likely [port] plugged in again; several
  /// candidates are identical devices the registry cannot tell apart, and
  /// the app has to decide.
  List<MidiPortInfo> replugCandidates(MidiPortInfo port) => [
    for (final known in _ports.values)
      if (known.id != port.id && known.fingerprint == port.fingerprint) known,
  ];

  // ...........................................................................
  /// Completes [events]; later changes are applied without being
  /// published.
  Future<void> close() => _controller.close();

  // ...........................................................................
  /// The known ports in the order they appeared; cannot be modified.
  List<MidiPortInfo> get ports => List.unmodifiable(_ports.values);

  /// The known input ports.
  List<MidiPortInfo> get inputs =>
      List.unmodifiable(_ports.values.where((port) => port.isInput));

  /// The known output ports.
  List<MidiPortInfo> get outputs =>
      List.unmodifiable(_ports.values.where((port) => port.isOutput));

  /// The devices of the known ports, in the order their first port
  /// appeared.
  ///
  /// A device takes its manufacturer, serial number and transport from its
  /// first port. Its name, product and driver come from the native extras
  /// [deviceNameKey], [productKey] and [driverKey] of that port when the
  /// backend provides them, otherwise from the port's name, nothing and the
  /// backend name. A device is offline when all its ports are.
  List<MidiDeviceInfo> get devices {
    final portsByDevice = <MidiDeviceId, List<MidiPortInfo>>{};
    for (final port in _ports.values) {
      final deviceId = port.deviceId;
      if (deviceId != null) {
        portsByDevice.putIfAbsent(deviceId, () => []).add(port);
      }
    }
    return [
      for (final MapEntry(:key, :value) in portsByDevice.entries)
        _device(key, value),
    ];
  }

  /// The applied port events.
  Stream<MidiPortEvent> get events => _controller.stream;

  /// Whether [close] was called.
  bool get isClosed => _controller.isClosed;

  // ...........................................................................
  /// The key of the device name in [MidiPortInfo.native].
  static const String deviceNameKey = 'deviceName';

  /// The key of the device's product name in [MidiPortInfo.native].
  static const String productKey = 'product';

  /// The key of the device's driver or owner in [MidiPortInfo.native].
  static const String driverKey = 'driver';

  // ...........................................................................
  final _ports = <MidiPortId, MidiPortInfo>{};
  final _controller = StreamController<MidiPortEvent>.broadcast();

  /// Applies [event] and returns its normalised form, or null when it
  /// changed nothing.
  MidiPortEvent? _apply(MidiPortEvent event) {
    final port = event.port;
    final known = _ports[port.id];
    switch (event) {
      case MidiPortRemoved():
        if (known == null) return null;
        _ports.remove(port.id);
        return MidiPortRemoved(port: known);
      case MidiPortAdded() || MidiPortChanged():
        _ports[port.id] = port;
        if (known == null) return MidiPortAdded(port: port);
        if (known == port) return null;
        return MidiPortChanged(port: port, previous: known);
    }
  }

  /// Returns the device [id] derived from its [ports].
  static MidiDeviceInfo _device(MidiDeviceId id, List<MidiPortInfo> ports) {
    final first = ports.first;
    return MidiDeviceInfo(
      id: id,
      name: _text(first, deviceNameKey) ?? first.name,
      manufacturer: first.manufacturer,
      product: _text(first, productKey) ?? '',
      serialNumber: first.serialNumber,
      transport: first.transport,
      driver: _text(first, driverKey) ?? id.backend,
      isOffline: ports.every((port) => port.state == MidiPortState.offline),
      ports: [for (final port in ports) port.id],
    );
  }

  /// Returns the native extra [key] of [port] when it is a string.
  static String? _text(MidiPortInfo port, String key) {
    final value = port.native[key];
    return value is String ? value : null;
  }
}
