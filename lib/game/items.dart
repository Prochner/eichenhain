enum ItemKind { weapon, boots, charm, consumable, quest }

/// Alle Gegenstände des Spiels.
enum Item {
  sword(
    'Schwert',
    'Brunos Klinge. Ausgerüstet schlägst du mit der Aktionstaste zu.',
    ItemKind.weapon,
  ),
  windBoots(
    'Windstiefel',
    'Mit Windkraut eingerieben. Ausgerüstet läufst du schneller.',
    ItemKind.boots,
  ),
  amulet(
    'Amulett von Eichenhain',
    'Sein Licht schützt das Dorf. Als Talisman heilt es dich langsam.',
    ItemKind.charm,
  ),
  ruinKey(
    'Ruinenschlüssel',
    'Ein alter Eisenschlüssel. Er passt zum Tor der Ruine im Norden.',
    ItemKind.quest,
  ),
  redBloom(
    'Rotblüte',
    'Eine seltene Blume aus dem Flüsterwald. Heilerin Elsa braucht sie.',
    ItemKind.quest,
    maxStack: 9,
  ),
  apple(
    'Apfel',
    'Frisch vom Baum. Heilt ein Herz.',
    ItemKind.consumable,
    maxStack: 9,
    heal: 1,
  ),
  smokedFish(
    'Räucherfisch',
    'Von Fischer Otto. Heilt zwei Herzen.',
    ItemKind.consumable,
    maxStack: 9,
    heal: 2,
  ),
  applePie(
    'Apfelkuchen',
    'Martas bester Kuchen. Heilt alle Herzen.',
    ItemKind.consumable,
    maxStack: 9,
    heal: 99,
  );

  const Item(
    this.label,
    this.description,
    this.kind, {
    this.maxStack = 1,
    this.heal = 0,
  });

  final String label;
  final String description;
  final ItemKind kind;

  /// Wie viele Stück auf ein Feld passen.
  final int maxStack;

  /// Geheilte Herzen beim Essen.
  final int heal;

  bool get isEquipment =>
      kind == ItemKind.weapon ||
      kind == ItemKind.boots ||
      kind == ItemKind.charm;
}

class ItemStack {
  ItemStack(this.item, this.count);

  final Item item;
  int count;
}

/// Ausrüstung (3 Felder) und Rucksack (12 Felder) in einer Liste:
/// Index 0–2 sind Waffe, Schuhe und Talisman, danach folgt der Rucksack.
class Inventory {
  static const int equipSlots = 3;
  static const int bagColumns = 4;
  static const int bagRows = 3;
  static const int bagSlots = bagColumns * bagRows;
  static const int size = equipSlots + bagSlots;

  static const List<ItemKind> equipKinds = [
    ItemKind.weapon,
    ItemKind.boots,
    ItemKind.charm,
  ];
  static const List<String> equipLabels = ['Waffe', 'Schuhe', 'Talisman'];

  final List<ItemStack?> slots = List<ItemStack?>.filled(size, null);

  static bool isEquipSlot(int slot) => slot < equipSlots;

  /// Ausrüstungsfeld für [item] oder null, wenn es keine Ausrüstung ist.
  static int? equipSlotFor(Item item) {
    final i = equipKinds.indexOf(item.kind);
    return i < 0 ? null : i;
  }

  int count(Item item) {
    var n = 0;
    for (final s in slots) {
      if (s != null && s.item == item) n += s.count;
    }
    return n;
  }

  bool has(Item item) => count(item) > 0;

  bool isEquipped(Item item) {
    for (var i = 0; i < equipSlots; i++) {
      if (slots[i]?.item == item) return true;
    }
    return false;
  }

  /// Darf [item] auf das Feld [slot]?
  bool accepts(int slot, Item item) =>
      !isEquipSlot(slot) || equipKinds[slot] == item.kind;

  int? firstFreeBagSlot() {
    for (var i = equipSlots; i < size; i++) {
      if (slots[i] == null) return i;
    }
    return null;
  }

  /// Legt Gegenstände ab: erst auf vorhandene Stapel, Ausrüstung in ein
  /// freies Ausrüstungsfeld, sonst in den Rucksack. Liefert die Anzahl,
  /// die keinen Platz mehr gefunden hat.
  int add(Item item, {int count = 1}) {
    var left = count;
    if (item.maxStack > 1) {
      for (final s in slots) {
        if (left == 0) break;
        if (s == null || s.item != item) continue;
        final moved = _min(item.maxStack - s.count, left);
        s.count += moved;
        left -= moved;
      }
    }
    final equip = equipSlotFor(item);
    if (left > 0 && equip != null && slots[equip] == null) {
      slots[equip] = ItemStack(item, 1);
      left--;
    }
    while (left > 0) {
      final free = firstFreeBagSlot();
      if (free == null) break;
      final moved = _min(item.maxStack, left);
      slots[free] = ItemStack(item, moved);
      left -= moved;
    }
    return left;
  }

  /// Entfernt bis zu [count] Stück (Rucksack zuerst); liefert die Anzahl,
  /// die tatsächlich entfernt wurde.
  int remove(Item item, int count) {
    var left = count;
    for (var i = size - 1; i >= 0 && left > 0; i--) {
      final s = slots[i];
      if (s == null || s.item != item) continue;
      final taken = _min(s.count, left);
      s.count -= taken;
      left -= taken;
      if (s.count == 0) slots[i] = null;
    }
    return count - left;
  }

  /// Verschiebt den Inhalt von [from] nach [to]. Gleiche Gegenstände werden
  /// gestapelt, verschiedene tauschen die Plätze. Liefert false, wenn der
  /// Zug nicht erlaubt ist (z. B. ein Apfel im Waffenfeld).
  bool move(int from, int to) {
    if (from == to) return false;
    final a = slots[from];
    if (a == null) return false;
    if (!accepts(to, a.item)) return false;
    final b = slots[to];
    if (b != null) {
      if (b.item == a.item && a.item.maxStack > 1) {
        final moved = _min(a.item.maxStack - b.count, a.count);
        if (moved == 0) return false;
        b.count += moved;
        a.count -= moved;
        if (a.count == 0) slots[from] = null;
        return true;
      }
      if (!accepts(from, b.item)) return false;
    }
    slots[to] = a;
    slots[from] = b;
    return true;
  }

  List<Object?> toJson() => [
    for (final s in slots)
      s == null ? null : {'item': s.item.name, 'count': s.count},
  ];

  void loadJson(List<dynamic> data) {
    slots.fillRange(0, size, null);
    for (var i = 0; i < data.length && i < size; i++) {
      final entry = data[i];
      if (entry == null) continue;
      final map = entry as Map<String, dynamic>;
      final item = Item.values.byName(map['item'] as String);
      final count = (map['count'] as num).toInt();
      if (count <= 0 || !accepts(i, item)) continue;
      slots[i] = ItemStack(item, _min(count, item.maxStack));
    }
  }

  static int _min(int a, int b) => a < b ? a : b;
}
