"""Boss themes on the Homeward melody: Slime Emperor, Signus and the Blightborer.

Built like Allseeingeye: a quiet 16-beat intro on the Homeward hook, a sudden
drop with a tempo change, then a body of whole bars from the drop to the end,
so the game can loop drop..end seamlessly (Shared.Audio.Music `loop`). Every
piece states the full Homeward theme at least once; compose_v2.validate checks
the notes.

    slimeemperor  "Royal Jelly"        100 -> 152 BPM. A courtly marimba intro, then
                                       a bouncing brass march: tuba leaping octaves,
                                       marimba, pizzicato, timpani and kit.
    signus        "Hallowed Eclipse"   76 -> 168 BPM. Voices sing the hook over
                                       organ; then choir and a synth lead carry the
                                       theme at half speed over harpsichord runs,
                                       organ, string ostinato and orchestral drums,
                                       with a "Totality" bridge.
    blightborer   "Devourer Below"     66 -> 138 BPM. A low rumble and deep piano,
                                       then chugging synthesized grit chords in E
                                       Phrygian, double kick, a gritty theme lead and
                                       a half-time breakdown under a low choir.

Guitar-like and synth parts are synthesized here (like Allseeingeye v5)
rather than played on General MIDI guitars. Everything else is the workspace
GeneralUser GS soundfont.

Run with the bundled Python:  python -I compose_bosses.py
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
nc = load('compose_night_cave', OUT / 'compose_night_cave.py')
eng = v2.eng
SR = eng.SR
A = eng.Arrangement
THEME = eng.THEME
PROGRESSION = eng.PROGRESSION  # Em C G D Em C D G, one bar each under the theme
theme, phrase, setup = v2.theme, v2.phrase, v2.setup
DROP = 16

PC = {'C': 0, 'C#': 1, 'D': 2, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'Ab': 8, 'A': 9, 'Bb': 10, 'B': 11}


def tones(chord, low):
    """Root position triad (or power chord for 'X5') with its root at or above `low`."""
    if chord.endswith('5'):
        name, steps = chord[:-1], (0, 7, 12)
    elif chord.endswith('m'):
        name, steps = chord[:-1], (0, 3, 7)
    else:
        name, steps = chord, (0, 4, 7)
    base = low + (PC[name] - low) % 12
    return [base + s for s in steps]


def root(chord, low):
    return tones(chord, low)[0]


def hook(beats=16, transpose=0, velocity=0):
    """The opening of the theme as phrase() notes (not a full statement)."""
    return [(e['beat'], e['pitch'] + transpose, e['length'], e['velocity'] + velocity)
            for e in THEME if e['beat'] < beats]


class Drums:
    """Collects drum hits for one part, merging duplicates (MIDI cannot overlap a pitch)."""

    def __init__(self, a, part):
        self.a, self.part, self.hits = a, part, {}

    def hit(self, beat, pitch, velocity, length=.1):
        key = (round(beat, 5), pitch)
        old = self.hits.get(key)
        self.hits[key] = (max(velocity, old[0]) if old else velocity, length)

    def commit(self):
        for (beat, pitch), (velocity, length) in sorted(self.hits.items()):
            self.a.note(self.part, beat, pitch, length, velocity)


def fill(d, b, velocity=96):
    for j, pitch in enumerate((50, 48, 47, 45, 43, 41)):
        d.hit(b + 2.5 + j * .25, pitch, velocity + j * 4, .12)


def sections(start, chords, beats=4):
    for i, chord in enumerate(chords):
        yield i, start + i * beats, chord


# ---------------------------------------------------------------------------
# Slime Emperor - Royal Jelly
# ---------------------------------------------------------------------------

def slime():
    a = setup(A('slimeemperor', 'Royal Jelly', [(0, 100, 'Courtly marimba'), (DROP, 152, 'The Emperor bounces in')], 144,
                'A courtly marimba intro, then a bouncing brass march: the theme on brass, tuba leaping '
                'octaves, marimba, pizzicato strings, timpani and kit.'), [])
    a.intro_parts = {'Marimba intro melody', 'Tuba intro'}
    a.space = 'room'
    a.synths = {}
    a.part('Marimba intro melody', 12, -26, 64, .1)
    a.part('Tuba intro', 58, -30, 64, .06)
    a.part('Brass theme melody', 61, -16, 64, .08)
    a.part('High strings melody', 48, -24, 76, .1)
    a.part('Trombone counter', 57, -21, 52, .08)
    a.part('Bouncing tuba', 58, -20, 64, .04)
    a.part('Marimba bounce', 12, -26, 40, .07)
    a.part('Pizzicato offbeats', 45, -28, 92, .07)
    a.part('Timpani', 47, -25, 64, .1)
    a.part('Drum kit', 0, -22, 64, .03, True)
    a.markers = [(0, 'Courtly intro'), (DROP, 'DROP - the Emperor bounces in'), (48, 'Court dance'),
                 (80, 'Theme returns, strings above'), (112, 'Wobble groove'), (140, 'Turnaround')]

    phrase(a, 'Marimba intro melody', 0, hook(16, velocity=-6))
    for i, chord in enumerate(['Em', 'C', 'G', 'D']):
        r = root(chord, 33)
        a.note('Tuba intro', i * 4, r, 1.8, 58)
        a.note('Tuba intro', i * 4 + 2, r + 7, 1.8, 52)

    court = ['C', 'D', 'Bm', 'Em', 'C', 'D', 'G', 'G']
    groove = ['Em', 'Em', 'C', 'C', 'Am', 'Am', 'D', 'D']
    plan = [(16, PROGRESSION, 'theme'), (48, court, 'court'), (80, PROGRESSION, 'theme'), (112, groove, 'groove')]
    d = Drums(a, 'Drum kit')
    for start, chords, kind in plan:
        d.hit(start, 49, 110, .9)
        for i, b, chord in sections(start, chords):
            r = root(chord, 33)
            bounce = [(0, r, .45, 98), (1.5, r + 12, .4, 84), (2, r + 7, .45, 88), (3, r, .4, 90), (3.5, r + 12, .35, 80)]
            if kind == 'groove':
                bounce += [(.75, r + 12, .2, 70), (2.75, r + 7, .2, 70)]
            for off, p, length, v in bounce:
                a.note('Bouncing tuba', b + off, p, length, v)
            t = tones(chord, 60)
            figure = [t[0], t[2], t[1] + 12, t[2], t[0] + 12, t[2], t[1] + 12, t[2]]
            for j, p in enumerate(figure):
                accent = j in (0, 3, 6)
                a.note('Marimba bounce', b + j * .5, p, .45, (62 if accent else 50) - (6 if kind == 'theme' else 0))
            for off in (.5, 1.5, 2.5, 3.5):
                for p in tones(chord, 55)[1:]:
                    a.note('Pizzicato offbeats', b + off, p, .2, 56)
            last = i == len(chords) - 1
            a.note('Timpani', b, root(chord, 40), 1.4, 92 if i % 2 == 0 else 78)
            if last:
                for j in range(8):
                    a.note('Timpani', b + 2 + j * .25, root(chord, 40), .2, 60 + j * 5)
            for off in ((0, 2, 2.5) if kind == 'groove' else (0, 2)):
                d.hit(b + off, 36, 112)
            for off in (1, 3):
                d.hit(b + off, 38, 108)
            for j in range(8):
                d.hit(b + j * .5, 42, 70 if j % 2 == 0 else 54, .08)
            if kind == 'groove':
                d.hit(b + 3.5, 46, 72, .2)
            if last:
                fill(d, b)
            if kind == 'groove':
                for p in tones(chord, 55):
                    a.note('Brass theme melody', b, p, .3, 84)
                    a.note('Brass theme melody', b + 2.5, p, .3, 78)
    d.commit()

    theme(a, 'Brass theme melody', 16, velocity=4)
    theme(a, 'Brass theme melody', 80, velocity=6)
    theme(a, 'High strings melody', 80, transpose=12, velocity=-6)
    phrase(a, 'Brass theme melody', 64, hook(8, velocity=-10))
    counter = [(0, 60, 1.45, 76), (1.5, 62, .45, 70), (2, 64, .95, 74), (3, 67, .95, 74), (4, 66, 1.45, 76),
               (5.5, 64, .45, 68), (6, 62, 1.9, 72), (8, 59, 1.45, 74), (9.5, 62, .45, 68), (10, 66, .95, 72),
               (11, 64, .95, 70), (12, 64, 2.9, 72), (16, 60, 1.45, 76), (17.5, 62, .45, 70), (18, 64, .95, 74),
               (19, 67, .95, 74), (20, 66, 1.45, 76), (21.5, 69, .45, 70), (22, 71, 1.9, 76), (24, 67, 1.45, 74),
               (25.5, 66, .45, 68), (26, 67, 3.9, 74)]
    phrase(a, 'Trombone counter', 48, counter)
    return a


# ---------------------------------------------------------------------------
# Signus - Hallowed Eclipse
# ---------------------------------------------------------------------------

def signus():
    a = setup(A('signus', 'Hallowed Eclipse', [(0, 76, 'Voices in the dark'), (DROP, 168, 'Eclipse')], 144,
                'Voices sing the hook over organ, then choir and a synth lead carry the theme at half '
                'speed over harpsichord runs, organ, string ostinato and orchestral drums.'), [])
    a.intro_parts = {'Voice hook intro', 'Organ intro'}
    a.space = 'hall'
    a.synths = {'Lead synth melody': 'lead', 'Synth bass': 'bass'}
    a.part('Voice hook intro', 53, -29, 64, .3)
    a.part('Organ intro', 19, -36, 64, .25)
    a.part('Choir theme melody', 52, -19, 70, .22)
    a.part('Lead synth melody', 81, -18, 58, .12)
    a.part('Harpsichord arpeggio', 6, -27, 36, .1)
    a.part('Organ chords', 19, -28, 64, .18)
    a.part('String ostinato', 48, -28, 92, .12)
    a.part('Synth bass', 38, -23, 64, .02)
    a.part('Timpani', 47, -26, 64, .14)
    a.part('Orchestral drums', 48, -22, 64, .06, True)
    a.markers = [(0, 'Voices in the dark'), (DROP, 'DROP - Eclipse, theme in half time'), (80, 'Totality'),
                 (112, 'Corona'), (140, 'Turnaround')]

    phrase(a, 'Voice hook intro', 0, hook(16, velocity=-10))
    for i, chord in enumerate(['Em', 'C', 'Am', 'B']):
        for p in tones(chord, 48):
            a.note('Organ intro', i * 4, p, 3.9, 50)

    totality = ['Am', 'F', 'C', 'G', 'Am', 'F', 'B', 'B']
    corona = ['Em', 'C', 'D', 'B', 'Em', 'C', 'Am', 'B']
    plan = [(16, PROGRESSION, 8, 'theme'), (80, totality, 4, 'totality'), (112, corona, 4, 'corona')]
    d = Drums(a, 'Orchestral drums')
    for start, chords, beats, kind in plan:
        d.hit(start, 49, 112, 1.2)
        for i, b, chord in sections(start, chords, beats):
            for p in tones(chord, 48) + [tones(chord, 60)[0]]:
                a.note('Organ chords', b, p, beats - .1, 54)
            if kind != 'theme':
                for p in tones(chord, 60):
                    a.note('Choir theme melody', b, p, beats - .1, 58)
            last = i == len(chords) - 1
            for bar in range(beats // 4):
                bb = b + bar * 4
                t = tones(chord, 60)
                run = [t[0], t[1], t[2], t[0] + 12, t[1] + 12, t[0] + 12, t[2], t[1]]
                if kind == 'totality':
                    for j in range(16):
                        a.note('Harpsichord arpeggio', bb + j * .25, run[j % 8], .22, 64 if j % 4 == 0 else 52)
                else:
                    for j, p in enumerate(run):
                        a.note('Harpsichord arpeggio', bb + j * .5, p, .45, 62 if j % 4 == 0 else 50)
                r = root(chord, 45)
                for j in range(8):
                    a.note('String ostinato', bb + j * .5, r if j % 2 == 0 else r + 7, .45, 62 if j % 4 == 0 else 52)
                rb = root(chord, 28)
                for j in range(8):
                    a.note('Synth bass', bb + j * .5, rb if j % 2 == 0 else rb + 12, .42, 92 if j == 0 else 78)
                end_of_section = last and bar == beats // 4 - 1
                if kind == 'totality':
                    d.hit(bb, 36, 116, .2)
                    d.hit(bb + 2, 38, 112)
                    if bar % 2 == 1 or end_of_section:
                        d.hit(bb + 3, 36, 100)
                else:
                    for off in ((0, 1.5, 2, 3.5) if kind == 'corona' else (0, 1.5, 2)):
                        d.hit(bb + off, 36, 112)
                    for off in (1, 3):
                        d.hit(bb + off, 38, 110)
                    if kind == 'corona':
                        for j in range(8):
                            d.hit(bb + j * .5, 42, 64 if j % 2 == 0 else 50, .08)
                if bar == 0:
                    a.note('Timpani', bb, root(chord, 40), 1.4, 94)
                if end_of_section:
                    fill(d, bb, 100)
                    for j in range(8):
                        a.note('Timpani', bb + 2 + j * .25, root(chord, 40), .2, 62 + j * 5)
    d.commit()

    theme(a, 'Choir theme melody', 16, scale=2, velocity=-4)
    theme(a, 'Lead synth melody', 16, scale=2, velocity=2)
    counter = [(0, 69, 2.9), (3, 72, .9), (4, 77, 2.9), (7, 76, .9), (8, 72, 3.9), (12, 74, 2.9), (15, 71, .9),
               (16, 69, 2.9), (19, 72, .9), (20, 77, 3.9), (24, 75, 3.9), (28, 78, 3.9)]
    phrase(a, 'Lead synth melody', 80, [(b, p, l, 82) for b, p, l in counter])
    phrase(a, 'Lead synth melody', 112, hook(8, transpose=12, velocity=4))
    phrase(a, 'Lead synth melody', 128, hook(8, transpose=12, velocity=6))
    phrase(a, 'Lead synth melody', 120, [(0, 78, 3.4, 80), (4, 75, 3.4, 78)])
    phrase(a, 'Lead synth melody', 136, [(0, 76, 3.4, 80), (4, 75, 3.8, 84)])
    return a


# ---------------------------------------------------------------------------
# The Blightborer - Devourer Below
# ---------------------------------------------------------------------------

def blightborer():
    a = setup(A('blightborer', 'Devourer Below', [(0, 66, 'Something moves below'), (DROP, 138, 'It breaches')], 144,
                'A low rumble and deep piano, then chugging synthesized grit chords in E Phrygian, double '
                'kick, a gritty theme lead and a half-time breakdown under a low choir.'), [])
    a.intro_parts = {'Low drone', 'Low piano intro', 'Tremolo strings intro'}
    a.space = 'cavern'
    a.synths = {'Low drone': 'pad', 'Grit rhythm': 'grit', 'Grit lead melody': 'gritlead', 'Sub bass': 'bass'}
    a.part('Low drone', 89, -34, 64, .3)
    a.part('Low piano intro', 0, -29, 60, .25)
    a.part('Tremolo strings intro', 44, -37, 70, .25)
    a.part('Grit rhythm', 30, -21, 64, .03)
    a.part('Grit lead melody', 29, -14.5, 64, .1)
    a.part('Low brass melody', 57, -24, 54, .1)
    a.part('Sub bass', 38, -23, 64, .01)
    a.part('Dark choir', 53, -27, 76, .3)
    a.part('Power drums', 16, -20, 64, .04, True)
    a.markers = [(0, 'Something moves below'), (DROP, 'DROP - it breaches'), (48, 'Homeward, devoured'),
                 (80, 'Breakdown - the pit opens'), (112, 'Last breach'), (140, 'Turnaround')]

    a.note('Low drone', 0, 28, 15.9, 70)
    a.note('Low drone', 0, 35, 15.9, 60)
    phrase(a, 'Low piano intro', 0, hook(16, transpose=-12, velocity=-6))
    for p in tones('Em', 40):
        a.note('Tremolo strings intro', 8, p, 7.9, 44)

    riff = ['E5', 'E5', 'F5', 'E5', 'E5', 'E5', 'G5', 'F5']
    powered = [c[0] + '5' for c in PROGRESSION]  # E5 C5 G5 D5 E5 C5 D5 G5
    breakdown = ['E5', 'F5', 'E5', 'D5', 'C5', 'D5', 'E5', 'F5']
    choir_of = {'E5': 'Em', 'F5': 'F', 'G5': 'G', 'D5': 'Dm', 'C5': 'C'}
    plan = [(16, riff, 'riff'), (48, powered, 'theme'), (80, breakdown, 'breakdown'), (112, powered, 'theme')]
    d = Drums(a, 'Power drums')
    for start, chords, kind in plan:
        d.hit(start, 49, 116, 1)
        for i, b, chord in sections(start, chords):
            power = tones(chord, 35)
            last = i == len(chords) - 1
            if kind == 'riff':
                hits = [(0, .4, 112), (.5, .2, 92), (.75, .2, 96), (1.5, .4, 108), (2, .2, 92), (2.25, .2, 96),
                        (2.75, .2, 100), (3, .4, 110), (3.5, .2, 94)]
            elif kind == 'theme':
                hits = [(j * .5, .4, 104 if j % 2 == 0 else 88) for j in range(8)]
            else:
                hits = [(0, 1.8, 116), (2.5, 1.2, 108)]
            for off, length, v in hits:
                for p in power:
                    a.note('Grit rhythm', b + off, p, length, v)
                a.note('Sub bass', b + off, power[0] - 12, length, v)
            if kind != 'riff':
                for p in tones(choir_of[chord], 52):
                    a.note('Dark choir', b, p, 3.9, 60 if kind == 'breakdown' else 50)
            if kind == 'riff':
                for off in (0, .25, .5, .75, 2, 2.25, 2.5, 2.75):
                    d.hit(b + off, 36, 112 if off in (0, 2) else 96)
                for off in (1, 3):
                    d.hit(b + off, 38, 116)
                if i % 2 == 0:
                    d.hit(b, 49, 108, .9)
                for off in (0, 1, 2, 3):
                    d.hit(b + off, 51, 70, .2)
            elif kind == 'theme':
                for j in range(8):
                    d.hit(b + j * .5, 36, 106 if j % 2 == 0 else 92)
                for off in (1, 3):
                    d.hit(b + off, 38, 114)
                d.hit(b, 49 if i % 2 == 0 else 57, 104, .9)
            else:
                d.hit(b, 36, 118)
                d.hit(b + 2.5, 36, 104)
                d.hit(b + 2, 38, 118)
                d.hit(b, 52 if i % 2 else 49, 100, 1.2)
            if last:
                fill(d, b, 104)
    d.commit()

    theme(a, 'Grit lead melody', 48, velocity=4)
    theme(a, 'Grit lead melody', 112, velocity=8)
    theme(a, 'Low brass melody', 112, transpose=-12, velocity=0)
    phrase(a, 'Grit lead melody', 88, hook(8, transpose=-12, velocity=-4))
    phrase(a, 'Grit lead melody', 104, [(0, 65, 3.4, 90), (4, 64, 3.6, 94)])
    return a


# ---------------------------------------------------------------------------
# Synthesized voices
# ---------------------------------------------------------------------------

def smooth(x, width):
    if width <= 1:
        return x
    kernel = np.ones(width) / width
    return np.convolve(x, kernel, mode='same')


def synth(a, name, kind):
    """Additive voices with gentle top ends; 'grit' kinds are saturated like a heavy guitar."""
    n = round((a.seconds(a.end) + 2.5) * SR)
    signal = np.zeros((n, 2), np.float32)
    pan = a.parts[name]['pan'] / 127
    settings = {
        'lead': dict(attack=.012, release=.12, harmonics=9, detunes=(-6, 0, 5), roll=1.35, drive=0, width=1),
        'gritlead': dict(attack=.006, release=.1, harmonics=12, detunes=(-8, 0, 7), roll=1.0, drive=3.0, width=3),
        'grit': dict(attack=.003, release=.05, harmonics=14, detunes=(-9, 9), roll=1.0, drive=4.5, width=5),
        'bass': dict(attack=.004, release=.06, harmonics=3, detunes=(0,), roll=1.6, drive=1.5, width=1),
        'pad': dict(attack=1.2, release=1.5, harmonics=5, detunes=(-7, 7), roll=1.6, drive=0, width=1),
    }[kind]
    for e in a.events:
        if e['part'] != name:
            continue
        first = round(a.seconds(e['beat']) * SR)
        hold = a.seconds(e['beat'] + e['length']) - a.seconds(e['beat'])
        release = settings['release']
        length = min(n - first, round((hold + release) * SR))
        t = np.arange(length) / SR
        frequency = 440 * 2 ** ((e['pitch'] - 69) / 12)
        env = (1 - np.exp(-t / settings['attack'])) * np.clip((hold + release - t) / release, 0, 1)
        if kind == 'grit':
            env *= .55 + .45 * np.exp(-t / .09)  # palm-muted chug
        elif kind == 'pad':
            env *= .85 + .15 * np.sin(2 * np.pi * .3 * t)
        velocity = (e['velocity'] / 95) ** 1.1
        vibrato = .0018 * np.sin(2 * np.pi * 4.8 * t) * np.clip((t - .18) / .25, 0, 1) if 'lead' in kind else 0
        phase_time = t + vibrato / (2 * np.pi * 4.8)
        for ch in range(2):
            voice = np.zeros(length)
            detunes = settings['detunes'] if ch == 0 else tuple(-x for x in settings['detunes'])
            for detune in detunes:
                f = frequency * 2 ** (detune / 1200)
                phase = 2 * np.pi * f * phase_time
                wave = np.sin(phase)
                for h in range(2, settings['harmonics'] + 1):
                    if f * h > 9000:
                        break
                    amp = .7 / h ** settings['roll']
                    if kind == 'lead' and h % 2 == 0:
                        amp *= .7
                    wave += amp * np.sin(h * phase + .12 * (h - 1))
                voice += wave / len(detunes)
            if settings['drive']:
                voice = np.tanh(voice * settings['drive']) / math.tanh(settings['drive'])
                voice = smooth(voice, settings['width'])
            gain = math.cos(pan * math.pi / 2) if ch == 0 else math.sin(pan * math.pi / 2)
            signal[first:first + length, ch] += voice * env * velocity * .15 * gain
    a.parts[name].update(render_gain=1., raw_rms_db=None, instrument='Custom ' + kind + ' synthesizer; GM MIDI proxy')
    return signal


def soft_peak_control(x):
    threshold, ceiling = .57, 10 ** (-1 / 20)
    magnitude = np.abs(x)
    above = threshold + (ceiling - threshold) * np.tanh(np.maximum(0, magnitude - threshold) / (ceiling - threshold))
    return np.sign(x) * np.where(magnitude <= threshold, magnitude, above)


SPACES = {
    'room': lambda send: eng.short_room(send),
    'hall': lambda send: eng.short_room(send) * .6 + nc.space(send, seconds=3.2, decay=.75, predelay=.03, brightness=22, seed=9) * 1.3,
    'cavern': lambda send: eng.short_room(send) * .5 + nc.space(send, seconds=2.4, decay=.5, predelay=.025, brightness=40, seed=13) * 1.2,
}
TARGET_RMS = -14.5  # after the drop; Allseeingeye sits about here


def render(a):
    v2.validate(a)
    for e in a.events:
        assert e['part'] in a.intro_parts or e['beat'] >= DROP, (a.slug, 'sound before the drop', e)
    assert (a.end - DROP) % 4 == 0, 'loop must be whole bars'
    n = round((a.seconds(a.end) + 2.5) * SR)
    mix = np.zeros((n, 2), np.float32)
    send = np.zeros_like(mix)
    lead = np.zeros_like(mix)
    backing = np.zeros_like(mix)
    for name, part in a.parts.items():
        kind = a.synths.get(name)
        signal = synth(a, name, kind) if kind else eng.render_part(a, name)
        padded = np.zeros((n, 2), np.float32)
        padded[:min(n, len(signal))] = signal[:n]
        signal = v2.normalize_active(a, name, padded)
        if 'melody' in name.lower():
            lead += signal
        elif name not in a.intro_parts:
            backing += signal
        mix += signal
        send += signal * part['wet']
        print(a.slug + ': ' + name, flush=True)
    mix += SPACES[a.space](send)
    drop = round(a.seconds(DROP) * SR)
    end = round(a.seconds(a.end) * SR)
    target = 10 ** (TARGET_RMS / 20)
    sample = mix[drop:end:8]
    low, high = .01, 40.
    for _ in range(30):
        trial = (low + high) / 2
        if np.sqrt(np.mean(soft_peak_control(sample * trial) ** 2)) < target:
            low = trial
        else:
            high = trial
    gain = (low + high) / 2
    mix = soft_peak_control(mix * gain).astype(np.float32)
    lead *= gain
    backing *= gain
    mix[-round(.8 * SR):] *= np.linspace(1, 0, round(.8 * SR))[:, None]
    largest = max(p['render_gain'] for p in a.parts.values())
    for part in a.parts.values():
        part['expression'] = max(1, min(127, round(127 * (part['render_gain'] / largest) ** (1 / 3))))
    midi = eng.midi_export(a)
    eng.save_wave(OUT / (a.slug + '.wav'), mix)

    def rms(x, first=drop, last=end):
        return float(np.sqrt(np.mean(x[first:last] ** 2)))
    loop_start, loop_end = a.seconds(DROP), a.seconds(a.end)
    report = dict(slug=a.slug, name=a.title, description=a.description,
                  duration_seconds=round(len(mix) / SR, 3), drop_seconds=round(loop_start, 4),
                  loop_end_seconds=round(loop_end, 4), loop_bars=(a.end - DROP) // 4,
                  bpm=[t[1] for t in a.tempos],
                  peak_dbfs=round(float(20 * np.log10(np.max(np.abs(mix)))), 2),
                  post_drop_rms_dbfs=round(20 * math.log10(rms(mix)), 2),
                  intro_rms_dbfs=round(20 * math.log10(rms(mix, 0, drop)), 2),
                  lead_to_backing_rms_db=round(20 * math.log10(rms(lead) / rms(backing)), 2),
                  verified_theme_statements=len(a.statements), **midi)
    report['drop_jump_db'] = round(report['post_drop_rms_dbfs'] - report['intro_rms_dbfs'], 2)
    assert report['drop_jump_db'] > 8, ('drop not dramatic enough', report)
    assert report['lead_to_backing_rms_db'] > -3, ('lead buried', report)
    (OUT / (a.slug + '_score.json')).write_text(json.dumps(dict(
        title=a.title, tempos=a.tempos, end=a.end, parts=a.parts, events=a.events, markers=a.markers,
        statements=a.statements, loop=[loop_start, loop_end], synths=a.synths, space=a.space, master_gain=gain),
        indent=2), encoding='utf-8')
    return report


def main():
    reports = [render(builder()) for builder in (slime, signus, blightborer)]
    (OUT / 'validation_bosses.json').write_text(json.dumps(reports, indent=2), encoding='utf-8')
    print(json.dumps(reports, indent=2))


if __name__ == '__main__':
    main()
