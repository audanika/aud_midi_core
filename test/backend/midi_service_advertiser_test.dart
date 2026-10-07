// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A registration of [_MemoryAdvertiser].
final class _Registration implements MidiServiceRegistration {
  _Registration(this.name, this._services);

  final Map<String, String> _services;

  @override
  final String name;

  @override
  Future<void> unregister() async => _services.remove(name);
}

/// An advertiser that keeps the services in memory and renames
/// conflicting ones like a DNS-SD registrar.
final class _MemoryAdvertiser implements MidiServiceAdvertiser {
  final services = <String, String>{};

  @override
  Future<MidiServiceRegistration> register({
    required String name,
    required String type,
    required int port,
    Map<String, String> txt = const {},
  }) async {
    var unique = name;
    for (var i = 2; services.containsKey(unique); i++) {
      unique = '$name ($i)';
    }
    services[unique] = '$type:$port$txt';
    return _Registration(unique, services);
  }
}

void main() {
  group('MidiServiceAdvertiser', () {
    group('register({name, type, port, txt})', () {
      test('registers a service and renames conflicts', () async {
        final memory = _MemoryAdvertiser();
        final MidiServiceAdvertiser advertiser = memory;
        final first = await advertiser.register(
          name: 'Studio',
          type: MidiNetworkHostInfo.appleMidiServiceType,
          port: 5004,
        );
        final second = await advertiser.register(
          name: 'Studio',
          type: MidiNetworkHostInfo.networkMidi2ServiceType,
          port: 5506,
          txt: const {'UMPEndpointName': 'Studio'},
        );
        expect([first.name, second.name], equals(['Studio', 'Studio (2)']));
        expect(
          memory.services,
          equals({
            'Studio': '_apple-midi._udp:5004{}',
            'Studio (2)': '_midi2._udp:5506{UMPEndpointName: Studio}',
          }),
        );
      });
    });
  });
}
