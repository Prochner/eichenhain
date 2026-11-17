import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'pixel_buf.dart';
import 'pixel_font.dart';

/// Farbpalette des Spiels (ARGB).
abstract final class Pal {
  static const int outline = 0xFF2B1B2E;
  static const int white = 0xFFF8F8F0;
  static const int skin = 0xFFF2C29B;
  static const int gold = 0xFFF0C040;
  static const int red = 0xFFD83A3A;
  static const int pink = 0xFFF29AC0;

  static const int grass = 0xFF5DAA4A;
  static const int grassDark = 0xFF4F9A40;
  static const int grassLight = 0xFF78C25C;
  static const int grassDeep = 0xFF3E8436;

  static const int path = 0xFFD9B77A;
  static const int pathDark = 0xFFC49F63;
  static const int pathLight = 0xFFE8CC96;

  static const int sand = 0xFFEAD9A0;
  static const int sandDark = 0xFFD6C285;
  static const int sandLight = 0xFFF6EBC0;

  static const int water = 0xFF3F8FD8;
  static const int waterDark = 0xFF3078C0;
  static const int waterDeep = 0xFF2A64A8;
  static const int waterLight = 0xFF8CCBF5;
  static const int foam = 0xFFD8F0FF;

  static const int leaves = 0xFF2F8040;
  static const int leavesLight = 0xFF58A852;
  static const int leavesDark = 0xFF226234;
  static const int leafOutline = 0xFF173F26;

  static const int trunk = 0xFF7A5030;
  static const int trunkDark = 0xFF553620;

  static const int stone = 0xFF83838F;
  static const int stoneDark = 0xFF62626E;
  static const int stoneLight = 0xFFA6A6B2;
  static const int stonePale = 0xFFBDBDC8;
  static const int moss = 0xFF5E8F4A;

  static const int wood = 0xFF9A6A3A;
  static const int woodDark = 0xFF6B4423;
  static const int woodLight = 0xFFBE8C54;

  static const int wall = 0xFFEADCB8;
  static const int wallShade = 0xFFCDBB90;
  static const int glass = 0xFF8CCBF5;

  static const int iron = 0xFF6A6F80;
  static const int ironDark = 0xFF3F4354;
  static const int ironLight = 0xFF9AA0B0;

  static const int soil = 0xFF8A5F3A;
  static const int soilDark = 0xFF6E4A2C;

  // Held: kurze braune Haare, blaue Tunika.
  static const int heroHair = 0xFF7A4A2A;
  static const int heroHairLight = 0xFF9C6438;
  static const int heroTunic = 0xFF3B7DD8;
  static const int heroTunicDark = 0xFF2A5AA8;
}

/// Ausschnitt im Sprite-Atlas.
class Sprite {
  Sprite(this.x, this.y, this.w, this.h)
    : src = ui.Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        w.toDouble(),
        h.toDouble(),
      );

  final int x;
  final int y;
  final int w;
  final int h;
  final ui.Rect src;
}

class _Packer {
  _Packer(this.atlas);

  final PixelBuf atlas;
  int _x = 0;
  int _y = 0;
  int _rowHeight = 0;

  Sprite add(PixelBuf buf) {
    if (_x + buf.w > atlas.w) {
      _x = 0;
      _y += _rowHeight + 1;
      _rowHeight = 0;
    }
    if (_y + buf.h > atlas.h) {
      throw StateError('Sprite-Atlas ist voll');
    }
    atlas.blit(buf, _x, _y);
    final sprite = Sprite(_x, _y, buf.w, buf.h);
    _x += buf.w + 1;
    if (buf.h > _rowHeight) _rowHeight = buf.h;
    return sprite;
  }
}

