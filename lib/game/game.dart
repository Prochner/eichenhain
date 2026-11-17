import 'dart:math' as math;

import 'entities.dart';
import 'items.dart';
import 'pixel_font.dart';
import 'quests.dart';
import 'world.dart';

enum Screen { title, playing, ending }

/// Geöffnetes Fenster über dem Spiel.
enum Panel { none, questLog, inventory, menu }

enum MenuEntry { resume, save, music, title }

/// Eingaben eines Frames. Alles außer [moveX]/[moveY] sind Einmal-Impulse.
class GameInput {
  double moveX = 0;
  double moveY = 0;
  bool action = false;
  bool log = false;
  bool inventory = false;

  /// Escape: Pause-Menü öffnen bzw. Fenster schließen.
  bool menu = false;
  bool music = false;

  /// Richtungstaste gerade gedrückt (für Menüs und Inventar).
  int navX = 0;
  int navY = 0;

  void clearImpulses() {
    action = false;
    log = false;
    inventory = false;
    menu = false;
    music = false;
    navX = 0;
    navY = 0;
  }
}

class DialogPage {
  DialogPage(this.speaker, this.text)
    : assert(PixelFont.supports(speaker), 'Zeichen fehlt: $speaker'),
      assert(PixelFont.supports(text), 'Zeichen fehlt: $text');

  /// Leer bei Erzähltext.
  final String speaker;
  final String text;
}

class DialogState {
  DialogState(this.pages, this.onDone);

  static const double charsPerSecond = 48;

  final List<DialogPage> pages;
  final void Function()? onDone;
  int index = 0;
  double shown = 0;

  DialogPage get page => pages[index];
  bool get pageComplete => shown >= page.text.length;
}

class Toast {
  Toast(this.text) : assert(PixelFont.supports(text), 'Zeichen fehlt: $text');

  static const double life = 3.2;

  final String text;
  double age = 0;
}

/// Die komplette Spiellogik – unabhängig von Flutter-Widgets und damit
/// direkt testbar.
class AdventureGame {
  AdventureGame({int seed = 7}) : _random = math.Random(seed) {
    npcs.addAll([
      Npc(NpcId.hilda, 'Dorfälteste Hilda', World.hildaPos),
      Npc(NpcId.bruno, 'Schmied Bruno', World.brunoPos),
      Npc(NpcId.marta, 'Bäuerin Marta', World.martaPos),
      Npc(NpcId.elsa, 'Heilerin Elsa', World.elsaPos),
      Npc(NpcId.otto, 'Fischer Otto', World.ottoPos),
    ]);
    for (final n in npcs) {
      _npcTiles.add(world.index(n.tilePos.tx, n.tilePos.ty));
    }
    chickens.addAll(World.chickenSpawns.map(Chicken.new));
    herbs.addAll(World.herbSpawns.map((p) => Pickup(p, Item.redBloom)));
    apples.addAll(World.appleSpawns.map((p) => Pickup(p, Item.apple)));
    slimes.addAll(World.forestSlimes.map(Slime.new));
    slimes.addAll(World.ruinSlimes.map((p) => Slime(p, leash: 36)));
  }

  static const String heroName = 'Finn';
  static const int saveVersion = 1;

  final World world = World.generate();
  final math.Random _random;

  final Player player = Player();
  final List<Npc> npcs = [];
  final List<Chicken> chickens = [];
  final List<Slime> slimes = [];
  final List<Pickup> herbs = [];
  final List<Pickup> apples = [];
  final Set<int> _npcTiles = {};

  final Inventory inventory = Inventory();

  final Map<QuestId, Quest> quests = {
    QuestId.amulet: Quest(
      QuestId.amulet,
      'Das Amulett von Eichenhain',
      'Hilda',
    ),
    QuestId.slimes: Quest(QuestId.slimes, 'Schleimjagd', 'Bruno', goal: 4),
    QuestId.chickens: Quest(
      QuestId.chickens,
      'Ausgebüxte Hühner',
      'Marta',
      goal: 3,
    ),
    QuestId.herbs: Quest(QuestId.herbs, 'Rotblüten', 'Elsa', goal: 3),
  };

  final List<Toast> toasts = [];

  Screen screen = Screen.title;
  Panel panel = Panel.none;
  DialogState? dialog;
  double time = 0;
  double shake = 0;
  double playTime = 0;

  bool gateOpen = false;
  bool musicEnabled = true;

  // Titelbild
  /// Geladener Spielstand, der mit "Fortsetzen" übernommen wird.
  Map<String, dynamic>? savedState;

  /// Ob in dieser Sitzung schon gespielt wurde.
  bool started = false;
  int titleIndex = 0;
  bool titleConfirm = false;

  /// Bitte an die App, ein frisches Spiel zu erzeugen.
  bool newGameRequested = false;

  // Pause-Menü und Inventar
  int menuIndex = 0;
  int invCursor = Inventory.equipSlots;
  int? invHeld;

  int _ottoLine = 0;
  bool _ottoGift = false;
  int _chickensHome = 0;
  double _regen = 0;
  double _autosave = 0;
  bool _saveRequested = false;
  bool _saveAnnounce = false;

  Quest quest(QuestId id) => quests[id]!;

  int get questsDone => quests.values.where((q) => q.isDone).length;

