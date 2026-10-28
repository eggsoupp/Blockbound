"""Longer Homeward derivatives and a breakcore-inspired boss arrangement.

Run this file to rebuild the current exports. compose.py is the v1 engine.
Previous WAVs/MIDIs are preserved in previous_v1. All drum source is generated
from the existing licensed soundfont; no commercial break recording is used.
"""
from pathlib import Path
import importlib.util
import json
import math
import wave
import zipfile
import numpy as np

OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('engine',OUT/'compose.py')
eng=importlib.util.module_from_spec(spec);spec.loader.exec_module(eng)
SR,PPQ=eng.SR,eng.PPQ
mido=eng.mido
A=eng.Arrangement
eng.VOICINGS.update(Am=(33,45,52,60),Bm=(35,42,50,54))
V=eng.VOICINGS
P=eng.PROGRESSION


def phrase(a,part,start,notes,transpose=0):
    for beat,pitch,length,velocity in notes:
        a.note(part,start+beat,pitch+transpose,length,velocity)


def theme(a,part,start,scale=1,transpose=0,velocity=0):
    for e in eng.THEME:
        a.note(part,start+e['beat']*scale,e['pitch']+transpose,e['length']*scale,e['velocity']+velocity)
    a.statements.append(dict(part=part,start=start,bars=8,transpose=transpose,scale=scale))


def setup(a,quiet):
    a.quiet=quiet
    a.edits=[]
    return a


def adventure1():
    a=setup(A('adventure1','Wide Skies - drifting paths',[(0,90,'Unhurried')],128,
              'Piano fragments emerge from harp and strings; the theme visits once, surrounded by long passages of open harmony.'),
            [(0,16),(64,96),(112,128)])
    a.part('Piano theme fragments',0,-28,64,.12)
    a.part('Harp',46,-29,39,.14)
    a.part('Warm strings',49,-31,88,.18)
    a.part('Acoustic bass',32,-32,64,.035)
    a.part('Piano low harmony',0,-30,52,.1)
    a.markers=[(0,'Clouds - no theme'),(16,'A memory of Homeward'),(32,'Theme passes through'),
               (64,'Drifting paths - no theme'),(96,'Distant echo'),(112,'Open sky - no theme')]
    progression=(['Em','C','G','D']+['Em','C','Am','D']+P+
                 ['C','G','Am','Em','C','Bm','Am','D']+['Em','C','D','G']+['C','Am','D','G'])
    for i,chord in enumerate(progression):
        b=i*4
        eng.harp(a,'Harp',b,chord,busy=72<=b<88)
        eng.bass(a,'Acoustic bass',b,chord,velocity=43 if b<32 else 49)
        if i%2==0 or 32<=b<64:eng.pad(a,'Piano low harmony',b,chord,velocity=43)
        if b>=8:eng.pad(a,'Warm strings',b,chord,velocity=44 if b<64 else 49)
    phrase(a,'Piano theme fragments',16,[(0,71,1.8,70),(2,69,.8,64),(3,67,2.5,67),(6,64,1.5,62),
                                        (8,69,2,69),(11,67,1,62),(13,64,2,64)])
    theme(a,'Piano theme fragments',32,velocity=-8)
    phrase(a,'Piano theme fragments',96,[(0,71,2,65),(3,69,.8,59),(4,67,2,64),(8,69,1.5,63),
                                        (10,66,1.5,58),(12,67,2.8,65)])
    return a