/// Alle Grafiken des Spiels. Die Pixelart wird beim Start im Code erzeugt
/// und in einen einzigen Atlas gepackt – es gibt keine Bilddateien.
class SpriteSheet {
  SpriteSheet() : atlas = PixelBuf(atlasSize, atlasSize) {
    final p = _Packer(atlas);

    houses = [
      p.add(_house(0xFFC0473A, 0xFF8E2F28, 0xFFDA6A52)), // rot
      p.add(_house(0xFF4A6A9A, 0xFF34507A, 0xFF6A8ABA)), // Schiefer
      p.add(_house(0xFF4A8A5A, 0xFF34683F, 0xFF68A878)), // grün
      p.add(_house(0xFFD0A850, 0xFFA88030, 0xFFE6C878)), // Stroh
    ];
    trees = [
      p.add(_tree(Pal.leaves, Pal.leavesLight, Pal.leavesDark, 5)),
      p.add(_tree(0xFF287048, 0xFF4A9460, 0xFF1C5438, 9)),
    ];

    grass = [p.add(_grass(0)), p.add(_grass(1)), p.add(_grass(2))];
    path = p.add(
      _speckled(Pal.path, Pal.pathDark, Pal.pathLight, 21, dark: 12, light: 9),
    );
    sand = p.add(
      _speckled(Pal.sand, Pal.sandDark, Pal.sandLight, 23, dark: 9, light: 9),
    );
    water = [p.add(_water(0)), p.add(_water(1))];
    stoneFloor = p.add(_stoneFloor());
    field = p.add(_field());
    pier = p.add(_pier());

    rock = p.add(_rock());
    bush = p.add(_bush());
    fence = p.add(_fence());
    sign = p.add(_sign());
    well = p.add(_well());
    chestClosed = p.add(_chest(open: false));
    chestOpen = p.add(_chest(open: true));
    gateClosed = p.add(_gate(open: false));
    gateOpen = p.add(_gate(open: true));
    ruinWall = p.add(_ruinWall());
    pillar = p.add(_pillar());
    stump = p.add(_stump());
    anvil = p.add(_anvil());

    final heroPal = _charPal(
      hair: Pal.heroHair,
      hairLight: Pal.heroHairLight,
      cloth: Pal.heroTunic,
      clothDark: Pal.heroTunicDark,
      belt: Pal.gold,
    );
    heroDown = [
      p.add(_art16(_heroDown, heroPal)),
      p.add(_art16([..._heroDown.sublist(0, 13), ..._legsStep], heroPal)),
    ];
    heroUp = [
      p.add(_art16(_heroUp, heroPal)),
      p.add(_art16([..._heroUp.sublist(0, 13), ..._legsStep], heroPal)),
    ];
    heroSide = [
      p.add(_art16(_heroSide, heroPal)),
      p.add(_art16([..._heroSide.sublist(0, 13), ..._legsSideStep], heroPal)),
    ];

    hilda = p.add(
      _art16(
        _villagerLong,
        _charPal(
          hair: 0xFFD0D0DA,
          hairLight: 0xFFE8E8F0,
          cloth: 0xFF8A4FB0,
          clothDark: 0xFF6A3A8C,
          belt: Pal.gold,
        ),
      ),
    );
    marta = p.add(
      _art16(
        _villagerLong,
        _charPal(
          hair: 0xFFE8C860,
          hairLight: 0xFFF6E090,
          cloth: 0xFFC84B4B,
          clothDark: 0xFF983434,
          belt: Pal.white,
        ),
      ),
    );
    elsa = p.add(
      _art16(
        _villagerLong,
        _charPal(
          hair: 0xFFD0603A,
          hairLight: 0xFFE88458,
          cloth: 0xFF3FA06A,
          clothDark: 0xFF2C7A4E,
          belt: Pal.woodDark,
        ),
      ),
    );
    bruno = p.add(
      _art16(
        _heroDown,
        _charPal(
          hair: 0xFF3A3038,
          beard: 0xFF3A3038,
          cloth: 0xFF8C6A4A,
          clothDark: 0xFF6A4E36,
          belt: 0xFF4A3A30,
          pants: 0xFF4A4A5A,
          boots: 0xFF3A2A20,
        ),
      ),
    );
    otto = p.add(
      _art16(
        _heroDown,
        _charPal(
          hair: 0xFFD8C070,
          hairLight: 0xFFEAD890,
          beard: 0xFFF0F0F0,
          cloth: 0xFFE0B83A,
          clothDark: 0xFFB8922A,
          belt: Pal.woodDark,
          pants: 0xFF4A5A7A,
          boots: 0xFF2F2F3A,
        ),
      ),
    );

    const chickenPal = {
      'o': Pal.outline,
      'w': Pal.white,
      'g': 0xFFD4D4CC,
      'r': Pal.red,
      'y': 0xFFF0A030,
      'e': Pal.outline,
    };
    chicken = [
      p.add(_art16(_chicken, chickenPal)),
      p.add(_art16([..._chicken.sublist(0, 14), ..._chickenStep], chickenPal)),
    ];
    slime = p.add(
      _art16(_slime, const {
        'o': 0xFF1E5A2A,
        'g': 0xFF5CCB5F,
        'l': 0xFFA6F0A0,
        'd': 0xFF3A9E48,
        'w': Pal.white,
        'e': Pal.outline,
      }),
    );
    herb = p.add(
      _art16(_herb, const {
        'r': Pal.red,
        'y': Pal.gold,
        'g': 0xFF1F6A30,
        'o': Pal.outline,
      }),
    );

    final sword = _art16(_sword, const {
      'o': Pal.outline,
      'w': Pal.white,
      'l': 0xFFB8C4D8,
      'y': Pal.gold,
      'b': Pal.woodDark,
    });
    swordUp = p.add(sword);
    swordRight = p.add(sword.rotatedCw());

    const heartPal = {
      'o': Pal.outline,
      'r': 0xFFE03A4A,
      'w': 0xFFFFB0B8,
    };
    heartFull = p.add(PixelBuf(9, 8)..art(_heart, heartPal));
    heartEmpty = p.add(
      PixelBuf(9, 8)..art(_heart, const {
        'o': Pal.outline,
        'r': 0xFF4A4458,
        'w': 0xFF4A4458,
      }),
    );
    itemKey = p.add(
      _art16(_itemKey, const {'o': Pal.outline, 'y': Pal.gold}),
    );
    itemAmulet = p.add(
      _art16(_itemAmulet, const {
        'o': Pal.outline,
        'y': Pal.gold,
        'g': 0xFF38C8D8,
        'l': 0xFFC8F8FF,
      }),
    );
    itemBoots = p.add(
      _art16(_itemBoots, const {
        'o': Pal.outline,
        'b': Pal.wood,
        'B': Pal.woodDark,
        'w': Pal.white,
      }),
    );
    itemPie = p.add(
      _art16(_itemPie, const {
        'o': Pal.outline,
        'c': 0xFFE8B860,
        'l': 0xFFF6D890,
        'C': 0xFFC08A3A,
        'b': 0xFFA0A6B4,
      }),
    );
    itemFish = p.add(
      _art16(_itemFish, const {
        'o': Pal.outline,
        's': 0xFFC98A5A,
        'w': 0xFFE8B888,
        'e': Pal.outline,
      }),
    );
    itemApple = p.add(
      _art16(_itemApple, const {
        'o': Pal.outline,
        'r': 0xFFE03A4A,
        'R': 0xFFA82A30,
        'w': 0xFFFFB0B8,
        'g': Pal.leavesLight,
      }),
    );
    iconBag = p.add(
      PixelBuf(12, 9)..art(_iconBag, const {
        'o': Pal.outline,
        'b': Pal.woodLight,
        'y': Pal.gold,
      }),
    );

    PixelFont.glyphs.forEach((code, rows) {
      final buf = PixelBuf(rows.first.length, rows.length)
        ..art(rows, const {'#': 0xFFFFFFFF});
      glyphs[code] = p.add(buf);
    });
  }

