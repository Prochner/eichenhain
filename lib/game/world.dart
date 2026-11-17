import 'dart:typed_data';

import 'pixel_buf.dart' show Rng;

enum Ground { grass, path, sand, water, stone, field, pier }

enum Obj {
  none,
  tree,
  rock,
  bush,
  fence,
  sign,
  well,
  chestClosed,
  chestOpen,
  gateClosed,
  gateOpen,
  ruinWall,
  pillar,
  stump,
  anvil,

  /// Unsichtbarer Block unter einem Haus (das Haus selbst ist ein Sprite).
  building,
}

/// Ein Haus belegt 4x3 Kacheln; (tx, ty) ist die linke obere Kachel.
class House {
  const House(this.tx, this.ty, this.style);

  static const int tilesWide = 4;
  static const int tilesHigh = 3;

  final int tx;
  final int ty;
  final int style;
}

class TilePos {
  const TilePos(this.tx, this.ty);

  final int tx;
  final int ty;

  /// Standpunkt einer Figur auf dieser Kachel (Füße unten in der Kachel).
  double get cx => tx * World.tile + 8.0;
  double get cy => ty * World.tile + 12.0;
}

/// Die Spielwelt: das Dorf Eichenhain mit Ruine, Flüsterwald und Spiegelsee.
/// Die Karte wird deterministisch im Code aufgebaut.
class World {
  World._()
    : ground = List<Ground>.filled(w * h, Ground.grass),
      obj = List<Obj>.filled(w * h, Obj.none),
      variant = Uint8List(w * h);

  factory World.generate() => World._().._build();

  static const int w = 48;
  static const int h = 36;
  static const int tile = 16;

  static const playerStart = TilePos(22, 19);
  static const respawnPoint = TilePos(21, 17);

  static const hildaPos = TilePos(25, 15);
  static const brunoPos = TilePos(17, 15);
  static const martaPos = TilePos(9, 16);
  static const elsaPos = TilePos(33, 16);
  static const ottoPos = TilePos(23, 29);

  static const chestPos = TilePos(22, 4);

  static const chickenSpawns = [TilePos(4, 8), TilePos(12, 5), TilePos(31, 24)];
  static const herbSpawns = [TilePos(41, 6), TilePos(38, 27), TilePos(44, 18)];
  static const appleSpawns = [
    TilePos(20, 12),
    TilePos(6, 13),
    TilePos(33, 23),
    TilePos(28, 24),
  ];
  static const forestSlimes = [
    TilePos(41, 11),
    TilePos(42, 14),
    TilePos(41, 22),
    TilePos(40, 27),
    TilePos(44, 16),
    TilePos(42, 25),
  ];
  static const ruinSlimes = [TilePos(19, 6), TilePos(26, 6)];

  /// Plätze im Hühnergehege für eingefangene Hühner.
  static const penSpots = [TilePos(11, 22), TilePos(13, 21), TilePos(14, 23)];

  final List<Ground> ground;
  final List<Obj> obj;

  /// Grasvariante (0–2) bzw. Baumvariante je Kachel.
  final Uint8List variant;

  final List<House> houses = [];
  final Map<int, String> signs = {};

  int index(int tx, int ty) => ty * w + tx;

  bool inBounds(int tx, int ty) => tx >= 0 && ty >= 0 && tx < w && ty < h;

  Ground groundAt(int tx, int ty) =>
      inBounds(tx, ty) ? ground[index(tx, ty)] : Ground.grass;

  Obj objAt(int tx, int ty) =>
      inBounds(tx, ty) ? obj[index(tx, ty)] : Obj.tree;

  void setObj(int tx, int ty, Obj value) {
    if (inBounds(tx, ty)) obj[index(tx, ty)] = value;
  }

  bool solid(int tx, int ty) {
    if (!inBounds(tx, ty)) return true;
    final i = index(tx, ty);
    if (ground[i] == Ground.water) return true;
    final o = obj[i];
    return o != Obj.none && o != Obj.gateOpen;
  }

  void openGates() {
    for (var i = 0; i < obj.length; i++) {
      if (obj[i] == Obj.gateClosed) obj[i] = Obj.gateOpen;
    }
  }

  // -------------------------------------------------------------------------
  // Aufbau der Karte
  // -------------------------------------------------------------------------

