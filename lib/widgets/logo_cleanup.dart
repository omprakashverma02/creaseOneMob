import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Remove a flat logo background (web logoBackgroundRemoval.ts): flood-fill from the
/// image border over pixels close to the dominant corner colour and make them transparent.
Future<File> removeLogoBackground(File input, {int tolerance = 38}) async {
  final bytes = await input.readAsBytes();
  final out = await compute(_process, (bytes, tolerance));
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/logo_clean_${DateTime.now().millisecondsSinceEpoch}.png');
  await f.writeAsBytes(out);
  return f;
}

Uint8List _process((Uint8List, int) args) {
  final decoded = img.decodeImage(args.$1);
  if (decoded == null) return args.$1;
  final src = decoded.numChannels == 4 ? decoded : decoded.convert(numChannels: 4);
  final w = src.width, h = src.height;
  final tol = args.$2;

  // Dominant background = average of the four corners.
  final corners = [src.getPixel(0, 0), src.getPixel(w - 1, 0), src.getPixel(0, h - 1), src.getPixel(w - 1, h - 1)];
  final br = corners.map((p) => p.r).reduce((a, b) => a + b) / 4;
  final bg = corners.map((p) => p.g).reduce((a, b) => a + b) / 4;
  final bb = corners.map((p) => p.b).reduce((a, b) => a + b) / 4;

  bool near(img.Pixel p) => (p.r - br).abs() + (p.g - bg).abs() + (p.b - bb).abs() <= tol * 3 && p.a > 10;

  final visited = Uint8List(w * h);
  final stack = <int>[];
  void push(int x, int y) {
    final i = y * w + x;
    if (visited[i] == 1) return;
    visited[i] = 1;
    stack.add(i);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    final p = src.getPixel(x, y);
    if (!near(p)) continue;
    p.a = 0;
    if (x > 0) push(x - 1, y);
    if (x < w - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1);
    if (y < h - 1) push(x, y + 1);
  }
  return Uint8List.fromList(img.encodePng(src));
}