  static const int atlasSize = 256;

  final PixelBuf atlas;

  late final List<Sprite> houses;
  late final List<Sprite> trees;
  late final List<Sprite> grass;
  late final Sprite path;
  late final Sprite sand;
  late final List<Sprite> water;
  late final Sprite stoneFloor;
  late final Sprite field;
  late final Sprite pier;

  late final Sprite rock;
  late final Sprite bush;
  late final Sprite fence;
  late final Sprite sign;
  late final Sprite well;
  late final Sprite chestClosed;
  late final Sprite chestOpen;
  late final Sprite gateClosed;
  late final Sprite gateOpen;
  late final Sprite ruinWall;
  late final Sprite pillar;
  late final Sprite stump;
  late final Sprite anvil;

  late final List<Sprite> heroDown;
  late final List<Sprite> heroUp;
  late final List<Sprite> heroSide;
  late final Sprite hilda;
  late final Sprite bruno;
  late final Sprite marta;
  late final Sprite elsa;
  late final Sprite otto;

  late final List<Sprite> chicken;
  late final Sprite slime;
  late final Sprite herb;
  late final Sprite swordUp;
  late final Sprite swordRight;

  late final Sprite heartFull;
  late final Sprite heartEmpty;
  late final Sprite itemKey;
  late final Sprite itemAmulet;
  late final Sprite itemBoots;
  late final Sprite itemPie;
  late final Sprite itemFish;
  late final Sprite itemApple;
  late final Sprite iconBag;

  final Map<int, Sprite> glyphs = {};