  void _build() {
    final rng = Rng(4711);
    final reserved = List<bool>.filled(w * h, false);

    void reserve(int x, int y, int rw, int rh) {
      for (var j = y; j < y + rh; j++) {
        for (var i = x; i < x + rw; i++) {
          if (inBounds(i, j)) reserved[index(i, j)] = true;
        }
      }
    }

    void fill(int x, int y, int rw, int rh, Ground g) {
      for (var j = y; j < y + rh; j++) {
        for (var i = x; i < x + rw; i++) {
          if (inBounds(i, j)) ground[index(i, j)] = g;
        }
      }
      reserve(x, y, rw, rh);
    }

    for (var i = 0; i < variant.length; i++) {
      final v = rng.range(100);
      variant[i] = v < 62 ? 0 : (v < 88 ? 1 : 2);
    }

    // Dorfkern: hier wächst nichts zufällig.
    reserve(5, 10, 31, 16);

    // Alte Ruine im Norden.
    fill(16, 2, 14, 8, Ground.stone);
    for (var y = 2; y <= 9; y++) {
      for (var x = 16; x <= 29; x++) {
        if (x == 16 || x == 29 || y == 2 || y == 9) {
          setObj(x, y, Obj.ruinWall);
        }
      }
    }
    setObj(22, 9, Obj.gateClosed);
    setObj(23, 9, Obj.gateClosed);
    for (final p in const [
      TilePos(18, 4),
      TilePos(27, 4),
      TilePos(18, 7),
      TilePos(27, 7),
    ]) {
      setObj(p.tx, p.ty, Obj.pillar);
    }
    setObj(chestPos.tx, chestPos.ty, Obj.chestClosed);

    // Spiegelsee im Süden mit Sandstrand.
    for (var y = 26; y <= 33; y++) {
      for (var x = 9; x <= 36; x++) {
        final nx = (x - 22.5) / 9.5;
        final ny = (y - 31.0) / 3.4;
        final d = nx * nx + ny * ny;
        if (d <= 1.0) {
          fill(x, y, 1, 1, Ground.water);
        } else if (d <= 1.7) {
          fill(x, y, 1, 1, Ground.sand);
        }
      }
    }

    // Wege und Dorfplatz.
    fill(5, 17, 37, 2, Ground.path); // Hauptweg West–Ost
    fill(22, 10, 2, 18, Ground.path); // Ruine–See
    fill(19, 15, 8, 6, Ground.path); // Dorfplatz
    fill(16, 14, 1, 3, Ground.path); // zur Schmiede
    fill(26, 14, 1, 1, Ground.path); // zu Hildas Haus
    fill(32, 16, 1, 1, Ground.path); // zu Elsas Hütte
    fill(8, 15, 1, 2, Ground.path); // zu Martas Hof
    fill(22, 28, 2, 2, Ground.pier); // Steg

    // Häuser.
    void house(int tx, int ty, int style) {
      houses.add(House(tx, ty, style));
      for (var j = 0; j < House.tilesHigh; j++) {
        for (var i = 0; i < House.tilesWide; i++) {
          setObj(tx + i, ty + j, Obj.building);
        }
      }
      reserve(tx, ty, House.tilesWide, House.tilesHigh);
    }

    house(25, 11, 0); // Hilda
    house(15, 11, 1); // Schmiede
    house(31, 13, 2); // Elsa
    house(7, 12, 3); // Marta

    setObj(18, 15, Obj.anvil);
    setObj(20, 16, Obj.well);

    // Martas Hof: Acker und Hühnergehege.
    fill(5, 21, 4, 4, Ground.field);
    for (var y = 20; y <= 24; y++) {
      for (var x = 10; x <= 15; x++) {
        if (x == 10 || x == 15 || y == 20 || y == 24) {
          setObj(x, y, Obj.fence);
        }
      }
    }

    // Flüsterwald: Pfad und Lichtungen freihalten.
    reserve(41, 5, 2, 26);
    reserve(39, 5, 5, 4);
    reserve(37, 26, 6, 4);
    reserve(43, 15, 3, 6);
    for (final p in chickenSpawns) {
      reserve(p.tx - 1, p.ty - 1, 3, 3);
    }

    // Deko im Dorf.
    for (final p in const [
      TilePos(13, 10),
      TilePos(21, 11),
      TilePos(30, 10),
      TilePos(35, 20),
      TilePos(6, 11),
      TilePos(29, 23),
      TilePos(17, 23),
      TilePos(34, 24),
      TilePos(12, 15),
      TilePos(20, 24),
      TilePos(27, 22),
    ]) {
      setObj(p.tx, p.ty, Obj.tree);
    }
    for (final p in const [
      TilePos(30, 15),
      TilePos(35, 15),
      TilePos(11, 13),
      TilePos(24, 22),
    ]) {
      setObj(p.tx, p.ty, Obj.bush);
    }
    setObj(14, 19, Obj.rock);
    setObj(28, 20, Obj.stump);
    for (final p in const [
      TilePos(30, 16),
      TilePos(34, 16),
      TilePos(35, 16),
      TilePos(31, 16),
    ]) {
      variant[index(p.tx, p.ty)] = 2;
    }

    // Waldrand rundherum und zufälliger Bewuchs.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = index(x, y);
        if (obj[i] != Obj.none || ground[i] != Ground.grass) continue;
        final border = x < 2 || x >= w - 2 || y < 2 || y >= h - 2;
        if (border) {
          obj[i] = Obj.tree;
          continue;
        }
        if (reserved[i]) continue;
        final roll = rng.unit();
        if (x >= 36) {
          if (roll < 0.45) {
            obj[i] = Obj.tree;
          } else if (roll < 0.49) {
            obj[i] = Obj.bush;
          } else if (roll < 0.52) {
            obj[i] = Obj.rock;
          }
        } else {
          if (roll < 0.09) {
            obj[i] = Obj.tree;
          } else if (roll < 0.11) {
            obj[i] = Obj.bush;
          } else if (roll < 0.125) {
            obj[i] = Obj.rock;
          } else if (roll < 0.133) {
            obj[i] = Obj.stump;
          }
        }
      }
    }

    // Schilder.
    void sign(int tx, int ty, String text) {
      setObj(tx, ty, Obj.sign);
      signs[index(tx, ty)] = text;
    }

    sign(
      25,
      19,
      'Eichenhain. Norden: Alte Ruine. Osten: Flüsterwald. '
          'Süden: Spiegelsee. Westen: Martas Hof.',
    );
    sign(36, 16, 'Flüsterwald. Vorsicht, Schleime!');
    sign(24, 10, 'Alte Ruine. Betreten auf eigene Gefahr!');
  }
}
