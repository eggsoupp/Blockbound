"""Two more exploration pieces on the Homeward melody: a night theme and a cave theme.

Same engine as the adventure tracks: compose.py renders each part through the
workspace GeneralUser GS soundfont, compose_v2.py supplies the theme helpers and
checks. What is new here is the space each piece sits in - a soft, wide night
air and a long, dark cave reverb with a faint echo - and the instrumentation.

    night  "Under the Stars"   72 BPM. Music box and celesta over warm pads and
                               slow harp, leaning on E minor; the theme appears
                               once, an octave up, like something half-remembered.
    cave   "Echoes Below"      64 BPM. Low piano carries the theme deep under
                               cello and contrabass drones and a faint choir;
                               sparse kalimba notes fall like drips and echo.

Run with the bundled Python:  python -I compose_night_cave.py
"""
from pathlib import Path
import importlib.util
import json
import math
import numpy as np

OUT = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v2 = load('compose_v2', OUT / 'compose_v2.py')
eng = v2.eng
SR = eng.SR
A = eng.Arrangement
V = eng.VOICINGS
V.update(B=(35, 42, 51, 54), Cmaj7=(36, 43, 52, 59), Am7=(33, 45, 52, 55), Em9=(40, 47, 54, 59))
theme, phrase, setup = v2.theme, v2.phrase, v2.setup

# E minor pentatonic, high: what the cave drips and night sparkles choose from.
PENTATONIC = [76, 79, 81, 83, 86, 88, 91]


def slow_harp(a, part, start, chord, velocity=42):
    """Four notes rising across the bar, unhurried."""
    root, fifth, third, top = V[chord]
    for i, (offset, pitch) in enumerate([(0, root + 12), (1, fifth + 12), (2, third + 12), (3, top + 12)]):
        a.note(part, start + offset, pitch, 2.6 if i < 3 else 0.9, velocity + (4 if i == 0 else 0))


def long_pad(a, part, start, chord, beats=4, velocity=40, octave=0):
    _, fifth, third, top = V[chord]
    for pitch in (fifth + octave, third + octave, top + octave):
        a.note(part, start, pitch, beats - 0.1, velocity)


def night():
    a = setup(A('night', 'Under the Stars', [(0, 72, 'Slow night air')], 128,
                'Music box and celesta drift over warm pads and slow harp; the theme visits once, '
                'an octave up, between long stretches of quiet harmony.'),
              [(0, 16), (64, 96), (112, 128)])
    a.part('Music box theme fragments', 10, -23, 64, .16)
    a.part('Celesta theme fragments', 8, -26, 74, .18)
    a.part('Warm pad', 89, -34, 64, .25)
    a.part('Slow harp', 46, -34, 42, .24)
    a.part('Low strings', 49, -37, 86, .22)
    a.part('Cello', 42, -36, 54, .15)
    a.part('Starlight celesta', 8, -36, 50, .3)
    a.markers = [(0, 'Dusk - no theme'), (16, 'First stars'), (32, 'Homeward, half-remembered'),
                 (64, 'Night walk - no theme'), (96, 'Fading memory'), (112, 'Before dawn - no theme')]
    chords = (['Em9', 'C', 'Am7', 'Em9'] + ['Em', 'C', 'Am', 'B'] + eng.PROGRESSION +
              ['Am7', 'Em', 'C', 'B', 'Am7', 'Em', 'Cmaj7', 'B'] + ['Em', 'C', 'Am', 'Em'] + ['Cmaj7', 'Am7', 'Em9', 'Em9'])
    assert len(chords) * 4 == a.end
    rng = np.random.default_rng(1307)
    for i, chord in enumerate(chords):
        b = i * 4
        long_pad(a, 'Warm pad', b, chord, velocity=38 if b < 16 or b >= 112 else 43)
        if b >= 8 and b < 120:
            slow_harp(a, 'Slow harp', b, chord, velocity=38 if 64 <= b < 96 else 42)
        if b >= 16:
            a.note('Cello', b, V[chord][0], 3.85, 42)
        if 32 <= b < 112 and i % 2 == 0:
            long_pad(a, 'Low strings', b, chord, beats=8, velocity=40, octave=12)
        # Starlight: an occasional high celesta note in the quiet passages.
        if (b < 16 or 64 <= b < 96 or b >= 112) and b % 8 == 4:
            a.note('Starlight celesta', b + 2.5, int(rng.choice(PENTATONIC)), 1.4, 38)
    phrase(a, 'Celesta theme fragments', 16, [(0, 71, 1.6, 58), (2, 69, .7, 52), (3, 67, 2.4, 55),
                                              (8, 69, 1.8, 56), (11, 66, .9, 50), (13, 64, 2.6, 54)], 12)
    theme(a, 'Music box theme fragments', 32, transpose=12, velocity=-16)
    phrase(a, 'Music box theme fragments', 96, [(0, 71, 2.4, 52), (4, 69, 1.4, 46), (6, 67, 3, 50),
                                                (10, 64, 3.6, 46)], 12)
    return a


