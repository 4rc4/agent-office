import 'package:office_core/office_core.dart';

/// What a tap on the scene means to the widgets. [coffee] and [cabinet]
/// both open the event log; the scene keeps them apart for its own hit test.
enum SceneTapKind { seat, whiteboard, mailbox, coffee, cabinet, unknown }

/// A classified scene tap. [seat] is set only for [SceneTapKind.seat].
class SceneTap {
  const SceneTap(this.kind, {this.seat});

  final SceneTapKind kind;
  final Seat? seat;

  @override
  String toString() =>
      seat == null ? 'SceneTap.${kind.name}' : 'SceneTap.seat(${seat!.name})';
}

/// Turns the scene's opaque tap target into a [SceneTap] without importing
/// the scene package.
///
/// The scene reports taps as `SceneTarget` values (lib/scene/scene_layout.dart)
/// whose `toString` is `SceneTarget.seat(<name>)`, `SceneTarget.whiteboard`,
/// `SceneTarget.mailbox`, `SceneTarget.coffee` or `SceneTarget.cabinet` and
/// whose runtime types are `SeatTarget`, `WhiteboardTarget`, ... The router
/// reads both, so the widgets stay decoupled from the scene and tests can hand
/// in any object with a matching `toString`. A bare [Seat] is accepted too.
///
/// Integrator: if a new target is added to the scene, give it a `toString`
/// that contains its lower-case name (e.g. `SceneTarget.plant`) and add the
/// matching word here.
abstract final class SceneTapRouter {
  /// Classifies [target]; anything unrecognised becomes [SceneTapKind.unknown].
  static SceneTap classify(Object target) {
    if (target is Seat) return SceneTap(SceneTapKind.seat, seat: target);
    if (target is SceneTap) return target;
    final text = '${target.runtimeType} $target'.toLowerCase();
    final seat = _seatIn(text);
    if (seat != null) return SceneTap(SceneTapKind.seat, seat: seat);
    for (final kind in const [
      SceneTapKind.whiteboard,
      SceneTapKind.mailbox,
      SceneTapKind.coffee,
      SceneTapKind.cabinet,
    ]) {
      if (text.contains(kind.name)) return SceneTap(kind);
    }
    return const SceneTap(SceneTapKind.unknown);
  }

  static Seat? _seatIn(String text) {
    if (!text.contains('seat')) return null;
    final match = RegExp(r'seat\((\w+)\)').firstMatch(text);
    if (match != null) {
      for (final seat in Seat.values) {
        if (seat.name.toLowerCase() == match.group(1)) return seat;
      }
    }
    for (final seat in Seat.values) {
      if (text.contains(seat.name.toLowerCase())) return seat;
    }
    return null;
  }
}
