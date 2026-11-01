"""Two additional night exploration themes: night1 (Homeward-derived), night2 (new).

Leaves all existing night/cave/adventure/boss files intact. Uses existing workspace
GeneralUser GS samples; produces WAV, editable MIDI, score and validation files.
"""
from pathlib import Path
import importlib.util
import json
import math
import zipfile
import numpy as np

OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('night_engine',OUT/'compose_v2.py')
v2=importlib.util.module_from_spec(spec);spec.loader.exec_module(v2)
eng=v2.eng;SR=eng.SR

N1_CHORDS={
    'Em9':(40,[55,59,66]), 'Cmaj7':(36,[52,55,59]),
    'G6':(31,[50,55,64]), 'Dsus':(38,[54,57,64]),
    'Am7':(33,[52,55,60]), 'Bm7':(35,[50,54,57]),
}
N2_CHORDS={
    'Dm9':(38,[53,60,64]), 'Cmaj7':(36,[52,55,59]),
    'G6':(31,[52,55,59]), 'Am7':(33,[52,55,60]),
    'Dm':(38,[53,57,62]),
}


def add_phrase(a,part,start,notes,velocity=58):
    for b,p,d in notes:a.note(part,start+b,p,d,velocity if d>=1 else velocity-5)


def night1():
    a=eng.Arrangement('night1','Lanterns Aloft',[(0,72,'Quietly, with space')],112,
        'A warm night exploration piece: slow Homeward piano recollections between soft guitar, strings and long pauses in the melody.')
    a.meter=(4,4);a.key='G'
    a.quiet=[(0,16),(32,48),(64,80),(104,112)]
    a.part('Piano - Homeward recollections',0,-27,64,.18)
    a.part('Nylon guitar - quiet figures',24,-31,38,.16)
    a.part('Warm string harmony',49,-33,84,.2)
    a.part('Acoustic bass',32,-34,58,.09)
    a.markers=[(0,'Night settles - no melody'),(16,'A familiar lantern'),(32,'Empty sky - no melody'),
               (48,'Another memory'),(64,'The quiet between islands'),(80,'A little light'),(96,'Home in the distance')]
    progression=['Em9','Cmaj7','G6','Dsus','Em9','Cmaj7','Am7','Dsus','Em9','Cmaj7','Bm7','Em9','Cmaj7','G6']
    for i,chord in enumerate(progression):
        b=i*8;root,voices=N1_CHORDS[chord]
        for p in voices:a.note('Warm string harmony',b,p,7.7,38 if b<16 else 43)
        a.note('Acoustic bass',b,root,5.6,42)
        # Slow independent plucks leave room instead of endlessly circling an arpeggio.
        figures=[(.4,root+12,2.1),(3,voices[1],1.8),(6,voices[0]+12,1.45)]
        if i%2:figures=[(.5,voices[0],2.4),(4.5,voices[2],2.1)]
        for j,(off,p,d) in enumerate(figures):a.note('Nylon guitar - quiet figures',b+off,p,d,43 if j==0 else 37)
    # Two short direct quotations, stretched to half speed. The full theme never loops.
    for start,original_start in [(16,0),(48,8)]:
        for e in eng.THEME:
            if original_start<=e['beat']<original_start+8:
                a.note('Piano - Homeward recollections',start+(e['beat']-original_start)*2,
                       e['pitch'],e['length']*2,e['velocity']-24)
    add_phrase(a,'Piano - Homeward recollections',80,
        [(0,71,1.8),(2.5,69,1.1),(4,67,2.2),(8,74,1.6),(10,76,2.5),(13,74,1.8)],57)
    add_phrase(a,'Piano - Homeward recollections',96,
        [(0,71,1.5),(2,69,1.3),(4,67,3.5)],53)
    a.quoted_windows=[(16,0),(48,8)]
    return a