  /// Wandelt den Atlas in ein GPU-Bild um.
  Future<ui.Image> toImage() {
    final bytes = Uint8List(atlas.w * atlas.h * 4);
    for (var i = 0; i < atlas.data.length; i++) {
      final c = atlas.data[i];
      bytes[i * 4] = (c >> 16) & 0xFF;
      bytes[i * 4 + 1] = (c >> 8) & 0xFF;
      bytes[i * 4 + 2] = c & 0xFF;
      bytes[i * 4 + 3] = (c >> 24) & 0xFF;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      atlas.w,
      atlas.h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

// ---------------------------------------------------------------------------
// Figuren (16x16, ein Zeichen = ein Pixel)
// ---------------------------------------------------------------------------

Map<String, int> _charPal({
  required int hair,
  int? hairLight,
  int? beard,
  required int cloth,
  required int clothDark,
  required int belt,
  int pants = 0xFF55556E,
  int boots = 0xFF5A3A22,
}) => {
  'o': Pal.outline,
  'h': hair,
  'H': hairLight ?? hair,
  's': Pal.skin,
  'e': Pal.outline,
  'm': beard ?? Pal.skin,
  'c': cloth,
  'C': clothDark,
  'b': belt,
  'p': pants,
  'f': boots,
};

PixelBuf _art16(List<String> rows, Map<String, int> palette) {
  if (rows.length != 16 || rows.first.length != 16) {
    throw ArgumentError('Sprite muss 16x16 Pixel groß sein');
  }
  return PixelBuf(16, 16)..art(rows, palette);
}

const _heroDown = [
  '................',
  '.....oooooo.....',
  '....ohHHhhho....',
  '...ohHhhhhhho...',
  '...ohhhhhhhho...',
  '...ohhsssshho...',
  '...ohsessesho...',
  '...osmmmmmmso...',
  '....ommmmmmo....',
  '...occcccccco...',
  '..osccccccccso..',
  '..osbbbbbbbbso..',
  '...oCccccccCo...',
  '....oppppppo....',
  '....oppooppo....',
  '....offooffo....',
];

const _legsStep = [
  '....oppppppo....',
  '....offooppo....',
  '....oooooffo....',
];

const _heroUp = [
  '................',
  '.....oooooo.....',
  '....ohhhhhho....',
  '...ohhhhhhhho...',
  '...ohhhhhhhho...',
  '...ohhhhhhhho...',
  '...ohhhhhhhho...',
  '...oshhhhhhso...',
  '....osssssso....',
  '...occcccccco...',
  '..osccccccccso..',
  '..osbbbbbbbbso..',
  '...oCccccccCo...',
  '....oppppppo....',
  '....oppooppo....',
  '....offooffo....',
];

const _heroSide = [
  '................',
  '.....oooooo.....',
  '....ohhHHhho....',
  '...ohhhhhHhho...',
  '...ohhhhhhhho...',
  '...ohhhhhssso...',
  '...ohhhhsseso...',
  '...ohhhssssso...',
  '....osssssso....',
  '....occcccco....',
  '....occcscco....',
  '....obbbbbbo....',
  '....oCcccCCo....',
  '.....oppppo.....',
  '.....oppppo.....',
  '.....offfffo....',
];

const _legsSideStep = [
  '....oppppppo....',
  '...oppo..oppo...',
  '...offo..offo...',
];

const _villagerLong = [
  '................',
  '.....oooooo.....',
  '....ohHHhhho....',
  '...ohHhhhhhho...',
  '...ohhhhhhhho...',
  '...ohhsssshho...',
  '...ohsessesho...',
  '...ohssssssho...',
  '...ohhsssshho...',
  '...ohhcccchho...',
  '..osccccccccso..',
  '..osbbbbbbbbso..',
  '...occcccccco...',
  '...occcccccco...',
  '...oCCCCCCCCo...',
  '.....ff..ff.....',
];

const _chicken = [
  '................',
  '................',
  '................',
  '................',
  '..........rr....',
  '.........owwo...',
  '.........owewyy.',
  '..oo.....owwo...',
  '..owoooooowwo...',
  '..owwwwwwwwwo...',
  '...owwwgwwwo....',
  '...owwggwwwo....',
  '....owwwwwo.....',
  '.....ooooo......',
  '......y..y......',
  '.....yy.yy......',
];

const _chickenStep = [
  '.......y.y......',
  '......yy.yy.....',
];

const _slime = [
  '................',
  '................',
  '................',
  '................',
  '................',
  '......oooo......',
  '.....oggggo.....',
  '....oglggggo....',
  '...ogllgggggo...',
  '...oggggggggo...',
  '..ogweggggwego..',
  '..ogweggggwego..',
  '..oggggggggggo..',
  '..odggggggggdo..',
  '...oddddddddo...',
  '....oooooooo....',
];

const _herb = [
  '................',
  '................',
  '................',
  '.......oo.......',
  '.....oorroo.....',
  '....orryyrro....',
  '....orryyrro....',
  '.....oorroo.....',
  '.......gg.......',
  '....gg.gg.gg....',
  '.....gggggg.....',
  '......gggg......',
  '.......gg.......',
  '................',
  '................',
  '................',
];

const _sword = [
  '.......oo.......',
  '......owlo......',
  '......owlo......',
  '......owlo......',
  '......owlo......',
  '......owlo......',
  '......owlo......',
  '......owlo......',
  '......owlo......',
  '....oooooooo....',
  '....oyyyyyyo....',
  '....oooooooo....',
  '......obbo......',
  '......obbo......',
  '......oyyo......',
  '.......oo.......',
];

const _heart = [
  '..oo.oo..',
  '.orrorro.',
  'orwrrrrro',
  'orrrrrrro',
  '.orrrrro.',
  '..orrro..',
  '...oro...',
  '....o....',
];

const _itemKey = [
  '................',
  '................',
  '.....oooo.......',
  '....oyyyyo......',
  '...oyyooyyo.....',
  '...oyo..oyo.....',
  '...oyyooyyo.....',
  '....oyyyyo......',
  '.....oyyo.......',
  '.....oyyo.......',
  '.....oyyooo.....',
  '.....oyyyyo.....',
  '.....oyyoo......',
  '.....oyyyyo.....',
  '.....oooooo.....',
  '................',
];

const _itemAmulet = [
  '................',
  '....oo....oo....',
  '...oyyo..oyyo...',
  '...oyo....oyo...',
  '...oyo....oyo...',
  '....oyo..oyo....',
  '.....oyooyo.....',
  '....ooyyyyoo....',
  '...oyyggggyyo...',
  '...oyglggggyo...',
  '...oyggggggyo...',
  '...oyyggggyyo...',
  '....ooyyyyoo....',
  '......oooo......',
  '................',
  '................',
];

const _itemBoots = [
  '................',
  '................',
  '.....ooooo......',
  '.....obbbo......',
  '.....obbbo......',
  '..ww.obbbo......',
  '.wwwoobbbo......',
  '..wwwobbboo.....',
  '...wwobbbbbooo..',
  '.....obbbbbbbbo.',
  '.....obBBBBBBBo.',
  '.....oooooooooo.',
  '................',
  '................',
  '................',
  '................',
];

const _itemPie = [
  '................',
  '................',
  '................',
  '................',
  '.....oooooo.....',
  '...ooccccccoo...',
  '..occlcccclcco..',
  '..occcccccccco..',
  '..oCCCCCCCCCCo..',
  '..obbbbbbbbbbo..',
  '...obbbbbbbbo...',
  '....oooooooo....',
  '................',
  '................',
  '................',
  '................',
];

const _itemFish = [
  '................',
  '................',
  '................',
  '................',
  '................',
  '......ooooo.....',
  '.oo.oosssssoo...',
  'osoossssssseso..',
  'osssssssssssso..',
  'osoowwwwwwwwo...',
  '.oo.oowwwwoo....',
  '......oooo......',
  '................',
  '................',
  '................',
  '................',
];

const _itemApple = [
  '................',
  '................',
  '................',
  '........o.gg....',
  '........ogg.....',
  '.....ooooooo....',
  '....orrrorrro...',
  '...orwrrrrrrro..',
  '...orwrrrrrrro..',
  '...orrrrrrrrro..',
  '...orrrrrrrRRo..',
  '....orrrrrRRo...',
  '.....orrrRRo....',
  '......ooooo.....',
  '................',
  '................',
];

const _iconBag = [
  '....oooo....',
  '...o....o...',
  '..oooooooo..',
  '.obbbbbbbbo.',
  '.obbbyybbbo.',
  '.obbbyybbbo.',
  '.obbbbbbbbo.',
  '.obbbbbbbbo.',
  '..oooooooo..',
];

// ---------------------------------------------------------------------------
// Bodenkacheln (prozedural, 16x16)
// ---------------------------------------------------------------------------

PixelBuf _speckled(
  int base,
  int darkColor,
  int lightColor,
  int seed, {
  int dark = 14,
  int light = 8,
}) {
  final b = PixelBuf(16, 16)..fill(base);
  final r = Rng(seed);
  for (var i = 0; i < dark; i++) {
    b.set(r.range(16), r.range(16), darkColor);
  }
  for (var i = 0; i < light; i++) {
    b.set(r.range(16), r.range(16), lightColor);
  }
  return b;
}

void _flower(PixelBuf b, int x, int y, int petal) {
  b.set(x - 1, y, petal);
  b.set(x + 1, y, petal);
  b.set(x, y - 1, petal);
  b.set(x, y + 1, petal);
  b.set(x, y, Pal.gold);
}

PixelBuf _grass(int variant) {
  final b = _speckled(
    Pal.grass,
    Pal.grassDark,
    Pal.grassLight,
    11 + variant * 7,
  );
  if (variant == 1) {
    for (final t in const [
      [3, 5],
      [11, 10],
      [6, 13],
    ]) {
      b.set(t[0], t[1], Pal.grassDeep);
      b.set(t[0] + 1, t[1] - 1, Pal.grassDeep);
      b.set(t[0] + 2, t[1], Pal.grassDeep);
    }
  } else if (variant == 2) {
    _flower(b, 4, 5, Pal.white);
    _flower(b, 11, 10, Pal.pink);
    _flower(b, 12, 3, Pal.white);
    _flower(b, 5, 12, Pal.pink);
  }
  return b;
}

PixelBuf _water(int frame) {
  final b = _speckled(Pal.water, Pal.waterDark, Pal.water, 31, dark: 10);
  const waves = [
    [1, 3, 4],
    [9, 6, 3],
    [4, 11, 4],
    [11, 13, 3],
  ];
  for (final w in waves) {
    for (var i = 0; i < w[2]; i++) {
      b.set((w[0] + i + frame * 3) % 16, w[1] + frame, Pal.waterLight);
    }
  }
  return b;
}

PixelBuf _stoneFloor() {
  final b = _speckled(
    Pal.stoneLight,
    Pal.stone,
    Pal.stonePale,
    41,
    dark: 8,
    light: 8,
  );
  b.rect(0, 7, 16, 1, Pal.stone);
  b.rect(0, 15, 16, 1, Pal.stone);
  b.rect(7, 0, 1, 7, Pal.stone);
  b.rect(15, 0, 1, 7, Pal.stone);
  b.rect(3, 8, 1, 7, Pal.stone);
  b.rect(11, 8, 1, 7, Pal.stone);
  return b;
}

PixelBuf _field() {
  final b = _speckled(Pal.soil, Pal.soilDark, Pal.soil, 51, dark: 8, light: 0);
  for (final y in const [3, 7, 11, 15]) {
    b.rect(0, y, 16, 1, Pal.soilDark);
  }
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 3; col++) {
      final x = 2 + col * 5 + (row.isOdd ? 2 : 0);
      final y = row * 4;
      b.set(x, y, Pal.grassLight);
      b.set(x + 1, y, Pal.grassLight);
      b.set(x, y + 1, Pal.leaves);
    }
  }
  return b;
}

PixelBuf _pier() {
  final b = _speckled(
    Pal.wood,
    Pal.woodDark,
    Pal.woodLight,
    53,
    dark: 5,
    light: 10,
  );
  for (final y in const [3, 7, 11, 15]) {
    b.rect(0, y, 16, 1, Pal.woodDark);
  }
  b.set(1, 1, Pal.woodDark);
  b.set(14, 5, Pal.woodDark);
  b.set(1, 9, Pal.woodDark);
  b.set(14, 13, Pal.woodDark);
  return b;
}

PixelBuf _ruinWall() {
  final b = _speckled(Pal.stone, Pal.stoneDark, Pal.stone, 43, dark: 8);
  b.rect(0, 0, 16, 2, Pal.stoneLight);
  b.rect(0, 6, 16, 1, Pal.stoneDark);
  b.rect(0, 11, 16, 1, Pal.stoneDark);
  b.rect(0, 15, 16, 1, Pal.outline);
  b.rect(5, 2, 1, 4, Pal.stoneDark);
  b.rect(12, 2, 1, 4, Pal.stoneDark);
  b.rect(2, 7, 1, 4, Pal.stoneDark);
  b.rect(9, 7, 1, 4, Pal.stoneDark);
  b.rect(5, 12, 1, 3, Pal.stoneDark);
  b.rect(13, 12, 1, 3, Pal.stoneDark);
  b.set(3, 3, Pal.moss);
  b.set(4, 3, Pal.moss);
  b.set(10, 9, Pal.moss);
  b.set(14, 13, Pal.moss);
  b.set(14, 12, Pal.moss);
  return b;
}

// ---------------------------------------------------------------------------
// Objekte (prozedural)
// ---------------------------------------------------------------------------

bool _inEllipse(int x, int y, double cx, double cy, double rx, double ry) {
  final nx = (x - cx) / rx;
  final ny = (y - cy) / ry;
  return nx * nx + ny * ny <= 1;
}

PixelBuf _rock() {
  final b = PixelBuf(16, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (!_inEllipse(x, y, 7.5, 9.5, 6, 4.6)) continue;
      var c = Pal.stone;
      if (y >= 12) c = Pal.stoneDark;
      if (_inEllipse(x, y, 5.8, 7.8, 3.2, 2.0)) c = Pal.stoneLight;
      b.set(x, y, c);
    }
  }
  b.set(10, 9, Pal.stoneDark);
  b.set(11, 10, Pal.stoneDark);
  b.outline(Pal.outline);
  return b;
}

