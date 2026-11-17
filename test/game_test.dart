import 'dart:collection';
import 'dart:convert';

import 'package:flutter_game/game/entities.dart';
import 'package:flutter_game/game/game.dart';
import 'package:flutter_game/game/items.dart';
import 'package:flutter_game/game/pixel_font.dart';
import 'package:flutter_game/game/quests.dart';
import 'package:flutter_game/game/sprites.dart';
import 'package:flutter_game/game/world.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alle begehbaren Kacheln, die vom Startpunkt aus erreichbar sind.
Set<int> reachable(World world) {
  final seen = <int>{};
  final queue = Queue<TilePos>()..add(World.playerStart);
  seen.add(world.index(World.playerStart.tx, World.playerStart.ty));
  while (queue.isNotEmpty) {
    final p = queue.removeFirst();
    for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = p.tx + d.$1;
      final ny = p.ty + d.$2;
      if (world.solid(nx, ny)) continue;
      if (seen.add(world.index(nx, ny))) queue.add(TilePos(nx, ny));
    }
  }
  return seen;
}

AdventureGame playing() => AdventureGame()
  ..started = true
  ..screen = Screen.playing;

Npc npc(AdventureGame game, NpcId id) =>
    game.npcs.firstWhere((n) => n.id == id);

void talk(AdventureGame game, NpcId id) {
  game.talkTo(npc(game, id));
  expect(game.dialog, isNotNull);
  game.finishDialog();
}

