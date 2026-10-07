// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// The errors the aud_midi family throws.
///
/// Streams never carry these errors; a lost port is a port event and a
/// data loss a diagnostic. Every exception can be created as a constant;
/// its [message] is built when it is read.
sealed class MidiException implements Exception {
  /// Creates an exception.
  const MidiException();

  // ...........................................................................
  /// What went wrong.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

// #############################################################################
/// The platform, backend or port does not support the requested feature.
final class MidiUnsupported extends MidiException {
  /// Creates the exception for a missing [feature].
  const MidiUnsupported(this.feature);

  // ...........................................................................
  /// The feature that is missing.
  final String feature;

  @override
  String get message => '$feature is not supported';
}

// #############################################################################
/// The operating system or the user denied a permission.
final class MidiPermissionDenied extends MidiException {
  /// Creates the exception for the denied [permission].
  const MidiPermissionDenied(this.permission);

  // ...........................................................................
  /// The permission that was denied.
  final MidiPermission permission;

  @override
  String get message => 'Permission denied: $permission';
}

// #############################################################################
/// The port disappeared or never existed.
final class MidiPortGone extends MidiException {
  /// Creates the exception for the missing [port].
  const MidiPortGone(this.port);

  // ...........................................................................
  /// The id of the port.
  final MidiPortId port;

  @override
  String get message => 'Port is gone: $port';
}

// #############################################################################
/// A call into the operating system failed.
final class MidiNativeError extends MidiException {
  /// Creates the exception for the failed call [api] with the native error
  /// [code].
  const MidiNativeError({required this.api, required this.code});

  // ...........................................................................
  /// The name of the failed call, e.g. `MIDIClientCreateWithBlock`.
  final String api;

  /// The native error code.
  final int code;

  @override
  String get message => '$api failed with $code';
}