PixelBuf _bush() {
  final b = PixelBuf(16, 16);
  final r = Rng(61);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (!_inEllipse(x, y, 7.5, 9.0, 6.4, 5.2)) continue;
      var c = Pal.leaves;
      if (y >= 11) c = Pal.leavesDark;
      if (_inEllipse(x, y, 5.5, 7.0, 3.4, 2.4)) c = Pal.leavesLight;
      if (r.chance(0.12)) c = Pal.leavesDark;
      b.set(x, y, c);
    }
  }
  b.set(4, 9, Pal.red);
  b.set(9, 7, Pal.red);
  b.set(11, 11, Pal.red);
  b.set(7, 12, Pal.red);
  b.outline(Pal.leafOutline);
  return b;
}

PixelBuf _fence() {
  final b = PixelBuf(16, 16);
  b.rect(0, 6, 16, 2, Pal.woodLight);
  b.rect(0, 8, 16, 1, Pal.woodDark);
  b.rect(0, 11, 16, 2, Pal.woodLight);
  b.rect(0, 13, 16, 1, Pal.woodDark);
  for (final x in const [2, 11]) {
    b.rect(x, 3, 3, 12, Pal.wood);
    b.rect(x, 3, 3, 1, Pal.woodLight);
    b.rect(x + 2, 4, 1, 11, Pal.woodDark);
  }
  b.outline(Pal.outline);
  return b;
}

