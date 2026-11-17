import 'dart:typed_data';

/// Kleine ARGB-Pixelfläche, auf der die gesamte Pixelart des Spiels
/// zur Laufzeit gezeichnet wird (0 = transparent).
class PixelBuf {
  PixelBuf(this.w, this.h) : data = Uint32List(w * h);

  final int w;
  final int h;
  final Uint32List data;

  bool _inside(int x, int y) => x >= 0 && y >= 0 && x < w && y < h;

  int get(int x, int y) => _inside(x, y) ? data[y * w + x] : 0;

  void set(int x, int y, int color) {
    if (_inside(x, y)) data[y * w + x] = color;
  }

  void setIfEmpty(int x, int y, int color) {
    if (_inside(x, y) && data[y * w + x] == 0) data[y * w + x] = color;
  }

  void fill(int color) => data.fillRange(0, data.length, color);

  void rect(int x, int y, int rw, int rh, int color) {
    for (var j = y; j < y + rh; j++) {
      for (var i = x; i < x + rw; i++) {
        set(i, j, color);
      }
    }
  }

  /// Kopiert [src] an die Position (dx, dy); transparente Pixel bleiben aus.
  void blit(PixelBuf src, int dx, int dy) {
    for (var j = 0; j < src.h; j++) {
      for (var i = 0; i < src.w; i++) {
        final c = src.data[j * src.w + i];
        if (c != 0) set(dx + i, dy + j, c);
      }
    }
  }

  /// Zeichnet ASCII-Pixelart: jedes Zeichen ist ein Pixel, '.' ist
  /// transparent, alle anderen Zeichen werden über [palette] aufgelöst.
  void art(
    List<String> rows,
    Map<String, int> palette, {
    int dx = 0,
    int dy = 0,
  }) {
    final width = rows.first.length;
    for (var j = 0; j < rows.length; j++) {
      final row = rows[j];
      if (row.length != width) {
        throw ArgumentError(
          'Pixelart-Zeile $j ist ${row.length} statt $width breit: "$row"',
        );
      }
      for (var i = 0; i < row.length; i++) {
        final ch = row[i];
        if (ch == '.') continue;
        final c = palette[ch];
        if (c == null) {
          throw ArgumentError('Unbekanntes Farbzeichen "$ch" in "$row"');
        }
        set(dx + i, dy + j, c);
      }
    }
  }

  /// Umrandet alle belegten Pixel mit einer 1 Pixel breiten Kontur.
  void outline(int color) {
    final src = Uint32List.fromList(data);
    int at(int x, int y) => _inside(x, y) ? src[y * w + x] : 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (at(x, y) != 0) continue;
        if (at(x - 1, y) != 0 ||
            at(x + 1, y) != 0 ||
            at(x, y - 1) != 0 ||
            at(x, y + 1) != 0) {
          data[y * w + x] = color;
        }
      }
    }
  }

  /// Um 90° im Uhrzeigersinn gedrehte Kopie.
  PixelBuf rotatedCw() {
    final out = PixelBuf(h, w);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out.set(h - 1 - y, x, get(x, y));
      }
    }
    return out;
  }
}

/// Deterministischer Zufallsgenerator (Lehmer). Bleibt unter 2^53 und liefert
/// deshalb auf allen Plattformen – auch im Web – exakt dieselbe Folge.
class Rng {
  Rng(int seed) : _state = (seed.abs() % 2147483646) + 1 {
    for (var i = 0; i < 4; i++) {
      next();
    }
  }

  int _state;

  int next() {
    _state = (_state * 48271) % 2147483647;
    return _state;
  }

  int range(int n) => next() % n;

  double unit() => next() / 2147483647;

  bool chance(double p) => unit() < p;
}
