import 'items.dart';
import 'world.dart';

enum Dir { down, up, left, right }

extension DirVector on Dir {
  double get dx => switch (this) {
    Dir.left => -1,
    Dir.right => 1,
    _ => 0,
  };

  double get dy => switch (this) {
    Dir.up => -1,
    Dir.down => 1,
    _ => 0,
  };
}

/// Alles, was in der Welt steht und mit Kacheln kollidiert.
/// (x, y) ist der Standpunkt; die Trefferbox liegt um die Füße.
class Body {
  Body(this.x, this.y);

  double x;
  double y;

  double get halfWidth => 5;
  double get top => 3;
  double get bottom => 4;
}

class Player extends Body {
  Player() : super(World.playerStart.cx, World.playerStart.cy);

  static const double attackDuration = 0.28;

  Dir dir = Dir.down;
  bool moving = false;
  double walkTime = 0;
  int hearts = 3;
  int maxHearts = 3;
  double invulnerable = 0;
  double attackTime = 0;
}

enum NpcId { hilda, bruno, marta, elsa, otto }

class Npc extends Body {
  Npc(this.id, this.name, this.tilePos) : super(tilePos.cx, tilePos.cy);

  final NpcId id;
  final String name;
  final TilePos tilePos;
}

class Chicken extends Body {
  Chicken(TilePos p) : super(p.cx, p.cy);

  double vx = 0;
  double vy = 0;
  double timer = 0;
  double anim = 0;
  bool faceLeft = false;

  /// Eingefangen und zurück im Gehege.
  bool home = false;

  @override
  double get halfWidth => 4;

  @override
  double get top => 2;
}

class Slime extends Body {
  Slime(TilePos p, {this.leash = 44})
    : homeX = p.cx,
      homeY = p.cy,
      targetX = p.cx,
      targetY = p.cy,
      super(p.cx, p.cy);

  static const int maxHp = 2;

  final double homeX;
  final double homeY;
  final double leash;

  int hp = maxHp;
  bool alive = true;
  double hurt = 0;
  double respawn = 0;
  double hop = 0;
  double knockX = 0;
  double knockY = 0;
  double wanderTimer = 0;
  double targetX;
  double targetY;
}

/// Etwas, das am Boden liegt und eingesammelt werden kann.
class Pickup {
  Pickup(TilePos p, this.item)
    : x = p.tx * World.tile + 8.0,
      y = p.ty * World.tile + 8.0;

  final Item item;
  final double x;
  final double y;
  bool taken = false;
}