PixelBuf _sign() {
  final b = PixelBuf(16, 16);
  b.rect(7, 9, 2, 6, Pal.woodDark);
  b.rect(2, 2, 12, 7, Pal.woodLight);
  b.rect(2, 8, 12, 1, Pal.wood);
  b.rect(4, 4, 8, 1, Pal.woodDark);
  b.rect(4, 6, 5, 1, Pal.woodDark);
  b.outline(Pal.outline);
  return b;
}

PixelBuf _well() {
  final b = PixelBuf(16, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (!_inEllipse(x, y, 7.5, 10.5, 6.5, 4.4)) continue;
      var c = y <= 9 ? Pal.stoneLight : Pal.stone;
      if (_inEllipse(x, y, 7.5, 10.0, 4.2, 2.4)) c = Pal.waterDeep;
      b.set(x, y, c);
    }
  }
  b.set(6, 9, Pal.waterLight);
  b.set(7, 9, Pal.waterLight);
  b.rect(1, 3, 2, 7, Pal.wood);
  b.rect(13, 3, 2, 7, Pal.wood);
  b.rect(7, 3, 1, 4, Pal.woodDark);
  b.rect(0, 1, 16, 2, 0xFFC0473A);
  b.rect(1, 1, 14, 1, 0xFFDA6A52);
  b.outline(Pal.outline);
  return b;
}

