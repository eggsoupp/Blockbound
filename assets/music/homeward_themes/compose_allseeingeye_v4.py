"""Allseeingeye v4: sustained guitar theme, audible countermelody, full dark harmony.

Preserves the original piano opening and v2's 186 BPM drum composition.
No metallic tones, reversed piano, orchestral strings, or horns.
"""
from pathlib import Path
import importlib.util
import json
import math
import zipfile
import numpy as np

OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('revision2',OUT/'compose_v2.py')
v2=importlib.util.module_from_spec(spec);spec.loader.exec_module(v2)
eng=v2.eng;SR=eng.SR
HARMONY=['Em','C','Am','D','Em','C','Bm','Em']
ROOTS={'Em':40,'C':36,'Am':33,'D':38,'Bm':35}
CHORDS={'Em':[52,59,66,67], 'C':[48,55,59,64], 'Am':[45,52,60,67],
        'D':[50,57,62,66], 'Bm':[47,54,57,62]}
COUNTER=[
    [(0,64,2),(3,67,1),(4.5,66,1),(6,64,1.6)],
    [(0,60,2.8),(3,64,1),(5,67,1),(6.5,64,1.2)],
    [(0,57,1.8),(2,60,1),(4,64,1),(5.5,67,1),(7,64,.8)],
    [(0,66,2),(2.5,64,1),(4,62,2),(6.5,57,1.2)],
    [(0,64,1.8),(2,67,1),(4,59,1),(5.5,64,1),(7,66,.8)],
    [(0,64,2.8),(3,67,1),(5,59,1),(6.5,60,1.2)],
    [(0,62,1.8),(2,66,1),(4,57,1),(5.5,59,1),(7,66,.8)],
    [(0,64,2.8),(3,59,1),(5,64,2.5)],
]