def adventure2():
    a=setup(A('adventure2','The Open Road - wandering onward',[(0,104,'Light walking pulse')],128,
              'Flute answers and guitar carry a travelling derivative, with extended rhythmic interludes and only one complete theme statement.'),
            [(0,8),(24,40),(72,104),(120,128)])
    a.part('Flute theme fragments',73,-28,65,.1)
    a.part('Nylon guitar',24,-27,42,.085)
    a.part('Pizzicato strings',45,-31,89,.08)
    a.part('Acoustic bass',32,-31,64,.035)
    a.part('Gentle percussion',0,-32,64,.025,True)
    a.markers=[(0,'Guitar path'),(8,'Flute answers'),(24,'Walking interlude - no theme'),
               (40,'Homeward glimpse'),(72,'Taking the long road - no theme'),(104,'Distant call'),(120,'Guitar farewell')]
    chords=['Em','C','G','D','Em','C','Am','G','C','D']+P+['C','G','Am','Em','C','Bm','Am','D']+['Em','C','D','G','C','G']
    for i,chord in enumerate(chords):
        b=i*4;root,fifth,third,top=V[chord]
        pattern=[root+12,fifth+12,third+12,fifth+12,top,third+12,fifth+12,third+12]
        if 72<=b<104:pattern=[root+12,third+12,top,fifth+12,third+12,top,fifth+12,third+12]
        for j,p in enumerate(pattern):
            if b>=120 and j in (1,3,5,7):continue
            a.note('Nylon guitar',b+j*.5,p,.46,53 if j%4==0 else 44)
        eng.bass(a,'Acoustic bass',b,chord,2,50)
        a.note('Acoustic bass',b+2,root+7,1.8,44)
        if b>=8 and b<120:
            for off in (1,3):
                for p in (third+12,top):a.note('Pizzicato strings',b+off,p,.25,44)
            for off,p,v in [(0,64,54),(1,62,43),(2,64,48),(3,62,46)]:a.note('Gentle percussion',b+off,p,.13,v)
            if 72<=b<104:
                for j in range(8):a.note('Gentle percussion',b+j*.5,42,.09,37 if j%2==0 else 29)
    phrase(a,'Flute theme fragments',8,[(0,71,.9,69),(1.5,69,.4,62),(2,67,1.7,66),
                                       (6,64,.7,61),(7,67,.7,65),(8,69,1.7,69),(11,67,.7,62),(13,64,1.6,65)])
    theme(a,'Flute theme fragments',40,velocity=-9)
    phrase(a,'Flute theme fragments',104,[(0,71,1.4,68),(2,69,.7,62),(3,67,1.6,65),
                                         (8,69,1.7,67),(11,66,.8,60),(13,67,1.8,65)])
    return a


def adventure3():
    a=setup(A('adventure3','Islands Above the Clouds - distant lights',[(0,82,'Broad and gentle')],112,
              'Warm orchestral space, slow horn recollections and a single understated return of the theme.'),
            [(0,16),(32,64),(104,112)])
    a.part('Horn theme fragments',60,-29,65,.16)
    a.part('Harp',46,-30,36,.16)
    a.part('String harmony',49,-29,88,.19)
    a.part('Cello bass',42,-32,48,.13)
    a.part('Quiet piano colours',0,-33,70,.12)
    a.markers=[(0,'Floating islands - no theme'),(16,'Horn recollection'),(32,'Distant lights - no theme'),
               (64,'Homeward return'),(96,'Last answer'),(104,'Home - no theme')]
    chords=['Em','C','G','D','Em','C','Am','D']+['C','G','Am','Em','C','Bm','Am','D']+P+['C','D','C','G']
    for i,chord in enumerate(chords):
        b=i*4;root,fifth,third,top=V[chord]
        eng.harp(a,'Harp',b,chord)
        for p in (fifth+12,third+12,top+12):a.note('String harmony',b,p,3.82,46 if b<64 else 50)
        eng.bass(a,'Cello bass',b,chord,velocity=46)
        if b in (8,24,40,56,72,88,104):
            # Bell-like harmonic punctuation, deliberately not the theme's rhythm or notes.
            a.note('Quiet piano colours',b+.5,third+24,2.3,43)
            a.note('Quiet piano colours',b+2.5,fifth+24,1.3,39)
    phrase(a,'Horn theme fragments',16,[(0,71,2.8,65),(4,69,1.8,60),(6,67,2.7,63),
                                       (10,64,1.8,60),(13,67,2.5,62)],-12)
    theme(a,'Horn theme fragments',64,transpose=-12,velocity=-13)
    phrase(a,'Horn theme fragments',96,[(0,69,2,63),(3,66,1.6,58),(5,67,2.7,62)],-12)
    return a


