// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../backend/midi_network_backend.dart';
import 'fake_midi_backend.dart';

// #############################################################################
/// The in-memory AppleMIDI session of a [FakeMidiBackend].
///
/// Hosts become browsable with [addHost]. A connection succeeds at once
/// and adds an input and an output byte port per host to the backend, with
/// the ids `'<backend>:<address>:<port>/input'` and `'…/output'`.
final class MidiFakeNetworkBackend implements MidiNetworkBackend {
  /// Creates the network session of [backend].
  MidiFakeNetworkBackend({required this.backend});

  // ...........................................................................
  /// Makes [host] browsable; running browsers report the new list.
  void addHost(MidiNetworkHostInfo host) {
    _hosts.add(host);
    _publishHosts();
  }

  /// Removes [host] from the browsable hosts.
  void removeHost(MidiNetworkHostInfo host) {
    if (_hosts.remove(host)) _publishHosts();
  }

  // ...........................................................................
  @override
  Future<MidiNetworkSessionInfo> enable({
    required String name,
    int? port,
    MidiNetworkConnectionPolicy policy = MidiNetworkConnectionPolicy.anyone,
  }) async {
    _update(
      _session.copyWith(
        localName: name,
        enabled: true,
        port: port ?? defaultPort,
        connectionPolicy: policy,
      ),
    );
    return _session;
  }

  /// Disables the session; every connection ends and its ports disappear.
  @override
  Future<void> disable() async {
    _session.connections.forEach(_removePorts);
    _update(_session.copyWith(enabled: false, connections: const []));
  }

  // ...........................................................................
  /// Connects [host] at once and returns the connection, the existing one
  /// when it is connected already.
  ///
  /// Throws a [StateError] while the session is disabled.
  @override
  Future<MidiNetworkConnectionInfo> connect(MidiNetworkHostInfo host) async {
    if (!_session.enabled) throw StateError('The session is not enabled');
    final existing = _connectionOf(host);
    if (existing != null) return existing;
    final connection = MidiNetworkConnectionInfo(
      host: host,
      state: MidiNetworkConnectionState.connected,
      portIds: [
        backend.addPort(_port(host, MidiDirection.input)).id,
        backend.addPort(_port(host, MidiDirection.output)).id,
      ],
    );
    _update(
      _session.copyWith(connections: [..._session.connections, connection]),
    );
    return connection;
  }

  /// Ends the connection to [host] and removes its ports; does nothing for
  /// a host that is not connected.
  @override
  Future<void> disconnect(MidiNetworkHostInfo host) async {
    final connection = _connectionOf(host);
    if (connection == null) return;
    _removePorts(connection);
    _update(
      _session.copyWith(
        connections: [
          for (final other in _session.connections)
            if (!identical(other, connection)) other,
        ],
      ),
    );
  }

  // ...........................................................................
  /// Reports the browsable hosts now and after every change.
  @override
  Stream<List<MidiNetworkHostInfo>> browse() {
    late final StreamController<List<MidiNetworkHostInfo>> browser;
    browser = StreamController(
      onListen: () {
        _browsers.add(browser);
        browser.add(hosts);
      },
      onCancel: () => _browsers.remove(browser),
    );
    return browser.stream;
  }

  // ...........................................................................
  /// The backend the ports appear on.
  final FakeMidiBackend backend;

  @override
  MidiNetworkSessionInfo get session => _session;

  @override
  Stream<MidiNetworkSessionInfo> get sessionChanges => _changes.stream;

  /// The browsable hosts; cannot be modified.
  List<MidiNetworkHostInfo> get hosts => List.unmodifiable(_hosts);

  // ...........................................................................
  /// The UDP port the session uses when [enable] gets none.
  static const int defaultPort = 5004;

  // ...........................................................................
  MidiNetworkSessionInfo _session = MidiNetworkSessionInfo(
    localName: '',
    enabled: false,
    port: defaultPort,
    protocol: MidiNetworkProtocol.appleMidi,
    connectionPolicy: MidiNetworkConnectionPolicy.anyone,
  );
  final _changes = StreamController<MidiNetworkSessionInfo>.broadcast();
  final _hosts = <MidiNetworkHostInfo>[];
  final _browsers = <StreamController<List<MidiNetworkHostInfo>>>{};

  /// Takes over [session] and reports it.
  void _update(MidiNetworkSessionInfo session) {
    _session = session;
    _changes.add(session);
  }

  /// Reports the browsable hosts to every browser.
  void _publishHosts() {
    for (final browser in [..._browsers]) {
      browser.add(hosts);
    }
  }

  /// Returns the connection to [host], or null.
  MidiNetworkConnectionInfo? _connectionOf(MidiNetworkHostInfo host) {
    for (final connection in _session.connections) {
      if (connection.host == host) return connection;
    }
    return null;
  }

  /// Removes the ports of [connection] that still exist.
  void _removePorts(MidiNetworkConnectionInfo connection) {
    for (final id in connection.portIds) {
      if (backend.port(id) != null) backend.removePort(id);
    }
  }

  /// Returns the port of [host] in [direction].
  MidiPortInfo _port(MidiNetworkHostInfo host, MidiDirection direction) =>
      MidiPortInfo(
        id: MidiPortId.of(
          backend: backend.name,
          nativeId: '${host.address}:${host.port}/${direction.name}',
        ),
        name: host.name,
        direction: direction,
        transport: MidiTransport.network,
      );
}
