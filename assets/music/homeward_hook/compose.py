"""Blockbound: Homeward. One eight-bar theme, melody-led piano sketch.

The first bar is a recurring six-note hook. Bars 1 and 3 are identical;
bar 5 retains its first four notes before lifting to the phrase's one peak.
The harmony is Em C G D / Em C D G. No reverb, chorus, pedal or drums.
"""
from pathlib import Path
import sys
import json
import wave
import zipfile
import numpy as np

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
sys.path.insert(0, str(ROOT / '.music-tools'))
import mido
import tinysoundfont

SR, PPQ, BPM = 44100, 960, 92
TITLE = 'Blockbound - Homeward'
STEM = 'Blockbound_Homeward'

# Pitch, rhythmic duration in quarter notes, velocity. R is a rest.
BARS = [
    [('B4',1,83),('B4',.5,74),('A4',.5,72),('G4',1,79),('E4',.5,71),('G4',.5,76)],
    [('A4',1.5,81),('G4',.5,73),('E4',1,76),('R',1,0)],
    [('B4',1,84),('B4',.5,75),('A4',.5,73),('G4',1,80),('E4',.5,72),('G4',.5,77)],
    [('A4',1.5,82),('F#4',.5,73),('D4',1,75),('R',1,0)],
    [('B4',1,84),('B4',.5,75),('A4',.5,73),('G4',1,80),('B4',.5,79),('D5',.5,84)],
    [('E5',1.5,88),('D5',.5,79),('B4',.5,76),('A4',.5,72),('G4',1,77)],
    [('A4',1,80),('B4',.5,78),('A4',.5,73),('F#4',1,76),('E4',.5,69),('F#4',.5,73)],
    [('G4',3,80),('R',1,0)],
]
CHORDS = [
    ('Em',['E3','G3','B3']), ('C',['C3','E3','G3']),
    ('G',['G2','D3','B3']), ('D',['D3','F#3','A3']),
    ('Em',['E3','G3','B3']), ('C',['C3','E3','G3']),
    ('D',['D3','F#3','A3']), ('G',['G2','D3','B3']),
]


def pitch(name):
    return 12*(int(name[-1])+1) + {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[name[0]] + name.count('#')


def score():
    melody, harmony = [], []
    for bar, notes in enumerate(BARS):
        assert sum(n[1] for n in notes) == 4
        beat = bar*4
        for name, duration, velocity in notes:
            if name != 'R':
                melody.append(dict(beat=beat, length=duration-min(.065,duration*.1),
                                   pitch=pitch(name), name=name, velocity=velocity))
            beat += duration
        for i, name in enumerate(CHORDS[bar][1]):
            # One soft, sustained chord per bar. The top voice stays under the melody.
            harmony.append(dict(beat=bar*4 + .018 + .006*i,
                                length=(2.94 if bar == 7 else 3.76)-.006*i,
                                pitch=pitch(name), name=name, velocity=[45,40,42][i]))
    return melody, harmony


def note_track(name, channel, events):
    track = mido.MidiTrack([
        mido.MetaMessage('track_name',name=name),
        mido.Message('program_change',channel=channel,program=0),
        mido.Message('control_change',channel=channel,control=7,value=100 if channel==0 else 65),
        mido.Message('control_change',channel=channel,control=10,value=64),
        mido.Message('control_change',channel=channel,control=64,value=0),
        mido.Message('control_change',channel=channel,control=91,value=0),
        mido.Message('control_change',channel=channel,control=93,value=0),
    ])
    schedule=[]
    for e in events:
        schedule.append((round(e['beat']*PPQ),1,mido.Message('note_on',channel=channel,note=e['pitch'],velocity=e['velocity'])))
        schedule.append((round((e['beat']+e['length'])*PPQ),0,mido.Message('note_off',channel=channel,note=e['pitch'],velocity=0)))
    previous=0
    for tick,_,message in sorted(schedule,key=lambda row:row[:2]):
        track.append(message.copy(time=tick-previous))
        previous=tick
    track.append(mido.MetaMessage('end_of_track',time=32*PPQ-previous))
    return track


def make_midi(path,melody,harmony):
    midi=mido.MidiFile(type=1,ticks_per_beat=PPQ)
    conductor=mido.MidiTrack([
        mido.MetaMessage('track_name',name=TITLE),
        mido.MetaMessage('set_tempo',tempo=mido.bpm2tempo(BPM)),
        mido.MetaMessage('time_signature',numerator=4,denominator=4),
        mido.MetaMessage('key_signature',key='G'),
    ])
    for i,(chord,_) in enumerate(CHORDS):
        conductor.append(mido.MetaMessage('marker',text=chord,time=0 if i==0 else 4*PPQ))
    conductor.append(mido.MetaMessage('end_of_track',time=4*PPQ))
    midi.tracks.extend([conductor,note_track('Main melody',0,melody)])
    if harmony:
        midi.tracks.append(note_track('Quiet piano chords - optional',1,harmony))
    midi.save(path)


def render(path):
    synth=tinysoundfont.Synth(gain=-9,samplerate=SR)
    sf=synth.sfload(str(ROOT/'.music-tools'/'GeneralUser-GS.sf2'))
    for channel in (0,1):
        synth.program_select(channel,sf,0,0)
    cursor, seconds=0,0.
    chunks=[]
    active=set()
    note_counts={0:0,1:0}
    melody_polyphony=0
    for message in mido.MidiFile(path):
        seconds+=message.time
        frame=round(seconds*SR)
        if frame>cursor:
            chunks.append(np.frombuffer(synth.generate_simple(frame-cursor),dtype=np.float32).reshape(-1,2).copy())
            cursor=frame
        if message.type=='control_change':
            synth.control_change(message.channel,message.control,message.value)
        elif message.type=='note_on' and message.velocity:
            key=(message.channel,message.note)
            assert key not in active
            active.add(key)
            note_counts[message.channel]+=1
            melody_polyphony=max(melody_polyphony,sum(k[0]==0 for k in active))
            synth.noteon(message.channel,message.note,message.velocity)
        elif message.type=='note_off' or (message.type=='note_on' and message.velocity==0):
            key=(message.channel,message.note)
            assert key in active
            active.remove(key)
            synth.noteoff(message.channel,message.note)
    assert not active and melody_polyphony==1
    chunks.append(np.frombuffer(synth.generate_simple(round(.8*SR)),dtype=np.float32).reshape(-1,2).copy())
    audio=np.concatenate(chunks)
    audio[-2205:]*=np.linspace(1,0,2205)[:,None]
    assert np.isfinite(audio).all()
    return audio,dict(duration_seconds=round(len(audio)/SR,3),note_counts=note_counts,
                      melody_is_monophonic=True,all_notes_released=True)


def save_wav(path,audio):
    assert 15<len(audio)/SR<25 and np.max(np.abs(audio))<1
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR)
        f.writeframes(np.rint(audio*32767).astype('<i2').tobytes())
    with wave.open(str(path),'rb') as f:
        assert f.getnframes()==len(audio)


