import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_game/game/entities.dart';
import 'package:flutter_game/game/game.dart';
import 'package:flutter_game/main.dart';
import 'package:flutter_game/services.dart';
import 'package:flutter_test/flutter_test.dart';

const saveKey = 'eichenhain.save';
const musicKey = 'eichenhain.music';

Future<void> frames(WidgetTester tester, [int count = 3]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Startet die App und wartet, bis der Sprite-Atlas dekodiert ist.
Future<void> launch(WidgetTester tester, GameServices services) async {
  await tester.pumpWidget(EichenhainApp(services: services));
  expect(find.byType(GameScreen), findsOneWidget);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await frames(tester);
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await frames(tester, 2);
}

Map<String, dynamic> savedGame(MemorySaveStore store) =>
    jsonDecode(store.values[saveKey]!) as Map<String, dynamic>;

void main() {
  testWidgets('Spielen, Fenster öffnen, speichern, Musik schalten', (
    WidgetTester tester,
  ) async {
    final store = MemorySaveStore();
    final music = SilentMusicPlayer();
    await launch(tester, GameServices(store: store, music: music));
    expect(music.started, false); // Ton erst nach einer Eingabe

    // Titelbild wegtippen: Das neue Spiel wird sofort gesichert.
    await tester.tapAt(const Offset(600, 300));
    await frames(tester);
    expect(music.started, true);
    expect(store.values, contains(saveKey));

    // Inventar und Questbuch über die Knöpfe oben rechts.
    await tester.tapAt(const Offset(650, 40));
    await frames(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.space);
    await press(tester, LogicalKeyboardKey.keyI);
    await press(tester, LogicalKeyboardKey.keyQ);
    await press(tester, LogicalKeyboardKey.keyQ);

    // Ein Stück laufen, dann im Pause-Menü speichern.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await frames(tester, 20);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.space);

    final player = savedGame(store)['player'] as Map<String, dynamic>;
    expect(player['x'] as num, greaterThan(370));
    expect(player['dir'], 'right');

    // Musik aus: wird angewendet und gemerkt.
    await press(tester, LogicalKeyboardKey.keyM);
    expect(music.enabled, false);
    expect(store.values[musicKey], '0');

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ein vorhandener Spielstand wird fortgesetzt', (
    WidgetTester tester,
  ) async {
    final earlier = AdventureGame()
      ..started = true
      ..screen = Screen.playing;
    earlier.talkTo(earlier.npcs.firstWhere((n) => n.id == NpcId.bruno));
    earlier.finishDialog();
    final store = MemorySaveStore()
      ..values[saveKey] = jsonEncode(earlier.toJson())
      ..values[musicKey] = '0';
    final music = SilentMusicPlayer();
    await launch(tester, GameServices(store: store, music: music));

    // "Fortsetzen" ist vorausgewählt.
    await press(tester, LogicalKeyboardKey.space);
    expect(music.started, true);
    expect(music.enabled, false);

    // Speichern: Der geladene Stand (mit Schwert) wird wieder geschrieben.
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.space);
    final inventory = savedGame(store)['inventory'] as List<dynamic>;
    expect((inventory[0] as Map<String, dynamic>)['item'], 'sword');
    final quests = savedGame(store)['quests'] as Map<String, dynamic>;
    expect((quests['slimes'] as Map<String, dynamic>)['status'], 'active');

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ein kaputter Spielstand stört den Start nicht', (
    WidgetTester tester,
  ) async {
    final store = MemorySaveStore()..values[saveKey] = '{"version": 1, "x"';
    await launch(
      tester,
      GameServices(store: store, music: SilentMusicPlayer()),
    );
    await press(tester, LogicalKeyboardKey.space);
    // Ohne brauchbaren Stand beginnt ein neues Spiel und überschreibt ihn.
    expect(savedGame(store)['version'], AdventureGame.saveVersion);
    expect(tester.takeException(), isNull);
  });
}
