import 'pixel.dart';
import 'scene_theme.dart';

/// What the window shows.
enum SkyKind {
  /// Blue sky, a high sun, a few clouds and green hills.
  daylight,

  /// Stars, a moon and a city skyline with lit windows.
  night,
}

/// A colour transform for one group of materials: every tone is multiplied
/// by [light] (a lamp or sky colour; white leaves it alone) and then mixed
/// toward [tint] by [mix]. Results are cached per colour, so the whole
/// scene is tinted at draw time without recolouring a single sprite.
class Tint {
  Tint({this.light = 0xFFFFFFFF, this.tint = 0xFF000000, this.mix = 0});

  /// Leaves every colour as it is.
  static final Tint identity = Tint();

  final int light;
  final int tint;
  final double mix;
  final Map<int, int> _cache = {};

  bool get isIdentity => light == 0xFFFFFFFF && mix == 0;

  int apply(int c) {
    if (isIdentity) return c;
    return _cache.putIfAbsent(c, () {
      final lr = ((light >> 16) & 0xFF) / 255.0;
      final lg = ((light >> 8) & 0xFF) / 255.0;
      final lb = (light & 0xFF) / 255.0;
      final r = ((c >> 16) & 0xFF) * lr;
      final g = ((c >> 8) & 0xFF) * lg;
      final b = (c & 0xFF) * lb;
      final lit = 0xFF000000 | (r.round() << 16) | (g.round() << 8) | b.round();
      return mix == 0 ? lit : PixelBuffer.mix(lit, tint, mix);
    });
  }
}

/// Everything that differs between the day and the night office. The room
/// itself (walls, floor, furniture, props) is drawn once in the daylight
/// palette and each lighting re-tints it at draw time.
class SceneLighting {
  SceneLighting({
    required this.theme,
    required this.background,
    required this.sky,
    required this.room,
    required this.lit,
    required this.windowGlow,
    required this.windowGlowStrength,
    required this.shaft,
    required this.lampsOn,
    required this.lampGlow,
    required this.lampPoolStrength,
    required this.lampHaloRadius,
    required this.lampHaloStrength,
    required this.stringLightsOn,
    required this.monitorGlow,
    required this.monitorHalo,
    required this.curtainLight,
    required this.curtainBase,
    required this.curtainDark,
    required this.curtainOutline,
  });

  final SceneTheme theme;

  /// Letterbox colour around the scene.
  final int background;
  final SkyKind sky;

  /// Tint of walls, floor, furniture and props: the ambient light.
  final Tint room;

  /// Tint of characters, paper and the whiteboard: things the eye should
  /// still read in their own colours, so only a light ambient tint.
  final Tint lit;

  /// Glow on the wall around the window (sun or moon) and its strength.
  final int windowGlow;
  final double windowGlowStrength;

  /// Transform applied to floor pixels inside the window's light shaft.
  final int Function(int) shaft;

  /// Desk lamps lit, with [lampGlow] pools of [lampPoolStrength] on the desk
  /// and a halo of [lampHaloRadius] pixels around the shade.
  final bool lampsOn;
  final int lampGlow;
  final double lampPoolStrength;
  final int lampHaloRadius;
  final double lampHaloStrength;

  /// Bulbs of the string lights along the back wall glow.
  final bool stringLightsOn;

  /// Strength 0..1 of the light a screen throws on the desk, and whether it
  /// also throws a halo on the wall behind the monitor.
  final double monitorGlow;
  final bool monitorHalo;

  final int curtainLight;
  final int curtainBase;
  final int curtainDark;
  final int curtainOutline;

  /// Bright daylight: blue sky, a strong warm sun shaft, lamps off.
  static final SceneLighting day = SceneLighting(
    theme: SceneTheme.day,
    background: 0xFF17121A,
    sky: SkyKind.daylight,
    room: Tint.identity,
    lit: Tint.identity,
    windowGlow: 0xFFFFF4D6,
    windowGlowStrength: 0.3,
    shaft: _sunlit,
    lampsOn: false,
    lampGlow: 0xFFFFEBB0,
    lampPoolStrength: 0,
    lampHaloRadius: 0,
    lampHaloStrength: 0,
    stringLightsOn: false,
    monitorGlow: 0.3,
    monitorHalo: false,
    curtainLight: 0xFFCD6A50,
    curtainBase: 0xFFAA503D,
    curtainDark: 0xFF823C2E,
    curtainOutline: 0xFF5A2921,
  );

  /// Night: moon and city lights in the window, string lights and lamps on,
  /// screens glowing, walls and floor in blue shade.
  static final SceneLighting night = SceneLighting(
    theme: SceneTheme.night,
    background: 0xFF0A0C16,
    sky: SkyKind.night,
    room: Tint(light: 0xFF6E7EC4, tint: 0xFF1B2140, mix: 0.1),
    lit: Tint(light: 0xFFC4CAE8, tint: 0xFF1B2140, mix: 0.04),
    windowGlow: 0xFFB9C9FF,
    windowGlowStrength: 0.2,
    shaft: _moonlit,
    lampsOn: true,
    lampGlow: 0xFFFFD98A,
    lampPoolStrength: 0.55,
    lampHaloRadius: 18,
    lampHaloStrength: 0.4,
    stringLightsOn: true,
    monitorGlow: 0.6,
    monitorHalo: true,
    curtainLight: 0xFFB8707E,
    curtainBase: 0xFF955466,
    curtainDark: 0xFF703B4C,
    curtainOutline: 0xFF48232F,
  );

  static SceneLighting of(SceneTheme theme) => switch (theme) {
    SceneTheme.day => day,
    SceneTheme.night => night,
  };

  static int _sunlit(int c) =>
      PixelBuffer.mix(PixelBuffer.lightOf(c), 0xFFFFF0C0, 0.18);

  static int _moonlit(int c) => PixelBuffer.mix(c, 0xFFAFC4FF, 0.14);
}
