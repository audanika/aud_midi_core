// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// The diagnostic counters of a `MidiDiagnosticsBus` at one moment.
///
/// A counter sums the [MidiDiagnostic.count] of the diagnostics of its kind.
/// Diagnostics without a port count in [byKind] only.
final class MidiDiagnosticsSnapshot {
  /// Creates a snapshot from copies of [byKind] and [byPort].
  MidiDiagnosticsSnapshot({
    Map<MidiDiagnosticKind, int> byKind = const {},
    Map<MidiPortId, Map<MidiDiagnosticKind, int>> byPort = const {},
  }) : byKind = Map.unmodifiable(byKind),
       byPort = Map.unmodifiable({
         for (final MapEntry(:key, :value) in byPort.entries)
           key: Map<MidiDiagnosticKind, int>.unmodifiable(value),
       });

  // ...........................................................................
  /// Returns the counter of [kind], over all ports or for [port] only.
  int count(MidiDiagnosticKind kind, {MidiPortId? port}) =>
      (port == null ? byKind : byPort[port])?[kind] ?? 0;

  // ...........................................................................
  /// The counters per kind over all ports; cannot be modified.
  final Map<MidiDiagnosticKind, int> byKind;

  /// The counters per port and kind; cannot be modified.
  final Map<MidiPortId, Map<MidiDiagnosticKind, int>> byPort;

  /// The sum of all counters per kind.
  int get total => byKind.values.fold(0, (sum, count) => sum + count);

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiDiagnosticsSnapshot &&
          _sameCounts(other.byKind, byKind) &&
          other.byPort.length == byPort.length &&
          byPort.entries.every(
            (entry) => _sameCounts(other.byPort[entry.key], entry.value),
          );

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(byKind.entries.map(_hashEntry)),
    Object.hashAllUnordered(
      byPort.entries.map(
        (entry) => Object.hash(
          entry.key,
          Object.hashAllUnordered(entry.value.entries.map(_hashEntry)),
        ),
      ),
    ),
  );

  @override
  String toString() {
    final ports = byPort.entries.map((e) => '${e.key}: ${_format(e.value)}');
    return 'MidiDiagnosticsSnapshot(byKind: ${_format(byKind)}, '
        'byPort: {${ports.join(', ')}})';
  }

  // ...........................................................................
  /// Whether [a] holds the same counters as [b].
  static bool _sameCounts(
    Map<MidiDiagnosticKind, int>? a,
    Map<MidiDiagnosticKind, int> b,
  ) =>
      a != null &&
      a.length == b.length &&
      b.entries.every((entry) => a[entry.key] == entry.value);

  /// Returns the hash of one counter.
  static int _hashEntry(MapEntry<MidiDiagnosticKind, int> entry) =>
      Object.hash(entry.key, entry.value);

  /// Returns [counts] as `{kind: count, …}`.
  static String _format(Map<MidiDiagnosticKind, int> counts) {
    final entries = counts.entries.map((e) => '${e.key.name}: ${e.value}');
    return '{${entries.join(', ')}}';
  }
}