void main() {
  test('Sprite-Atlas lässt sich vollständig aufbauen', () {
    final sheet = SpriteSheet();
    expect(sheet.heroDown, hasLength(2));
    expect(sheet.glyphs.length, PixelFont.glyphs.length);
    // Der Held hat braune Haare.
    final hero = sheet.heroDown.first;
    expect(sheet.atlas.get(hero.x + 7, hero.y + 4), Pal.heroHair);
  });

  test('Pixel-Schrift kennt deutsche Sonderzeichen und bricht um', () {
    expect(PixelFont.supports('Grüße aus Eichenhain: Äpfel, Öl, Übung!'), true);
    final lines = PixelFont.wrap('Ein kleines Abenteuer im Dorf', 60);
    expect(lines.length, greaterThan(1));
    for (final l in lines) {
      expect(PixelFont.measure(l), lessThanOrEqualTo(60));
    }
    for (final item in Item.values) {
      expect(PixelFont.supports(item.label), true, reason: item.name);
      expect(PixelFont.supports(item.description), true, reason: item.name);
    }
    for (final label in Inventory.equipLabels) {
      expect(PixelFont.supports(label), true);
    }
  });

  test('Alle Questziele der Welt sind erreichbar', () {
    final world = World.generate();
    world.openGates();
    final seen = reachable(world);

    bool at(TilePos p) => seen.contains(world.index(p.tx, p.ty));
    bool nextTo(TilePos p) =>
        at(TilePos(p.tx + 1, p.ty)) ||
        at(TilePos(p.tx - 1, p.ty)) ||
        at(TilePos(p.tx, p.ty + 1)) ||
        at(TilePos(p.tx, p.ty - 1));

    for (final p in [
      ...World.chickenSpawns,
      ...World.herbSpawns,
      ...World.appleSpawns,
      ...World.forestSlimes,
      ...World.ruinSlimes,
      World.respawnPoint,
    ]) {
      expect(at(p), true, reason: 'Kachel ${p.tx},${p.ty} nicht erreichbar');
    }
    for (final p in [
      World.hildaPos,
      World.brunoPos,
      World.martaPos,
      World.elsaPos,
      World.ottoPos,
      World.chestPos,
    ]) {
      expect(world.solid(p.tx, p.ty) || at(p), true);
      expect(nextTo(p), true, reason: '${p.tx},${p.ty} nicht ansprechbar');
    }
    // Gehegeplätze sind frei, aber vom Zaun umschlossen.
    for (final p in World.penSpots) {
      expect(world.solid(p.tx, p.ty), false);
      expect(at(p), false);
    }
  });

  test('Die Ruine ist ohne Schlüssel verschlossen', () {
    final world = World.generate();
    final seen = reachable(world);
    expect(seen.contains(world.index(22, 5)), false);
  });

  test('Der Held läuft und bleibt an Hindernissen hängen', () {
    final game = playing();
    final input = GameInput()..moveX = 1;
    final startX = game.player.x;
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60, input);
    }
    expect(game.player.x, greaterThan(startX + 20));
    expect(game.player.dir, Dir.right);

    // Minutenlang nach Norden laufen: irgendwann ist Schluss.
    input
      ..moveX = 0
      ..moveY = -1;
    for (var i = 0; i < 60 * 30; i++) {
      game.update(1 / 60, input);
    }
    final tx = (game.player.x / World.tile).floor();
    final ty = (game.player.y / World.tile).floor();
    expect(game.world.solid(tx, ty), false);
    expect(game.player.y, greaterThan(9 * World.tile));
  });

  test('Kompletter Questverlauf bis zum Abspann', () {
    final game = playing();

    // Hauptquest annehmen.
    expect(game.markerFor(npc(game, NpcId.hilda)), '!');
    talk(game, NpcId.hilda);
    expect(game.quest(QuestId.amulet).isActive, true);

    // Bruno: Schwert (gleich ausgerüstet), Schleime, Schlüssel.
    talk(game, NpcId.bruno);
    expect(game.hasSword, true);
    expect(game.inventory.isEquipped(Item.sword), true);
    for (final s in game.slimes.take(4)) {
      game.hitSlime(s);
      game.hitSlime(s);
    }
    expect(game.quest(QuestId.slimes).isReady, true);
    expect(game.markerFor(npc(game, NpcId.bruno)), '?');
    talk(game, NpcId.bruno);
    expect(game.hasKey, true);
    expect(game.quest(QuestId.slimes).isDone, true);

    // Marta: Hühner einfangen gibt ein Herz und einen Kuchen.
    talk(game, NpcId.marta);
    for (final c in game.chickens) {
      game.catchChicken(c);
    }
    expect(game.chickens.every((c) => c.home), true);
    talk(game, NpcId.marta);
    expect(game.player.maxHearts, 4);
    expect(game.inventory.has(Item.applePie), true);

    // Elsa: Rotblüten landen im Rucksack und werden gegen Stiefel getauscht.
    talk(game, NpcId.elsa);
    for (final h in game.herbs) {
      game.collectHerb(h);
    }
    expect(game.inventory.count(Item.redBloom), 3);
    talk(game, NpcId.elsa);
    expect(game.inventory.count(Item.redBloom), 0);
    expect(game.swift, true);

    // Otto schenkt beim ersten Gespräch einen Fisch.
    talk(game, NpcId.otto);
    expect(game.inventory.count(Item.smokedFish), 1);
    talk(game, NpcId.otto);
    expect(game.inventory.count(Item.smokedFish), 1);

    // Tor öffnen, Amulett holen, abgeben.
    expect(game.useTile(22, 9), true);
    game.finishDialog();
    expect(game.gateOpen, true);
    expect(game.world.solid(22, 9), false);
    expect(game.useTile(World.chestPos.tx, World.chestPos.ty), true);
    game.finishDialog();
    expect(game.hasAmulet, true);
    expect(game.markerFor(npc(game, NpcId.hilda)), '?');
    talk(game, NpcId.hilda);

    expect(game.questsDone, 4);
    expect(game.screen, Screen.ending);
    expect(game.inventory.isEquipped(Item.amulet), true);
    for (final q in game.quests.values) {
      expect(PixelFont.supports(game.objective(q)), true);
    }
  });

  test('Schleime verletzen den Helden, der Brunnen heilt', () {
    final game = playing();
    final slime = game.slimes.first;
    game.player
      ..x = slime.x
      ..y = slime.y + 6;
    game.update(1 / 60, GameInput());
    expect(game.player.hearts, 2);

    expect(game.useTile(20, 16), true);
    game.finishDialog();
    expect(game.player.hearts, game.player.maxHearts);
  });

  group('Inventar', () {
    const bag0 = Inventory.equipSlots;

    test('stapelt, rüstet aus und entfernt', () {
      final inv = Inventory();
      expect(inv.add(Item.apple, count: 3), 0);
      expect(inv.slots[bag0]!.count, 3);
      expect(inv.add(Item.sword), 0);
      expect(inv.slots[0]!.item, Item.sword); // direkt im Waffenfeld
      expect(inv.isEquipped(Item.sword), true);
      expect(inv.remove(Item.apple, 2), 2);
      expect(inv.count(Item.apple), 1);
      // Stapelgrenze: 9 pro Feld, der Rest wandert ins nächste Feld.
      expect(inv.add(Item.apple, count: 10), 0);
      expect(inv.slots[bag0]!.count, 9);
      expect(inv.slots[bag0 + 1]!.count, 2);
    });

    test('verschiebt, tauscht und lehnt falsche Felder ab', () {
      final inv = Inventory()
        ..add(Item.sword)
        ..add(Item.apple)
        ..add(Item.ruinKey);
      // Apfel (Feld 3) und Schlüssel (Feld 4) tauschen.
      expect(inv.move(bag0, bag0 + 1), true);
      expect(inv.slots[bag0]!.item, Item.ruinKey);
      expect(inv.slots[bag0 + 1]!.item, Item.apple);
      // In ein leeres Feld verschieben.
      expect(inv.move(bag0, bag0 + 7), true);
      expect(inv.slots[bag0], isNull);
      // Ein Apfel ist keine Waffe.
      expect(inv.move(bag0 + 1, 0), false);
      // Das Schwert darf nicht gegen den Apfel aus dem Waffenfeld tauschen.
      expect(inv.move(0, bag0 + 1), false);
      // Schwert ablegen: nicht mehr ausgerüstet, aber noch im Besitz.
      expect(inv.move(0, bag0), true);
      expect(inv.isEquipped(Item.sword), false);
      expect(inv.has(Item.sword), true);
    });

    test('Aufnehmen, Ablegen und Benutzen über die Spielsteuerung', () {
      final game = playing();
      game.inventory
        ..add(Item.sword)
        ..add(Item.apple, count: 2);
      game.update(1 / 60, GameInput()..inventory = true);
      expect(game.panel, Panel.inventory);
      expect(game.invCursor, bag0);

      // Apfel aufnehmen, zwei Felder nach rechts, ablegen.
      game.update(1 / 60, GameInput()..action = true);
      expect(game.invHeld, bag0);
      game.update(1 / 60, GameInput()..navX = 1);
      game.update(1 / 60, GameInput()..navX = 1);
      game.update(1 / 60, GameInput()..action = true);
      expect(game.invHeld, isNull);
      expect(game.inventory.slots[bag0], isNull);
      expect(game.inventory.slots[bag0 + 2]!.item, Item.apple);

      // Zweimal auf demselben Feld = essen (nur wenn Herzen fehlen).
      game.player.hearts = 1;
      game.update(1 / 60, GameInput()..action = true);
      game.update(1 / 60, GameInput()..action = true);
      expect(game.player.hearts, 2);
      expect(game.inventory.count(Item.apple), 1);

      // Schwert ablegen: ganz nach links zur Ausrüstung, zweimal Aktion.
      for (var i = 0; i < 4; i++) {
        game.update(1 / 60, GameInput()..navX = -1);
      }
      expect(game.invCursor, 0);
      game.update(1 / 60, GameInput()..action = true);
      game.update(1 / 60, GameInput()..action = true);
      expect(game.inventory.isEquipped(Item.sword), false);
      expect(game.hasSword, true);

      // Inventar schließen; das Spiel läuft erst dann weiter.
      game.update(1 / 60, GameInput()..inventory = true);
      expect(game.panel, Panel.none);
    });

    test('Windstiefel wirken nur, wenn sie angelegt sind', () {
      final game = playing();
      game.inventory.add(Item.windBoots);
      expect(game.swift, true);
      game.useSlot(1);
      expect(game.swift, false);
      expect(game.inventory.has(Item.windBoots), true);
    });
  });

  group('Speichern', () {
    test('Spielstand übersteht JSON hin und zurück', () {
      final game = playing();
      talk(game, NpcId.hilda);
      talk(game, NpcId.bruno);
      game.hitSlime(game.slimes[0]);
      game.hitSlime(game.slimes[0]);
      talk(game, NpcId.marta);
      game.catchChicken(game.chickens[1]);
      talk(game, NpcId.elsa);
      game.collectHerb(game.herbs[2]);
      game.inventory.add(Item.apple, count: 2);
      game.apples[0].taken = true;
      game.inventory.move(0, Inventory.equipSlots + 5); // Schwert verstaut
      game.player
        ..x = 300
        ..y = 290
        ..hearts = 2
        ..dir = Dir.left;
      expect(game.takeSaveRequest(), isNotNull);

      final json = jsonEncode(game.toJson());
      final loaded = AdventureGame()
        ..loadJson(jsonDecode(json) as Map<String, dynamic>);

      expect(loaded.player.x, 300);
      expect(loaded.player.y, 290);
      expect(loaded.player.hearts, 2);
      expect(loaded.player.dir, Dir.left);
      expect(loaded.quest(QuestId.amulet).isActive, true);
      expect(loaded.quest(QuestId.slimes).progress, 1);
      expect(loaded.quest(QuestId.chickens).progress, 1);
      expect(loaded.chickens[1].home, true);
      expect(loaded.chickens[0].home, false);
      expect(loaded.herbs[2].taken, true);
      expect(loaded.apples[0].taken, true);
      expect(loaded.inventory.count(Item.apple), 2);
      expect(loaded.inventory.count(Item.redBloom), 1);
      expect(loaded.inventory.slots[Inventory.equipSlots + 5]!.item, Item.sword);
      expect(loaded.inventory.isEquipped(Item.sword), false);
      expect(jsonEncode(loaded.toJson()), json);
    });

    test('Geöffnetes Tor und geleerte Truhe bleiben erhalten', () {
      final game = playing();
      game.inventory.add(Item.ruinKey);
      game.useTile(22, 9);
      game.finishDialog();
      game.useTile(World.chestPos.tx, World.chestPos.ty);
      game.finishDialog();

      final loaded = AdventureGame()..loadJson(game.toJson());
      expect(loaded.gateOpen, true);
      expect(loaded.world.solid(22, 9), false);
      expect(
        loaded.world.objAt(World.chestPos.tx, World.chestPos.ty),
        Obj.chestOpen,
      );
      expect(loaded.hasAmulet, true);
    });

    test('Unbrauchbare Spielstände werden abgelehnt', () {
      expect(() => AdventureGame().loadJson({'version': 99}), throwsA(anything));
      expect(() => AdventureGame().loadJson({}), throwsA(anything));
    });

    test('Titelbild: Fortsetzen lädt, Neues Spiel fragt nach', () {
      final saved = playing();
      talk(saved, NpcId.bruno);
      final data = saved.toJson();

      final game = AdventureGame()..savedState = data;
      expect(game.titleOptions, hasLength(2));
      game.update(1 / 60, GameInput()..action = true);
      expect(game.screen, Screen.playing);
      expect(game.hasSword, true);

      final fresh = AdventureGame()..savedState = data;
      fresh.update(1 / 60, GameInput()..navY = 1);
      fresh.update(1 / 60, GameInput()..action = true);
      expect(fresh.newGameRequested, false); // erst Rückfrage
      expect(fresh.titleConfirm, true);
      fresh.update(1 / 60, GameInput()..action = true);
      expect(fresh.newGameRequested, true);
    });

    test('Pause-Menü speichert und schaltet die Musik', () {
      final game = playing();
      game.takeSaveRequest();
      game.update(1 / 60, GameInput()..menu = true);
      expect(game.panel, Panel.menu);
      game.update(1 / 60, GameInput()..navY = 1);
      game.update(1 / 60, GameInput()..action = true);
      expect(game.takeSaveRequest(), true); // mit Bestätigung
      expect(game.panel, Panel.none);

      expect(game.musicEnabled, true);
      game.update(1 / 60, GameInput()..music = true);
      expect(game.musicEnabled, false);
    });
  });
}
