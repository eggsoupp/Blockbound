"""Four arrangements of the approved Homeward melody, plus its solo reference.

Uses the existing GeneralUser GS soundfont. MIDI preserves separate named parts.
Run with the bundled Python (numpy) and workspace-local mido/tinysoundfont.
"""
from pathlib import Path
import importlib.util
import json
import math
import shutil
import sys
import wave
import zipfile
import numpy as np

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
sys.path.insert(0, str(ROOT / '.music-tools'))
import mido
import tinysoundfont

spec = importlib.util.spec_from_file_location('homeward', OUT.parent/'homeward_hook'/'compose.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)
THEME, _ = source.score()
SR, PPQ = 44100, 960
SF = ROOT/'.music-tools'/'GeneralUser-GS.sf2'

# Root, fifth, third, upper root. Accompaniments stay below the principal melody.
VOICINGS = {
    'Em': (40,47,55,59), 'C': (36,43,52,55),
    'G': (31,43,50,59), 'D': (38,45,54,57),
}
PROGRESSION = ['Em','C','G','D','Em','C','D','G']


class Arrangement:
    def __init__(self,slug,title,tempos,end,description):
        self.slug,self.title,self.tempos,self.end,self.description = slug,title,tempos,end,description
        self.parts={}
        self.events=[]
        self.markers=[]
        self.statements=[]

    def part(self,name,program,level,pan=64,wet=.08,drums=False):
        used={p['channel'] for p in self.parts.values()}
        channel=9 if drums else next(c for c in range(16) if c!=9 and c not in used)
        self.parts[name]=dict(channel=channel,program=program,target_rms_db=level,pan=pan,wet=wet,drums=drums)

    def note(self,part,beat,pitch,length,velocity):
        assert part in self.parts and beat>=0 and length>0 and beat+length<=self.end+.001
        self.events.append(dict(part=part,beat=round(beat,5),pitch=pitch,length=round(length,5),velocity=max(1,min(127,velocity))))

    def melody(self,part,start,bars=8,octave=0,velocity=0):
        for e in THEME:
            if e['beat']<bars*4:
                self.note(part,start+e['beat'],e['pitch']+octave,e['length'],e['velocity']+velocity)
        self.statements.append(dict(part=part,start=start,bars=bars,transpose=octave))

    def seconds(self,beat):
        total=0.
        for i,(start,bpm,_) in enumerate(self.tempos):
            stop=self.tempos[i+1][0] if i+1<len(self.tempos) else beat
            if beat<=start:break
            total+=(min(beat,stop)-start)*60/bpm
            if beat<=stop:break
        return total


def pad(a,part,start,chord,duration=4,velocity=52):
    root,fifth,third,top=VOICINGS[chord]
    for p in (fifth,third,top):
        a.note(part,start,p,duration-.14,velocity)


def bass(a,part,start,chord,duration=4,velocity=60):
    a.note(part,start,VOICINGS[chord][0],duration-.18,velocity)


def harp(a,part,start,chord,busy=False):
    root,fifth,third,top=VOICINGS[chord]
    pattern=[(0,root+12),(.75,fifth+12),(1.5,third+12),(2.5,top),(3.25,third+12)]
    if busy:pattern=[(i*.5,p) for i,p in enumerate([root+12,fifth+12,third+12,top,third+12,fifth+12,top,third+12])]
    for i,(offset,p) in enumerate(pattern):
        a.note(part,start+offset,p,min(.44 if busy else .9,3.96-offset),48+(5 if i==0 else 0))


def closing(a,part,start,octave=0):
    # Reuse the hook's opening and give it an unambiguous tonic answer.
    notes=[(0,71,1),(1,71,.5),(1.5,69,.5),(2,67,1),(3,64,.5),(3.5,67,.5),
           (4,69,1),(5,66,.5),(5.5,69,.5),(6,67,1.8)]
    for b,p,d in notes:a.note(part,start+b,p+octave,max(.1,d-.05),77 if d>=1 else 70)


def adventure1():
    a=Arrangement('adventure1','Wide Skies',[(0,90,'Piano and harp')],76,
                  'Spacious piano melody, flowing harp and soft strings, with a gently fuller second statement.')
    a.part('Piano melody',0,-21,64,.11)
    a.part('Harp',46,-33,40,.13)
    a.part('Warm strings',49,-34,84,.15)
    a.part('Acoustic bass',32,-33,64,.03)
    a.part('Piano low harmony',0,-34,52,.09)
    a.markers=[(0,'Short opening'),(4,'Homeward - first statement'),(36,'Homeward - fuller return'),(68,'Home')]
    harp(a,'Harp',0,'Em')
    pad(a,'Piano low harmony',0,'Em',velocity=42)
    for start in (4,36):
        a.melody('Piano melody',start,velocity=3 if start==36 else 0)
        for i,chord in enumerate(PROGRESSION):
            b=start+i*4
            harp(a,'Harp',b,chord,busy=start==36)
            bass(a,'Acoustic bass',b,chord,velocity=48)
            pad(a,'Piano low harmony',b,chord,velocity=41)
            if start==36 or i>=4:pad(a,'Warm strings',b,chord,velocity=46)
    closing(a,'Piano melody',68)
    for b,chord in [(68,'C'),(72,'G')]:
        pad(a,'Piano low harmony',b,chord,velocity=39)
        bass(a,'Acoustic bass',b,chord,velocity=43)
        pad(a,'Warm strings',b,chord,velocity=41)
    return a


def adventure2():
    a=Arrangement('adventure2','The Open Road',[(0,104,'Walking pace')],72,
                  'A clear flute lead over nylon guitar, pizzicato strings and light hand percussion.')
    a.part('Flute melody',73,-21,64,.09)
    a.part('Nylon guitar',24,-32,42,.06)
    a.part('Pizzicato strings',45,-34,86,.07)
    a.part('Acoustic bass',32,-32,64,.03)
    a.part('Gentle percussion',0,-36,64,.015,True)
    a.markers=[(0,'Homeward - open road'),(32,'Homeward - travelling onward'),(64,'Home')]
    for start in (0,32):
        a.melody('Flute melody',start,velocity=-3)
        for i,chord in enumerate(PROGRESSION):
            b=start+4*i
            root,fifth,third,top=VOICINGS[chord]
            for j,p in enumerate([root+12,fifth+12,third+12,fifth+12,top,third+12,fifth+12,third+12]):
                a.note('Nylon guitar',b+j*.5,p,.47,51 if j%4==0 else 44)
            bass(a,'Acoustic bass',b,chord,2,53)
            a.note('Acoustic bass',b+2,root+7,1.8,46)
            for off in (1,3):
                for p in (third+12,top):a.note('Pizzicato strings',b+off,p,.25,46)
            # A low conga, muted high conga and closed hat form a quiet walking pulse.
            for off,p,v in [(0,64,52),(1,62,41),(2,64,47),(3,62,45)]:
                a.note('Gentle percussion',b+off,p,.13,v)
            if start==32:
                for j in range(8):a.note('Gentle percussion',b+j*.5,42,.08,31 if j%2 else 36)
    closing(a,'Flute melody',64)
    for b,chord in [(64,'C'),(68,'G')]:
        bass(a,'Acoustic bass',b,chord,velocity=44)
        pad(a,'Nylon guitar',b,chord,velocity=47)
    return a


def adventure3():
    a=Arrangement('adventure3','Islands Above the Clouds',[(0,82,'Broad and warm')],72,
                  'A warm French horn carries the theme over harp and strings; quiet piano reinforces the return.')
    a.part('French horn melody',60,-22,64,.14)
    a.part('Piano melody reinforcement',0,-31,68,.08)
    a.part('Harp',46,-34,36,.14)
    a.part('String harmony',49,-33,86,.18)
    a.part('Cello bass',42,-34,48,.12)
    a.markers=[(0,'Homeward - broad horizon'),(32,'Homeward - piano joins'),(64,'Home')]
    for start in (0,32):
        a.melody('French horn melody',start,octave=-12,velocity=-8)
        if start==32:a.melody('Piano melody reinforcement',start,velocity=-8)
        for i,chord in enumerate(PROGRESSION):
            b=start+i*4
            harp(a,'Harp',b,chord)
            # Avoid the horn's core octave; harmony voices are higher and quiet.
            fifth,third,top=VOICINGS[chord][1:]
            for p in (fifth+12,third+12,top+12):a.note('String harmony',b,p,3.8,46)
            bass(a,'Cello bass',b,chord,velocity=49)
    closing(a,'French horn melody',64,octave=-12)
    for b,chord in [(64,'C'),(68,'G')]:
        harp(a,'Harp',b,chord)
        pad(a,'String harmony',b,chord,velocity=43)
        bass(a,'Cello bass',b,chord,velocity=43)
    return a


def boss1():
    a=Arrangement('boss1','Homeward - Stand Your Ground',
                  [(0,92,'Exposed piano'),(16,152,'Sudden full-band entrance')],88,
                  'Solo piano reveals the hook; drums, guitar, bass, strings and a synth lead enter together without warning.')
    a.part('Exposed piano melody',0,-27,64,.04)
    a.part('Synth main melody',81,-18,64,.055)
    a.part('Strings melody reinforcement',48,-29,72,.08)
    a.part('Guitar rhythm left',30,-29,27,.035)
    a.part('Guitar rhythm right',29,-30,101,.035)
    a.part('Finger bass',33,-27,64,.015)
    a.part('Driving strings',48,-33,45,.075)
    a.part('Low orchestral accents',60,-33,80,.08)
    a.part('Drum kit',0,-24,64,.025,True)
    a.markers=[(0,'Almost naked: piano alone'),(16,'DROP - all parts enter immediately'),
               (48,'Full melody return - octave strings'),(80,'Final hook')]
    a.melody('Exposed piano melody',0,bars=4)
    for start in (16,48):
        a.melody('Synth main melody',start,velocity=5)
        a.melody('Strings melody reinforcement',start,octave=12 if start==48 else 0,velocity=-2)
        for i,chord in enumerate(PROGRESSION):
            b=start+i*4
            root,fifth,third,top=VOICINGS[chord]
            # Keep the melody's pitches and rhythm intact; energy comes from accompaniment.
            rhythm=[0,.5,1.5,2,2.5,3.5]
            for j,off in enumerate(rhythm):
                for part,delay in [('Guitar rhythm left',0),('Guitar rhythm right',.018)]:
                    for p in (root+12,root+19):
                        a.note(part,b+off+delay,p,.31 if off%1 else .4,83 if j in (0,3) else 72)
                a.note('Finger bass',b+off,root,.39,84 if off%1==0 else 72)
            for j,p in enumerate([fifth+12,third+12,top,third+12]*2):
                a.note('Driving strings',b+j*.5,p,.29,61 if j%2==0 else 52)
            for off in (0,2):
                for p in (root+12,root+19):a.note('Low orchestral accents',b+off,p,.65,71)
            # Rock groove. No drums of any kind exist before the drop.
            kicks=[0,1.5,2,2.75] if i%2==0 else [0,.75,2,3.5]
            for off in kicks:a.note('Drum kit',b+off,36,.11,104 if off in (0,2) else 89)
            for off in (1,3):a.note('Drum kit',b+off,38,.12,107)
            for j in range(8):
                a.note('Drum kit',b+j*.5,46 if j==7 and i%2 else 42,.12,66 if j%2==0 else 51)
            if i in (0,4):a.note('Drum kit',b,49,.8,100 if i==0 else 85)
            if i in (3,7):
                for off,p,v in [(3.25,45,75),(3.5,47,81),(3.75,50,89)]:
                    a.note('Drum kit',b+off,p,.14,v)
    closing(a,'Synth main melody',80)
    closing(a,'Strings melody reinforcement',80,octave=12)
    for off,chord in [(0,'Em'),(2,'C'),(4,'D'),(6,'G')]:
        b=80+off
        root=VOICINGS[chord][0]
        for part in ('Guitar rhythm left','Guitar rhythm right'):
            for p in (root+12,root+19):a.note(part,b,p,1.7,85)
        a.note('Finger bass',b,root,1.7,88)
        a.note('Drum kit',b,36,.1,108)
        a.note('Drum kit',b,49,.7,83 if off<6 else 106)
        if off<6:a.note('Drum kit',b+1,38,.12,102)
    return a


def midi_export(a):
    midi=mido.MidiFile(type=1,ticks_per_beat=PPQ)
    conductor=mido.MidiTrack([mido.MetaMessage('track_name',name='Blockbound - '+a.title),
        mido.MetaMessage('time_signature',numerator=4,denominator=4),
        mido.MetaMessage('key_signature',key='G')])
    timeline=[]
    for beat,bpm,label in a.tempos:
        timeline.append((round(beat*PPQ),0,mido.MetaMessage('set_tempo',tempo=mido.bpm2tempo(bpm))))
    for beat,label in a.markers:timeline.append((round(beat*PPQ),1,mido.MetaMessage('marker',text=label)))
    previous=0
    for tick,_,msg in sorted(timeline,key=lambda x:x[:2]):
        conductor.append(msg.copy(time=tick-previous));previous=tick
    conductor.append(mido.MetaMessage('end_of_track',time=a.end*PPQ-previous))
    midi.tracks.append(conductor)
    for name,part in a.parts.items():
        ch=part['channel']
        track=mido.MidiTrack([mido.MetaMessage('track_name',name=name),
            mido.Message('program_change',channel=ch,program=part['program']),
            mido.Message('control_change',channel=ch,control=7,value=100),
            mido.Message('control_change',channel=ch,control=11,value=part['expression']),
            mido.Message('control_change',channel=ch,control=10,value=part['pan']),
            mido.Message('control_change',channel=ch,control=64,value=0),
            mido.Message('control_change',channel=ch,control=91,value=round(part['wet']*127)),
            mido.Message('control_change',channel=ch,control=93,value=0)])
        timeline=[]
        for e in a.events:
            if e['part']!=name:continue
            timeline.append((round(e['beat']*PPQ),1,mido.Message('note_on',channel=ch,note=e['pitch'],velocity=e['velocity'])))
            timeline.append((round((e['beat']+e['length'])*PPQ),0,mido.Message('note_off',channel=ch,note=e['pitch'],velocity=0)))
        previous=0
        for tick,_,msg in sorted(timeline,key=lambda x:x[:2]):
            track.append(msg.copy(time=tick-previous));previous=tick
        track.append(mido.MetaMessage('end_of_track',time=a.end*PPQ-previous))
        midi.tracks.append(track)
    path=OUT/(a.slug+'.mid')
    midi.save(path)
    # Reload and check every note, including per-pitch overlap and final release.
    active=set();counts={};clock=0.;first_on={}
    for msg in mido.MidiFile(path):
        clock+=msg.time
        if msg.type not in ('note_on','note_off'):continue
        key=(msg.channel,msg.note)
        if msg.type=='note_on' and msg.velocity:
            assert key not in active,(a.slug,'overlapping repeated pitch',key,clock)
            active.add(key);counts[msg.channel]=counts.get(msg.channel,0)+1
            first_on.setdefault(msg.channel,clock)
        else:
            assert key in active,(a.slug,'unbalanced MIDI',key)
            active.remove(key)
    assert not active
    if a.slug=='boss1':
        for name,part in a.parts.items():
            if name!='Exposed piano melody':assert abs(first_on[part['channel']]-a.seconds(16))<.02
    return dict(midi_notes=sum(counts.values()),midi_notes_balanced=True,midi_duration_seconds=round(clock,3))


def render_part(a,name):
    part=a.parts[name]
    events=[e for e in a.events if e['part']==name]
    synth=tinysoundfont.Synth(gain=-9,samplerate=SR)
    sf=synth.sfload(str(SF))
    synth.program_select(part['channel'],sf,128 if part['drums'] else 0,part['program'],is_drums=part['drums'])
    synth.control_change(part['channel'],7,100)
    synth.control_change(part['channel'],10,part['pan'])
    synth.control_change(part['channel'],91,0)
    synth.control_change(part['channel'],93,0)
    n=round((a.seconds(a.end)+2.5)*SR)
    audio=np.zeros((n,2),np.float32)
    schedule=[]
    for e in events:
        schedule.extend([(round(a.seconds(e['beat'])*SR),1,e),
                         (round(a.seconds(e['beat']+e['length'])*SR),0,e)])
    cursor=0
    for pos,on,e in sorted(schedule,key=lambda x:x[:2]):
        if pos>cursor:
            audio[cursor:pos]=np.frombuffer(synth.generate_simple(pos-cursor),dtype=np.float32).reshape(-1,2)
            cursor=pos
        if on:synth.noteon(part['channel'],e['pitch'],e['velocity'])
        else:synth.noteoff(part['channel'],e['pitch'])
    if cursor<n:audio[cursor:]=np.frombuffer(synth.generate_simple(n-cursor),dtype=np.float32).reshape(-1,2)
    first=round(a.seconds(min(e['beat'] for e in events))*SR)
    last=round(a.seconds(max(e['beat']+e['length'] for e in events))*SR)
    rms=float(np.sqrt(np.mean(audio[first:last]**2)))
    assert rms>1e-7,(a.slug,name,'silent instrument')
    gain=10**(part['target_rms_db']/20)/rms
    part['render_gain']=gain
    part['instrument']=synth.sfpreset_name(sf,128 if part['drums'] else 0,part['program'])
    part['raw_rms_db']=round(20*math.log10(rms),2)
    audio*=gain
    return audio


def short_room(send):
    # A restrained short room, not a long pad or rhythmic echo.
    n=len(send);irn=round(.62*SR)
    rng=np.random.default_rng(725)
    impulse=rng.normal(size=(irn,2)).astype(np.float32)
    envelope=np.exp(-np.arange(irn)/(SR*.105))
    envelope[:round(.014*SR)]=0
    for ch in range(2):
        impulse[:,ch]=np.convolve(impulse[:,ch],np.ones(10)/10,mode='same')*envelope
        impulse[:,ch]/=max(np.sqrt(np.sum(impulse[:,ch]**2)),1e-8)
    size=1<<(n+irn-1).bit_length()
    result=np.empty_like(send)
    for ch in range(2):
        result[:,ch]=np.fft.irfft(np.fft.rfft(send[:,ch],size)*np.fft.rfft(impulse[:,ch],size),size)[:n]
    return result


def save_wave(path,audio):
    assert np.isfinite(audio).all() and np.max(np.abs(audio))<1
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR)
        f.writeframes(np.rint(audio*32767).astype('<i2').tobytes())
    with wave.open(str(path),'rb') as f:
        assert f.getnframes()==len(audio) and f.getnchannels()==2