  bool get logOpen => panel == Panel.questLog;

  bool get hasSword => inventory.has(Item.sword);
  bool get hasKey => inventory.has(Item.ruinKey);
  bool get hasAmulet => inventory.has(Item.amulet);
  bool get swift => inventory.isEquipped(Item.windBoots);

  // -------------------------------------------------------------------------
  // Hauptschleife
  // -------------------------------------------------------------------------

  void update(double dt, GameInput input) {
    time += dt;
    for (final t in toasts) {
      t.age += dt;
    }
    toasts.removeWhere((t) => t.age > Toast.life);
    if (shake > 0) shake = math.max(0, shake - dt);
    if (input.music) toggleMusic();

    switch (screen) {
      case Screen.title:
        _updateTitle(input);
        return;
      case Screen.ending:
        if (input.action) screen = Screen.playing;
        return;
      case Screen.playing:
        break;
    }

    final d = dialog;
    if (d != null) {
      d.shown += dt * DialogState.charsPerSecond;
      if (input.action) advanceDialog();
      return;
    }

    if (_updatePanels(input)) return;

    playTime += dt;
    _autosave += dt;
    if (_autosave >= 20) requestSave();

    _updatePlayer(dt, input);
    if (dialog != null) return;

    for (final c in chickens) {
      _updateChicken(c, dt);
    }
    for (final s in slimes) {
      _updateSlime(s, dt);
      if (dialog != null) return;
    }
    _collectPickups();
    _updateRegen(dt);
  }

  // -------------------------------------------------------------------------
  // Titelbild
  // -------------------------------------------------------------------------

  bool get canContinue => started || savedState != null;

  /// Auswahl auf dem Titelbild (leer, solange es keinen Spielstand gibt).
  List<String> get titleOptions => canContinue
      ? ['Fortsetzen', titleConfirm ? 'Wirklich neu beginnen?' : 'Neues Spiel']
      : const [];

  void _updateTitle(GameInput input) {
    if (!canContinue) {
      if (input.action) {
        started = true;
        screen = Screen.playing;
        requestSave();
      }
      return;
    }
    if (input.navY != 0) {
      titleIndex = (titleIndex + input.navY).clamp(0, 1);
      titleConfirm = false;
    }
    if (input.action) activateTitle(titleIndex);
  }

  void activateTitle(int index) {
    if (!canContinue) return;
    titleIndex = index;
    if (index == 0) {
      titleConfirm = false;
      if (!started) {
        final saved = savedState;
        if (saved != null) loadJson(saved);
        started = true;
      }
      screen = Screen.playing;
      return;
    }
    // Ein neues Spiel überschreibt den Spielstand – erst nachfragen.
    if (!titleConfirm) {
      titleConfirm = true;
      return;
    }
    newGameRequested = true;
  }

  // -------------------------------------------------------------------------
  // Fenster: Questbuch, Inventar, Pause-Menü
  // -------------------------------------------------------------------------

  void openInventory() {
    player.moving = false;
    invHeld = null;
    panel = Panel.inventory;
  }

  void closePanel() {
    invHeld = null;
    panel = Panel.none;
  }

  /// Liefert true, solange ein Fenster das Spiel anhält.
  bool _updatePanels(GameInput input) {
    switch (panel) {
      case Panel.none:
        if (input.inventory) {
          openInventory();
        } else if (input.log) {
          player.moving = false;
          panel = Panel.questLog;
        } else if (input.menu) {
          player.moving = false;
          menuIndex = 0;
          panel = Panel.menu;
        } else {
          return false;
        }
      case Panel.questLog:
        if (input.inventory) {
          openInventory();
        } else if (input.log || input.menu || input.action) {
          closePanel();
        }
      case Panel.inventory:
        if (input.menu && invHeld != null) {
          invHeld = null;
        } else if (input.inventory || input.menu) {
          closePanel();
        } else if (input.log) {
          invHeld = null;
          panel = Panel.questLog;
        } else {
          if (input.navX != 0 || input.navY != 0) {
            moveInvCursor(input.navX, input.navY);
          }
          if (input.action) inventoryAction();
        }
      case Panel.menu:
        if (input.menu) {
          closePanel();
        } else {
          if (input.navY != 0) {
            final n = MenuEntry.values.length;
            menuIndex = (menuIndex + input.navY + n) % n;
          }
          if (input.action) activateMenu(menuIndex);
        }
    }
    return true;
  }

  String menuLabel(MenuEntry entry) => switch (entry) {
    MenuEntry.resume => 'Weiterspielen',
    MenuEntry.save => 'Speichern',
    MenuEntry.music => musicEnabled ? 'Musik: an' : 'Musik: aus',
    MenuEntry.title => 'Zum Titelbild',
  };

  void activateMenu(int index) {
    menuIndex = index;
    switch (MenuEntry.values[index]) {
      case MenuEntry.resume:
        closePanel();
      case MenuEntry.save:
        requestSave(announce: true);
        closePanel();
      case MenuEntry.music:
        toggleMusic();
      case MenuEntry.title:
        requestSave();
        closePanel();
        titleIndex = 0;
        titleConfirm = false;
        screen = Screen.title;
    }
  }

  void toggleMusic() {
    musicEnabled = !musicEnabled;
    toast(musicEnabled ? 'Musik an' : 'Musik aus');
  }