def night2():
    a=eng.Arrangement('night2','Beyond the Firelight',[(0,64,'Still, gently swaying')],96,
        'An independent D-Dorian night melody: low clarinet calls, soft electric piano and sparse nylon guitar, with a quietly hopeful ending.')
    a.meter=(3,4);a.key='Dm'
    a.quiet=[(0,12),(24,36),(60,72),(90,96)]
    a.part('Clarinet - independent night melody',71,-27,62,.2)
    a.part('Soft electric piano harmony',4,-31,78,.18)
    a.part('Nylon guitar responses',24,-33,34,.21)
    a.part('Low warm atmosphere',89,-36,64,.24)
    a.part('Acoustic bass',32,-35,56,.1)
    a.markers=[(0,'Beyond the firelight'),(12,'First call'),(24,'Stillness'),(36,'A distant answer'),
               (48,'Something opens'),(60,'Listening'),(72,'The call returns'),(90,'Safe for now')]
    progression=['Dm9','Cmaj7','Dm9','G6','Am7','Dm9','Dm9','Cmaj7',
                 'G6','Dm9','Cmaj7','Am7','Dm9','G6','Dm','Dm']
    for i,chord in enumerate(progression):
        b=i*6;root,voices=N2_CHORDS[chord]
        for j,p in enumerate(voices):a.note('Soft electric piano harmony',b+.025*j,p,5.35,42-j*3)
        # A low two-note bed, avoiding a high sparkly/music-box register.
        a.note('Low warm atmosphere',b,root+12,5.85,35)
        a.note('Low warm atmosphere',b,root+19,5.85,33)
        a.note('Acoustic bass',b,root,4.7,40)
        if i%2==0:
            a.note('Nylon guitar responses',b+2.5,voices[1],1.7,41)
            a.note('Nylon guitar responses',b+4.5,voices[0]+12,1.2,35)
        else:a.note('Nylon guitar responses',b+3.5,voices[2],1.7,38)
    # New four-note idea: D down to A, then C up to E. No Homeward quotation.
    call=[(0,62,1.35),(1.5,57,.85),(3,60,1.8),(5,64,.75),(6,62,2.4),(9,57,1.4)]
    add_phrase(a,'Clarinet - independent night melody',12,call,59)
    add_phrase(a,'Clarinet - independent night melody',36,
        [(0,62,1.35),(1.5,57,.85),(3,60,1.8),(5,64,.75),(6,65,2.4),(9,64,1.4)],60)
    add_phrase(a,'Clarinet - independent night melody',48,
        [(0,64,1.8),(2.25,67,.6),(3,65,2),(6,64,1.4),(8,60,.8),(9,57,1.8)],60)
    add_phrase(a,'Clarinet - independent night melody',72,call,57)
    add_phrase(a,'Clarinet - independent night melody',84,
        [(0,65,1.3),(1.5,64,1.2),(3,62,2.7)],55)
    return a


def room(send):
    n=len(send);irn=round(1.45*SR);rng=np.random.default_rng(2926)
    t=np.arange(irn)/SR;env=np.exp(-t/.23);env[:round(.022*SR)]=0
    size=1<<(n+irn-1).bit_length();out=np.zeros_like(send)
    for ch in range(2):
        ir=np.convolve(rng.normal(size=irn),np.ones(22)/22,mode='same')*env
        ir/=max(np.sqrt(np.sum(ir**2)),1e-8)
        out[:,ch]=np.fft.irfft(np.fft.rfft(send[:,ch],size)*np.fft.rfft(ir,size),size)[:n]
    return out


def validate(a):
    lead_name=next(name for name in a.parts if 'recollections' in name or 'independent night melody' in name)
    events=sorted([e for e in a.events if e['part']==lead_name],key=lambda e:e['beat'])
    for x,y in zip(events,events[1:]):assert x['beat']+x['length']<=y['beat']
    for start,end in a.quiet:
        assert not any(e['beat']<end and e['beat']+e['length']>start for e in events)
    if a.slug=='night1':
        for start,original in a.quoted_windows:
            expected=[(round((e['beat']-original)*2,4),e['pitch'],round(e['length']*2,4))
                      for e in eng.THEME if original<=e['beat']<original+8]
            actual=[(round(e['beat']-start,4),e['pitch'],round(e['length'],4)) for e in events if start<=e['beat']<start+16]
            assert expected==actual
    else:
        # No six-note interval sequence from Homeward appears in the new lead.
        def patterns(pitches):
            return {tuple(pitches[i+j+1]-pitches[i+j] for j in range(5)) for i in range(len(pitches)-5)}
        assert not patterns([e['pitch'] for e in events]) & patterns([e['pitch'] for e in eng.THEME])
    return lead_name


