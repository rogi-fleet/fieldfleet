// Generates FieldFleet launcher/logo PNGs.
//
// Run: `dart run tool/generate_brand_logos.dart`
//
// The design is the FieldFleet brand badge scaled up to a full app icon: a
// solid orange field with a white "FF" monogram (the product initials). Every
// output here overwrites one of the app/web icon files used by Flutter and
// the PWA shell. Colors are kept in sync with `lib/widgets/logo_widget.dart`.

import 'dart:io';

import 'package:image/image.dart' as img;

const _outputMasterSize = 1024;
const _canvasScale = 2;
const _canvasSize = _outputMasterSize * _canvasScale;
const _orange = (r: 0xF4, g: 0x7A, b: 0x2A);

img.ColorRgba8 _color(
  int r,
  int g,
  int b, [
  int a = 255,
]) =>
    img.ColorRgba8(r, g, b, a);

int _s(num value) => (value * _canvasScale).round();

void _fillRect(
  img.Image image, {
  required num x1,
  required num y1,
  required num x2,
  required num y2,
  required img.Color color,
  num radius = 0,
}) {
  img.fillRect(
    image,
    x1: _s(x1),
    y1: _s(y1),
    x2: _s(x2),
    y2: _s(y2),
    color: color,
    radius: radius * _canvasScale,
  );
}

img.Image _renderMaster() {
  final image = img.Image(width: _canvasSize, height: _canvasSize);

  final orange = _color(_orange.r, _orange.g, _orange.b);
  final white = _color(255, 255, 255);

  // Solid orange field — the app icon is the FieldFleet badge scaled up to
  // fill the canvas. Launcher masks round the corners.
  img.fill(image, color: orange);

  // White "FF" lettering, built from filled geometry so it stays crisp when
  // resized down to favicon dimensions. Coordinates use the 1024 master grid;
  // the canvas is rendered at 2× and downsampled, which anti-aliases edges.

  // First "F" — an upright bar with a full top arm and a shorter middle arm.
  _fillRect(image, x1: 190, y1: 300, x2: 294, y2: 720, color: white);
  _fillRect(image, x1: 190, y1: 300, x2: 474, y2: 404, color: white);
  _fillRect(image, x1: 190, y1: 486, x2: 418, y2: 578, color: white);

  // Second "F".
  _fillRect(image, x1: 550, y1: 300, x2: 654, y2: 720, color: white);
  _fillRect(image, x1: 550, y1: 300, x2: 834, y2: 404, color: white);
  _fillRect(image, x1: 550, y1: 486, x2: 778, y2: 578, color: white);

  return image;
}

img.Image _render(int size, img.Image master) {
  return img.copyResize(
    master,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
}

void _writePng(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('  wrote ${image.width}×${image.height}  $path');
}

void main() {
  final targets = <String, int>{
    // App icon master (in-app watermark + icon source of truth).
    'assets/images/logo_icon.png': 1024,
    'site/assets/logo.png': 1024,

    // Web favicon + PWA icons.
    'web/favicon.png': 32,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,

    // Android launcher (mipmap buckets).
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,

    // iOS AppIcon set.
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
        167,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
        1024,
  };

  final base = _renderMaster();
  for (final entry in targets.entries) {
    _writePng(entry.key, _render(entry.value, base));
  }
}