PixelBuf _chest({required bool open}) {
  final b = PixelBuf(16, 16);
  if (open) {
    b.rect(2, 1, 12, 4, Pal.woodDark);
    b.rect(3, 2, 10, 2, Pal.wood);
    b.rect(2, 5, 12, 3, 0xFF1A1020);
  } else {
    b.rect(2, 4, 12, 4, Pal.woodLight);
  }
  b.rect(2, 8, 12, 6, Pal.wood);
  b.rect(2, 8, 12, 1, Pal.woodDark);
  final top = open ? 8 : 4;
  b.rect(4, top, 1, 14 - top, Pal.gold);
  b.rect(11, top, 1, 14 - top, Pal.gold);
  if (!open) {
    b.rect(7, 7, 2, 3, Pal.gold);
    b.set(8, 8, Pal.outline);
  }
  b.outline(Pal.outline);
  return b;
}

PixelBuf _gate({required bool open}) {
  final b = PixelBuf(16, 16);
  b.rect(0, 0, 16, 3, Pal.ironDark);
  b.rect(0, 0, 16, 1, Pal.iron);
  for (final x in const [1, 4, 7, 10, 13]) {
    final len = open ? 2 : 13;
    b.rect(x, 3, 2, len, Pal.iron);
    b.rect(x, 3, 1, len, Pal.ironLight);
  }
  if (!open) {
    b.rect(0, 9, 16, 2, Pal.ironDark);
    b.rect(7, 8, 2, 4, Pal.gold);
    b.set(7, 10, Pal.outline);
  }
  return b;
}

PixelBuf _pillar() {
  final b = PixelBuf(16, 16);
  b.rect(4, 3, 8, 11, Pal.stoneLight);
  b.rect(10, 3, 2, 11, Pal.stone);
  b.rect(6, 3, 1, 11, Pal.stonePale);
  b.rect(3, 1, 10, 2, Pal.stonePale);
  b.rect(3, 13, 10, 2, Pal.stone);
  b.set(8, 6, Pal.stoneDark);
  b.set(9, 7, Pal.stoneDark);
  b.set(5, 10, Pal.moss);
  b.set(5, 11, Pal.moss);
  b.outline(Pal.outline);
  return b;
}

PixelBuf _stump() {
  final b = PixelBuf(16, 16);
  b.rect(4, 9, 8, 5, Pal.trunk);
  b.rect(4, 9, 1, 5, Pal.trunkDark);
  b.rect(8, 10, 1, 4, Pal.trunkDark);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (!_inEllipse(x, y, 7.5, 8.0, 4.4, 2.4)) continue;
      b.set(x, y, _inEllipse(x, y, 7.5, 8.0, 2.2, 1.0)
          ? Pal.wood
          : Pal.woodLight);
    }
  }
  b.outline(Pal.outline);
  return b;
}

PixelBuf _anvil() {
  final b = PixelBuf(16, 16);
  b.rect(3, 5, 11, 3, Pal.iron);
  b.rect(3, 5, 11, 1, Pal.ironLight);
  b.rect(1, 6, 2, 1, Pal.iron);
  b.rect(6, 8, 5, 3, Pal.ironDark);
  b.rect(4, 11, 9, 3, Pal.iron);
  b.rect(4, 13, 9, 1, Pal.ironDark);
  b.outline(Pal.outline);
  return b;
}

