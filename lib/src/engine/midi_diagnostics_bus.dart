// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_diagnostics_snapshot.dart';

// #############################################################################
/// Collects the diagnostics of an engine: it counts them per kind and per
/// port and publishes them on a broadcast stream.
///
/// Diagnostics reported while nobody listens are counted but not kept.
final class MidiDiagnosticsBus {
  /// Creates an empty bus.
  MidiDiagnosticsBus();

  // ...........................................................................
  /// Counts [diagnostic] and publishes it; does nothing after [close].
  void report(MidiDiagnostic diagnostic) {
    if (_controller.isClosed) return;
    final kind = diagnostic.kind;
    _byKind[kind] = (_byKind[kind] ?? 0) + diagnostic.count;
    final port = diagnostic.port;
    if (port != null) {
      final counters = _byPort.putIfAbsent(port, () => {});
      counters[kind] = (counters[kind] ?? 0) + diagnostic.count;
    }
    _controller.add(diagnostic);
  }

  /// Returns the current counters.
  MidiDiagnosticsSnapshot snapshot() =>
      MidiDiagnosticsSnapshot(byKind: _byKind, byPort: _byPort);

  /// Sets all counters back to zero.
  void resetCounters() {
    _byKind.clear();
    _byPort.clear();
  }

  /// Completes [diagnostics]; later reports are ignored.
  Future<void> close() => _controller.close();

  // ...........................................................................
  /// The diagnostics as they are reported.
  Stream<MidiDiagnostic> get diagnostics => _controller.stream;

  /// Whether the bus was closed.
  bool get isClosed => _controller.isClosed;

  // ...........................................................................
  final _controller = StreamController<MidiDiagnostic>.broadcast();
  final _byKind = <MidiDiagnosticKind, int>{};
  final _byPort = <MidiPortId, Map<MidiDiagnosticKind, int>>{};
}
