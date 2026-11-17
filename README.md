# Eichenhain

Ein kleines 2D-Abenteuer im Pixelart-Stil, gebaut mit Flutter für Web,
Windows, iOS und Android.

Du spielst Finn (kurze braune Haare, blaue Tunika) und hilfst dem Dorf
Eichenhain: Sprich mit den Dorfbewohnern, nimm Quests an und hole das
verlorene Amulett aus der alten Ruine zurück.

## Quests

| Quest | Auftraggeber | Belohnung |
| --- | --- | --- |
| Das Amulett von Eichenhain (Hauptquest) | Dorfälteste Hilda | Abspann |
| Schleimjagd | Schmied Bruno | Schwert, danach der Ruinenschlüssel |
| Ausgebüxte Hühner | Bäuerin Marta | ein zusätzliches Herz |
| Rotblüten | Heilerin Elsa | schnelleres Laufen |

Der Dorfbrunnen füllt die Herzen wieder auf.

## Steuerung

| | Tastatur | Touch / Maus |
| --- | --- | --- |
| Laufen | WASD oder Pfeiltasten | linke Bildhälfte ziehen |
| Aktion (reden, benutzen, Schwert) | Leertaste, Enter oder E | rechte Bildhälfte tippen / A-Knopf |
| Questbuch | Q (schließen auch mit Esc) | Knopf oben rechts |

## Starten

```bash
flutter run -d chrome
```

```bash
flutter run -d windows
```

Android und iOS laufen über `flutter run` mit angeschlossenem Gerät oder
Emulator. Für Windows wird Visual Studio (C++-Desktop-Workload) benötigt, für
Android das Android SDK, für iOS ein Mac mit Xcode.

## Webversion auf GitHub Pages

Die gebaute Webversion liegt im Ordner `docs/` und ist unter
https://prochner.github.io/eichenhain/ erreichbar (GitHub: *Settings → Pages →
Branch `main`, Ordner `/docs`*).

Nach Änderungen am Spiel neu bauen und `docs/` mit committen (in PowerShell):

```powershell
flutter build web --release --base-href /eichenhain/ -o docs
New-Item -ItemType File docs/.nojekyll -Force
```

## Tests

```bash
flutter test
```

## Aufbau

- `lib/main.dart` – App, Spielschleife, Tastatur-, Maus- und Touch-Eingabe
- `lib/game/game.dart` – Spiellogik: Quests, Dialoge, Kampf, Kollision
- `lib/game/world.dart` – die Karte (Dorf, Ruine, Wald, See)
- `lib/game/sprites.dart` – die gesamte Pixelart, im Code gezeichnet
- `lib/game/pixel_font.dart` – eigene Pixel-Schrift mit Umlauten
- `lib/game/renderer.dart` – Zeichnen von Welt, Figuren und Oberfläche

Das Spiel braucht keine Bild- oder Schriftdateien und keine zusätzlichen
Pakete: Alle Grafiken entstehen beim Start aus dem Code.
