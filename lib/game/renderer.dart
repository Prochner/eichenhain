import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'entities.dart';
import 'game.dart';
import 'items.dart';
import 'pixel_font.dart';
import 'quests.dart';
import 'sprites.dart';
import 'world.dart';

/// Zustand der Touch-/Maus-Steuerung (Positionen in Spielpixeln).
class TouchState {
  bool visible = false;

  // Virtueller Stick
  int? pointer;
  Offset base = Offset.zero;
  Offset pos = Offset.zero;

  // Gegenstand, der im Inventar gerade gezogen wird
  int? dragPointer;
  int dragFrom = 0;
  Offset? dragPos;

  /// Bewegungsrichtung des virtuellen Sticks (Länge 0 oder 1).
  Offset get vector {
    if (pointer == null) return Offset.zero;
    final d = pos - base;
    final len = d.distance;
    if (len < 5) return Offset.zero;
    return d / len;
  }

  void release() => pointer = null;

  void endDrag() {
    dragPointer = null;
    dragPos = null;
  }
}

/// Positionen der festen Bedienelemente – von Darstellung und Eingabe genutzt.
abstract final class UiLayout {
  static const double actionRadius = 16;

  static Rect _button(Size view, EdgeInsets pad, int fromRight) =>
      Rect.fromLTWH(
        view.width - pad.right - 22 - fromRight * 22,
        pad.top + 4,
        18,
        18,
      );

  static Rect menuButton(Size view, EdgeInsets pad) => _button(view, pad, 0);
  static Rect logButton(Size view, EdgeInsets pad) => _button(view, pad, 1);
  static Rect bagButton(Size view, EdgeInsets pad) => _button(view, pad, 2);

  static Offset actionCenter(Size view, EdgeInsets pad) =>
      Offset(view.width - pad.right - 30, view.height - pad.bottom - 34);

  static Offset stickHome(Size view, EdgeInsets pad) =>
      Offset(pad.left + 36, view.height - pad.bottom - 38);
}

/// Klickbare Flächen des zuletzt gezeichneten Bildes (in Spielpixeln).
class HitRegions {
  final List<Rect> titleOptions = [];
  final List<Rect> menuItems = [];
  final List<Rect> slots = [];
  Rect panel = Rect.zero;

  void clear() {
    titleOptions.clear();
    menuItems.clear();
    slots.clear();
    panel = Rect.zero;
  }

  static int? indexAt(List<Rect> rects, Offset p) {
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(p)) return i;
    }
    return null;
  }
}

class _Drawable {
  _Drawable(this.key, this.draw);

  final double key;
  final void Function() draw;
}

/// Zeichnet das komplette Spiel. Alle Koordinaten sind Spielpixel; die
/// Leinwand wird vorher ganzzahlig (in Gerätepixeln) skaliert.
class GameRenderer {
  GameRenderer(this.sheet, this.image);

  final SpriteSheet sheet;
  final ui.Image image;
  final HitRegions hit = HitRegions();

  static const int _ink = 0xFF14101E;
  static const int _cream = 0xFFF4EEDC;
  static const int _gold = 0xFFF6D25A;
  static const int _muted = 0xFFA9A2C0;
  static const int _panelFill = 0xFF241C3A;
  static const int _dim = 0xA0100C1C;

  final Paint _sprite = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  final Paint _fill = Paint()..isAntiAlias = false;
  final Map<int, Paint> _tints = {};

  Paint _tint(int argb) => _tints.putIfAbsent(
    argb,
    () => Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none
      ..colorFilter = ColorFilter.mode(Color(argb), BlendMode.srcIn),
  );

  // -------------------------------------------------------------------------
  // Grundfunktionen
  // -------------------------------------------------------------------------

  void _draw(
    Canvas c,
    Sprite s,
    double x,
    double y, {
    bool flipX = false,
    bool flipY = false,
    int scale = 1,
    Paint? paint,
  }) {
    final w = s.w * scale.toDouble();
    final h = s.h * scale.toDouble();
    if (!flipX && !flipY) {
      c.drawImageRect(image, s.src, Rect.fromLTWH(x, y, w, h), paint ?? _sprite);
      return;
    }
    c.save();
    c.translate(x + (flipX ? w : 0), y + (flipY ? h : 0));
    c.scale(flipX ? -1 : 1, flipY ? -1 : 1);
    c.drawImageRect(image, s.src, Rect.fromLTWH(0, 0, w, h), paint ?? _sprite);
    c.restore();
  }

  void _rect(Canvas c, double x, double y, double w, double h, int argb) {
    _fill.color = Color(argb);
    c.drawRect(Rect.fromLTWH(x, y, w, h), _fill);
  }

  /// 1 Pixel breiter Rahmen.
  void _frame(Canvas c, double x, double y, double w, double h, int argb) {
    _rect(c, x, y, w, 1, argb);
    _rect(c, x, y + h - 1, w, 1, argb);
    _rect(c, x, y + 1, 1, h - 2, argb);
    _rect(c, x + w - 1, y + 1, 1, h - 2, argb);
  }

