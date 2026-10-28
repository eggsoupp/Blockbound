"""Allseeingeye: piano-led breakcore with sparse mechanical/metallic backing.

Replaces the v2 boss's saw lead, strings, horns and generic guitar backing.
Keeps the approved piano opening and the complete v2 drum arrangement.
"""
from pathlib import Path
import importlib.util
import json
import math
import wave
import zipfile
import numpy as np

OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('revision2',OUT/'compose_v2.py')
v2=importlib.util.module_from_spec(spec);spec.loader.exec_module(v2)
eng=v2.eng
SR=eng.SR


def build():
    old=v2.boss1()
    a=v2.setup(eng.Arrangement('allseeingeye','Allseeingeye',old.tempos,old.end,
        'Hard-struck, driven piano over chopped breaks, a rough bass pulse, sparse metallic echoes and reversed piano.'),[])
    a.part('Exposed piano melody',0,-27,64,.04)
    a.part('Driven piano melody',0,-20,64,.06)
    a.part('Distorted low pulse',38,-25,64,.015)
    a.part('Metallic echoes',11,-33,84,.12)
    a.part('Reversed piano breaths',0,-33,38,.12)
    a.part('Chopped break drums',0,-17,64,.025,True)
    mapping={'Exposed piano melody':'Exposed piano melody',
             'Synth main melody':'Driven piano melody',
             'Heavy synth bass':'Distorted low pulse',
             'Chopped break drums':'Chopped break drums'}
    for e in old.events:
        if e['part'] in mapping:a.note(mapping[e['part']],e['beat'],e['pitch'],e['length'],e['velocity'])
    for s in old.statements:
        if s['part'] in mapping:a.statements.append(dict(s,part=mapping[s['part']]))
    a.edits=old.edits
    a.markers=[(0,'Original piano opening'),(16,'Allseeingeye - driven piano and breaks'),
               (80,'Fracture - metallic echoes'),(96,'Theme returns'),(160,'Final assault'),(176,'Last gaze')]
    # Sparse two-note responses replace continuous arpeggios and orchestral pads.
    for i,b in enumerate(range(16,192,8)):
        if b<80:chord=v2.P[(b-16)//8]
        elif b<96:chord=['Em','Am'][(b-80)//8]
        elif b<160:chord=v2.P[(b-96)//8]
        elif b<176:chord=['Em','G'][(b-160)//8]
        else:chord=['Em','D'][(b-176)//8]
        root,fifth,third,top=v2.V[chord]
        # Turn the hook's repeated-note gesture into quiet, displaced echoes.
        a.note('Metallic echoes',b+2.75,top+12,.65,58)
        a.note('Metallic echoes',b+3.5,top+12,.4,46)
        if i%2:a.note('Metallic echoes',b+6.25,third+12,1.1,52)
        if b in (24,56,72,88,120,152,168,184):
            a.note('Reversed piano breaths',b+5.5,root+24,1.8,55)
            a.note('Reversed piano breaths',b+5.75,third+12,1.5,48)
    for part in a.parts.values():assert part['program'] not in (48,49,60,81)
    original_drums=[e for e in old.events if e['part']=='Chopped break drums']
    new_drums=[e for e in a.events if e['part']=='Chopped break drums']
    assert original_drums==new_drums
    return a


def custom_glass(a,name):
    """A softly inharmonic struck tone; MIDI uses vibraphone as an editable proxy."""
    n=round((a.seconds(a.end)+2.5)*SR)
    signal=np.zeros((n,2),np.float32)
    pan=a.parts[name]['pan']/127
    gains=np.array([math.cos(pan*math.pi/2),math.sin(pan*math.pi/2)],np.float32)
    for e in a.events:
        if e['part']!=name:continue
        first=round(a.seconds(e['beat'])*SR)
        duration=a.seconds(e['beat']+e['length'])-a.seconds(e['beat'])
        length=min(n-first,round((duration+.22)*SR));t=np.arange(length)/SR
        f=440*2**((e['pitch']-69)/12)
        mod=1.7*np.exp(-t/0.085)*np.sin(2*np.pi*f*2.71*t)
        voice=(.78*np.sin(2*np.pi*f*t+mod)+.14*np.sin(2*np.pi*f*2.006*t))
        envelope=(1-np.exp(-t/.003))*np.exp(-t/.2)
        release=np.clip(1-(t-duration)/.22,0,1)
        mono=voice*envelope*release*(e['velocity']/127)**1.6
        signal[first:first+length]+=mono[:,None]*gains
    a.parts[name].update(render_gain=1.,instrument='Custom FM struck glass; MIDI proxy: vibraphone',raw_rms_db=None)
    return signal


def reverse_piano(a,name):
    synth=eng.tinysoundfont.Synth(gain=-9,samplerate=SR)
    sf=synth.sfload(str(eng.SF));ch=a.parts[name]['channel']
    synth.program_select(ch,sf,0,0)
    synth.control_change(ch,7,100);synth.control_change(ch,10,a.parts[name]['pan'])
    n=round((a.seconds(a.end)+2.5)*SR);signal=np.zeros((n,2),np.float32)
    for e in a.events:
        if e['part']!=name:continue
        first=round(a.seconds(e['beat'])*SR)
        length=round((a.seconds(e['beat']+e['length'])-a.seconds(e['beat']))*SR)
        synth.sounds_off();synth.noteon(ch,e['pitch'],e['velocity'])
        clip=np.frombuffer(synth.generate_simple(length),dtype=np.float32).reshape(-1,2).copy()[::-1].copy()
        fade=min(450,length//8)
        clip[:fade]*=np.linspace(0,1,fade)[:,None];clip[-fade:]*=np.linspace(1,0,fade)[:,None]
        signal[first:first+length]+=clip
    a.parts[name].update(render_gain=1.,instrument='Reversed grand piano; MIDI contains forward source notes',raw_rms_db=None)
    return signal


def render(a):
    v2.validate(a)
    n=round((a.seconds(a.end)+2.5)*SR)
    mix=np.zeros((n,2),np.float32);send=np.zeros_like(mix)
    lead=None;drums=None
    for name,part in a.parts.items():
        if name=='Metallic echoes':signal=custom_glass(a,name)
        elif name=='Reversed piano breaths':signal=reverse_piano(a,name)
        else:signal=eng.render_part(a,name)
        signal=v2.normalize_active(a,name,signal)
        if name=='Driven piano melody':
            # Keep the piano attack and pitched body, with restrained parallel grit.
            signal=.42*signal+.58*np.tanh(signal*4)/4
            signal=v2.normalize_active(a,name,signal)
            lead=signal.copy()
        elif name=='Distorted low pulse':
            signal=.6*signal+.4*np.tanh(signal*5)/5
            signal=v2.normalize_active(a,name,signal)
        elif name=='Chopped break drums':
            signal=v2.process_break(a,signal)
            signal=v2.normalize_active(a,name,signal);drums=signal.copy()
        mix+=signal;send+=signal*part['wet']
        print('allseeingeye: '+name,flush=True)
    mix+=eng.short_room(send)
    drop=round(a.seconds(16)*SR)
    finish=round(a.seconds(a.end)*SR)
    gain=min(10**(-15.5/20)/float(np.sqrt(np.mean(mix[drop:finish]**2))),
             10**(-1.2/20)/float(np.max(np.abs(mix))))
    mix*=gain
    original=v2.read_wav(OUT/'previous_v2'/'boss1.wav')
    mix[:drop]=original[:drop]
    mix[-round(.8*SR):]*=np.linspace(1,0,round(.8*SR))[:,None]
    assert np.array_equal(np.rint(mix[:drop]*32767).astype('<i2'),np.rint(original[:drop]*32767).astype('<i2'))
    assert not np.any(drums[:drop]) and not np.any(lead[:drop])
    highest=max(p['render_gain'] for p in a.parts.values())
    for p in a.parts.values():p['expression']=max(1,min(127,round(127*(p['render_gain']/highest)**(1/3))))
    midi=eng.midi_export(a)
    eng.save_wave(OUT/'allseeingeye.wav',mix)
    # Validate the written file, not just the float buffer.
    exported=v2.read_wav(OUT/'allseeingeye.wav')
    assert np.array_equal(exported[:drop],original[:drop])
    assert len(exported)==len(original)
    report=dict(slug='allseeingeye',name='Allseeingeye',version=3,description=a.description,
                duration_seconds=round(len(mix)/SR,3),drop_seconds=round(a.seconds(16),3),
                peak_dbfs=round(float(20*np.log10(np.max(np.abs(mix)))),2),
                rms_dbfs=round(float(20*np.log10(np.sqrt(np.mean(mix**2)))),2),
                verified_theme_statements=len(a.statements),piano_intro_sample_identical_to_v2=True,
                drum_notes_and_chop_edits_unchanged=True,post_drop_bpm=186,
                strings_horns_and_saw_lead_removed=True,
                drums_to_lead_rms_db=round(float(20*np.log10(np.sqrt(np.mean(drums[drop:finish]**2))/np.sqrt(np.mean(lead[drop:finish]**2)))),2),
                **midi)
    assert report['drums_to_lead_rms_db']>1
    (OUT/'allseeingeye_score.json').write_text(json.dumps(dict(title=a.title,version=3,tempos=a.tempos,end=a.end,
        parts=a.parts,events=a.events,markers=a.markers,statements=a.statements,drum_audio_edits=a.edits,
        master_gain=gain,processing={'Driven piano melody':'58% parallel tanh drive, factor 4',
        'Distorted low pulse':'40% parallel tanh drive, factor 5',
        'Metallic echoes':'Custom decaying 2.71-ratio FM with faint 2.006-ratio partial',
        'Reversed piano breaths':'Individual piano samples reversed inside note bounds'}),indent=2),encoding='utf-8')
    return report


def main():
    report=render(build())
    reports=json.loads((OUT/'validation.json').read_text())
    reports=[r for r in reports if r['slug'] not in ('boss1','allseeingeye')]+[report]
    (OUT/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    readme='''# Blockbound - Homeward themes

Current files: melody, adventure1, adventure2, adventure3, allseeingeye, each as WAV and editable MIDI.
The three exploration derivatives are unchanged from revision 2. The boss is now named Allseeingeye.

Allseeingeye: 69.7 seconds. The first 10.435 seconds are sample-identical to the previously approved solo-piano opening.
At the 186 BPM drop, a hard-struck, lightly driven piano carries the melody. Sparse FM glass echoes,
reversed piano and a rough low pulse replace the previous strings, horns and guitar backing.
The chopped drum notes, ghost hits, retriggers, reverse edits and tape stops are retained.

WAVs: 44.1 kHz, 16-bit stereo, natural endings. MIDI files contain separate named tracks and tempo/section markers.
Allseeingeye MIDI uses editable source notes and a vibraphone proxy for the custom glass sound;
distortion, custom synthesis, reversed piano and drum edits are baked into the WAV.

Previous versions: previous_v1/ and previous_v2/. The old boss1 name is retained only in those archives and historical build scripts.
Use compose_allseeingeye.py to rebuild the current boss; compose_v2.py builds the exploration revision and historical boss.
Each *_score.json contains note events and mix details. validation.json records export checks.
The current ZIP includes the three exploration tracks, Allseeingeye and the melody reference, with MIDI for each.

Sample source: the existing GeneralUser GS bank by S. Christian Collins. License: .music-tools/GeneralUser-LICENSE.txt.
'''
    (OUT/'README.md').write_text(readme,encoding='utf-8')
    # Retire the previous visible boss files only after both new exports validate.
    for name in ('boss1.wav','boss1.mid','boss1_score.json'):
        old=OUT/name;backup=OUT/'previous_v2'/name
        if old.exists():
            assert backup.is_file() and old.read_bytes()==backup.read_bytes()
            old.unlink()
    with zipfile.ZipFile(OUT/'Blockbound_Homeward_Themes.zip','w',zipfile.ZIP_DEFLATED) as z:
        for slug in ('melody','adventure1','adventure2','adventure3','allseeingeye'):
            for ext in ('.wav','.mid'):z.write(OUT/(slug+ext),slug+ext)
        for name in ('README.md','validation.json'):z.write(OUT/name,name)
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
