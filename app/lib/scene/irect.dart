import 'dart:ui';

/// Integer rectangle in sprite pixels (props and screens are laid out on
/// the pixel grid before scaling).
class IRect {
  const IRect(this.x, this.y, this.w, this.h);

  final int x;
  final int y;
  final int w;
  final int h;

  int get right => x + w;
  int get bottom => y + h;
  int get centerX => x + w ~/ 2;
  int get centerY => y + h ~/ 2;

  Rect get rect =>
      Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());

  /// True when the point lies inside (right and bottom edges excluded).
  bool contains(Offset p) =>
      p.dx >= x && p.dx < x + w && p.dy >= y && p.dy < y + h;

  @override
  bool operator ==(Object other) =>
      other is IRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'IRect($x, $y, $w, $h)';
}
