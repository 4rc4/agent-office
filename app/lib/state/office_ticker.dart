import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';

import 'office_model.dart';
import 'seat_state.dart';

/// The animation clock of the scene: a periodic [tick] that runs only while
/// [OfficeSnapshot.anyAnimated] is true and the ticker is not paused.
///
/// Zero timers while the office is idle: the ticker starts on the model's
/// notification that made a seat animated and stops on the notification (or,
/// at the latest, on the next period) that parked the last one.
class OfficeTicker {
  OfficeTicker(this.model, {this.period = const Duration(milliseconds: 100)}) {
    model.addListener(_sync);
    _sync();
  }

  final OfficeModel model;

  /// Interval between ticks while animating.
  final Duration period;

  /// Increments once per [period] while running; sprites key frames off it.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  Timer? _timer;
  bool _paused = false;
  bool _disposed = false;

  /// Whether a periodic timer is live right now.
  bool get isRunning => _timer != null;

  /// Whether [pause] is in effect.
  bool get isPaused => _paused;

  /// Stops ticking until [resume]; for a hidden or minimised window.
  void pause() {
    if (_paused) return;
    _paused = true;
    _stop();
  }

  /// Lifts [pause]; ticking restarts at once when a seat is animated.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _sync();
  }

  /// Pauses while the app is hidden, paused or detached; resumes otherwise.
  /// An inactive (unfocused) window keeps animating.
  void onLifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        pause();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        resume();
    }
  }

  /// Releases the timer and the model listener.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    model.removeListener(_sync);
    _stop();
    tick.dispose();
  }

  void _sync() {
    if (_disposed) return;
    final wanted = !_paused && model.snapshot.anyAnimated;
    if (wanted) {
      _timer ??= Timer.periodic(period, _onTick);
    } else {
      _stop();
    }
  }

  void _onTick(Timer _) {
    if (_paused || !model.snapshot.anyAnimated) {
      _stop();
      return;
    }
    tick.value++;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}
