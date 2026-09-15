// Générateur d'icône QuizRail (offline, reproductible) :
// `dart run tool/generate_icon.dart` → assets/icon/app_icon.png (1024,
// fond perdu), assets/icon/app_icon_fg.png (1024, avant-plan adaptatif
// transparent, zone sûre 66 %), assets/icon/app_splash.png (splash).
// Palette identité : nuit #14102E, violet #7C4DFF, rose #FF4D8D, jaune #FFC93C.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart';

const _deepTop = (0x1B, 0x14, 0x40);
const _deepMid = (0x14, 0x10, 0x2E);
const _deepBottom = (0x2A, 0x16, 0x56);
const _violet = (0x7C, 0x4D, 0xFF);
const _pink = (0xFF, 0x4D, 0x8D);
const _sun = (0xFF, 0xC9, 0x3C);
const _sunDeep = (0xE8, 0xA1, 0x00);
const _sunSoft = (0xFF, 0xE2, 0x9A);
const _cream = (0xFF, 0xF6, 0xE9);

ColorRgb8 _rgb((int, int, int) c) => ColorRgb8(c.$1, c.$2, c.$3);

ColorRgb8 _lerp((int, int, int) a, (int, int, int) b, double t) => ColorRgb8(
      (a.$1 + (b.$1 - a.$1) * t).round(),
      (a.$2 + (b.$2 - a.$2) * t).round(),
      (a.$3 + (b.$3 - a.$3) * t).round(),
    );

/// Dégradé diagonal nuit (même esprit que backgroundGradient de l'app).
void _paintNight(Image img) {
  final w = img.width, h = img.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final t = (x / w * 0.6 + y / h * 0.6).clamp(0.0, 1.0);
      final c = t < 0.55
          ? _lerp(_deepTop, _deepMid, t / 0.55)
          : _lerp(_deepMid, _deepBottom, (t - 0.55) / 0.45);
      img.setPixel(x, y, c);
    }
  }
}

/// Bandeau diagonal rose/violet derrière la pièce.
void _paintRibbons(Image img) {
  final w = img.width, h = img.height;
  drawLine(img,
      x1: -w ~/ 4,
      y1: (h * 0.78).round(),
      x2: (w * 0.75).round(),
      y2: (h * 0.18).round(),
      color: _rgb(_pink),
      thickness: (w * 0.055).round());
  drawLine(img,
      x1: (w * 0.25).round(),
      y1: (h * 1.05).round(),
      x2: (w * 1.1).round(),
      y2: (h * 0.42).round(),
      color: _rgb(_violet),
      thickness: (w * 0.04).round());
}

/// Étoile 5 branches (violet nuit) au centre de la pièce.
List<Point> _star(double cx, double cy, double outer, double inner) {
  final pts = <Point>[];
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outer : inner;
    // -90° : pointe vers le haut.
    final a = -math.pi / 2 + i * math.pi / 5;
    pts.add(Point(cx + r * math.cos(a), cy + r * math.sin(a)));
  }
  return pts;
}

void _paintCoin(Image img, double cx, double cy, double radius) {
  // Contour + corps doré + reflet.
  fillCircle(img, x: cx.round(), y: cy.round(), radius: radius.round(),
      color: _rgb(_sunDeep));
  fillCircle(img, x: cx.round(), y: cy.round(),
      radius: (radius * 0.9).round(), color: _rgb(_sun));
  fillCircle(img,
      x: (cx - radius * 0.28).round(),
      y: (cy - radius * 0.32).round(),
      radius: (radius * 0.34).round(),
      color: _rgb(_sunSoft));
  // Étoile identité.
  fillPolygon(img,
      vertices: _star(cx, cy, radius * 0.52, radius * 0.22),
      color: _rgb(_violet));
  // Étincelles crème.
  fillCircle(img, x: (cx + radius * 0.72).round(),
      y: (cy - radius * 0.62).round(),
      radius: (radius * 0.07).round(), color: _rgb(_cream));
  fillCircle(img, x: (cx - radius * 0.78).round(),
      y: (cy + radius * 0.5).round(),
      radius: (radius * 0.05).round(), color: _rgb(_cream));
}

Future<void> main() async {
  const size = 1024;
  final dir = Directory('assets/icon');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  // 1. Icône fond perdu (legacy).
  final full = Image(width: size, height: size);
  _paintNight(full);
  _paintRibbons(full);
  _paintCoin(full, size / 2, size / 2, size * 0.30);
  await File('assets/icon/app_icon.png').writeAsBytes(encodePng(full));

  // 2. Avant-plan adaptatif (fond transparent, zone sûre 66 %).
  final fg = Image(width: size, height: size);
  _paintCoin(fg, size / 2, size / 2, size * 0.24);
  await File('assets/icon/app_icon_fg.png').writeAsBytes(encodePng(fg));

  // 3. Splash (même pièce, centrée, pour flutter_native_splash).
  final splash = Image(width: size, height: size);
  _paintCoin(splash, size / 2, size / 2, size * 0.22);
  await File('assets/icon/app_splash.png').writeAsBytes(encodePng(splash));

  // ignore: avoid_print
  print('OK: assets/icon/app_icon.png, app_icon_fg.png, app_splash.png');
}