KICKS=[
    [0,.75,1.75,2.5,3.5], [0,.5,1.5,2.75,3.75],
    [0,1.25,2,2.5,3.25], [0,.75,1.75,2.25,3.5],
    [0,.5,1.75,2.5,3.75], [0,1.5,2.25,2.75,3.5],
    [0,.75,1.25,2.5,3.25], [0,.5,1.75,2.25,2.75],
]


def break_bar(a,b,index,section='full'):
    part='Chopped break drums';variant=index%8
    hits={}
    def hit(off,p,v,d=.1):
        key=(round(off,5),p)
        hits[key]=(max(v,hits.get(key,(0,0))[0]),min(d,3.99-off))
    for j,off in enumerate(KICKS[variant]):hit(off,36,118 if j==0 else 99+(j%3)*6,.13)
    # Main snares stay readable while ghost hits and cut-up endings vary each bar.
    for off in (1,3):hit(off,38,120 if off==3 else 115,.12)
    for off in ([.625,1.625,2.375] if variant%2==0 else [.25,1.875,2.625]):hit(off,38,49+variant*3,.055)
    for j in range(16):
        if (j+variant)%5==2:continue
        hit(j*.25,42,66 if j%4==0 else 45+(j%3)*5,.065)
    hit(2.75 if variant%2 else .75,46,64,.12)
    if variant in (1,5):
        for j in range(4):hit(3.5+j*.125,40,72+j*9,.052)
    if variant in (3,7):
        for j in range(6):hit(3+j/6,40,62+j*9,.055)
        for j in range(4):hit(2.5+j*.125,45 if j%2 else 47,71+j*6,.06)
    if variant in (2,6):
        for j in range(4):hit(1.5+j*.125,40,53+j*8,.05)
    if section=='chop':
        for j in range(8):hit(2+j*.125,40,66+(j%4)*9,.05)
        for j in range(6):hit(3.25+j*.0625,38,61+j*7,.027)
    if index%8==0:hit(0,49,105,.9)
    for (off,p),(v,d) in sorted(hits.items()):a.note(part,b+off,p,max(.015,d),v)
    if variant==3:a.edits.append(dict(beat=b+3.5,length=.5,kind='reverse_slice'))
    if variant==5:a.edits.append(dict(beat=b+2.75,length=.5,kind='four_retriggers'))
    if variant==7:a.edits.append(dict(beat=b+3.75,length=.25,kind='tape_stop'))


