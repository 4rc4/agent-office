/// Lighting of the office. Picked from the clock by default; the user can
/// pin one in the settings or cycle it from the status bar.
enum SceneTheme {
  /// 06:00-10:59: pale cool light, sun low on the left, lamps off.
  morning,

  /// 11:00-16:59: bright daylight, strong light shaft, lamps off.
  day,

  /// 17:00-20:59: sunset through the window, desk lamps on.
  evening,

  /// 21:00-05:59: moon and city lights, string lights on, screen glow.
  night;

  static SceneTheme forHour(int hour) {
    if (hour >= 6 && hour < 11) return SceneTheme.morning;
    if (hour >= 11 && hour < 17) return SceneTheme.day;
    if (hour >= 17 && hour < 21) return SceneTheme.evening;
    return SceneTheme.night;
  }

  static SceneTheme forTime(DateTime time) => forHour(time.hour);

  SceneTheme get next =>
      SceneTheme.values[(index + 1) % SceneTheme.values.length];

  /// Short Turkish label for the status bar.
  String get labelTr => switch (this) {
    SceneTheme.morning => 'Sabah',
    SceneTheme.day => 'Gündüz',
    SceneTheme.evening => 'Akşam',
    SceneTheme.night => 'Gece',
  };
}
