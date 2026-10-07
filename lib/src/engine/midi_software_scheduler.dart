// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../clock/midi_clock.dart';
import '../clock/midi_timer_factory.dart';

// #############################################################################
/// Holds packets until they are due and hands each one to [dispatch].
///
/// A packet is due at its time minus the lead it was scheduled with: ports
/// that cannot send at a later time use no lead, ports that schedule in
/// the operating system may get their packets a lead before their time.
///
/// Every port has its own queue ordered by dispatch time; packets with the
/// same dispatch time keep the order they were scheduled in, also across
/// ports. One timer waits for the earliest packet of all ports. Timers are
/// rounded up to whole milliseconds, so packets never leave early; a packet
/// that leaves more than [lateThreshold] after its time — the time itself,
/// not the dispatch time — is reported as
/// [MidiDiagnosticKind.schedulerLate], one diagnostic per port and round.
final class MidiSoftwareScheduler {
  /// Creates a scheduler.
  ///
  /// - [clock] the package clock the due times refer to.
  /// - [dispatch] receives each packet when it is due; it must not throw.
  /// - [timerFactory] creates the timer; tests pass fake timers.
  /// - [lateThreshold] how late a packet may leave without a diagnostic.
  /// - [onDiagnostic] receives the diagnostics about late packets.
  MidiSoftwareScheduler({
    required this.clock,
    required this.dispatch,
    this.timerFactory = Timer.new,
    this.lateThreshold = const Duration(milliseconds: 5),
    this.onDiagnostic,
  });

  // ...........................................................................
  /// Queues [packet] for [port] until [lead] before its [MidiPacket.time].
  ///
  /// Throws a [StateError] after [dispose].
  void schedule(
    MidiPortId port,
    MidiPacket packet, {
    Duration lead = Duration.zero,
  }) {
    if (_isDisposed) throw StateError('The scheduler is disposed');
    final queue = _queues.putIfAbsent(port, () => []);
    final at = packet.time - lead;
    var index = queue.length;
    while (index > 0 && queue[index - 1].at.isAfter(at)) {
      index--;
    }
    final entry = (port: port, packet: packet, at: at, sequence: _sequence++);
    queue.insert(index, entry);
    _arm();
  }

  /// Dispatches the packets that are due now: those of [port] only, or of
  /// all ports when [port] is null.
  ///
  /// Call it before sending a packet of [port] immediately, so that due
  /// packets keep their place in front of it.
  void dispatchDue({MidiPortId? port}) {
    final now = clock.now();
    final due = [
      for (final id in port == null ? [..._queues.keys] : [port])
        ..._takeDue(id, now),
    ]..sort(_compare);
    _reportLate(due, now);
    for (final entry in due) {
      dispatch(entry.port, entry.packet);
    }
    _arm();
  }

  // ...........................................................................
  /// Discards the queued packets of [port] and returns their number.
  int cancel(MidiPortId port) {
    final count = _queues.remove(port)?.length ?? 0;
    _arm();
    return count;
  }

  /// Discards the queued packets of all ports and returns their number.
  int cancelAll() {
    final count = pending();
    _queues.clear();
    _arm();
    return count;
  }

  /// Discards all queued packets and stops the timer for good.
  void dispose() {
    _isDisposed = true;
    cancelAll();
  }

  /// Returns the number of queued packets of [port], or of all ports when
  /// [port] is null.
  int pending({MidiPortId? port}) => port == null
      ? _queues.values.fold(0, (sum, queue) => sum + queue.length)
      : _queues[port]?.length ?? 0;

  // ...........................................................................
  /// The package clock the due times refer to.
  final MidiClock clock;

  /// Receives each packet with its port when it is due.
  final void Function(MidiPortId port, MidiPacket packet) dispatch;

  /// Creates the timer.
  final MidiTimerFactory timerFactory;

  /// How late a packet may leave without a diagnostic.
  final Duration lateThreshold;

  /// Receives the diagnostics about late packets.
  final void Function(MidiDiagnostic diagnostic)? onDiagnostic;

  /// The dispatch time of the earliest queued packet, or null when no
  /// packet waits.
  MidiTime? get nextDue {
    MidiTime? next;
    for (final queue in _queues.values) {
      final time = queue.first.at;
      if (next == null || time.isBefore(next)) next = time;
    }
    return next;
  }

  /// Whether [dispose] was called.
  bool get isDisposed => _isDisposed;

  // ...........................................................................
  final _queues = <MidiPortId, List<_Entry>>{};
  Timer? _timer;
  MidiTime? _timerDue;
  bool _isDisposed = false;
  int _sequence = 0;

  /// Removes and returns the entries of [port] due at [now].
  List<_Entry> _takeDue(MidiPortId port, MidiTime now) {
    final queue = _queues[port];
    if (queue == null) return const [];
    var count = 0;
    while (count < queue.length && !queue[count].at.isAfter(now)) {
      count++;
    }
    final due = queue.sublist(0, count);
    queue.removeRange(0, count);
    if (queue.isEmpty) _queues.remove(port);
    return due;
  }

  /// Reports the packets of [due] that leave late at [now], per port.
  void _reportLate(List<_Entry> due, MidiTime now) {
    final late = <MidiPortId, ({int count, Duration max})>{};
    for (final (:port, :packet, at: _, sequence: _) in due) {
      final lateness = now.difference(packet.time);
      if (lateness <= lateThreshold) continue;
      final previous = late[port];
      late[port] = (
        count: (previous?.count ?? 0) + 1,
        max: previous == null || lateness > previous.max
            ? lateness
            : previous.max,
      );
    }
    for (final MapEntry(key: port, value: (:count, :max)) in late.entries) {
      onDiagnostic?.call(
        MidiDiagnostic(
          kind: MidiDiagnosticKind.schedulerLate,
          port: port,
          count: count,
          cause:
              '$count scheduled packet(s) left up to '
              '${(max.inMicroseconds / 1000).toStringAsFixed(1)} ms late',
          time: now,
        ),
      );
    }
  }

  /// Points the timer at the earliest queued packet.
  void _arm() {
    final next = _isDisposed ? null : nextDue;
    if (next == _timerDue) return;
    _timer?.cancel();
    _timer = null;
    _timerDue = next;
    if (next == null) return;
    final wait = next.difference(clock.now()).inMicroseconds;
    final milliseconds = wait <= 0 ? 0 : (wait + 999) ~/ 1000;
    _timer = timerFactory(Duration(milliseconds: milliseconds), _onTimer);
  }

  /// Dispatches the due packets when the timer fires.
  void _onTimer() {
    _timer = null;
    _timerDue = null;
    dispatchDue();
  }

  /// Orders [a] and [b] by dispatch time, then by the order they were
  /// scheduled in.
  static int _compare(_Entry a, _Entry b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.sequence.compareTo(b.sequence);
  }
}

// #############################################################################
/// A queued [packet] of [port], dispatched [at]; [sequence] counts the
/// scheduled packets and orders packets with equal dispatch times.
typedef _Entry = ({
  MidiPortId port,
  MidiPacket packet,
  MidiTime at,
  int sequence,
});