  // -------------------------------------------------------------------------
  // Inventar
  // -------------------------------------------------------------------------

  /// Das Inventar ist ein Raster aus 5 Spalten und 3 Zeilen: Spalte 0 ist
  /// die Ausrüstung, die Spalten 1–4 sind der Rucksack.
  static int slotAt(int column, int row) => column == 0
      ? row
      : Inventory.equipSlots + row * Inventory.bagColumns + (column - 1);

  static int slotColumn(int slot) => Inventory.isEquipSlot(slot)
      ? 0
      : 1 + (slot - Inventory.equipSlots) % Inventory.bagColumns;

  static int slotRow(int slot) => Inventory.isEquipSlot(slot)
      ? slot
      : (slot - Inventory.equipSlots) ~/ Inventory.bagColumns;

  void moveInvCursor(int dx, int dy) {
    final column = (slotColumn(invCursor) + dx).clamp(0, Inventory.bagColumns);
    final row = (slotRow(invCursor) + dy).clamp(0, Inventory.bagRows - 1);
    invCursor = slotAt(column, row);
  }

  /// Aktion auf dem markierten Feld: Gegenstand aufnehmen, auf einem anderen
  /// Feld ablegen (verschieben/tauschen) oder – auf demselben Feld – benutzen.
  void inventoryAction() {
    final held = invHeld;
    if (held == null) {
      if (inventory.slots[invCursor] != null) invHeld = invCursor;
      return;
    }
    invHeld = null;
    if (held == invCursor) {
      useSlot(held);
    } else if (inventory.move(held, invCursor)) {
      requestSave();
    } else {
      toast('Das passt dort nicht hin.');
    }
  }

  /// Benutzt den Gegenstand im Feld: essen, an- oder ablegen.
  void useSlot(int slot) {
    final stack = inventory.slots[slot];
    if (stack == null) return;
    final item = stack.item;
    switch (item.kind) {
      case ItemKind.consumable:
        if (player.hearts >= player.maxHearts) {
          toast('Deine Herzen sind schon voll.');
          return;
        }
        player.hearts = math.min(player.maxHearts, player.hearts + item.heal);
        inventory.remove(item, 1);
        toast('${item.label} gegessen.');
      case ItemKind.weapon:
      case ItemKind.boots:
      case ItemKind.charm:
        if (Inventory.isEquipSlot(slot)) {
          final free = inventory.firstFreeBagSlot();
          if (free == null) {
            toast('Kein Platz im Rucksack.');
            return;
          }
          inventory.move(slot, free);
          toast('${item.label} abgelegt.');
        } else {
          inventory.move(slot, Inventory.equipSlotFor(item)!);
          toast('${item.label} ausgerüstet.');
        }
      case ItemKind.quest:
        toast('Das kannst du hier nicht benutzen.');
        return;
    }
    requestSave();
  }

  /// Gibt dem Helden einen Gegenstand. Liefert false, wenn kein Platz ist.
  bool _give(Item item, {int count = 1, bool announce = true}) {
    final left = inventory.add(item, count: count);
    if (left == count) {
      toast('Kein Platz im Rucksack.');
      return false;
    }
    if (announce) toast('${item.label} erhalten!');
    requestSave();
    return true;
  }

  void _updateRegen(double dt) {
    if (!inventory.isEquipped(Item.amulet) ||
        player.hearts >= player.maxHearts) {
      _regen = 0;
      return;
    }
    _regen += dt;
    if (_regen >= 15) {
      _regen = 0;
      player.hearts++;
    }
  }

  // -------------------------------------------------------------------------
  // Speichern und Laden
  // -------------------------------------------------------------------------

  /// Merkt einen Speicherwunsch vor; die App schreibt den Stand dann weg.
  /// [announce] zeigt danach eine Bestätigung (manuelles Speichern).
  void requestSave({bool announce = false}) {
    _saveRequested = true;
    _saveAnnounce = _saveAnnounce || announce;
    _autosave = 0;
  }

  /// null = nichts zu tun, sonst: soll das Speichern bestätigt werden?
  bool? takeSaveRequest() {
    if (!_saveRequested) return null;
    final announce = _saveAnnounce;
    _saveRequested = false;
    _saveAnnounce = false;
    return announce;
  }

  Map<String, dynamic> toJson() => {
    'version': saveVersion,
    'playTime': playTime,
    'player': {
      'x': player.x,
      'y': player.y,
      'dir': player.dir.name,
      'hearts': player.hearts,
      'maxHearts': player.maxHearts,
    },
    'quests': {
      for (final q in quests.values)
        q.id.name: {'status': q.status.name, 'progress': q.progress},
    },
    'inventory': inventory.toJson(),
    'gateOpen': gateOpen,
    'chestOpen':
        world.objAt(World.chestPos.tx, World.chestPos.ty) == Obj.chestOpen,
    'chickens': [
      for (final c in chickens) {'x': c.x, 'y': c.y, 'home': c.home},
    ],
    'chickensHome': _chickensHome,
    'herbs': [for (final h in herbs) h.taken],
    'apples': [for (final a in apples) a.taken],
    'ottoLine': _ottoLine,
    'ottoGift': _ottoGift,
  };