  /// Pixel-Kreis aus waagerechten Streifen.
  void _disc(Canvas c, double cx, double cy, int r, int argb) {
    _fill.color = Color(argb);
    for (var dy = -r; dy <= r; dy++) {
      final half = math.sqrt((r + 0.5) * (r + 0.5) - dy * dy).floorToDouble();
      c.drawRect(Rect.fromLTWH(cx - half, cy + dy, half * 2, 1), _fill);
    }
  }

  void _glyphs(Canvas c, String s, double x, double y, int argb, int scale) {
    final paint = _tint(argb);
    var cx = x;
    for (final code in s.codeUnits) {
      if (code == 0x20) {
        cx += PixelFont.spaceWidth * scale;
        continue;
      }
      final g = sheet.glyphs[code] ?? sheet.glyphs[0x3F]!;
      c.drawImageRect(
        image,
        g.src,
        Rect.fromLTWH(cx, y, g.w * scale.toDouble(), g.h * scale.toDouble()),
        paint,
      );
      cx += (g.w + 1) * scale;
    }
  }

  void _text(
    Canvas c,
    String s,
    double x,
    double y,
    int argb, {
    int scale = 1,
    bool shadow = true,
  }) {
    if (shadow) {
      _glyphs(c, s, x + scale, y + scale, _ink, scale);
    }
    _glyphs(c, s, x, y, argb, scale);
  }

  void _textCentered(
    Canvas c,
    String s,
    double centerX,
    double y,
    int argb, {
    int scale = 1,
  }) {
    final w = PixelFont.measure(s) * scale;
    _text(c, s, (centerX - w / 2).floorToDouble(), y, argb, scale: scale);
  }

  void _outlinedText(Canvas c, String s, double x, double y, int argb) {
    _glyphs(c, s, x - 1, y, _ink, 1);
    _glyphs(c, s, x + 1, y, _ink, 1);
    _glyphs(c, s, x, y - 1, _ink, 1);
    _glyphs(c, s, x, y + 1, _ink, 1);
    _glyphs(c, s, x, y, argb, 1);
  }

  void _panel(Canvas c, double x, double y, double w, double h) {
    _rect(c, x - 1, y - 1, w + 2, h + 2, _ink);
    _rect(c, x, y, w, h, _cream);
    _rect(c, x + 1, y + 1, w - 2, h - 2, 0xFF6A5A8C);
    _rect(c, x + 2, y + 2, w - 4, h - 4, _panelFill);
  }

  Sprite _itemSprite(Item item) => switch (item) {
    Item.sword => sheet.swordUp,
    Item.windBoots => sheet.itemBoots,
    Item.amulet => sheet.itemAmulet,
    Item.ruinKey => sheet.itemKey,
    Item.redBloom => sheet.herb,
    Item.apple => sheet.itemApple,
    Item.smokedFish => sheet.itemFish,
    Item.applePie => sheet.itemPie,
  };

  // -------------------------------------------------------------------------
  // Einstieg
  // -------------------------------------------------------------------------

