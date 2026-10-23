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