  /// Übernimmt einen mit [toJson] erzeugten Spielstand. Wirft bei
  /// unbrauchbaren Daten – die App prüft Spielstände deshalb vorab an
  /// einer Wegwerf-Instanz.
  void loadJson(Map<String, dynamic> data) {
    if (data['version'] != saveVersion) {
      throw const FormatException('Unbekannte Spielstand-Version');
    }
    playTime = (data['playTime'] as num).toDouble();

    final p = data['player'] as Map<String, dynamic>;
    player
      ..x = (p['x'] as num).toDouble()
      ..y = (p['y'] as num).toDouble()
      ..dir = Dir.values.byName(p['dir'] as String)
      ..maxHearts = (p['maxHearts'] as num).toInt().clamp(3, 9)
      ..moving = false
      ..attackTime = 0
      ..invulnerable = 0;
    player.hearts = (p['hearts'] as num).toInt().clamp(1, player.maxHearts);

    final qs = data['quests'] as Map<String, dynamic>;
    for (final q in quests.values) {
      final entry = qs[q.id.name] as Map<String, dynamic>;
      q
        ..status = QuestStatus.values.byName(entry['status'] as String)
        ..progress = (entry['progress'] as num).toInt();
    }

    inventory.loadJson(data['inventory'] as List<dynamic>);

    gateOpen = data['gateOpen'] as bool;
    if (gateOpen) world.openGates();
    if (data['chestOpen'] as bool) {
      world.setObj(World.chestPos.tx, World.chestPos.ty, Obj.chestOpen);
    }

    final cs = data['chickens'] as List<dynamic>;
    for (var i = 0; i < chickens.length && i < cs.length; i++) {
      final entry = cs[i] as Map<String, dynamic>;
      chickens[i]
        ..x = (entry['x'] as num).toDouble()
        ..y = (entry['y'] as num).toDouble()
        ..home = entry['home'] as bool
        ..vx = 0
        ..vy = 0;
    }
    _chickensHome = (data['chickensHome'] as num).toInt();

    void restore(List<Pickup> pickups, List<dynamic> taken) {
      for (var i = 0; i < pickups.length && i < taken.length; i++) {
        pickups[i].taken = taken[i] as bool;
      }
    }

    restore(herbs, data['herbs'] as List<dynamic>);
    restore(apples, data['apples'] as List<dynamic>);
    _ottoLine = (data['ottoLine'] as num).toInt();
    _ottoGift = data['ottoGift'] as bool;

    // Sicherheitsnetz: nie in einer Wand aufwachen.
    if (_boxBlocked(player, player.x, player.y)) {
      player
        ..x = World.respawnPoint.cx
        ..y = World.respawnPoint.cy;
    }
    dialog = null;
    panel = Panel.none;
    invHeld = null;
  }

  // -------------------------------------------------------------------------
  // Dialoge und Meldungen
  // -------------------------------------------------------------------------

  void _say(String speaker, List<String> texts, {void Function()? onDone}) {
    player.moving = false;
    dialog = DialogState([
      for (final t in texts) DialogPage(speaker, t),
    ], onDone);
  }

  void advanceDialog() {
    final d = dialog;
    if (d == null) return;
    if (!d.pageComplete) {
      d.shown = d.page.text.length.toDouble();
      return;
    }
    if (d.index < d.pages.length - 1) {
      d.index++;
      d.shown = 0;
      return;
    }
    dialog = null;
    d.onDone?.call();
  }

  /// Blättert den aktuellen Dialog (und Folgedialoge) bis zum Ende durch.
  void finishDialog() {
    var guard = 0;
    while (dialog != null && guard++ < 200) {
      advanceDialog();
    }
  }

  void toast(String text) {
    if (toasts.isNotEmpty && toasts.last.text == text) {
      toasts.last.age = 0;
      return;
    }
    toasts.add(Toast(text));
    if (toasts.length > 3) toasts.removeAt(0);
  }

  // -------------------------------------------------------------------------
  // Quests
  // -------------------------------------------------------------------------

  void _start(Quest q) {
    q.status = QuestStatus.active;
    toast('Neue Quest: ${q.title}');
    requestSave();
  }

  void _complete(Quest q) {
    q.status = QuestStatus.done;
    toast('Quest geschafft: ${q.title}');
    requestSave();
  }

  void _progress(Quest q) {
    if (!q.isActive) return;
    q.progress++;
    if (q.progress >= q.goal) {
      q.status = QuestStatus.ready;
      toast('Ziel erreicht! Zurück zu ${q.giver}.');
    } else {
      toast('${q.title}: ${q.progress}/${q.goal}');
    }
    requestSave();
  }

  /// Aktueller Auftragstext fürs Questbuch.
  String objective(Quest q) {
    if (q.isDone) return 'Abgeschlossen.';
    switch (q.id) {
      case QuestId.amulet:
        if (hasAmulet) return 'Bringe das Amulett zu Hilda.';
        if (gateOpen) return 'Öffne die Truhe in der Ruine.';
        if (hasKey) return 'Öffne das Tor der Ruine im Norden.';
        return 'Besorge den Ruinenschlüssel von Schmied Bruno.';
      case QuestId.slimes:
        if (q.isReady) return 'Kehre zu Schmied Bruno zurück.';
        return 'Besiege Schleime im Flüsterwald: ${q.progress}/${q.goal}';
      case QuestId.chickens:
        if (q.isReady) return 'Kehre zu Bäuerin Marta zurück.';
        return 'Fange Martas Hühner ein: ${q.progress}/${q.goal}';
      case QuestId.herbs:
        if (q.isReady) return 'Kehre zu Heilerin Elsa zurück.';
        return 'Sammle Rotblüten im Flüsterwald: ${q.progress}/${q.goal}';
    }
  }