def boss1():
    a=setup(A('boss1','Stand Your Ground - fractured sky',[(0,92,'Original piano opening'),(16,186,'Breakcore drop')],192,
              'The preserved solo-piano opening breaks into loud, syncopated 186 BPM drums, chopped snares and heavy bass under the clear theme.'),[])
    a.part('Exposed piano melody',0,-27,64,.04)
    a.part('Synth main melody',81,-21,64,.045)
    a.part('String melody reinforcement',48,-28,74,.07)
    a.part('Guitar rhythm left',30,-29,24,.025)
    a.part('Guitar rhythm right',29,-30,103,.025)
    a.part('Heavy synth bass',38,-25,64,.01)
    a.part('Driving strings',48,-32,43,.07)
    a.part('Low orchestral accents',60,-31,82,.075)
    a.part('Chopped break drums',0,-17,64,.025,True)
    a.markers=[(0,'Original piano - preserved'),(16,'DROP - 186 BPM chopped break'),(80,'Drum fracture'),
               (96,'Theme return over denser breaks'),(160,'Final assault'),(176,'Homeward coda')]
    a.melody('Exposed piano melody',0,bars=4)
    # Half-time melodic phrasing leaves the identity clear over fast breakbeats.
    for start in (16,96):
        theme(a,'Synth main melody',start,scale=2,velocity=4)
        theme(a,'String melody reinforcement',start,scale=2,transpose=12 if start==96 else 0,velocity=-3)
    phrase(a,'Synth main melody',80,[(0,71,1.8,87),(2,71,.8,79),(3,69,.8,76),(4,67,2,83),
                                    (8,71,1.8,88),(10,71,.8,80),(11,69,.8,77),(12,67,2.8,85)])
    a.melody('Synth main melody',160,bars=4,velocity=7)
    a.melody('String melody reinforcement',160,bars=4,octave=12,velocity=-2)
    phrase(a,'Synth main melody',176,[(0,71,1.8,86),(2,71,.8,79),(3,69,.8,76),(4,67,1.8,83),
                                     (6,64,.8,74),(7,67,.8,79),(8,69,2.5,84),
                                     (11,66,.8,76),(12,67,3.5,87)])
    for i,b in enumerate(range(16,192,4)):
        if b<80:chord=P[(b-16)//8]
        elif b<96:chord=['Em','C','Am','D'][(b-80)//4]
        elif b<160:chord=P[(b-96)//8]
        elif b<176:chord=P[(b-160)//4]
        else:chord=['Em','C','D','G'][(b-176)//4]
        root,fifth,third,top=V[chord]
        chop=80<=b<96
        if not chop:
            rhythm=[0,.75,1.5,2,2.75,3.5] if i%2==0 else [0,.5,1.75,2.5,3.25]
            for off in rhythm:
                for name,delay in [('Guitar rhythm left',0),('Guitar rhythm right',.015)]:
                    for p in (root+12,root+19):a.note(name,b+off+delay,p,.25,82 if off==0 else 72)
                a.note('Heavy synth bass',b+off,root,.35,87 if off==0 else 76)
            for j,p in enumerate([fifth+12,third+12,top,third+12]*2):a.note('Driving strings',b+j*.5,p,.23,58 if j%2==0 else 48)
            for p in (root+12,root+19):a.note('Low orchestral accents',b,p,.85,70)
        else:
            a.note('Heavy synth bass',b,root,2.3,88)
            for p in (fifth,third,top):a.note('Driving strings',b,p,3.6,46)
        break_bar(a,b,i,'chop' if chop or 160<=b<176 else 'full')
    return a


def validate(a):
    for s in a.statements:
        scale=s.get('scale',1)
        expected=[(round(e['beat']*scale,4),e['pitch']+s['transpose'],round(e['length']*scale,4))
                  for e in eng.THEME if e['beat']<s['bars']*4]
        actual=[(round(e['beat']-s['start'],4),e['pitch'],round(e['length'],4)) for e in a.events
                if e['part']==s['part'] and s['start']<=e['beat']<s['start']+s['bars']*4*scale]
        assert expected==actual,(a.slug,s)
    for start,end in a.quiet:
        assert not any(e['beat']<end and e['beat']+e['length']>start for e in a.events if 'theme fragments' in e['part'].lower())


def normalize_active(a,name,signal):
    part=a.parts[name]
    mask=np.zeros(len(signal),bool)
    for e in a.events:
        if e['part']==name:
            first=round(a.seconds(e['beat'])*SR)
            last=min(len(signal),round((a.seconds(e['beat']+e['length'])+.12)*SR))
            mask[first:last]=True
    rms=float(np.sqrt(np.mean(signal[mask]**2)))
    gain=10**(part['target_rms_db']/20)/rms
    signal*=gain;part['render_gain']*=gain
    return signal


def process_break(a,signal):
    # Parallel saturation gives the acoustic kit density without flattening the lead.
    signal=.5*signal+.5*np.tanh(signal*3)/3
    for edit in a.edits:
        start=round(a.seconds(edit['beat'])*SR)
        end=round(a.seconds(edit['beat']+edit['length'])*SR)
        clip=signal[start:end].copy();n=len(clip)
        if edit['kind']=='reverse_slice':clip=clip[::-1].copy()
        elif edit['kind']=='four_retriggers':clip=np.tile(clip[:max(1,n//4)],(5,1))[:n]
        else:
            positions=np.linspace(0,1,n)**.55*(n-1)
            clip=np.column_stack([np.interp(positions,np.arange(n),clip[:,ch]) for ch in range(2)])
            clip*=np.linspace(1,0,n)[:,None]
        cross=min(90,n//8)
        weight=np.ones(n);weight[:cross]=np.linspace(0,1,cross);weight[-cross:]=np.linspace(1,0,cross)
        signal[start:end]=signal[start:end]*(1-weight[:,None])+clip*weight[:,None]
    return signal


def read_wav(path):
    with wave.open(str(path),'rb') as f:
        assert f.getframerate()==SR and f.getnchannels()==2 and f.getsampwidth()==2
        return np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').reshape(-1,2).astype(np.float32)/32767


def render(a):
    validate(a)
    n=round((a.seconds(a.end)+2.5)*SR)
    mix=np.zeros((n,2),np.float32);send=np.zeros_like(mix)
    drum_audio=None;lead_audio=np.zeros_like(mix)
    for name,part in a.parts.items():
        signal=normalize_active(a,name,eng.render_part(a,name))
        if name=='Chopped break drums':
            signal=process_break(a,signal)
            signal=normalize_active(a,name,signal)
            drum_audio=signal.copy()
        if 'melody' in name.lower() or 'theme fragments' in name.lower():lead_audio+=signal
        mix+=signal;send+=signal*part['wet']
        print(a.slug+': '+name,flush=True)
    mix+=eng.short_room(send)
    is_boss=a.slug=='boss1'
    start=round(a.seconds(16)*SR) if is_boss else 0
    reference=mix[start:round(a.seconds(a.end)*SR)]
    target=-15.5 if is_boss else -21
    gain=min(10**(target/20)/float(np.sqrt(np.mean(reference**2))),10**(-1.2/20)/float(np.max(np.abs(mix))))
    mix*=gain
    if is_boss:
        old=read_wav(OUT/'previous_v1'/'boss1.wav')
        # Preserve the exact opening the user liked, including its piano sound and level.
        mix[:start]=old[:start]
        assert np.array_equal(np.rint(mix[:start]*32767).astype('<i2'),np.rint(old[:start]*32767).astype('<i2'))
    fade=round(.8*SR);mix[-fade:]*=np.linspace(1,0,fade)[:,None]
    largest=max(p['render_gain'] for p in a.parts.values())
    for part in a.parts.values():part['expression']=max(1,min(127,round(127*(part['render_gain']/largest)**(1/3))))
    midi=eng.midi_export(a)
    eng.save_wave(OUT/(a.slug+'.wav'),mix)
    report=dict(slug=a.slug,name=a.title,description=a.description,version=2,
                duration_seconds=round(len(mix)/SR,3),peak_dbfs=round(float(20*np.log10(np.max(np.abs(mix)))),2),
                rms_dbfs=round(float(20*np.log10(np.sqrt(np.mean(mix**2)))),2),
                verified_theme_statements=len(a.statements),**midi)
    if is_boss:
        before=np.sqrt(np.mean(mix[:round(a.seconds(15)*SR)]**2))
        after=np.sqrt(np.mean(mix[start:round(a.seconds(48)*SR)]**2))
        drum_rms=np.sqrt(np.mean(drum_audio[start:round(a.seconds(a.end)*SR)]**2))
        lead_rms=np.sqrt(np.mean(lead_audio[start:round(a.seconds(a.end)*SR)]**2))
        report.update(drop_seconds=round(a.seconds(16),3),piano_intro_sample_identical_to_v1=True,
                      drop_rms_increase_db=round(float(20*np.log10(after/before)),2),
                      drums_to_lead_rms_db=round(float(20*np.log10(drum_rms/lead_rms)),2),
                      post_drop_bpm=186,drum_edits=len(a.edits),no_drums_before_drop=True)
        assert not np.any(drum_audio[:start])
        assert report['drop_rms_increase_db']>9 and report['drums_to_lead_rms_db']>1
    else:
        report['theme_absent_sections_seconds']=[[round(a.seconds(s),2),round(a.seconds(e),2)] for s,e in a.quiet]
        report['theme_absent_duration_seconds']=round(sum(a.seconds(e)-a.seconds(s) for s,e in a.quiet),2)
        assert report['theme_absent_duration_seconds']>25
    old_report=json.loads((OUT/'previous_v1'/'validation.json').read_text())
    previous=next(r for r in old_report if r['slug']==a.slug)
    assert report['duration_seconds']>previous['duration_seconds']+20
    (OUT/(a.slug+'_score.json')).write_text(json.dumps(dict(title=a.title,version=2,tempos=a.tempos,
        end=a.end,parts=a.parts,events=a.events,markers=a.markers,statements=a.statements,
        theme_absent_sections=a.quiet,drum_audio_edits=a.edits,master_gain=gain),indent=2),encoding='utf-8')
    return report


def main():
    reports=[render(builder()) for builder in (adventure1,adventure2,adventure3,boss1)]
    (OUT/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    lines=['# Blockbound - Homeward themes, revision 2','',
           'Longer exploration derivatives and a breakcore-inspired boss version. Previous arrangements are preserved in previous_v1/.',
           'Current exports retain the clear names adventure1, adventure2, adventure3 and boss1, each with WAV and multitrack MIDI.',
           'melody.wav and melody.mid remain the original solo reference.','',
           '| File | Duration | Description |','|---|---:|---|']
    for r in reports:lines.append(f"| {r['slug']} | {r['duration_seconds']:.1f} s | {r['description']} |")
    lines+=['','Exploration arrangements use fragments, altered phrasing, harmony-led interludes and one complete theme appearance apiece. Named MIDI markers identify the sections.',
            'Boss1 preserves the first 10.435 seconds of the previous WAV sample-for-sample. At the drop the tempo becomes 186 BPM, while the main theme uses half-time phrasing. Drums are louder than the melodic bus, with varied syncopation, ghost notes, 32nd/64th-note retriggers, reverse slices and short tape stops.',
            'Drum source: the workspace GeneralUser GS kit, newly sequenced for this arrangement. No external break sample is used. The MIDI includes the drum notes; reversal, saturation and tape-stop processing are baked into the WAV and documented in boss1_score.json.',
            'Audio: 44.1 kHz, 16-bit stereo WAV with natural endings. MIDI uses named instrument tracks, General MIDI programs and section/tempo markers; playback timbres can differ in another synthesizer.',
            'Run compose_v2.py to rebuild current versions. compose.py is the original rendering engine. Per-track score JSONs and validation.json document the arrangement and checks.',
            'Piano opening recovery source: previous_v1/boss1.wav. GeneralUser GS by S. Christian Collins; bank license is in .music-tools/GeneralUser-LICENSE.txt.']
    (OUT/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    with zipfile.ZipFile(OUT/'Blockbound_Homeward_Themes.zip','w',zipfile.ZIP_DEFLATED) as z:
        for slug in ('melody','adventure1','adventure2','adventure3','boss1'):
            for ext in ('.wav','.mid'):z.write(OUT/(slug+ext),slug+ext)
        for name in ('README.md','validation.json'):z.write(OUT/name,name)
    print(json.dumps(reports,indent=2))


if __name__=='__main__':main()
