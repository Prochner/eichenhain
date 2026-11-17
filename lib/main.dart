import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'game/game.dart';
import 'game/renderer.dart';
import 'game/sprites.dart';
import 'services.dart';

void main() {
  runApp(const EichenhainApp());
}

class EichenhainApp extends StatelessWidget {
  const EichenhainApp({super.key, this.services});

  /// Speicher und Musik; ohne Angabe die echten Gerätedienste.
  final GameServices? services;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Eichenhain',
      color: const Color(0xFF1C3A26),
      debugShowCheckedModeBanner: false,
      builder: (context, _) => GameScreen(services: services),
    );
  }
}

/// Verbindet Spiellogik, Darstellung, Eingabe (Tastatur, Maus, Touch),
/// Spielstand und Musik.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.services});

  final GameServices? services;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _saveKey = 'eichenhain.save';
  static const String _musicKey = 'eichenhain.music';

  late final GameServices _services;
  AdventureGame _game = AdventureGame();
  final GameInput _input = GameInput();
  final TouchState _touch = TouchState();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final FocusNode _focus = FocusNode(debugLabel: 'Spiel');
  final Set<LogicalKeyboardKey> _keys = {};

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  GameRenderer? _renderer;

  bool _musicOn = true;
  bool _musicStarted = false;

  // Wird in build() aus der Fenstergröße berechnet.
  double _scale = 3;
  Size _view = Size.zero;
  EdgeInsets _pad = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _services = widget.services ?? GameServices.device();
    WidgetsBinding.instance.addObserver(this);
    _touch.visible =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    final sheet = SpriteSheet();
    sheet.toImage().then((image) {
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _renderer = GameRenderer(sheet, image));
    });

    _loadSaved();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focus.dispose();
    _frame.dispose();
    _renderer?.image.dispose();
    _services.music.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Spielstand
  // ---------------------------------------------------------------------

  Future<void> _loadSaved() async {
    try {
      final music = await _services.store.read(_musicKey);
      final raw = await _services.store.read(_saveKey);
      if (!mounted) return;
      if (music == '0') {
        _musicOn = false;
        _game.musicEnabled = false;
      }
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // Erst an einer Wegwerf-Instanz prüfen, ob der Stand brauchbar ist.
      AdventureGame().loadJson(data);
      if (!_game.started) _game.savedState = data;
    } catch (_) {
      // Kein oder unlesbarer Spielstand: einfach neu beginnen.
    }
  }

  Future<void> _save({required bool announce}) async {
    final game = _game;
    if (!game.started) return;
    try {
      await _services.store.write(_saveKey, jsonEncode(game.toJson()));
      if (announce && mounted) game.toast('Spiel gespeichert.');
    } catch (_) {
      if (mounted) game.toast('Speichern fehlgeschlagen.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _services.music.setSuspended(!active);
    // Beim Wechsel in den Hintergrund sichern – aber nicht mitten in einem
    // Gespräch, dessen Belohnung noch aussteht.
    if (!active && _game.screen == Screen.playing && _game.dialog == null) {
      _save(announce: false);
    }
  }

  // ---------------------------------------------------------------------
  // Spielschleife
  // ---------------------------------------------------------------------

  bool _down(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
      _keys.contains(a) || _keys.contains(b);

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;

    var mx = 0.0;
    var my = 0.0;
    if (_down(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA)) mx -= 1;
    if (_down(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD)) mx += 1;
    if (_down(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW)) my -= 1;
    if (_down(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS)) my += 1;
    final stick = _touch.vector;
    if (stick != Offset.zero) {
      mx = stick.dx;
      my = stick.dy;
    }
    _input
      ..moveX = mx
      ..moveY = my;

    _game.update(dt, _input);
    _input.clearImpulses();
    _afterUpdate();
    _frame.value++;
  }

  /// Erledigt, worum die Spiellogik die App gebeten hat.
  void _afterUpdate() {
    if (_game.newGameRequested) {
      final old = _game;
      setState(() {
        _game = AdventureGame()
          ..started = true
          ..screen = Screen.playing
          ..musicEnabled = old.musicEnabled
          ..requestSave();
      });
    }

    final announce = _game.takeSaveRequest();
    if (announce != null) _save(announce: announce);

    if (_game.musicEnabled != _musicOn) {
      _musicOn = _game.musicEnabled;
      _services.music.setEnabled(_musicOn);
      _services.store
          .write(_musicKey, _musicOn ? '1' : '0')
          .catchError((Object _) {});
    }
  }

  /// Browser erlauben Ton erst nach einer Eingabe – also hier starten.
  void _userGesture() {
    if (_musicStarted) return;
    _musicStarted = true;
    _services.music.start(enabled: _game.musicEnabled);
  }

  // ---------------------------------------------------------------------
  // Tastatur
  // ---------------------------------------------------------------------

  static final Map<LogicalKeyboardKey, (int, int)> _moveKeys = {
    LogicalKeyboardKey.arrowLeft: (-1, 0),
    LogicalKeyboardKey.keyA: (-1, 0),
    LogicalKeyboardKey.arrowRight: (1, 0),
    LogicalKeyboardKey.keyD: (1, 0),
    LogicalKeyboardKey.arrowUp: (0, -1),
    LogicalKeyboardKey.keyW: (0, -1),
    LogicalKeyboardKey.arrowDown: (0, 1),
    LogicalKeyboardKey.keyS: (0, 1),
  };

  static final Set<LogicalKeyboardKey> _actionKeys = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.keyE,
  };

  static final Set<LogicalKeyboardKey> _otherKeys = {
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.escape,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final move = _moveKeys[key];
    if (move == null && !_actionKeys.contains(key) && !_otherKeys.contains(key)) {
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) {
      _keys.remove(key);
      return KeyEventResult.handled;
    }

    // Richtungstasten blättern in Menüs – auch bei gehaltener Taste.
    if (move != null) {
      _input
        ..navX = move.$1
        ..navY = move.$2;
    }
    if (event is KeyDownEvent) {
      _userGesture();
      _keys.add(key);
      if (_actionKeys.contains(key)) _input.action = true;
      if (key == LogicalKeyboardKey.keyQ) _input.log = true;
      if (key == LogicalKeyboardKey.keyI) _input.inventory = true;
      if (key == LogicalKeyboardKey.keyM) _input.music = true;
      if (key == LogicalKeyboardKey.escape) _input.menu = true;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------
  // Maus und Touch
  // ---------------------------------------------------------------------

  void _pointerDown(PointerDownEvent e) {
    _focus.requestFocus();
    _userGesture();
    if (e.kind == PointerDeviceKind.touch) _touch.visible = true;
    final renderer = _renderer;
    if (renderer == null) return;

    final p = e.localPosition / _scale;
    final g = _game;
    final hit = renderer.hit;

    if (g.screen == Screen.title) {
      if (!g.canContinue) {
        _input.action = true;
      } else {
        final option = HitRegions.indexAt(hit.titleOptions, p);
        if (option != null) g.activateTitle(option);
      }
      return;
    }
    if (g.screen == Screen.ending || g.dialog != null) {
      _input.action = true;
      return;
    }

    switch (g.panel) {
      case Panel.menu:
        final entry = HitRegions.indexAt(hit.menuItems, p);
        if (entry != null) {
          g.activateMenu(entry);
        } else if (!hit.panel.contains(p)) {
          _input.menu = true;
        }
        return;
      case Panel.inventory:
        _inventoryPointerDown(e, p, hit);
        return;
      case Panel.questLog:
        _input.log = true;
        return;
      case Panel.none:
        break;
    }

    if (UiLayout.bagButton(_view, _pad).inflate(2).contains(p)) {
      _input.inventory = true;
      return;
    }
    if (UiLayout.logButton(_view, _pad).inflate(2).contains(p)) {
      _input.log = true;
      return;
    }
    if (UiLayout.menuButton(_view, _pad).inflate(2).contains(p)) {
      _input.menu = true;
      return;
    }
    final toAction = (p - UiLayout.actionCenter(_view, _pad)).distance;
    if (_touch.visible && toAction <= UiLayout.actionRadius + 8) {
      _input.action = true;
      return;
    }
    if (p.dx < _view.width * 0.5) {
      if (_touch.pointer == null) {
        _touch
          ..pointer = e.pointer
          ..base = p
          ..pos = p;
      }
    } else {
      _input.action = true;
    }
  }

  /// Inventar: Antippen nimmt auf bzw. legt ab, Ziehen verschiebt direkt.
  void _inventoryPointerDown(PointerDownEvent e, Offset p, HitRegions hit) {
    final g = _game;
    final slot = HitRegions.indexAt(hit.slots, p);
    if (slot == null) {
      if (!hit.panel.contains(p)) _input.inventory = true;
      return;
    }
    g.invCursor = slot;
    if (g.invHeld == null && g.inventory.slots[slot] != null) {
      g.invHeld = slot;
      _touch
        ..dragPointer = e.pointer
        ..dragFrom = slot
        ..dragPos = p;
    } else {
      g.inventoryAction();
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    final p = e.localPosition / _scale;
    if (e.pointer == _touch.pointer) _touch.pos = p;
    if (e.pointer == _touch.dragPointer) _touch.dragPos = p;
  }

  void _pointerEnd(PointerEvent e) {
    if (e.pointer == _touch.pointer) _touch.release();
    if (e.pointer != _touch.dragPointer) return;

    final from = _touch.dragFrom;
    _touch.endDrag();
    final g = _game;
    final renderer = _renderer;
    if (renderer == null || g.panel != Panel.inventory || g.invHeld != from) {
      return;
    }
    final slot = HitRegions.indexAt(
      renderer.hit.slots,
      e.localPosition / _scale,
    );
    if (slot == null) {
      g.invHeld = null; // neben dem Raster losgelassen: zurücklegen
    } else if (slot != from) {
      g.invCursor = slot;
      g.inventoryAction(); // auf anderem Feld losgelassen: verschieben
    }
    // Auf demselben Feld losgelassen: bleibt "in der Hand" (Antippen).
  }

  // ---------------------------------------------------------------------
  // Aufbau
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final dpr = media.devicePixelRatio;

        // Ein Spielpixel ist immer eine ganze Zahl von Gerätepixeln groß –
        // so bleibt die Pixelart auf jedem Bildschirm gestochen scharf.
        final shortSide = math.min(size.width, size.height) * dpr;
        final devicePixels = (shortSide / 180).round().clamp(2, 16);
        _scale = devicePixels / dpr;
        _view = size / _scale;
        _pad = EdgeInsets.fromLTRB(
          media.padding.left / _scale,
          media.padding.top / _scale,
          media.padding.right / _scale,
          media.padding.bottom / _scale,
        );

        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          onFocusChange: (focused) {
            if (!focused) _keys.clear();
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerEnd,
            onPointerCancel: _pointerEnd,
            child: CustomPaint(
              painter: _GamePainter(
                game: _game,
                renderer: _renderer,
                scale: _scale,
                pad: _pad,
                touch: _touch,
                repaint: _frame,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter({
    required this.game,
    required this.renderer,
    required this.scale,
    required this.pad,
    required this.touch,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final AdventureGame game;
  final GameRenderer? renderer;
  final double scale;
  final EdgeInsets pad;
  final TouchState touch;

  @override
  void paint(Canvas canvas, Size size) {
    final r = renderer;
    if (r == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1C3A26));
      return;
    }
    r.render(canvas, size, scale, pad, game, touch);
  }

  @override
  bool shouldRepaint(_GamePainter oldDelegate) =>
      oldDelegate.game != game ||
      oldDelegate.renderer != renderer ||
      oldDelegate.scale != scale ||
      oldDelegate.pad != pad;
}