PixelBuf _tree(int leaves, int light, int dark, int seed) {
  final b = PixelBuf(24, 32);
  // Stamm
  b.rect(10, 19, 4, 11, Pal.trunk);
  b.rect(10, 19, 1, 11, Pal.trunkDark);
  b.set(9, 29, Pal.trunk);
  b.set(14, 29, Pal.trunk);
  b.set(12, 23, Pal.trunkDark);
  b.set(12, 26, Pal.trunkDark);
  // Krone
  for (var y = 0; y < 24; y++) {
    for (var x = 0; x < 24; x++) {
      final dx = x - 11.5;
      final dy = (y - 11.0) * 1.08;
      final angle = math.atan2(dy, dx);
      final radius = 10.0 + math.sin(angle * 7) * 0.9;
      if (math.sqrt(dx * dx + dy * dy) > radius) continue;
      var c = dark;
      final mx = dx + 2.5;
      final my = dy + 3.0;
      if (math.sqrt(mx * mx + my * my) < 7.6) c = leaves;
      final lx = dx + 3.5;
      final ly = dy + 4.5;
      if (math.sqrt(lx * lx + ly * ly) < 3.6) c = light;
      b.set(x, y, c);
    }
  }
  final r = Rng(seed);
  for (var i = 0; i < 36; i++) {
    final x = 2 + r.range(20);
    final y = 2 + r.range(19);
    final current = b.get(x, y);
    if (current == leaves) {
      b.set(x, y, r.chance(0.5) ? light : dark);
    } else if (current == dark) {
      b.set(x, y, leaves);
    }
  }
  b.outline(Pal.leafOutline);
  // Schatten am Boden
  for (var x = 6; x < 18; x++) {
    b.setIfEmpty(x, 30, Pal.grassDeep);
  }
  for (var x = 8; x < 16; x++) {
    b.setIfEmpty(x, 31, Pal.grassDeep);
  }
  return b;
}

PixelBuf _house(int roof, int roofDark, int roofLight) {
  final b = PixelBuf(64, 48);
  // Wand
  b.rect(3, 26, 58, 21, Pal.wall);
  b.rect(3, 26, 58, 3, Pal.wallShade);
  final r = Rng(roof & 0xFFFF);
  for (var i = 0; i < 26; i++) {
    b.set(5 + r.range(54), 30 + r.range(15), Pal.wallShade);
  }
  // Fachwerk
  b.rect(3, 26, 2, 21, Pal.wood);
  b.rect(59, 26, 2, 21, Pal.wood);
  b.rect(33, 29, 2, 18, Pal.wood);
  b.rect(3, 45, 58, 2, Pal.woodDark);
  // Tür
  b.rect(18, 30, 12, 17, Pal.woodDark);
  b.rect(19, 31, 10, 16, Pal.wood);
  b.rect(19, 31, 10, 1, Pal.woodLight);
  b.rect(22, 32, 1, 15, Pal.woodDark);
  b.rect(25, 32, 1, 15, Pal.woodDark);
  b.rect(27, 39, 1, 2, Pal.gold);
  // großes Fenster
  b.rect(40, 31, 15, 11, Pal.woodDark);
  b.rect(41, 32, 13, 9, Pal.glass);
  b.rect(47, 32, 1, 9, Pal.woodDark);
  b.rect(41, 36, 13, 1, Pal.woodDark);
  b.rect(42, 33, 2, 1, Pal.white);
  b.rect(49, 33, 2, 1, Pal.white);
  b.rect(39, 42, 17, 1, Pal.woodLight);
  // kleines Fenster
  b.rect(7, 32, 8, 8, Pal.woodDark);
  b.rect(8, 33, 6, 6, Pal.glass);
  b.rect(11, 33, 1, 6, Pal.woodDark);
  b.set(9, 34, Pal.white);
  // Dach mit Schindeln
  for (var y = 1; y < 27; y++) {
    final inset = y < 7 ? 7 - y : 0;
    for (var x = 1 + inset; x < 63 - inset; x++) {
      final row = (y - 1) ~/ 4;
      final line = (y - 1) % 4;
      var c = roof;
      if (line == 0) c = roofLight;
      if (line == 3) c = roofDark;
      if (line != 0 && (x + (row.isOdd ? 3 : 0)) % 6 == 0) c = roofDark;
      b.set(x, y, c);
    }
  }
  b.rect(1, 26, 62, 1, roofDark);
  // Schornstein
  b.rect(46, 3, 7, 8, Pal.stone);
  b.rect(46, 3, 7, 2, Pal.stoneDark);
  b.rect(46, 5, 1, 6, Pal.stoneLight);
  b.outline(Pal.outline);
  return b;
}