def build():
    old=v2.boss1()
    a=v2.setup(eng.Arrangement('allseeingeye','Allseeingeye',old.tempos,old.end,
        'A sustained guitar theme and audible piano countermelody over wide minor harmony, heavy rhythm guitars, bass and chopped breaks.'),[])
    a.part('Exposed piano melody',0,-27,64,.04)
    a.part('Sustained guitar melody',29,-17,64,.075)
    a.part('Lower guitar melody shadow',30,-29,72,.065)
    a.part('Piano countermelody',0,-23,48,.075)
    a.part('Wide minor harmony',89,-24,64,.11)
    a.part('Rhythm guitar left',30,-27,23,.035)
    a.part('Rhythm guitar right',30,-28,104,.035)
    a.part('Heavy bass',38,-23,64,.01)
    a.part('Chopped break drums',0,-19,64,.025,True)
    mapping={'Exposed piano melody':'Exposed piano melody','Synth main melody':'Sustained guitar melody',
             'Chopped break drums':'Chopped break drums'}
    for e in old.events:
        if e['part'] in mapping:a.note(mapping[e['part']],e['beat'],e['pitch'],e['length'],e['velocity'])
        if e['part']=='Synth main melody' and (e['beat']<80 or e['beat']>=96):
            a.note('Lower guitar melody shadow',e['beat']+.018,e['pitch']-12,max(.1,e['length']-.025),e['velocity']-8)
    for s in old.statements:
        if s['part'] in mapping:a.statements.append(dict(s,part=mapping[s['part']]))
    a.edits=old.edits
    a.markers=[(0,'Original exposed piano'),(16,'DROP - full musical weight'),(80,'Threat closes in'),
               (96,'Second phase - full theme and counterline'),(160,'Final assault'),(176,'Last stand')]
    for start in (16,96):
        for bar,notes in enumerate(COUNTER):
            for off,p,d in notes:a.note('Piano countermelody',start+bar*8+off,p,d-.055,75 if off==0 else 67)
    # The bridge retains a clear answering line while the break edits intensify.
    bridge=[(0,64,2),(2.5,67,1),(4,66,1.5),(6,64,1.5),
            (8,60,2),(11,62,1),(12,66,1),(14,63,1.5)]
    finale=[(0,64,1.8),(2,67,.8),(4,64,1.8),(6,60,.8),
                                        (8,57,1.8),(10,60,.8),(12,66,1.8),(14,62,.8),
                                        (16,64,2),(19,67,1),(20,60,2),(23,64,1),
                                        (24,66,2),(27,63,.8),(28,64,3.5)]
    for start,notes in [(80,bridge),(160,finale)]:
        v2.phrase(a,'Piano countermelody',start,[(b,p,d,73 if d>=1.5 else 66) for b,p,d in notes])
    for index,b in enumerate(range(16,192,4)):
        if b<80:chord=HARMONY[(b-16)//8]
        elif b<96:chord=['Em','C','Am','Bm'][(b-80)//4]
        elif b<160:chord=HARMONY[(b-96)//8]
        elif b<176:chord=['Em','C','Am','D'][(b-160)//4]
        else:chord=['Em','C','Bm','Em'][(b-176)//4]
        root=ROOTS[chord]
        for p in CHORDS[chord]:a.note('Wide minor harmony',b,p,3.94,66)
        rhythm=[0,.75,1.5,2,2.75,3.5] if index%2==0 else [0,.5,1.75,2.5,3.25]
        if 80<=b<96:rhythm=[0,1.5,2.75]
        for off in rhythm:
            for name,delay in [('Rhythm guitar left',0),('Rhythm guitar right',.017)]:
                for p in (root+12,root+19):a.note(name,b+off+delay,p,.32,88 if off==0 else 76)
            a.note('Heavy bass',b+off,root,.43,92 if off==0 else 80)
        # A few longer low notes make the drop's body continuous between drum hits.
        if index%4==0:a.note('Heavy bass',b,root-12,3.7,69)
    assert not any(x in name.lower() for name in a.parts for x in ('glass','metallic','reversed','horn','strings'))
    assert [e for e in a.events if e['part']=='Chopped break drums']==[e for e in old.events if e['part']=='Chopped break drums']
    return a


def synth_harmony(a,name):
    """A warm, band-limited unison chord instrument, voiced beneath the lead."""
    n=round((a.seconds(a.end)+2.5)*SR);signal=np.zeros((n,2),np.float32)
    for e in a.events:
        if e['part']!=name:continue
        first=round(a.seconds(e['beat'])*SR)
        hold=a.seconds(e['beat']+e['length'])-a.seconds(e['beat'])
        length=min(n-first,round((hold+.13)*SR));t=np.arange(length)/SR
        f=440*2**((e['pitch']-69)/12)
        envelope=(1-np.exp(-t/.012))*np.clip((hold+.13-t)/.13,0,1)
        pulse=.86+.14*np.cos(2*np.pi*186/60*t)
        for ch,cents in enumerate((-5,5)):
            frequency=f*2**(cents/1200)
            voice=np.sin(2*np.pi*frequency*t)
            for h in range(2,8):voice+=(.48/h**1.45)*np.sin(2*np.pi*frequency*h*t+.17*h)
            signal[first:first+length,ch]+=voice*envelope*pulse*.11
    a.parts[name].update(render_gain=1.,instrument='Custom warm unison harmony; MIDI proxy Warm Pad',raw_rms_db=None)
    return signal


def guitar_width(signal):
    # Short stereo offsets retain the centre attack and avoid a thin single-sample lead.
    dry=signal.copy()
    for ch,delay in [(0,round(.011*SR)),(1,round(.017*SR))]:
        signal[delay:,ch]+=.16*dry[:-delay,ch]
    return .8*signal+.2*np.tanh(signal*2.4)/2.4


def render(a):
    v2.validate(a)
    n=round((a.seconds(a.end)+2.5)*SR)
    mix=np.zeros((n,2),np.float32);send=np.zeros_like(mix)
    music=np.zeros_like(mix);lead=np.zeros_like(mix);backing=np.zeros_like(mix);drums=None
    for name,part in a.parts.items():
        signal=synth_harmony(a,name) if name=='Wide minor harmony' else eng.render_part(a,name)
        signal=v2.normalize_active(a,name,signal)
        if name=='Sustained guitar melody':
            signal=v2.normalize_active(a,name,guitar_width(signal))
        if name=='Chopped break drums':
            signal=v2.normalize_active(a,name,v2.process_break(a,signal));drums=signal.copy()
        else:
            music+=signal
            if 'guitar melody' in name.lower():lead+=signal
            elif name!='Exposed piano melody':backing+=signal
        mix+=signal;send+=signal*part['wet']
        print('allseeingeye v4: '+name,flush=True)
    mix+=eng.short_room(send)
    drop=round(a.seconds(16)*SR);end=round(a.seconds(a.end)*SR)
    gain=min(10**(-14.5/20)/float(np.sqrt(np.mean(mix[drop:end]**2))),
             10**(-1.1/20)/float(np.max(np.abs(mix))))
    mix*=gain
    original=v2.read_wav(OUT/'previous_v2'/'boss1.wav')
    mix[:drop]=original[:drop]
    mix[-round(.8*SR):]*=np.linspace(1,0,round(.8*SR))[:,None]
    highest=max(p['render_gain'] for p in a.parts.values())
    for p in a.parts.values():p['expression']=max(1,min(127,round(127*(p['render_gain']/highest)**(1/3))))
    midi=eng.midi_export(a)
    eng.save_wave(OUT/'allseeingeye.wav',mix)
    exported=v2.read_wav(OUT/'allseeingeye.wav')
    assert np.array_equal(exported[:drop],original[:drop])
    assert not np.any(drums[:drop]) and not np.any(backing[:drop])
    def rms(x):return float(np.sqrt(np.mean(x[drop:end]**2)))
    report=dict(slug='allseeingeye',name='Allseeingeye',version=4,description=a.description,
        duration_seconds=round(len(mix)/SR,3),drop_seconds=round(a.seconds(16),3),
        peak_dbfs=round(float(20*np.log10(np.max(np.abs(mix)))),2),
        rms_dbfs=round(float(20*np.log10(np.sqrt(np.mean(mix**2)))),2),
        piano_intro_sample_identical=True,theme_statements_verified=len(a.statements),
        music_to_drums_rms_db=round(20*math.log10(rms(music)/rms(drums)),2),
        backing_to_drums_rms_db=round(20*math.log10(rms(backing)/rms(drums)),2),
        lead_to_drums_rms_db=round(20*math.log10(rms(lead)/rms(drums)),2),
        metallic_layers_removed=True,background_countermelody_present=True,
        drum_notes_and_edits_preserved=True,post_drop_bpm=186,**midi)
    # Music must have real sustained weight; drums no longer dominate the entire mix.
    assert report['music_to_drums_rms_db']>3
    assert report['backing_to_drums_rms_db']>-2
    assert report['lead_to_drums_rms_db']>0
    (OUT/'allseeingeye_score.json').write_text(json.dumps(dict(title=a.title,version=4,tempos=a.tempos,end=a.end,
        parts=a.parts,events=a.events,markers=a.markers,statements=a.statements,drum_audio_edits=a.edits,
        master_gain=gain,harmony=HARMONY,processing={'Sustained guitar melody':'Short stereo doubling; restrained parallel saturation',
        'Wide minor harmony':'Custom band-limited unison synthesizer; MIDI Warm Pad proxy'}),indent=2),encoding='utf-8')
    return report


def main():
    report=render(build())
    reports=json.loads((OUT/'validation.json').read_text())
    reports=[r for r in reports if r['slug'] not in ('boss1','allseeingeye')]+[report]
    (OUT/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    (OUT/'README.md').write_text('''# Blockbound - Homeward themes

Current exports: melody, adventure1, adventure2, adventure3, allseeingeye, as WAV and MIDI.
Exploration tracks remain revision 2; Allseeingeye is now revision 4.

Allseeingeye: 69.7 seconds. The original piano opening is preserved sample-for-sample.
At 10.435 seconds the 186 BPM drop introduces a sustained electric-guitar theme,
a lower piano countermelody, wide minor-key harmony, heavy rhythm guitars and bass.
The revised balance gives the musical layers more weight than the drum bus.
The chopped breaks, ghost notes, retriggers, reverse edits and tape stops are retained.
The rejected metallic/glass and reversed-piano textures are removed.

Harmony: Em - C - Am - D / Em - C - Bm - Em. The original theme notes remain intact;
the minor final chord changes the emotional landing without rewriting the hook.

Audio: 44.1 kHz, 16-bit stereo WAV. MIDI contains separate named parts and tempo markers.
Custom synth harmony uses a Warm Pad MIDI proxy. Stereo processing and drum edits
are baked into the WAV; MIDI playback depends on the receiving instruments.

Use compose_allseeingeye_v4.py to rebuild the current boss. compose_v2.py builds
the exploration revision. Earlier sources and exports are retained for comparison.
validation.json and allseeingeye_score.json record the notes, mix and export checks.
Source samples: existing GeneralUser GS by S. Christian Collins; license in .music-tools/GeneralUser-LICENSE.txt.
''',encoding='utf-8')
    with zipfile.ZipFile(OUT/'Blockbound_Homeward_Themes.zip','w',zipfile.ZIP_DEFLATED) as z:
        for slug in ('melody','adventure1','adventure2','adventure3','allseeingeye'):
            for ext in ('.wav','.mid'):z.write(OUT/(slug+ext),slug+ext)
        for name in ('README.md','validation.json'):z.write(OUT/name,name)
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
