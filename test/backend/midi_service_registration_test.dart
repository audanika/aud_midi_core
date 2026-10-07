// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:test/test.dart';

/// A registration that remembers whether it was withdrawn.
final class _Registration implements MidiServiceRegistration {
  _Registration(this.name);

  bool isRegistered = true;

  @override
  final String name;

  @override
  Future<void> unregister() async => isRegistered = false;
}

void main() {
  group('MidiServiceRegistration', () {
    group('name', () {
      test('is the registered name', () {
        final MidiServiceRegistration registration = _Registration('Studio');
        expect(registration.name, 'Studio');
      });
    });

    group('unregister()', () {
      test('withdraws the registration', () async {
        final registration = _Registration('Studio');
        await (registration as MidiServiceRegistration).unregister();
        expect(registration.isRegistered, isFalse);
      });
    });
  });
}