  /// Kurzzeile für die Anzeige am Bildschirmrand.
  String trackerLine(Quest q) {
    if (q.goal == 0) return q.title;
    if (q.isReady) return '${q.title}: fertig!';
    return '${q.title} ${q.progress}/${q.goal}';
  }

  /// '!' = neue Quest, '?' = Quest kann abgegeben werden.
  String markerFor(Npc n) {
    final Quest q;
    switch (n.id) {
      case NpcId.hilda:
        final a = quest(QuestId.amulet);
        if (a.isDone) return '';
        if (hasAmulet) return '?';
        return a.status == QuestStatus.available ? '!' : '';
      case NpcId.bruno:
        q = quest(QuestId.slimes);
      case NpcId.marta:
        q = quest(QuestId.chickens);
      case NpcId.elsa:
        q = quest(QuestId.herbs);
      case NpcId.otto:
        return '';
    }
    if (q.status == QuestStatus.available) return '!';
    if (q.isReady) return '?';
    return '';
  }

  // -------------------------------------------------------------------------
  // Gespräche
  // -------------------------------------------------------------------------

  void talkTo(Npc n) {
    switch (n.id) {
      case NpcId.hilda:
        _talkHilda(n);
      case NpcId.bruno:
        _talkBruno(n);
      case NpcId.marta:
        _talkMarta(n);
      case NpcId.elsa:
        _talkElsa(n);
      case NpcId.otto:
        _talkOtto(n);
    }
  }

  void _talkHilda(Npc n) {
    final q = quest(QuestId.amulet);
    if (q.isDone) {
      _say(n.name, ['Eichenhain ist wieder sicher. Danke, $heroName!']);
    } else if (hasAmulet) {
      _say(
        n.name,
        [
          'Das Amulett! Du hast es wirklich geschafft, $heroName!',
          'Sein Licht vertreibt die Schatten aus dem Wald. '
              'Ganz Eichenhain dankt dir!',
          'Behalte es. Als Talisman getragen, schenkt es dir neue Kraft.',
        ],
        onDone: () {
          _complete(q);
          screen = Screen.ending;
        },
      );
    } else if (q.status == QuestStatus.available) {
      _say(
        n.name,
        [
          '$heroName! Gut, dass du da bist. Unser Dorf braucht deine Hilfe.',
          'Seit das Amulett von Eichenhain in der alten Ruine verschwand, '
              'wimmelt der Wald von Schleimen.',
          'Das Tor der Ruine im Norden ist verschlossen. Schmied Bruno '
              'weiß vielleicht, wo der Schlüssel ist.',
          'Bring mir das Amulett zurück, dann ist Eichenhain wieder sicher!',
        ],
        onDone: () => _start(q),
      );
    } else if (gateOpen) {
      _say(n.name, ['Das Amulett muss in der Truhe der Ruine liegen.']);
    } else if (hasKey) {
      _say(n.name, [
        'Du hast den Schlüssel! Die Ruine liegt im Norden. '
            'Folge einfach dem Weg.',
      ]);
    } else {
      _say(n.name, [
        'Sprich mit Schmied Bruno. Seine Schmiede steht gleich '
            'westlich vom Dorfplatz.',
      ]);
    }
  }

  void _talkBruno(Npc n) {
    final q = quest(QuestId.slimes);
    switch (q.status) {
      case QuestStatus.available:
        _say(
          n.name,
          [
            'Hm? Ah, $heroName. Die Schleime aus dem Flüsterwald fressen '
                'mir die ganze Kohle weg!',
            'Hier, nimm dieses Schwert. Besiege ${q.goal} Schleime im Wald '
                'im Osten.',
            'Dann habe ich etwas für dich: einen alten Schlüssel, den ich '
                'bei der Ruine gefunden habe.',
          ],
          onDone: () {
            _give(Item.sword);
            _start(q);
          },
        );
      case QuestStatus.active:
        final left = q.goal - q.progress;
        _say(n.name, [
          'Noch $left Schleime, dann gehört der Schlüssel dir. '
              'Der Wald liegt im Osten.',
        ]);
      case QuestStatus.ready:
        _say(
          n.name,
          [
            'Ha! Das nenne ich saubere Arbeit.',
            'Wie versprochen: Hier ist der Ruinenschlüssel. '
                'Pass da drin auf dich auf!',
          ],
          onDone: () {
            _give(Item.ruinKey);
            _complete(q);
          },
        );
      case QuestStatus.done:
        _say(n.name, ['Das Schwert steht dir gut. Halte die Klinge sauber!']);
    }
  }

