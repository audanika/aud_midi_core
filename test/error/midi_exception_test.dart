// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  // Creates the exceptions at runtime, so that their constructors run.
  const unsupported = MidiUnsupported.new;
  const permissionDenied = MidiPermissionDenied.new;
  const portGone = MidiPortGone.new;
  const nativeError = MidiNativeError.new;

  // Returns the name of the kind of [exception], exhaustively.
  String kindOf(MidiException exception) => switch (exception) {
    MidiUnsupported() => 'unsupported',
    MidiPermissionDenied() => 'permission',
    MidiPortGone() => 'gone',
    MidiNativeError() => 'native',
  };

  group('MidiException', () {
    test('has exactly four kinds, all of them exceptions', () {
      final exceptions = <MidiException>[
        unsupported('Virtual ports'),
        permissionDenied(MidiPermission.bluetooth),
        portGone(const MidiPortId('fake:in')),
        nativeError(api: 'MIDIClientCreate', code: -10830),
      ];
      expect(
        exceptions.map(kindOf),
        equals(['unsupported', 'permission', 'gone', 'native']),
      );
      expect(exceptions, everyElement(isA<Exception>()));
    });
  });

  group('const construction', () {
    test('works for every kind', () {
      const exceptions = <MidiException>[
        MidiUnsupported('Virtual ports'),
        MidiPermissionDenied(MidiPermission.bluetooth),
        MidiPortGone(MidiPortId('fake:in')),
        MidiNativeError(api: 'MIDISend', code: 7),
      ];
      expect(
        [for (final exception in exceptions) exception.toString()],
        equals([
          'MidiUnsupported: Virtual ports is not supported',
          'MidiPermissionDenied: Permission denied: MidiPermission.bluetooth',
          'MidiPortGone: Port is gone: fake:in',
          'MidiNativeError: MIDISend failed with 7',
        ]),
      );
      expect(
        identical(
          const MidiPermissionDenied(MidiPermission.bluetooth),
          const MidiPermissionDenied(MidiPermission.bluetooth),
        ),
        isTrue,
      );
    });
  });

  group('MidiUnsupported(feature)', () {
    test('names the missing feature', () {
      final exception = unsupported('Virtual ports');
      expect(exception.feature, 'Virtual ports');
      expect(exception.message, 'Virtual ports is not supported');
      expect(
        exception.toString(),
        'MidiUnsupported: Virtual ports is not supported',
      );
    });
  });

  group('MidiPermissionDenied(permission)', () {
    test('names the denied permission', () {
      final exception = permissionDenied(MidiPermission.localNetwork);
      expect(exception.permission, MidiPermission.localNetwork);
      expect(
        exception.message,
        'Permission denied: MidiPermission.localNetwork',
      );
    });
  });

  group('MidiPortGone(port)', () {
    test('names the port', () {
      final exception = portGone(const MidiPortId('fake:in'));
      expect(exception.port, const MidiPortId('fake:in'));
      expect(exception.message, 'Port is gone: fake:in');
    });
  });

  group('MidiNativeError({api, code})', () {
    test('names the call and the code', () {
      final exception = nativeError(api: 'MIDISend', code: 7);
      expect([exception.api, exception.code], equals(['MIDISend', 7]));
      expect(exception.message, 'MIDISend failed with 7');
    });
  });
}