def cave():
    a = setup(A('cave', 'Echoes Below', [(0, 64, 'Deep and still')], 112,
                'Low piano carries the theme far underground over cello and contrabass drones and a '
                'faint choir; sparse kalimba notes fall like drips and echo away.'),
              [(0, 24), (64, 88), (104, 112)])
    a.part('Low piano theme fragments', 0, -23, 60, .26)
    a.part('Contrabass drone', 43, -34, 64, .2)
    a.part('Cello drone', 42, -36, 46, .24)
    a.part('Distant choir', 52, -37, 82, .4)
    a.part('Kalimba drips', 108, -33, 64, .45)
    a.part('Dark atmosphere', 95, -36, 64, .35)
    a.markers = [(0, 'Darkness - no theme'), (24, 'Something familiar'), (32, 'Homeward, far below'),
                 (64, 'Deeper - no theme'), (88, 'An echo of home'), (104, 'Silence - no theme')]
    chords = (['Em', 'Em', 'C', 'Em', 'Am', 'B'] + ['Em', 'C'] + eng.PROGRESSION +
              ['Am', 'Em', 'C', 'B', 'Am', 'Em', 'C', 'B'] + ['Em', 'C'] + ['Em', 'Em'])
    assert len(chords) * 4 == a.end
    rng = np.random.default_rng(4096)
    for i, chord in enumerate(chords):
        b = i * 4
        root = V[chord][0]
        if i % 2 == 0:
            # Drones change every two bars at most, so they feel like the rock itself.
            a.note('Contrabass drone', b, root, 7.8 if b + 8 <= a.end else 3.8, 50)
        a.note('Cello drone', b, root + 7, 3.85, 40)
        if 24 <= b < 104 and i % 2 == 1:
            long_pad(a, 'Distant choir', b - 4, chord, beats=8, velocity=36, octave=12)
        if b % 16 == 0:
            a.note('Dark atmosphere', b, root + 24, 15.6 if b + 16 <= a.end else a.end - b - .2, 40)
        # Drips: one or two per bar at uneven times, sparser under the theme.
        count = 1 if 32 <= b < 56 else int(rng.integers(1, 3))
        for offset in sorted(rng.choice([.5, 1.25, 2, 2.75, 3.25], size=count, replace=False)):
            a.note('Kalimba drips', b + float(offset), int(rng.choice(PENTATONIC)), .5, int(rng.integers(34, 46)))
    phrase(a, 'Low piano theme fragments', 24, [(0, 71, 1.8, 58), (2, 69, .8, 52), (3, 67, 2.6, 55)], -12)
    theme(a, 'Low piano theme fragments', 32, transpose=-12, velocity=-12)
    phrase(a, 'Low piano theme fragments', 88, [(0, 71, 2.2, 54), (3, 69, .9, 48), (4, 67, 2.4, 52),
                                                (8, 64, 3.4, 48)], -12)
    return a


def convolve(send, impulse):
    n, irn = len(send), len(impulse)
    size = 1 << (n + irn - 1).bit_length()
    out = np.empty_like(send)
    for ch in range(2):
        out[:, ch] = np.fft.irfft(np.fft.rfft(send[:, ch], size) * np.fft.rfft(impulse[:, ch], size), size)[:n]
    return out


def space(send, seconds, decay, predelay, brightness, seed):
    """A diffuse tail: filtered noise under an exponential decay, per channel."""
    irn = round(seconds * SR)
    rng = np.random.default_rng(seed)
    impulse = rng.normal(size=(irn, 2)).astype(np.float32)
    envelope = np.exp(-np.arange(irn) / (SR * decay))
    envelope[:round(predelay * SR)] = 0
    for ch in range(2):
        impulse[:, ch] = np.convolve(impulse[:, ch], np.ones(brightness) / brightness, mode='same') * envelope
        impulse[:, ch] /= max(np.sqrt(np.sum(impulse[:, ch] ** 2)), 1e-8)
    return convolve(send, impulse)


