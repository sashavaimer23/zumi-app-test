import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Маленькая копия фото для карточек (JPEG ~800 px).
/// Карточки в ленте грузят её вместо оригинала — это в разы меньше трафика.
/// null — если не получилось; тогда используется оригинал.
Future<Uint8List?> makeThumb(Uint8List bytes, {int width = 800, int quality = 72}) async {
  try {
    return await compute(_thumb, (bytes, width, quality, false));
  } catch (_) {
    return null;
  }
}

/// Квадратное фото профиля 400×400
Future<Uint8List?> makeAvatar(Uint8List bytes) async {
  try {
    return await compute(_thumb, (bytes, 400, 82, true));
  } catch (_) {
    return null;
  }
}

Uint8List? _thumb((Uint8List, int, int, bool) a) {
  final (bytes, width, quality, square) = a;
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  final oriented = img.bakeOrientation(src);
  final img.Image out;
  if (square) {
    out = img.copyResizeCropSquare(oriented, size: width);
  } else if (oriented.width > width) {
    out = img.copyResize(oriented, width: width, interpolation: img.Interpolation.average);
  } else {
    out = oriented;
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

// ----------------------------------------------------------------------
// Картинка для продвижения: формат 3:2, не меньше 1200×800, сжатие до ~1500×1000
// ----------------------------------------------------------------------
const kBannerRatio = 1.5;
const kBannerMinW = 1200;
const kBannerMinH = 800;
const kBannerMaxBytes = 15 * 1024 * 1024;

/// Обрезать по долям (0..1) от ширины/высоты и сжать в JPEG 1500×1000
Future<Uint8List?> cropBanner(Uint8List bytes, double left, double top, double width, double height) async {
  try {
    return await compute(_cropBanner, (bytes, left, top, width, height));
  } catch (_) {
    return null;
  }
}

Uint8List? _cropBanner((Uint8List, double, double, double, double) a) {
  final (bytes, l, t, w, h) = a;
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  final o = img.bakeOrientation(src);
  final x = (l * o.width).round().clamp(0, o.width - 1);
  final y = (t * o.height).round().clamp(0, o.height - 1);
  final cw = (w * o.width).round().clamp(1, o.width - x);
  final ch = (h * o.height).round().clamp(1, o.height - y);
  final cropped = img.copyCrop(o, x: x, y: y, width: cw, height: ch);
  final out = cropped.width > 1500
      ? img.copyResize(cropped, width: 1500, height: 1000, interpolation: img.Interpolation.average)
      : cropped;
  return Uint8List.fromList(img.encodeJpg(out, quality: 82));
}
