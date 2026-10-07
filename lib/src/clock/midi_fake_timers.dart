// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_fake_clock.dart';

// #############################################################################
/// Timers that fire when a [MidiFakeClock] moves, for deterministic tests
/// of code that waits with timers.
///
/// Pass [create] where a `MidiTimerFactory` is expected and move the time
/// with [advance] instead of waiting:
///
/// ```dart
/// final clock = MidiFakeClock();
/// final timers = MidiFakeTimers(clock: clock);
/// final engine = MidiEngine(
///   backend: backend,
///   clock: clock,
///   timerFactory: timers.create,
/// );
/// timers.advance(const Duration(milliseconds: 10));
/// ```
final class MidiFakeTimers {
  /// Creates timers driven by [clock].
  MidiFakeTimers({required this.clock});

  // ...........................................................................
  /// Creates a timer that calls [callback] once [duration] has passed on
  /// [clock]; a negative duration counts as zero.
  Timer create(Duration duration, void Function() callback) {
    final timer = _MidiFakeTimer(
      due: clock.now() + (duration.isNegative ? Duration.zero : duration),
      callback: callback,
    );
    _timers.add(timer);
    return timer;
  }

  // ...........................................................................
  /// Moves [clock] forward by [duration] and fires every timer that comes
  /// due on the way, ordered by due time and then by creation.
  ///
  /// The clock shows the due time of each timer while it fires, so timers
  /// created by a callback fire within the same call when they come due
  /// before its end.
  void advance(Duration duration) {
    assert(!duration.isNegative);
    final end = clock.now() + duration;
    for (var timer = _next(end); timer != null; timer = _next(end)) {
      if (timer.due.isAfter(clock.now())) clock.jumpTo(timer.due);
      _timers.remove(timer);
      timer.fire();
    }
    clock.jumpTo(end);
  }

  /// Fires every timer that is due now without moving the clock.
  void flush() => advance(Duration.zero);

  // ...........................................................................
  /// The clock that drives the timers.
  final MidiFakeClock clock;

  /// The number of timers that have neither fired nor been cancelled.
  int get pending => _timers.where((timer) => timer.isActive).length;

  // ...........................................................................
  /// The timers in the order of their creation, which breaks ties of due
  /// times.
  final _timers = <_MidiFakeTimer>[];

  /// Returns the active timer due first, not later than [end], and drops
  /// cancelled timers on the way.
  _MidiFakeTimer? _next(MidiTime end) {
    _timers.removeWhere((timer) => !timer.isActive);
    _MidiFakeTimer? next;
    for (final timer in _timers) {
      if (timer.due.isAfter(end)) continue;
      if (next == null || timer.due.isBefore(next.due)) next = timer;
    }
    return next;
  }
}

// #############################################################################
/// A timer of [MidiFakeTimers].
final class _MidiFakeTimer implements Timer {
  _MidiFakeTimer({required this.due, required this.callback});

  // ...........................................................................
  @override
  void cancel() => _isActive = false;

  /// Calls the callback unless the timer was cancelled.
  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _tick = 1;
    callback();
  }

  // ...........................................................................
  /// The time the timer fires at.
  final MidiTime due;

  /// The function the timer calls.
  final void Function() callback;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  // ...........................................................................
  bool _isActive = true;
  int _tick = 0;
}