def validate_theme(a):
    for statement in a.statements:
        expected=[(round(e['beat'],4),e['pitch'],round(e['length'],4)) for e in THEME if e['beat']<statement['bars']*4]
        actual=[(round(e['beat']-statement['start'],4),e['pitch']-statement['transpose'],round(e['length'],4))
                for e in a.events if e['part']==statement['part'] and statement['start']<=e['beat']<statement['start']+statement['bars']*4]
        assert actual==expected,(a.slug,statement)


def render(a):
    validate_theme(a)
    n=round((a.seconds(a.end)+2.5)*SR)
    mix=np.zeros((n,2),np.float32);send=np.zeros_like(mix)
    lead=np.zeros_like(mix);backing=np.zeros_like(mix)
    for name,part in a.parts.items():
        signal=render_part(a,name)
        mix+=signal;send+=signal*part['wet']
        if 'melody' in name.lower():lead+=signal
        else:backing+=signal
        print(f'{a.slug}: {name}',flush=True)
    mix+=short_room(send)
    # Preserve the sudden dynamic change in boss1: no per-section normalization.
    reference_start=round(a.seconds(16)*SR) if a.slug=='boss1' else 0
    reference=mix[reference_start:round(a.seconds(a.end)*SR)]
    target=-18 if a.slug=='boss1' else -21
    peak=float(np.max(np.abs(mix)))
    master=min(10**(target/20)/float(np.sqrt(np.mean(reference**2))),10**(-1.5/20)/peak)
    mix*=master
    fade=round(.8*SR);mix[-fade:]*=np.linspace(1,0,fade)[:,None]
    # Store compatible MIDI expression levels; audio mix gains are exact in score.json.
    highest=max(p['render_gain'] for p in a.parts.values())
    for part in a.parts.values():
        part['expression']=max(1,min(127,round(127*(part['render_gain']/highest)**(1/3))))
    midi_report=midi_export(a)
    save_wave(OUT/(a.slug+'.wav'),mix)
    lead_rms=float(np.sqrt(np.mean(lead[reference_start:]**2)))
    backing_rms=float(np.sqrt(np.mean(backing[reference_start:]**2)))
    report=dict(name=a.title,slug=a.slug,description=a.description,duration_seconds=round(len(mix)/SR,3),
                peak_dbfs=round(20*math.log10(float(np.max(np.abs(mix)))),2),
                rms_dbfs=round(20*math.log10(float(np.sqrt(np.mean(mix**2)))),2),
                lead_to_backing_rms_db=round(20*math.log10(lead_rms/backing_rms),2),
                theme_notes_preserved=True,verified_theme_statements=len(a.statements),**midi_report)
    if a.slug=='boss1':
        drop=round(a.seconds(16)*SR)
        before=float(np.sqrt(np.mean(mix[round(a.seconds(0)*SR):round(a.seconds(15)*SR)]**2)))
        after=float(np.sqrt(np.mean(mix[drop:round(a.seconds(32)*SR)]**2)))
        report.update(drop_seconds=round(a.seconds(16),3),drop_rms_increase_db=round(20*math.log10(after/before),2),
                      intro_is_piano_only=True,no_riser_or_drum_pickup=True)
        assert np.max(np.abs(backing[:drop]))==0
        assert report['drop_rms_increase_db']>6
    assert report['lead_to_backing_rms_db']>2.5,(a.slug,'backing masks lead',report)
    (OUT/(a.slug+'_score.json')).write_text(json.dumps(dict(title=a.title,tempos=a.tempos,end=a.end,
        parts=a.parts,events=a.events,markers=a.markers,master_gain=master,statements=a.statements),indent=2),encoding='utf-8')
    return report


