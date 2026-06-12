#!/usr/bin/env python3
"""Regenerate the launch-film ambient bed (v3: 58s).

Warm, fully-synthesized chord pads — ownable, no samples. Each chord is a
stack of soft sine partials with a slow amplitude LFO; chords crossfade so
the bed breathes under the narration beats. Writes video/public/bed.wav.
"""
import numpy as np
import wave
import os

SR = 44100
DUR = 58.0

def note(freq, t, lfo_rate=0.13, lfo_depth=0.18):
    # Soft partials: fundamental + quiet octave + faint fifth — warm, not buzzy.
    s = (np.sin(2 * np.pi * freq * t)
         + 0.35 * np.sin(2 * np.pi * freq * 2 * t)
         + 0.18 * np.sin(2 * np.pi * freq * 3 * t))
    lfo = 1.0 + lfo_depth * np.sin(2 * np.pi * lfo_rate * t + freq % 3.0)
    return s * lfo

# Progression (Am – F – C – G – Am – F feel, low voicings), ~9.7s per chord.
CHORDS = [
    [110.00, 164.81, 220.00, 261.63],   # A2 E3 A3 C4
    [ 87.31, 130.81, 174.61, 220.00],   # F2 C3 F3 A3
    [ 98.00, 130.81, 196.00, 246.94],   # G2 C3 G3 B3
    [ 87.31, 130.81, 174.61, 261.63],   # F2 C3 F3 C4
    [110.00, 164.81, 220.00, 329.63],   # A2 E3 A3 E4 (lift)
    [ 87.31, 130.81, 174.61, 220.00],   # F2 C3 F3 A3 (resolve, fades out)
]

n = int(SR * DUR)
t = np.arange(n) / SR
mix = np.zeros(n)
seg = DUR / len(CHORDS)
xfade = 2.4  # seconds of overlap between chords

for i, chord in enumerate(CHORDS):
    start, end = i * seg, (i + 1) * seg
    env = np.clip((t - (start - xfade)) / xfade, 0, 1) * np.clip(((end + xfade) - t) / xfade, 0, 1)
    pad = sum(note(f, t) for f in chord) / len(chord)
    mix += pad * env

# Master envelope: gentle fade-in, long tail out.
master = np.clip(t / 2.5, 0, 1) * np.clip((DUR - t) / 4.0, 0, 1)
mix *= master
mix = mix / np.max(np.abs(mix)) * 0.32   # quiet bed — narration sits on top

stereo = np.stack([mix, np.roll(mix, int(0.011 * SR))], axis=1)  # tiny haas width
pcm = (stereo * 32767).astype(np.int16)

out = os.path.join(os.path.dirname(__file__), "..", "public", "bed.wav")
with wave.open(os.path.abspath(out), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"wrote {os.path.abspath(out)} ({DUR}s)")