  void _talkMarta(Npc n) {
    final q = quest(QuestId.chickens);
    switch (q.status) {
      case QuestStatus.available:
        _say(
          n.name,
          [
            'Ach herrje, ach herrje! Meine Hühner sind ausgebüxt!',
            'Drei Stück laufen irgendwo da draußen herum. '
                'Kannst du sie einfangen, $heroName?',
            'Sie sind flink. Lauf einfach auf sie zu und schnapp sie dir!',
          ],
          onDone: () => _start(q),
        );
      case QuestStatus.active:
        final left = q.goal - q.progress;
        _say(n.name, [
          'Es fehlen noch $left Hühner. Schau auf den Wiesen im Westen '
              'und südlich vom Dorf.',
        ]);
      case QuestStatus.ready:
        _say(
          n.name,
          [
            'Alle wieder da! Du bist ein Schatz.',
            'Hier, ein Apfelkuchen für unterwegs. Und iss dich erst mal '
                'satt, das macht stark!',
          ],
          onDone: () {
            player.maxHearts++;
            player.hearts = player.maxHearts;
            toast('Ein Herz mehr!');
            _give(Item.applePie);
            _complete(q);
          },
        );
      case QuestStatus.done:
        _say(n.name, ['Die Hühner legen wieder fleißig Eier. Danke dir!']);
    }
  }

  void _talkElsa(Npc n) {
    final q = quest(QuestId.herbs);
    switch (q.status) {
      case QuestStatus.available:
        _say(
          n.name,
          [
            'Sei gegrüßt, $heroName. Ich braue gerade einen Trank.',
            'Mir fehlen drei Rotblüten. Sie wachsen auf den Lichtungen '
                'im Flüsterwald.',
            'Aber Vorsicht: Dort treiben sich Schleime herum.',
          ],
          onDone: () => _start(q),
        );
      case QuestStatus.active:
        final left = q.goal - q.progress;
        _say(n.name, [
          'Noch $left Rotblüten. Du erkennst sie an den roten Blättern.',
        ]);
      case QuestStatus.ready:
        _say(
          n.name,
          [
            'Wunderbar, die sind ganz frisch!',
            'Nimm diese Windstiefel. Ich habe sie mit Windkraut '
                'eingerieben. Damit läufst du schneller als der Wind.',
          ],
          onDone: () {
            inventory.remove(Item.redBloom, q.goal);
            _give(Item.windBoots);
            _complete(q);
          },
        );
      case QuestStatus.done:
        _say(n.name, [
          'Wenn du verletzt bist, trink am Dorfbrunnen. '
              'Das Wasser wirkt Wunder.',
        ]);
    }
  }

  void _talkOtto(Npc n) {
    if (!_ottoGift) {
      _say(
        n.name,
        [
          'Petri Heil, $heroName! Du siehst hungrig aus.',
          'Hier, ein Räucherfisch für unterwegs. Selbst gefangen!',
        ],
        onDone: () {
          if (_give(Item.smokedFish)) _ottoGift = true;
        },
      );
      return;
    }
    const lines = [
      'Im Spiegelsee beißen heute nur die kleinen Fische.',
      'Schleime können nicht schwimmen. Aber du leider auch nicht.',
      'Der Brunnen auf dem Dorfplatz heilt alle Wunden. '
          'Altes Fischerwissen!',
    ];
    _say(n.name, [lines[_ottoLine % lines.length]]);
    _ottoLine++;
  }

  // -------------------------------------------------------------------------
  // Aktionen in der Welt
  // -------------------------------------------------------------------------

  /// Benutzt die Kachel (tx, ty). Liefert false, wenn dort nichts zu tun ist.
  bool useTile(int tx, int ty) {
    switch (world.objAt(tx, ty)) {
      case Obj.sign:
        _say('Schild', [world.signs[world.index(tx, ty)] ?? '...']);
      case Obj.well:
        player.hearts = player.maxHearts;
        _say('', [
          'Du trinkst das klare Brunnenwasser. '
              'Deine Herzen sind wieder voll!',
        ]);
      case Obj.gateClosed:
        if (hasKey) {
          world.openGates();
          gateOpen = true;
          requestSave();
          _say('', ['Der Schlüssel passt! Knarrend öffnet sich das Tor.']);
        } else {
          _say('', ['Ein schweres Eisentor. Es ist fest verschlossen.']);
        }
      case Obj.chestClosed:
        if (inventory.firstFreeBagSlot() == null &&
            inventory.slots[Inventory.equipSlotFor(Item.amulet)!] != null) {
          _say('', ['Dein Rucksack ist voll. Schaffe erst etwas Platz.']);
        } else {
          // Truhe und Amulett gehören zusammen in denselben Spielstand.
          world.setObj(tx, ty, Obj.chestOpen);
          _give(Item.amulet, announce: false);
          _say(
            '',
            [
              'In der Truhe liegt ein leuchtendes Amulett!',
              'Du hast das Amulett von Eichenhain gefunden!',
            ],
            onDone: () => toast('${Item.amulet.label} erhalten!'),
          );
        }
      case Obj.chestOpen:
        _say('', ['Die Truhe ist leer.']);
      case Obj.anvil:
        _say('', ['Ein schwerer Amboss. Noch warm vom Schmieden.']);
      default:
        return false;
    }
    return true;
  }

  void catchChicken(Chicken c) {
    if (c.home) return;
    final spot = World.penSpots[_chickensHome % World.penSpots.length];
    _chickensHome++;
    c
      ..home = true
      ..x = spot.cx
      ..y = spot.cy
      ..vx = 0
      ..vy = 0
      ..timer = 1;
    _progress(quest(QuestId.chickens));
  }

