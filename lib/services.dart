import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dauerhafter Speicher für Spielstand und Einstellungen.
abstract class SaveStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Speichert über shared_preferences: im Web im localStorage des Browsers,
/// auf Windows, Android und iOS in den App-Einstellungen des Geräts.
class PrefsSaveStore implements SaveStore {
  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> get _instance =>
      _prefs ??= SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance).getString(key);

  @override
  Future<void> write(String key, String value) async {
    final ok = await (await _instance).setString(key, value);
    if (!ok) throw StateError('Speichern von "$key" fehlgeschlagen');
  }
}

/// Flüchtiger Speicher für Tests.
class MemorySaveStore implements SaveStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Hintergrundmusik.
abstract class MusicPlayer {
  /// Startet die Musik. Erst nach einer Eingabe des Spielers aufrufen –
  /// Browser erlauben vorher keinen Ton.
  Future<void> start({required bool enabled});

  /// Schaltet die Musik an oder aus.
  Future<void> setEnabled(bool enabled);

  /// Pausiert, solange die App im Hintergrund ist.
  Future<void> setSuspended(bool suspended);

  Future<void> dispose();
}

/// Spielt die Dorfmelodie aus den Assets in Dauerschleife.
class AssetMusicPlayer implements MusicPlayer {
  static const String _asset = 'audio/dorfmelodie.wav';
  static const double _volume = 0.45;

  AudioPlayer? _player;
  bool _started = false;
  bool _enabled = true;
  bool _suspended = false;
  bool _loaded = false;

  @override
  Future<void> start({required bool enabled}) {
    _started = true;
    _enabled = enabled;
    return _apply();
  }

  @override
  Future<void> setEnabled(bool enabled) {
    _enabled = enabled;
    return _apply();
  }

  @override
  Future<void> setSuspended(bool suspended) {
    _suspended = suspended;
    return _apply();
  }

  Future<void> _apply() async {
    if (!_started) return;
    final shouldPlay = _enabled && !_suspended;
    // Fehlender Ton darf das Spiel nie anhalten.
    try {
      if (shouldPlay) {
        final player = _player ??= AudioPlayer();
        if (_loaded) {
          await player.resume();
        } else {
          await player.setReleaseMode(ReleaseMode.loop);
          await player.play(AssetSource(_asset), volume: _volume);
          _loaded = true;
        }
      } else {
        await _player?.pause();
      }
    } catch (_) {
      _loaded = false;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}

/// Kein Ton (für Tests).
class SilentMusicPlayer implements MusicPlayer {
  bool started = false;
  bool enabled = true;

  @override
  Future<void> start({required bool enabled}) async {
    started = true;
    this.enabled = enabled;
  }

  @override
  Future<void> setEnabled(bool enabled) async => this.enabled = enabled;

  @override
  Future<void> setSuspended(bool suspended) async {}

  @override
  Future<void> dispose() async {}
}

class GameServices {
  const GameServices({required this.store, required this.music});

  factory GameServices.device() =>
      GameServices(store: PrefsSaveStore(), music: AssetMusicPlayer());

  final SaveStore store;
  final MusicPlayer music;
}
