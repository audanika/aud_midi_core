// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A session that is always enabled and connects every host at once.
final class _AlwaysOn implements MidiNetworkBackend {
  final log = <String>[];

  @override
  Future<MidiNetworkSessionInfo> enable({
    required String name,
    int? port,
    MidiNetworkConnectionPolicy policy = MidiNetworkConnectionPolicy.anyone,
  }) async {
    log.add('enable $name $port ${policy.name}');
    return session;
  }

  @override
  Future<void> disable() async => log.add('disable');

  @override
  Future<MidiNetworkConnectionInfo> connect(MidiNetworkHostInfo host) async {
    log.add('connect ${host.name}');
    return MidiNetworkConnectionInfo(
      host: host,
      state: MidiNetworkConnectionState.connected,
    );
  }

  @override
  Future<void> disconnect(MidiNetworkHostInfo host) async =>
      log.add('disconnect ${host.name}');

  @override
  Stream<List<MidiNetworkHostInfo>> browse() => Stream.value(const []);

  @override
  MidiNetworkSessionInfo get session => MidiNetworkSessionInfo(
    localName: 'Studio',
    enabled: true,
    port: 5004,
    protocol: MidiNetworkProtocol.appleMidi,
    connectionPolicy: MidiNetworkConnectionPolicy.anyone,
  );

  @override
  Stream<MidiNetworkSessionInfo> get sessionChanges => const Stream.empty();
}

void main() {
  group('MidiNetworkBackend', () {
    test('is implemented by the package', () {
      expect(FakeMidiBackend().network, isA<MidiNetworkBackend>());
    });

    test('runs an implementation through the whole contract', () async {
      final alwaysOn = _AlwaysOn();
      final MidiNetworkBackend network = alwaysOn;
      const host = MidiNetworkHostInfo(
        name: 'Mac',
        address: '10.0.0.2',
        port: 5004,
      );
      final session = await network.enable(name: 'Studio');
      final connection = await network.connect(host);
      await network.disconnect(host);
      await network.disable();
      expect(session.localName, 'Studio');
      expect(connection.host, host);
      expect(await network.browse().first, isEmpty);
      expect(await network.sessionChanges.isEmpty, isTrue);
      expect(
        alwaysOn.log,
        equals([
          'enable Studio null anyone',
          'connect Mac',
          'disconnect Mac',
          'disable',
        ]),
      );
    });
  });
}