def main():
    melody,harmony=score()
    # Exact first-bar return, including note durations, on the third bar.
    first=[(e['beat'],e['pitch'],e['length']) for e in melody if e['beat']<4]
    repeated=[(e['beat']-8,e['pitch'],e['length']) for e in melody if 8<=e['beat']<12]
    assert first==repeated
    results=[]
    for suffix,chords in [('',harmony),('_Melody_Only',[])]:
        midi_path=OUT/(STEM+suffix+'.mid')
        make_midi(midi_path,melody,chords)
        audio,report=render(midi_path)
        results.append((suffix,audio,report))
    # Shared gain preserves the same lead level in both versions.
    reference=results[0][1]
    gain=min(10**(-22/20)/float(np.sqrt(np.mean(reference**2))),
             10**(-3/20)/max(float(np.max(np.abs(a))) for _,a,_ in results))
    reports=[]
    for suffix,audio,report in results:
        audio*=gain
        save_wav(OUT/(STEM+suffix+'.wav'),audio)
        report.update(file=STEM+suffix,peak_dbfs=round(20*np.log10(float(np.max(np.abs(audio)))),2),
                      rms_dbfs=round(20*np.log10(float(np.sqrt(np.mean(audio**2)))),2))
        reports.append(report)
    (OUT/'score.json').write_text(json.dumps(dict(title=TITLE,bpm=BPM,meter='4/4',
        chords=[c[0] for c in CHORDS],bars=BARS,melody=melody,harmony=harmony),indent=2),encoding='utf-8')
    (OUT/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    (OUT/'README.md').write_text('''# Blockbound - Homeward

One original 21.7-second melody study, at 92 BPM in 4/4.

The hook is B-B-A-G-E-G, followed by the shorter answer A-G-E.
The hook returns exactly in bar 3; the answer changes to leave the phrase open.
Bar 5 begins with the same four notes, then reaches the only high E in bar 6.
The last two bars resolve onto G, giving the complete phrase a homecoming.

Harmony: Em | C | G | D | Em | C | D | G.
The starting point is vi-IV-I-V in G major; the final V-I closes the phrase.
Chord progression reference: https://musescore.com/tools/chord-progression-player/vi-iv-i-v
The melody is newly written; the reference was used for harmonic context only.

The main WAV includes one quiet piano chord per bar, with no other instruments,
drums, reverb, chorus or sustain pedal. Melody_Only is the same composition and
performance without the chords, at the same lead level.

The main MIDI has separate editable melody and chord tracks plus tempo/meter
metadata and chord markers. Melody_Only MIDI contains only the lead and metadata.
Audio: 44.1 kHz, 16-bit stereo, GeneralUser GS Grand Piano.
Sample bank: S. Christian Collins; existing license in .music-tools/GeneralUser-LICENSE.txt.

compose.py rebuilds the files using numpy and the existing .music-tools packages.
score.json contains every note. validation.json records export checks.
''',encoding='utf-8')
    with zipfile.ZipFile(OUT/(STEM+'.zip'),'w',zipfile.ZIP_DEFLATED) as z:
        for name in [STEM+'.wav',STEM+'.mid',STEM+'_Melody_Only.wav',STEM+'_Melody_Only.mid',
                     'score.json','validation.json','README.md','compose.py']:
            z.write(OUT/name,name)
    print(json.dumps(reports,indent=2))


if __name__=='__main__':
    main()