def echo(send, delay, feedback, repeats):
    out = np.zeros_like(send)
    step = round(delay * SR)
    for k in range(1, repeats + 1):
        shift = step * k
        if shift >= len(send):
            break
        gain = feedback ** k
        # Alternate sides so the echoes move around the cave.
        left, right = (1.0, .55) if k % 2 else (.55, 1.0)
        out[shift:, 0] += send[:-shift, 0] * gain * left
        out[shift:, 1] += send[:-shift, 1] * gain * right
    return out


SPACES = {
    'night': dict(seconds=2.4, decay=.55, predelay=.02, brightness=24, seed=72),
    'cave': dict(seconds=4.5, decay=1.15, predelay=.045, brightness=40, seed=64),
}
TARGET_RMS = {'night': -23, 'cave': -24}


def render(a):
    v2.validate(a)
    tail = 4.5
    n = round((a.seconds(a.end) + tail) * SR)
    mix = np.zeros((n, 2), np.float32)
    send = np.zeros_like(mix)
    lead = np.zeros_like(mix)
    for name, part in a.parts.items():
        raw = eng.render_part(a, name)
        signal = np.zeros((n, 2), np.float32)
        signal[:len(raw)] = raw[:n]
        signal = v2.normalize_active(a, name, signal)
        if 'theme fragments' in name.lower():
            lead += signal
        mix += signal
        send += signal * part['wet']
        print(a.slug + ': ' + name, flush=True)
    wet = space(send, **SPACES[a.slug])
    if a.slug == 'cave':
        wet += echo(send, delay=60 / 64 * 1.5, feedback=.38, repeats=4) * .5
    dry_backing = mix - lead
    mix += wet * 1.6
    body = mix[:round(a.seconds(a.end) * SR)]
    gain = min(10 ** (TARGET_RMS[a.slug] / 20) / float(np.sqrt(np.mean(body ** 2))),
               10 ** (-1.5 / 20) / float(np.max(np.abs(mix))))
    mix *= gain
    lead *= gain
    # Fade in from silence and let the tail die completely.
    fade_in = round(1.5 * SR)
    mix[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    fade_out = round(3 * SR)
    mix[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None] ** 2
    largest = max(p['render_gain'] for p in a.parts.values())
    for part in a.parts.values():
        part['expression'] = max(1, min(127, round(127 * (part['render_gain'] / largest) ** (1 / 3))))
    midi = eng.midi_export(a)
    eng.save_wave(OUT / (a.slug + '.wav'), mix)

    theme_span = [s for s in a.statements][0]
    start = round(a.seconds(theme_span['start']) * SR)
    stop = round(a.seconds(theme_span['start'] + 32) * SR)
    lead_rms = float(np.sqrt(np.mean(lead[start:stop] ** 2)))
    rest_rms = float(np.sqrt(np.mean(dry_backing[start:stop] ** 2))) * gain
    report = dict(slug=a.slug, name=a.title, description=a.description,
                  duration_seconds=round(len(mix) / SR, 3),
                  peak_dbfs=round(float(20 * np.log10(np.max(np.abs(mix)))), 2),
                  rms_dbfs=round(float(20 * np.log10(np.sqrt(np.mean(body ** 2)))), 2),
                  theme_to_backing_rms_db_during_theme=round(20 * math.log10(lead_rms / rest_rms), 2),
                  verified_theme_statements=len(a.statements),
                  theme_absent_sections_seconds=[[round(a.seconds(s), 2), round(a.seconds(e), 2)] for s, e in a.quiet],
                  theme_absent_duration_seconds=round(sum(a.seconds(e) - a.seconds(s) for s, e in a.quiet), 2),
                  **midi)
    assert report['theme_absent_duration_seconds'] > 25
    assert report['peak_dbfs'] < -1.4
    assert report['theme_to_backing_rms_db_during_theme'] > -1, ('theme buried', report)
    (OUT / (a.slug + '_score.json')).write_text(json.dumps(dict(
        title=a.title, tempos=a.tempos, end=a.end, parts=a.parts, events=a.events, markers=a.markers,
        statements=a.statements, theme_absent_sections=a.quiet, space=SPACES[a.slug], master_gain=gain),
        indent=2), encoding='utf-8')
    return report


def main():
    reports = [render(builder()) for builder in (night, cave)]
    (OUT / 'validation_night_cave.json').write_text(json.dumps(reports, indent=2), encoding='utf-8')
    print(json.dumps(reports, indent=2))


if __name__ == '__main__':
    main()
