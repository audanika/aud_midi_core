// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:collection';

// #############################################################################
/// A single-subscription stream fed through a bounded queue.
///
/// Values wait in the queue until the listener takes them; they are
/// delivered in a microtask after [addAll], never synchronously, and only
/// while the subscription is not paused. When the queue holds [capacity]
/// values, newer values are dropped (drop newest) and [onOverflow] receives
/// their number once per [addAll] call. After the listener cancels, values
/// are discarded without being counted.
final class MidiBoundedStream<T> {
  /// Creates a stream that keeps at most [capacity] undelivered values.
  MidiBoundedStream({required this.capacity, required this.onOverflow})
    : assert(capacity > 0) {
    _controller = StreamController<T>(
      sync: true,
      onListen: _schedule,
      onResume: _schedule,
      onCancel: _cancel,
    );
  }

  // ...........................................................................
  /// Queues [values] for delivery and drops those that do not fit.
  void addAll(Iterable<T> values) {
    if (_isCancelled || _isEnding || _isClosed) return;
    var dropped = 0;
    for (final value in values) {
      if (_queue.length < capacity) {
        _queue.add(value);
      } else {
        dropped++;
      }
    }
    if (dropped > 0) onOverflow(dropped);
    _schedule();
  }

  /// Completes the stream once the queued values are delivered.
  void end() {
    if (_isEnding || _isClosed) return;
    _isEnding = true;
    _schedule();
  }

  /// Completes the stream now and discards the queued values.
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _queue.clear();
    _schedule();
  }

  // ...........................................................................
  /// The largest number of undelivered values.
  final int capacity;

  /// Receives the number of values one [addAll] call dropped.
  final void Function(int dropped) onOverflow;

  /// The stream of the values.
  Stream<T> get stream => _controller.stream;

  /// The number of values waiting for delivery.
  int get queued => _queue.length;

  /// Whether the stream was ended or closed.
  bool get isDone => _isEnding || _isClosed;

  // ...........................................................................
  late final StreamController<T> _controller;
  final _queue = ListQueue<T>();
  bool _isScheduled = false;
  bool _isCancelled = false;
  bool _isEnding = false;
  bool _isClosed = false;
  bool _isFinished = false;

  /// Schedules a delivery round unless one is pending.
  void _schedule() {
    if (_isScheduled || _isFinished) return;
    _isScheduled = true;
    scheduleMicrotask(_deliver);
  }

  /// Delivers queued values while the listener takes them and completes
  /// the stream when it is due.
  void _deliver() {
    _isScheduled = false;
    while (!_isClosed &&
        _queue.isNotEmpty &&
        _controller.hasListener &&
        !_controller.isPaused) {
      _controller.add(_queue.removeFirst());
    }
    if (_isClosed || _isEnding && _queue.isEmpty) _finish();
  }

  /// Closes the controller once.
  void _finish() {
    if (_isFinished) return;
    _isFinished = true;
    unawaited(_controller.close());
  }

  /// Discards everything after the listener cancelled.
  void _cancel() {
    _isCancelled = true;
    _queue.clear();
  }
}
