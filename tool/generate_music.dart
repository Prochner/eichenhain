// Erzeugt die Hintergrundmelodie des Spiels als WAV-Datei.
//
// Aufruf im Projektordner:
//   dart run tool/generate_music.dart
//
// Die Melodie ist ein eigener kleiner Dorfwalzer im Chiptune-Stil. Sie wird
// vollständig aus Wellenformen berechnet und so gebaut, dass sie sich
// nahtlos wiederholen lässt (ausklingende Töne laufen in den Anfang hinein).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;
const double bpm = 120;
const double beat = 60 / bpm;
const int bars = 16;
const int beatsPerBar = 3;

const double tau = math.pi * 2;

double freq(String note) {
  const semis = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  var i = 0;
  var semi = semis[note[i++]]!;
  if (note[i] == '#') {
    semi++;
    i++;
  } else if (note[i] == 'b') {
    semi--;
    i++;
  }
  final octave = int.parse(note.substring(i));
  final midi = 12 * (octave + 1) + semi;
  return 440.0 * math.pow(2, (midi - 69) / 12);
}

double triangle(double phase) {
  final p = (phase / tau) % 1.0;
  return p < 0.5 ? 4 * p - 1 : 3 - 4 * p;
}

late Float64List mix;

/// Mischt einen Ton ein; alles hinter dem Ende läuft in den Anfang zurück.
void addTone({
  required double startBeat,
  required double lengthBeats,
  required double frequency,
  required double Function(double phase) wave,
  required double Function(double t, double gate) envelope,
  required double amp,
  double release = 0.1,
  double vibrato = 0,
}) {
  final start = (startBeat * beat * sampleRate).round();
  final gate = lengthBeats * beat;
  final count = ((gate + release) * sampleRate).round();
  var phase = 0.0;
  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    var f = frequency;
    if (vibrato > 0 && t > 0.18) {
      final depth = vibrato * math.min(1.0, (t - 0.18) * 4);
      f *= 1 + math.sin(tau * 5.5 * t) * depth;
    }
    phase += tau * f / sampleRate;
    final index = (start + i) % mix.length;
    mix[index] += wave(phase) * envelope(t, gate) * amp;
  }
}

double leadWave(double p) =>
    0.62 * triangle(p) + 0.26 * math.sin(p) + 0.12 * math.sin(2 * p);

double leadEnvelope(double t, double gate) {
  var e = t < 0.02 ? t / 0.02 : 0.72 + 0.28 * math.exp(-(t - 0.02) * 9);
  if (t > gate) e *= math.max(0.0, 1 - (t - gate) / 0.1);
  return e;
}

double pluckWave(double p) =>
    0.7 * triangle(p) + 0.3 * (math.sin(p) >= 0 ? 0.6 : -0.6);

double pluckEnvelope(double t, double gate) =>
    math.min(1.0, t / 0.005) * math.exp(-t * 5.5);

double bassWave(double p) => 0.75 * triangle(p) + 0.35 * math.sin(2 * p);

double bassEnvelope(double t, double gate) {
  var e = math.min(1.0, t / 0.01) * math.exp(-t * 1.6);
  if (t > gate) e *= math.max(0.0, 1 - (t - gate) / 0.1);
  return e;
}

void main() {
  final total = (bars * beatsPerBar * beat * sampleRate).round();
  mix = Float64List(total);

  // Melodie: je Takt eine Liste aus (Ton, Länge in Schlägen).
  const melody = <List<(String, double)>>[
    [('E5', 1), ('G5', 1), ('E5', 1)],
    [('D5', 2), ('G5', 1)],
    [('C5', 1), ('E5', 1), ('A5', 1)],
    [('A5', 2), ('F5', 1)],
    [('G5', 1), ('E5', 1), ('C5', 1)],
    [('F5', 1), ('A5', 1), ('C6', 1)],
    [('B5', 1.5), ('A5', 0.5), ('G5', 1)],
    [('D5', 3)],
    [('E5', 1), ('A5', 1), ('C6', 1)],
    [('B5', 2), ('G5', 1)],
    [('A5', 1), ('F5', 1), ('C5', 1)],
    [('E5', 2), ('G5', 1)],
    [('F5', 1), ('A5', 1), ('F5', 1)],
    [('E5', 1), ('G5', 1), ('E5', 1)],
    [('D5', 1), ('F5', 0.5), ('E5', 0.5), ('D5', 1)],
    [('C5', 3)],
  ];

  // Begleitung: Basston auf der Eins, zwei Akkordtöne auf Zwei und Drei.
  const backing = <(String, String, String)>[
    ('C3', 'E4', 'G4'),
    ('B2', 'D4', 'G4'),
    ('A2', 'C4', 'E4'),
    ('F2', 'C4', 'F4'),
    ('C3', 'E4', 'G4'),
    ('F2', 'C4', 'F4'),
    ('G2', 'B3', 'D4'),
    ('G2', 'B3', 'D4'),
    ('A2', 'C4', 'E4'),
    ('E2', 'B3', 'E4'),
    ('F2', 'C4', 'F4'),
    ('C3', 'E4', 'G4'),
    ('F2', 'C4', 'F4'),
    ('C3', 'E4', 'G4'),
    ('G2', 'B3', 'D4'),
    ('C3', 'E4', 'G4'),
  ];

  for (var bar = 0; bar < bars; bar++) {
    final barStart = bar * beatsPerBar * 1.0;

    var at = barStart;
    for (final (note, length) in melody[bar]) {
      addTone(
        startBeat: at,
        lengthBeats: length * 0.94,
        frequency: freq(note),
        wave: leadWave,
        envelope: leadEnvelope,
        amp: 0.30,
        vibrato: 0.004,
      );
      // Im zweiten Teil singt eine leise Unteroktave mit.
      if (bar >= 8) {
        addTone(
          startBeat: at,
          lengthBeats: length * 0.94,
          frequency: freq(note) / 2,
          wave: leadWave,
          envelope: leadEnvelope,
          amp: 0.10,
        );
      }
      at += length;
    }

    final (bass, low, high) = backing[bar];
    addTone(
      startBeat: barStart,
      lengthBeats: 1.6,
      frequency: freq(bass),
      wave: bassWave,
      envelope: bassEnvelope,
      amp: 0.30,
    );
    for (final offset in const [1.0, 2.0]) {
      for (final note in [low, high]) {
        addTone(
          startBeat: barStart + offset,
          lengthBeats: 0.8,
          frequency: freq(note),
          wave: pluckWave,
          envelope: pluckEnvelope,
          amp: 0.11,
          release: 0.3,
        );
      }
    }
  }

  // Sanfter Tiefpass (zweimal im Kreis, damit die Schleife nahtlos bleibt).
  var y = 0.0;
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < mix.length; i++) {
      y += 0.5 * (mix[i] - y);
      if (pass == 1) mix[i] = y;
    }
  }

  var peak = 0.0;
  for (final v in mix) {
    peak = math.max(peak, v.abs());
  }
  final gain = 0.72 / peak;

  final data = ByteData(44 + mix.length * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + mix.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, mix.length * 2, Endian.little);
  for (var i = 0; i < mix.length; i++) {
    final v = (mix[i] * gain * 32767).round().clamp(-32768, 32767);
    data.setInt16(44 + i * 2, v, Endian.little);
  }

  final file = File('assets/audio/dorfmelodie.wav');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data.buffer.asUint8List());
  final seconds = (mix.length / sampleRate).toStringAsFixed(1);
  stdout.writeln('${file.path}: $seconds s, ${file.lengthSync()} Bytes');
}