  void collectHerb(Pickup h) {
    if (h.taken) return;
    if (!_give(Item.redBloom, announce: false)) return;
    h.taken = true;
    _progress(quest(QuestId.herbs));
  }

  void hitSlime(Slime s, [double dirX = 0, double dirY = 0]) {
    if (!s.alive) return;
    s.hp--;
    s.hurt = 0.25;
    s.knockX = dirX * 150;
    s.knockY = dirY * 150;
    if (s.hp <= 0) {
      s.alive = false;
      s.respawn = 25;
      _progress(quest(QuestId.slimes));
    }
  }

  void _action() {
    final p = player;
    final fx = p.x + p.dir.dx * 12;
    final fy = p.y - 1 + p.dir.dy * 12;

    // Ansprechen klappt auch, wenn der Held nur daneben steht – er dreht
    // sich dann zur Person um.
    for (final n in npcs) {
      if (_dist(fx, fy, n.x, n.y - 4) < 14 || _dist(p.x, p.y, n.x, n.y) < 20) {
        final dx = n.x - p.x;
        final dy = n.y - p.y;
        if (dx.abs() > dy.abs()) {
          p.dir = dx < 0 ? Dir.left : Dir.right;
        } else {
          p.dir = dy < 0 ? Dir.up : Dir.down;
        }
        talkTo(n);
        return;
      }
    }
    for (final c in chickens) {
      if (_dist(fx, fy, c.x, c.y - 3) < 14) {
        if (c.home) {
          _say('', ['Gack, gack. Das Huhn ist zufrieden.']);
        } else if (quest(QuestId.chickens).isActive) {
          catchChicken(c);
        } else {
          _say('', ['Gack! Das Huhn sieht aus, als wäre es ausgebüxt.']);
        }
        return;
      }
    }
    final tx = (fx / World.tile).floor();
    final ty = (fy / World.tile).floor();
    if (useTile(tx, ty)) return;

    for (final h in herbs) {
      if (!h.taken && _dist(p.x, p.y, h.x, h.y) < 15) {
        if (quest(QuestId.herbs).isActive) {
          collectHerb(h);
        } else {
          _say('', [
            'Eine Rotblüte. Heilerin Elsa könnte mehr darüber wissen.',
          ]);
        }
        return;
      }
    }

    if (inventory.isEquipped(Item.sword)) {
      _attack();
    } else if (hasSword) {
      toast('Dein Schwert ist nicht ausgerüstet.');
    }
  }

