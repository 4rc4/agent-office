/// Lighting of the office. Follows the computer's clock by default; the
/// user can pin one from the status bar to preview it.
enum SceneTheme {
  /// 06:00-19:59: daylight through the window, lamps off.
  day,

  /// 20:00-05:59: moon and city lights, string lights and lamps on.
  night;

  static SceneTheme forHour(int hour) =>
      hour >= 6 && hour < 20 ? SceneTheme.day : SceneTheme.night;

  static SceneTheme forTime(DateTime time) => forHour(time.hour);

  SceneTheme get next =>
      this == SceneTheme.day ? SceneTheme.night : SceneTheme.day;

  /// Short Turkish label for the status bar.
  String get labelTr => this == SceneTheme.day ? 'Gündüz' : 'Gece';
}