def render(a):
    lead_name=validate(a)
    n=round((a.seconds(a.end)+2.5)*SR);mix=np.zeros((n,2),np.float32);send=np.zeros_like(mix)
    for name,part in a.parts.items():
        signal=v2.normalize_active(a,name,eng.render_part(a,name))
        mix+=signal;send+=signal*part['wet']
        print(a.slug+': '+name,flush=True)
    mix+=room(send)
    # Both tracks are deliberately quieter than the daytime arrangements.
    active=mix[:round(a.seconds(a.end)*SR)]
    gain=min(10**(-24/20)/float(np.sqrt(np.mean(active**2))),10**(-5/20)/float(np.max(np.abs(mix))))
    mix*=gain
    fadein=round(1.2*SR);mix[:fadein]*=np.linspace(0,1,fadein)[:,None]
    fadeout=round(1.7*SR);mix[-fadeout:]*=np.linspace(1,0,fadeout)[:,None]
    largest=max(p['render_gain'] for p in a.parts.values())
    for part in a.parts.values():part['expression']=max(1,min(127,round(127*(part['render_gain']/largest)**(1/3))))
    checks=eng.midi_export(a)
    path=OUT/(a.slug+'.mid');midi=eng.mido.MidiFile(path)
    for msg in midi.tracks[0]:
        if msg.type=='time_signature':msg.numerator,msg.denominator=a.meter
        if msg.type=='key_signature':msg.key=a.key
    midi.save(path)
    eng.save_wave(OUT/(a.slug+'.wav'),mix)
    report=dict(slug=a.slug,title=a.title,description=a.description,duration_seconds=round(len(mix)/SR,3),
        bpm=a.tempos[0][1],meter=f'{a.meter[0]}/{a.meter[1]}',
        peak_dbfs=round(float(20*np.log10(np.max(np.abs(mix)))),2),
        rms_dbfs=round(float(20*np.log10(np.sqrt(np.mean(mix**2)))),2),
        theme_relationship='Two half-speed Homeward quotations plus derivatives' if a.slug=='night1' else 'Independent melody; no Homeward quotations',
        no_lead_sections_seconds=[[round(a.seconds(s),2),round(a.seconds(e),2)] for s,e in a.quiet],
        lead_is_monophonic=True,no_drums=True,**checks)
    assert np.isfinite(mix).all() and len(mix)/SR>80
    (OUT/(a.slug+'_score.json')).write_text(json.dumps(dict(title=a.title,tempos=a.tempos,meter=a.meter,key=a.key,
        parts=a.parts,events=a.events,end=a.end,markers=a.markers,quiet_sections=a.quiet,master_gain=gain),indent=2),encoding='utf-8')
    return report


def main():
    reports=[render(night1()),render(night2())]
    (OUT/'validation_night_variants.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    lines=['# Additional night themes','',
        'night1 - Lanterns Aloft: slow Homeward piano recollections, quiet nylon guitar, soft strings and bass. 72 BPM, 4/4.',
        'night2 - Beyond the Firelight: an independent D-Dorian clarinet melody, soft electric piano, nylon guitar and a low warm bed. 64 BPM, 3/4.',
        '', 'Both contain long passages without a lead melody, have no drums, and are mixed around -24 dBFS RMS.',
        'WAV: 44.1 kHz, 16-bit stereo, natural endings with faded tails. MIDI: separate named instrument tracks, tempo, key and meter.',
        'Existing night, cave, adventure and boss tracks are unchanged. These are additional assets; game playback configuration is unchanged.',
        'Run compose_night_variants.py to rebuild. GeneralUser GS sample license is in .music-tools/GeneralUser-LICENSE.txt.',
        'The night1 theme relationship is verified against the original score; night2 has no shared six-note interval sequence with Homeward.']
    (OUT/'README_night_variants.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    readme=OUT/'README.md';text=readme.read_text(encoding='utf-8')
    section='## Additional night variants (compose_night_variants.py)'
    if section not in text:
        text+='\n'+section+'\n\n'
        for r in reports:text+=f"- {r['slug']} - {r['title']}: {r['duration_seconds']:.1f} seconds. {r['description']}\n"
        text+='\nWAV and editable MIDI for each; details in README_night_variants.md.\n'
        readme.write_text(text,encoding='utf-8')
    with zipfile.ZipFile(OUT/'Blockbound_Night_Themes.zip','w',zipfile.ZIP_DEFLATED) as z:
        for slug in ('night1','night2'):
            for ext in ('.wav','.mid','_score.json'):z.write(OUT/(slug+ext),slug+ext)
        for name in ('README_night_variants.md','validation_night_variants.json'):z.write(OUT/name,name)
    print(json.dumps(reports,indent=2))


if __name__=='__main__':main()