  void _attack() {
    final p = player;
    p.attackTime = Player.attackDuration;
    final cx = p.x + p.dir.dx * 13;
    final cy = p.y - 3 + p.dir.dy * 13;
    for (final s in slimes) {
      if (!s.alive) continue;
      if ((s.x - cx).abs() < 13 && (s.y - 3 - cy).abs() < 13) {
        hitSlime(s, p.dir.dx, p.dir.dy);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Bewegung und Kollision
  // -------------------------------------------------------------------------

  bool _boxBlocked(Body b, double x, double y) {
    final left = ((x - b.halfWidth) / World.tile).floor();
    final right = ((x + b.halfWidth - 0.001) / World.tile).floor();
    final top = ((y - b.top) / World.tile).floor();
    final bottom = ((y + b.bottom - 0.001) / World.tile).floor();
    for (var ty = top; ty <= bottom; ty++) {
      for (var tx = left; tx <= right; tx++) {
        if (world.solid(tx, ty)) return true;
        if (_npcTiles.contains(world.index(tx, ty))) return true;
      }
    }
    return false;
  }

  bool _moveAxis(Body b, double delta, bool horizontal) {
    var remaining = delta;
    while (remaining != 0) {
      final step = remaining.abs() > 1 ? remaining.sign : remaining;
      final nx = horizontal ? b.x + step : b.x;
      final ny = horizontal ? b.y : b.y + step;
      if (_boxBlocked(b, nx, ny)) return true;
      b.x = nx;
      b.y = ny;
      remaining -= step;
    }
    return false;
  }

  /// Bewegt [b] pixelweise; liefert true, wenn ein Hindernis im Weg war.
  bool _move(Body b, double dx, double dy) {
    final hitX = _moveAxis(b, dx, true);
    final hitY = _moveAxis(b, dy, false);
    return hitX || hitY;
  }

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _updatePlayer(double dt, GameInput input) {
    final p = player;
    p.invulnerable = math.max(0, p.invulnerable - dt);

    if (p.attackTime > 0) {
      p.attackTime = math.max(0, p.attackTime - dt);
      p.moving = false;
      return;
    }

    var mx = input.moveX;
    var my = input.moveY;
    final len = math.sqrt(mx * mx + my * my);
    p.moving = len > 0.01;
    if (p.moving) {
      if (len > 1) {
        mx /= len;
        my /= len;
      }
      if (mx.abs() > my.abs()) {
        p.dir = mx < 0 ? Dir.left : Dir.right;
      } else {
        p.dir = my < 0 ? Dir.up : Dir.down;
      }
      final speed = swift ? 84.0 : 62.0;
      _move(p, mx * speed * dt, my * speed * dt);
      p.walkTime += dt;
    } else {
      p.walkTime = 0;
    }

    if (input.action) _action();
  }

  void _hurtPlayer(double fromX, double fromY) {
    final p = player;
    if (p.invulnerable > 0) return;
    p.hearts--;
    p.invulnerable = 1.2;
    shake = 0.25;
    var dx = p.x - fromX;
    var dy = p.y - fromY;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.01) {
      dx = 0;
      dy = 1;
    } else {
      dx /= d;
      dy /= d;
    }
    _move(p, dx * 12, dy * 12);

    if (p.hearts <= 0) {
      _say(
        '',
        [
          'Dir wird schwarz vor Augen ...',
          'Du wachst am Dorfbrunnen wieder auf.',
        ],
        onDone: () {
          p
            ..x = World.respawnPoint.cx
            ..y = World.respawnPoint.cy
            ..dir = Dir.down
            ..hearts = p.maxHearts
            ..invulnerable = 2;
          requestSave();
        },
      );
    }
  }

  // -------------------------------------------------------------------------
  // Hühner, Schleime, Fundstücke
  // -------------------------------------------------------------------------

  void _updateChicken(Chicken c, double dt) {
    c.anim += dt;
    final p = player;
    final d = _dist(c.x, c.y, p.x, p.y);

    if (!c.home && d < 36) {
      // Flucht vor dem Spieler.
      var dx = c.x - p.x;
      var dy = c.y - p.y;
      if (d < 0.01) {
        dx = 1;
        dy = 0;
      } else {
        dx /= d;
        dy /= d;
      }
      c.vx = dx * 48;
      c.vy = dy * 48;
      c.timer = 0.3;
    } else {
      c.timer -= dt;
      if (c.timer <= 0) {
        if (_random.nextDouble() < 0.45) {
          c.vx = 0;
          c.vy = 0;
          c.timer = 0.6 + _random.nextDouble() * 1.6;
        } else {
          final angle = _random.nextDouble() * math.pi * 2;
          c.vx = math.cos(angle) * 18;
          c.vy = math.sin(angle) * 18;
          c.timer = 0.4 + _random.nextDouble() * 0.9;
        }
      }
    }

    if (c.vx != 0 || c.vy != 0) {
      _move(c, c.vx * dt, c.vy * dt);
      if (c.vx.abs() > 1) c.faceLeft = c.vx < 0;
    }

    if (!c.home && d < 11 && quest(QuestId.chickens).isActive) {
      catchChicken(c);
    }
  }

  void _updateSlime(Slime s, double dt) {
    final p = player;
    if (!s.alive) {
      s.respawn -= dt;
      if (s.respawn <= 0 && _dist(s.homeX, s.homeY, p.x, p.y) > 90) {
        s
          ..alive = true
          ..hp = Slime.maxHp
          ..x = s.homeX
          ..y = s.homeY
          ..knockX = 0
          ..knockY = 0;
      }
      return;
    }

    s.hurt = math.max(0, s.hurt - dt);
    s.hop += dt;

    if (s.knockX.abs() + s.knockY.abs() > 4) {
      _move(s, s.knockX * dt, s.knockY * dt);
      final decay = math.pow(0.001, dt).toDouble();
      s.knockX *= decay;
      s.knockY *= decay;
    } else {
      final toPlayer = _dist(s.x, s.y, p.x, p.y);
      final fromHome = _dist(s.x, s.y, s.homeX, s.homeY);
      double tx;
      double ty;
      double speed;
      if (fromHome > s.leash) {
        tx = s.homeX;
        ty = s.homeY;
        speed = 30;
      } else if (toPlayer < 56) {
        tx = p.x;
        ty = p.y;
        speed = 30;
      } else {
        s.wanderTimer -= dt;
        if (s.wanderTimer <= 0) {
          s.wanderTimer = 1.5 + _random.nextDouble() * 2;
          s.targetX = s.homeX + (_random.nextDouble() - 0.5) * 40;
          s.targetY = s.homeY + (_random.nextDouble() - 0.5) * 40;
        }
        tx = s.targetX;
        ty = s.targetY;
        speed = 14;
      }
      final dx = tx - s.x;
      final dy = ty - s.y;
      final d = math.sqrt(dx * dx + dy * dy);
      // Schleime bewegen sich nur während des Sprungs.
      if (d > 2 && slimeHopHeight(s) > 0) {
        _move(s, dx / d * speed * 1.8 * dt, dy / d * speed * 1.8 * dt);
      }
    }

    if (_dist(s.x, s.y, p.x, p.y) < 11) {
      _hurtPlayer(s.x, s.y);
    }
  }

  /// Sprunghöhe eines Schleims in Pixeln (0 = am Boden).
  double slimeHopHeight(Slime s) {
    final phase = (s.hop * 2.2) % 1.0;
    if (phase > 0.55) return 0;
    return math.sin(phase / 0.55 * math.pi) * 3;
  }

  void _collectPickups() {
    final p = player;
    if (quest(QuestId.herbs).isActive) {
      for (final h in herbs) {
        if (!h.taken && _dist(p.x, p.y, h.x, h.y) < 10) collectHerb(h);
      }
    }
    for (final a in apples) {
      if (a.taken || _dist(p.x, p.y, a.x, a.y) >= 10) continue;
      if (inventory.add(Item.apple) == 0) {
        a.taken = true;
        toast('Apfel eingesammelt.');
        requestSave();
      }
    }
  }
}