def main():
    for suffix in ('.wav','.mid'):
        shutil.copyfile(OUT.parent/'homeward_hook'/('Blockbound_Homeward_Melody_Only'+suffix),OUT/('melody'+suffix))
    reports=[]
    for builder in (adventure1,adventure2,adventure3,boss1):
        reports.append(render(builder()))
    (OUT/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    lines=['# Blockbound - Homeward themes','',
           'The approved Homeward melody is retained in every arrangement. All complete statements preserve its notes and rhythm; octave changes and tempo changes are intentional.',
           'Files: melody.wav/.mid, adventure1.wav/.mid, adventure2.wav/.mid, adventure3.wav/.mid, boss1.wav/.mid.',
           'The MIDI files contain separate named instrument tracks, General MIDI patches, mix expression, tempo changes and section markers.',
           'Audio is 44.1 kHz, 16-bit stereo WAV. These are complete arrangement studies with natural endings, not seamless loops.','',
           '| File | Name | Duration | Description |','|---|---|---:|---|',
           '| melody | Homeward, solo piano | 21.7 s | Original melody reference, unchanged. |']
    for r in reports:lines.append(f"| {r['slug']} | {r['name']} | {r['duration_seconds']:.1f} s | {r['description']} |")
    lines.extend(['','Boss1: the exposed piano lasts 10.435 seconds; the full band enters at beat 16, with a tempo change from 92 to 152 BPM. No drum pickup, riser or crescendo precedes it.',
                  'Exploration tempos: adventure1 90 BPM; adventure2 104 BPM; adventure3 82 BPM.',
                  'Harmony: Em - C - G - D / Em - C - D - G, with short closing tags.',
                  'Rendering: GeneralUser GS by S. Christian Collins, short room ambience and static gain balancing. No audio generation service was used.',
                  'Sample-bank license: .music-tools/GeneralUser-LICENSE.txt in the workspace. No soundfont is redistributed here.',
                  'compose.py rebuilds the arrangements; each *_score.json contains every note and exact audio mix settings. MIDI timbres and relative levels can vary in other synthesizers.',
                  'validation.json records melody preservation, note balance, audio levels and the boss entrance checks.'])
    (OUT/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    with zipfile.ZipFile(OUT/'Blockbound_Homeward_Themes.zip','w',zipfile.ZIP_DEFLATED) as z:
        for slug in ('melody','adventure1','adventure2','adventure3','boss1'):
            for suffix in ('.wav','.mid'):z.write(OUT/(slug+suffix),slug+suffix)
        for name in ('README.md','validation.json'):z.write(OUT/name,name)
    print(json.dumps(reports,indent=2),flush=True)


if __name__=='__main__':main()
