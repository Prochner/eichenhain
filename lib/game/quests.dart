import 'pixel_font.dart';

enum QuestId { amulet, slimes, chickens, herbs }

enum QuestStatus {
  /// Noch nicht angenommen.
  available,

  /// Angenommen, Ziel noch offen.
  active,

  /// Ziel erreicht – zurück zum Auftraggeber.
  ready,

  /// Belohnung erhalten.
  done,
}

class Quest {
  Quest(this.id, this.title, this.giver, {this.goal = 0})
    : assert(PixelFont.supports(title) && PixelFont.supports(giver));

  final QuestId id;
  final String title;
  final String giver;

  /// Anzahl zu sammelnder/besiegter Dinge (0 = Quest ohne Zähler).
  final int goal;

  QuestStatus status = QuestStatus.available;
  int progress = 0;

  bool get isActive => status == QuestStatus.active;
  bool get isReady => status == QuestStatus.ready;
  bool get isDone => status == QuestStatus.done;

  /// Im Questbuch sichtbar, sobald die Quest angenommen wurde.
  bool get discovered => status != QuestStatus.available;
}