  void render(
    Canvas canvas,
    Size size,
    double scale,
    EdgeInsets pad,
    AdventureGame g,
    TouchState touch,
  ) {
    final vw = size.width / scale;
    final vh = size.height / scale;
    final view = Size(vw, vh);
    hit.clear();

    canvas.save();
    canvas.scale(scale);
    _rect(canvas, 0, 0, vw, vh, 0xFF1C3A26);

    // Kamera
    final title = g.screen == Screen.title;
    final focusX = title ? World.playerStart.cx : g.player.x;
    final focusY = title ? World.playerStart.cy - 24 : g.player.y - 4;
    const worldW = World.w * World.tile * 1.0;
    const worldH = World.h * World.tile * 1.0;
    double camX = vw >= worldW
        ? (worldW - vw) / 2
        : (focusX - vw / 2).clamp(0.0, worldW - vw).toDouble();
    double camY = vh >= worldH
        ? (worldH - vh) / 2
        : (focusY - vh / 2).clamp(0.0, worldH - vh).toDouble();
    if (g.shake > 0) {
      camX += ((g.time * 60).floor().isEven ? 1 : -1);
      camY += ((g.time * 45).floor().isEven ? 1 : -1);
    }
    camX = camX.roundToDouble();
    camY = camY.roundToDouble();

    canvas.save();
    canvas.translate(-camX, -camY);
    _drawWorld(canvas, g, camX, camY, vw, vh);
    canvas.restore();

    switch (g.screen) {
      case Screen.title:
        _drawTitle(canvas, g, view, touch);
      case Screen.playing:
        _drawHud(canvas, g, view, pad, touch);
        switch (g.panel) {
          case Panel.none:
            break;
          case Panel.questLog:
            _drawQuestLog(canvas, g, view);
          case Panel.inventory:
            _drawInventory(canvas, g, view, touch);
          case Panel.menu:
            _drawMenu(canvas, g, view);
        }
        if (g.dialog != null) _drawDialog(canvas, g, view, pad);
      case Screen.ending:
        _drawEnding(canvas, g, view, touch);
    }
    _drawToasts(canvas, g, view, pad);
    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Welt
  // -------------------------------------------------------------------------

  Sprite _groundSprite(World wd, int i, int waterFrame) =>
      switch (wd.ground[i]) {
        Ground.grass => sheet.grass[wd.variant[i]],
        Ground.path => sheet.path,
        Ground.sand => sheet.sand,
        Ground.water => sheet.water[waterFrame],
        Ground.stone => sheet.stoneFloor,
        Ground.field => sheet.field,
        Ground.pier => sheet.pier,
      };

  Sprite? _objSprite(Obj o) => switch (o) {
    Obj.rock => sheet.rock,
    Obj.bush => sheet.bush,
    Obj.fence => sheet.fence,
    Obj.sign => sheet.sign,
    Obj.well => sheet.well,
    Obj.chestClosed => sheet.chestClosed,
    Obj.chestOpen => sheet.chestOpen,
    Obj.gateClosed => sheet.gateClosed,
    Obj.gateOpen => sheet.gateOpen,
    Obj.ruinWall => sheet.ruinWall,
    Obj.pillar => sheet.pillar,
    Obj.stump => sheet.stump,
    Obj.anvil => sheet.anvil,
    Obj.none || Obj.tree || Obj.building => null,
  };

  void _drawWorld(
    Canvas c,
    AdventureGame g,
    double camX,
    double camY,
    double vw,
    double vh,
  ) {
    final wd = g.world;
    const ts = World.tile;
    final tx0 = math.max(0, (camX / ts).floor());
    final ty0 = math.max(0, (camY / ts).floor());
    final tx1 = math.min(World.w - 1, ((camX + vw) / ts).floor());
    final ty1 = math.min(World.h - 1, ((camY + vh) / ts).floor());
    final waterFrame = (g.time * 1.6).floor() % 2;

    // Boden
    for (var ty = ty0; ty <= ty1; ty++) {
      for (var tx = tx0; tx <= tx1; tx++) {
        final i = wd.index(tx, ty);
        _draw(c, _groundSprite(wd, i, waterFrame), tx * 16.0, ty * 16.0);
      }
    }

    // Ufer und flache Objekte
    bool water(int tx, int ty) =>
        wd.inBounds(tx, ty) && wd.ground[wd.index(tx, ty)] == Ground.water;
    for (var ty = ty0; ty <= ty1; ty++) {
      for (var tx = tx0; tx <= tx1; tx++) {
        final i = wd.index(tx, ty);
        final x = tx * 16.0;
        final y = ty * 16.0;
        if (wd.ground[i] == Ground.water) {
          if (!water(tx, ty - 1)) {
            _rect(c, x, y, 16, 3, Pal.waterDeep);
            _rect(c, x, y + 3, 16, 1, Pal.waterDark);
          }
          if (!water(tx, ty + 1)) _rect(c, x, y + 15, 16, 1, Pal.foam);
          if (!water(tx - 1, ty)) _rect(c, x, y, 1, 16, Pal.foam);
          if (!water(tx + 1, ty)) _rect(c, x + 15, y, 1, 16, Pal.foam);
        }
        final s = _objSprite(wd.obj[i]);
        if (s != null) _draw(c, s, x, y);
      }
    }

    // Fundstücke liegen flach am Boden.
    final herbsActive = g.quest(QuestId.herbs).isActive;
    for (final h in g.herbs) {
      if (h.taken) continue;
      _draw(c, sheet.herb, h.x - 8, h.y - 8);
      if (herbsActive) {
        final phase = ((g.time * 3 + h.x) % 3).floor();
        if (phase == 0) _rect(c, h.x + 3, h.y - 6, 1, 1, Pal.white);
        if (phase == 1) _rect(c, h.x - 5, h.y - 2, 1, 1, Pal.white);
      }
    }
    for (final a in g.apples) {
      if (a.taken) continue;
      _rect(c, a.x - 4, a.y + 4, 8, 2, 0x38000000);
      _draw(c, sheet.itemApple, a.x - 8, a.y - 9);
    }

    // Alles Aufrechte nach Tiefe sortiert.
    final list = <_Drawable>[];
    for (var ty = ty0; ty <= math.min(World.h - 1, ty1 + 2); ty++) {
      for (var tx = math.max(0, tx0 - 1);
          tx <= math.min(World.w - 1, tx1 + 1);
          tx++) {
        final i = wd.index(tx, ty);
        if (wd.obj[i] != Obj.tree) continue;
        final s = sheet.trees[wd.variant[i] == 2 ? 1 : 0];
        final x = tx * 16.0 - 4;
        final y = ty * 16.0 - 16;
        list.add(_Drawable(ty * 16.0 + 14, () => _draw(c, s, x, y)));
      }
    }
    for (final h in wd.houses) {
      final x = h.tx * 16.0;
      final y = h.ty * 16.0;
      list.add(
        _Drawable(
          y + House.tilesHigh * 16 - 1,
          () => _draw(c, sheet.houses[h.style], x, y),
        ),
      );
    }
    for (final n in g.npcs) {
      list.add(_Drawable(n.y, () => _drawNpc(c, g, n)));
    }
    for (final ch in g.chickens) {
      list.add(_Drawable(ch.y, () => _drawChicken(c, g, ch)));
    }
    for (final s in g.slimes) {
      if (s.alive) list.add(_Drawable(s.y, () => _drawSlime(c, g, s)));
    }
    if (g.screen != Screen.title) {
      list.add(_Drawable(g.player.y, () => _drawPlayer(c, g)));
    }
    list.sort((a, b) => a.key.compareTo(b.key));
    for (final d in list) {
      d.draw();
    }

    // Quest-Markierungen über den Köpfen.
    final bob = (math.sin(g.time * 4) * 1.5).roundToDouble();
    for (final n in g.npcs) {
      final mark = g.markerFor(n);
      if (mark.isEmpty) continue;
      final w = PixelFont.measure(mark);
      _outlinedText(
        c,
        mark,
        (n.x - w / 2).roundToDouble(),
        n.y.roundToDouble() - 23 + bob,
        _gold,
      );
    }
  }

  void _shadow(Canvas c, double x, double y) {
    _rect(c, x - 5, y + 2, 10, 2, 0x38000000);
    _rect(c, x - 3, y + 1, 6, 1, 0x38000000);
    _rect(c, x - 3, y + 4, 6, 1, 0x38000000);
  }

  Sprite _npcSprite(NpcId id) => switch (id) {
    NpcId.hilda => sheet.hilda,
    NpcId.bruno => sheet.bruno,
    NpcId.marta => sheet.marta,
    NpcId.elsa => sheet.elsa,
    NpcId.otto => sheet.otto,
  };

  void _drawNpc(Canvas c, AdventureGame g, Npc n) {
    final x = n.x.roundToDouble();
    final y = n.y.roundToDouble();
    _shadow(c, x, y);
    _draw(c, _npcSprite(n.id), x - 8, y - 12);
  }

  void _drawChicken(Canvas c, AdventureGame g, Chicken ch) {
    final x = ch.x.roundToDouble();
    final y = ch.y.roundToDouble();
    final moving = ch.vx != 0 || ch.vy != 0;
    final frame = moving ? (ch.anim * 9).floor() % 2 : 0;
    _rect(c, x - 4, y + 2, 8, 2, 0x38000000);
    _draw(
      c,
      sheet.chicken[frame],
      x - 8,
      y - 12 - (moving && frame == 1 ? 1 : 0),
      flipX: ch.faceLeft,
    );
  }

  void _drawSlime(Canvas c, AdventureGame g, Slime s) {
    final x = s.x.roundToDouble();
    final y = s.y.roundToDouble();
    final hop = g.slimeHopHeight(s).roundToDouble();
    _rect(c, x - 5, y + 2, 10, 2, 0x38000000);
    _draw(
      c,
      sheet.slime,
      x - 8,
      y - 12 - hop,
      paint: s.hurt > 0 ? _tint(0xFFFFFFFF) : null,
    );
  }

  void _drawPlayer(Canvas c, AdventureGame g) {
    final p = g.player;
    final x = p.x.roundToDouble();
    final y = p.y.roundToDouble();
    _shadow(c, x, y);

    // Blinken, solange der Held nach einem Treffer unverwundbar ist.
    final hidden = p.invulnerable > 0 && (g.time * 14).floor().isOdd;
    final step = p.moving ? (p.walkTime * 7).floor() % 4 : 0;
    final frame = step.isOdd ? 1 : 0;
    final sx = x - 8;
    final sy = y - 12 - (frame == 1 ? 1 : 0);

    final attacking = p.attackTime > 0;
    final reach =
        attacking
            ? (5 +
                      math.sin(
                            (1 - p.attackTime / Player.attackDuration) *
                                math.pi,
                          ) *
                          6)
                  .roundToDouble()
            : 0.0;

    if (attacking && p.dir == Dir.up) {
      _draw(c, sheet.swordUp, sx + 3, sy - reach - 4);
    }
    if (!hidden) {
      switch (p.dir) {
        case Dir.down:
          _draw(c, sheet.heroDown[frame], sx, sy, flipX: step == 3);
        case Dir.up:
          _draw(c, sheet.heroUp[frame], sx, sy, flipX: step == 3);
        case Dir.right:
          _draw(c, sheet.heroSide[frame], sx, sy);
        case Dir.left:
          _draw(c, sheet.heroSide[frame], sx, sy, flipX: true);
      }
    }
    if (attacking) {
      switch (p.dir) {
        case Dir.up:
          break;
        case Dir.down:
          _draw(c, sheet.swordUp, sx - 3, sy + reach + 2, flipY: true);
        case Dir.right:
          _draw(c, sheet.swordRight, sx + reach + 2, sy + 3);
        case Dir.left:
          _draw(c, sheet.swordRight, sx - reach - 2, sy + 3, flipX: true);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Anzeige am Bildschirmrand
  // -------------------------------------------------------------------------

  void _hudButton(Canvas c, Rect r, bool active) {
    _rect(c, r.left - 1, r.top - 1, r.width + 2, r.height + 2, _ink);
    _rect(c, r.left, r.top, r.width, r.height, active ? _gold : _cream);
    _rect(c, r.left + 1, r.top + 1, r.width - 2, r.height - 2, 0xFF3A2E5C);
  }

  void _drawHud(
    Canvas c,
    AdventureGame g,
    Size view,
    EdgeInsets pad,
    TouchState touch,
  ) {
    final p = g.player;
    final left = pad.left + 4;
    var y = pad.top + 4;

    for (var i = 0; i < p.maxHearts; i++) {
      _draw(c, i < p.hearts ? sheet.heartFull : sheet.heartEmpty, left + i * 10, y);
    }
    y += 12;

    for (final q in g.quests.values) {
      if (!q.isActive && !q.isReady) continue;
      _text(c, g.trackerLine(q), left, y, q.isReady ? _gold : _cream);
      y += PixelFont.lineHeight;
    }

    // Knöpfe: Inventar, Questbuch, Pause
    final bag = UiLayout.bagButton(view, pad);
    _hudButton(c, bag, g.panel == Panel.inventory);
    _draw(c, sheet.iconBag, bag.left + 3, bag.top + 5);

    final log = UiLayout.logButton(view, pad);
    _hudButton(c, log, g.panel == Panel.questLog);
    for (var i = 0; i < 3; i++) {
      _rect(c, log.left + 4, log.top + 5 + i * 4, 2, 1, _gold);
      _rect(c, log.left + 7, log.top + 5 + i * 4, 7, 1, _cream);
    }

    final menu = UiLayout.menuButton(view, pad);
    _hudButton(c, menu, g.panel == Panel.menu);
    _rect(c, menu.left + 5, menu.top + 5, 3, 8, _cream);
    _rect(c, menu.left + 10, menu.top + 5, 3, 8, _cream);

    // Touch-Steuerung
    if (touch.visible && g.dialog == null && g.panel == Panel.none) {
      final ac = UiLayout.actionCenter(view, pad);
      _disc(c, ac.dx, ac.dy, UiLayout.actionRadius.toInt(), 0x50FFFFFF);
      _disc(c, ac.dx, ac.dy, UiLayout.actionRadius.toInt() - 3, 0x40241C3A);
      _text(c, 'A', ac.dx - 5, ac.dy - 7, _cream, scale: 2);

      final active = touch.pointer != null;
      final base = active ? touch.base : UiLayout.stickHome(view, pad);
      var knob = base;
      if (active) {
        final d = touch.pos - touch.base;
        final len = d.distance;
        knob = len > 14 ? touch.base + d / len * 14 : touch.pos;
      }
      _disc(c, base.dx.roundToDouble(), base.dy.roundToDouble(), 18, 0x38FFFFFF);
      _disc(c, knob.dx.roundToDouble(), knob.dy.roundToDouble(), 8, 0x80FFFFFF);
    }
  }

  void _drawToasts(Canvas c, AdventureGame g, Size view, EdgeInsets pad) {
    var ty = pad.top + 26;
    for (final t in g.toasts) {
      final w = PixelFont.measure(t.text) + 10.0;
      final x = ((view.width - w) / 2).floorToDouble();
      _rect(c, x - 1, ty - 1, w + 2, 15, _ink);
      _rect(c, x, ty, w, 13, 0xF0241C3A);
      _text(c, t.text, x + 5, ty + 3, _gold, shadow: false);
      ty += 17;
    }
  }

  void _drawDialog(Canvas c, AdventureGame g, Size view, EdgeInsets pad) {
    final d = g.dialog!;
    final page = d.page;
    final bw = math
        .min(view.width - pad.left - pad.right - 10, 264.0)
        .floorToDouble();
    final lines = PixelFont.wrap(page.text, bw.toInt() - 16);
    final hasName = page.speaker.isNotEmpty;
    final bh = 12.0 + (hasName ? 12 : 0) + lines.length * PixelFont.lineHeight;
    final bx = ((view.width - bw) / 2).floorToDouble();
    final by = (view.height - pad.bottom - bh - 6).floorToDouble();

    _panel(c, bx, by, bw, bh);
    var y = by + 7;
    if (hasName) {
      _text(c, page.speaker, bx + 8, y, _gold);
      y += 12;
    }
    var remaining = d.shown.floor();
    for (final line in lines) {
      if (remaining <= 0) break;
      final visible = remaining >= line.length
          ? line
          : line.substring(0, remaining);
      _text(c, visible, bx + 8, y, _cream);
      remaining -= line.length + 1;
      y += PixelFont.lineHeight;
    }

    if (d.pageComplete && (g.time * 3).floor().isEven) {
      final ax = bx + bw - 12;
      final ay = by + bh - 8;
      _rect(c, ax, ay, 5, 1, _gold);
      _rect(c, ax + 1, ay + 1, 3, 1, _gold);
      _rect(c, ax + 2, ay + 2, 1, 1, _gold);
    }
  }

  void _drawQuestLog(Canvas c, AdventureGame g, Size view) {
    _rect(c, 0, 0, view.width, view.height, _dim);
    final bw = math.min(view.width - 12, 250.0).floorToDouble();
    final textW = bw.toInt() - 26;

    final known = g.quests.values.where((q) => q.discovered).toList();
    final blocks = <(Quest, List<String>)>[
      for (final q in known) (q, PixelFont.wrap(g.objective(q), textW)),
    ];
    var bh = 30.0 + 14;
    if (blocks.isEmpty) {
      bh += 24;
    } else {
      for (final b in blocks) {
        bh += 12 + b.$2.length * PixelFont.lineHeight + 5;
      }
    }
    final bx = ((view.width - bw) / 2).floorToDouble();
    final by = math.max(4.0, ((view.height - bh) / 2).floorToDouble());
    _panel(c, bx, by, bw, bh);

    _textCentered(c, 'Questbuch', view.width / 2, by + 8, _gold, scale: 2);
    var y = by + 30;
    if (blocks.isEmpty) {
      for (final line in PixelFont.wrap(
        'Noch keine Quests. Sprich mit den Dorfbewohnern!',
        textW,
      )) {
        _text(c, line, bx + 10, y, _cream);
        y += PixelFont.lineHeight;
      }
    }
    for (final (q, lines) in blocks) {
      final color = q.isDone ? _muted : (q.isReady ? _gold : _cream);
      // Kästchen mit Haken
      _rect(c, bx + 9, y, 7, 7, color);
      _rect(c, bx + 10, y + 1, 5, 5, _panelFill);
      if (q.isDone) {
        _rect(c, bx + 11, y + 3, 1, 2, _gold);
        _rect(c, bx + 12, y + 4, 1, 1, _gold);
        _rect(c, bx + 13, y + 2, 1, 2, _gold);
      }
      _text(c, q.title, bx + 20, y, color);
      y += 12;
      for (final line in lines) {
        _text(c, line, bx + 20, y, _muted, shadow: false);
        y += PixelFont.lineHeight;
      }
      y += 5;
    }
    _textCentered(
      c,
      'Fertig: ${g.questsDone}/${g.quests.length}',
      view.width / 2,
      by + bh - 13,
      _muted,
    );
  }

  // -------------------------------------------------------------------------
  // Inventar
  // -------------------------------------------------------------------------

  static const double _slotSize = 20;
  static const double _slotPitch = 22;
  static const double _equipGap = 9;

  String _inventoryHint(AdventureGame g, TouchState touch, {int? state}) {
    // state: 0 = Gegenstand in der Hand, 1 = Gegenstand markiert, 2 = leer
    final s =
        state ??
        (g.invHeld != null
            ? 0
            : (g.inventory.slots[g.invCursor] != null ? 1 : 2));
    return switch (s) {
      0 => 'Anderes Feld: verschieben. Gleiches Feld: benutzen.',
      1 =>
        touch.visible
            ? 'Antippen: aufnehmen. Ziehen: verschieben.'
            : 'Aktion: aufnehmen. Dann das Zielfeld wählen.',
      _ =>
        touch.visible
            ? 'Tippe auf einen Gegenstand.'
            : 'Wähle einen Gegenstand mit den Pfeiltasten.',
    };
  }

  void _drawInventory(
    Canvas c,
    AdventureGame g,
    Size view,
    TouchState touch,
  ) {
    _rect(c, 0, 0, view.width, view.height, _dim);
    final inv = g.inventory;

    const gridW =
        _slotSize + _equipGap + Inventory.bagColumns * _slotPitch - 2;
    const gridH = Inventory.bagRows * _slotPitch - 2;
    final bw = math.min(view.width - 8, 216.0).floorToDouble();
    final textW = bw.toInt() - 18;

    // Feste Höhe, damit das Fenster beim Blättern nicht springt.
    var descLines = 1;
    for (final item in Item.values) {
      descLines = math.max(
        descLines,
        PixelFont.wrap(item.description, textW).length,
      );
    }
    var hintLines = 1;
    for (var s = 0; s < 3; s++) {
      hintLines = math.max(
        hintLines,
        PixelFont.wrap(_inventoryHint(g, touch, state: s), textW).length,
      );
    }
    final bh =
        8.0 +
        10 +
        5 +
        gridH +
        6 +
        11 +
        descLines * PixelFont.lineHeight +
        3 +
        hintLines * PixelFont.lineHeight +
        5;
    final bx = ((view.width - bw) / 2).floorToDouble();
    final by = math.max(2.0, ((view.height - bh) / 2).floorToDouble());
    _panel(c, bx, by, bw, bh);
    hit.panel = Rect.fromLTWH(bx, by, bw, bh);

    _text(c, 'Inventar', bx + 9, by + 7, _gold);
    final gx = bx + ((bw - gridW) / 2).floorToDouble();
    final gy = by + 23;

    // Trennlinie zwischen Ausrüstung und Rucksack
    _rect(c, gx + _slotSize + 4, gy, 1, gridH, 0xFF6A5A8C);

    final ghosts = [sheet.swordUp, sheet.itemBoots, sheet.itemAmulet];
    Rect? cursorRect;
    for (var i = 0; i < Inventory.size; i++) {
      final column = AdventureGame.slotColumn(i);
      final row = AdventureGame.slotRow(i);
      final x = column == 0
          ? gx
          : gx + _slotSize + _equipGap + (column - 1) * _slotPitch;
      final y = gy + row * _slotPitch;
      final rect = Rect.fromLTWH(x, y, _slotSize, _slotSize);
      hit.slots.add(rect);
      if (i == g.invCursor) cursorRect = rect;

      final equip = Inventory.isEquipSlot(i);
      _rect(c, x, y, _slotSize, _slotSize, equip ? 0xFFB8963C : 0xFF6A5A8C);
      _rect(c, x + 1, y + 1, _slotSize - 2, _slotSize - 2, 0xFF1A1430);

      final stack = inv.slots[i];
      if (stack == null) {
        if (equip) _draw(c, ghosts[i], x + 2, y + 2, paint: _tint(0xFF3A2E5C));
        continue;
      }
      final sprite = _itemSprite(stack.item);
      if (i == g.invHeld) {
        // Der Gegenstand ist "in der Hand" – hier bleibt nur ein Schatten.
        _draw(c, sprite, x + 2, y + 2, paint: _tint(0xFF4A3E6C));
        continue;
      }
      _draw(c, sprite, x + 2, y + 2);
      if (stack.count > 1) {
        final label = '${stack.count}';
        _outlinedText(
          c,
          label,
          x + _slotSize - 2 - PixelFont.measure(label),
          y + 11,
          _cream,
        );
      }
    }

    if (cursorRect != null) {
      _frame(
        c,
        cursorRect.left - 1,
        cursorRect.top - 1,
        _slotSize + 2,
        _slotSize + 2,
        (g.time * 3).floor().isEven ? _cream : _gold,
      );
    }

    // Gegenstand in der Hand: am Mauszeiger/Finger oder über dem Cursor.
    final held = g.invHeld;
    final heldStack = held == null ? null : inv.slots[held];
    if (heldStack != null) {
      final drag = touch.dragPos;
      final hx = drag != null
          ? (drag.dx - 8).roundToDouble()
          : (cursorRect?.left ?? 0) + 2;
      final hy = drag != null
          ? (drag.dy - 10).roundToDouble()
          : (cursorRect?.top ?? 0) - 3;
      _rect(c, hx + 2, hy + 15, 12, 2, 0x50000000);
      _draw(c, _itemSprite(heldStack.item), hx, hy);
    }

    // Beschreibung
    final focus = held ?? g.invCursor;
    final shown = inv.slots[focus];
    var y = gy + gridH + 6;
    if (shown != null) {
      final name = shown.count > 1
          ? '${shown.item.label} x${shown.count}'
          : shown.item.label;
      _text(c, name, bx + 9, y, _gold);
      y += 11;
      for (final line in PixelFont.wrap(shown.item.description, textW)) {
        _text(c, line, bx + 9, y, _cream, shadow: false);
        y += PixelFont.lineHeight;
      }
    } else {
      final label = Inventory.isEquipSlot(focus)
          ? '${Inventory.equipLabels[focus]}: leer'
          : 'Leeres Feld';
      _text(c, label, bx + 9, y, _muted);
    }

    var hintY = by + bh - 5 - hintLines * PixelFont.lineHeight;
    for (final line in PixelFont.wrap(_inventoryHint(g, touch), textW)) {
      _text(c, line, bx + 9, hintY, _muted, shadow: false);
      hintY += PixelFont.lineHeight;
    }
  }

  // -------------------------------------------------------------------------
  // Pause-Menü
  // -------------------------------------------------------------------------

  void _optionRow(
    Canvas c,
    String label,
    double centerX,
    double y,
    double width,
    bool selected,
    List<Rect> regions,
  ) {
    final rect = Rect.fromLTWH(
      (centerX - width / 2).floorToDouble(),
      y - 3,
      width,
      13,
    );
    regions.add(rect);
    if (selected) {
      _rect(c, rect.left, rect.top, rect.width, rect.height, 0xFF4A3E7A);
      _text(c, '>', rect.left + 4, y, _gold);
    }
    _textCentered(c, label, centerX, y, selected ? _gold : _cream);
  }

  void _drawMenu(Canvas c, AdventureGame g, Size view) {
    _rect(c, 0, 0, view.width, view.height, _dim);
    const entries = MenuEntry.values;
    final bw = math.min(view.width - 12, 136.0).floorToDouble();
    final bh = 32.0 + entries.length * 15 + 5;
    final bx = ((view.width - bw) / 2).floorToDouble();
    final by = math.max(2.0, ((view.height - bh) / 2).floorToDouble());
    _panel(c, bx, by, bw, bh);
    hit.panel = Rect.fromLTWH(bx, by, bw, bh);

    final cx = view.width / 2;
    _textCentered(c, 'Pause', cx, by + 8, _gold, scale: 2);
    var y = by + 33;
    for (var i = 0; i < entries.length; i++) {
      _optionRow(
        c,
        g.menuLabel(entries[i]),
        cx,
        y,
        bw - 10,
        i == g.menuIndex,
        hit.menuItems,
      );
      y += 15;
    }
  }

  // -------------------------------------------------------------------------
  // Titel und Abspann
  // -------------------------------------------------------------------------

  void _drawTitle(Canvas c, AdventureGame g, Size view, TouchState touch) {
    _rect(c, 0, 0, view.width, view.height, 0x9C100C1C);
    final cx = view.width / 2;
    final big = view.width >= 230 ? 3 : 2;
    final options = g.titleOptions;
    final roomy = view.height >= (options.isEmpty ? 190 : 215);
    final heroScale = roomy ? 4 : 3;
    final help = PixelFont.wrap(
      touch.visible
          ? 'Links ziehen: laufen. Rechts tippen: Aktion.'
          : 'Laufen: WASD/Pfeile. Aktion: Leertaste. Inventar: I. '
                'Quests: Q. Pause: Esc. Musik: M.',
      view.width.toInt() - 20,
    );
    final choiceH = options.isEmpty ? 20.0 : options.length * 15.0 + 6;

    final total =
        8.0 * big + 8 + 18 + 16 * heroScale + 10 + choiceH +
        help.length * PixelFont.lineHeight;
    var y = math.max(4.0, ((view.height - total) / 2).floorToDouble());

    _textCentered(c, 'EICHENHAIN', cx, y, _gold, scale: big);
    y += 8.0 * big + 8;
    _textCentered(c, 'Ein kleines Pixel-Abenteuer', cx, y, _cream);
    y += 18;

    final hw = 16.0 * heroScale;
    final bob = (math.sin(g.time * 2.5) * 1.5).roundToDouble();
    _draw(
      c,
      sheet.heroDown[0],
      (cx - hw / 2).floorToDouble(),
      y + bob,
      scale: heroScale,
    );
    y += hw + 10;

    if (options.isEmpty) {
      if ((g.time * 2).floor().isEven) {
        _textCentered(
          c,
          touch.visible ? 'Tippen zum Starten' : 'Leertaste oder Klick: Start',
          cx,
          y,
          _gold,
        );
      }
    } else {
      final width = math.min(view.width - 16, 150.0);
      for (var i = 0; i < options.length; i++) {
        _optionRow(
          c,
          options[i],
          cx,
          y + i * 15,
          width,
          i == g.titleIndex,
          hit.titleOptions,
        );
      }
    }
    y += choiceH;
    for (final line in help) {
      _textCentered(c, line, cx, y, _muted);
      y += PixelFont.lineHeight;
    }
  }

  void _drawEnding(Canvas c, AdventureGame g, Size view, TouchState touch) {
    _rect(c, 0, 0, view.width, view.height, 0xB4100C1C);
    final cx = view.width / 2;
    final big = view.width >= 200 ? 2 : 1;
    final lines = PixelFont.wrap(
      'Das Amulett ist zurück, und Eichenhain ist wieder sicher.',
      view.width.toInt() - 24,
    );
    final total =
        8.0 * big + 12 + lines.length * PixelFont.lineHeight + 8 + 10 + 16 + 10;
    var y = math.max(6.0, ((view.height - total) / 2).floorToDouble());

    _textCentered(c, 'Danke fürs Spielen!', cx, y, _gold, scale: big);
    y += 8.0 * big + 12;
    for (final line in lines) {
      _textCentered(c, line, cx, y, _cream);
      y += PixelFont.lineHeight;
    }
    y += 8;
    _textCentered(
      c,
      'Quests geschafft: ${g.questsDone}/${g.quests.length}',
      cx,
      y,
      _cream,
    );
    y += 26;
    if ((g.time * 2).floor().isEven) {
      _textCentered(
        c,
        touch.visible ? 'Tippen: weiterspielen' : 'Leertaste: weiterspielen',
        cx,
        y,
        _gold,
      );
    }
  }
}
