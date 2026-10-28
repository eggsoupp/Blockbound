"""Allseeingeye v5: layered electronic boss theme, quieter intro/louder drop.

Keeps the original melody, countermelody, dark harmony and chopped breaks.
All guitar voices are replaced with custom band-limited electronic instruments.
Broad reference only: https://dmdokuro.bandcamp.com/track/universal-collapse
No melody, transcription or recording from that reference is used.
"""
from pathlib import Path
import importlib.util
import json
import math
import zipfile
import numpy as np

OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('revision4',OUT/'compose_allseeingeye_v4.py')
v4=importlib.util.module_from_spec(spec);spec.loader.exec_module(v4)
v2=v4.v2;eng=v4.eng;SR=eng.SR


def build():
    old=v4.build()
    a=v2.setup(eng.Arrangement('allseeingeye','Allseeingeye',old.tempos,old.end,
        'A wide electronic lead, flowing synth figure, piano countermelody and dark harmony over powerful chopped breaks; quieter piano opening and louder drop.'),[])
    a.part('Exposed piano melody',0,-31.5,64,.04)
    a.part('Wide unison melody',81,-17,64,.075)
    a.part('Lower synth melody',80,-30,64,.055)
    a.part('Piano countermelody',0,-23,48,.075)
    a.part('Wide minor harmony',89,-24,64,.11)
    a.part('Pulsing synth chords',81,-27,40,.055)
    a.part('Flowing synth figure',80,-30,88,.075)
    a.part('Heavy bass',38,-23,64,.01)
    a.part('Chopped break drums',0,-19,64,.025,True)
    mapping={'Exposed piano melody':'Exposed piano melody','Sustained guitar melody':'Wide unison melody',
             'Lower guitar melody shadow':'Lower synth melody','Piano countermelody':'Piano countermelody',
             'Wide minor harmony':'Wide minor harmony','Rhythm guitar left':'Pulsing synth chords',
             'Heavy bass':'Heavy bass','Chopped break drums':'Chopped break drums'}
    for e in old.events:
        if e['part'] in mapping:a.note(mapping[e['part']],e['beat'],e['pitch'],e['length'],e['velocity'])
    a.statements=[dict(s,part=mapping[s['part']]) for s in old.statements if s['part'] in mapping]
    a.edits=old.edits
    a.markers=[(0,'Quiet piano'),(16,'DROP - full electronic theme'),(80,'Fracture'),
               (96,'Second phase - widened return'),(160,'Final assault'),(176,'Last stand')]
    for index,b in enumerate(range(16,192,4)):
        if b<80:chord=v4.HARMONY[(b-16)//8]
        elif b<96:chord=['Em','C','Am','Bm'][(b-80)//4]
        elif b<160:chord=v4.HARMONY[(b-96)//8]
        elif b<176:chord=['Em','C','Am','D'][(b-160)//4]
        else:chord=['Em','C','Bm','Em'][(b-176)//4]
        tones=v4.CHORDS[chord]
        # Smooth, pitched movement rather than bells or metallic percussion.
        pattern=[tones[1]+12,tones[3],tones[2]+12,tones[3],tones[1]+12,tones[2]+12,tones[3],tones[1]+12]
        for j,p in enumerate(pattern):
            if 80<=b<96 and j%2:continue
            a.note('Flowing synth figure',b+j*.5,p,.4,62 if b>=96 else 53)
    assert not any(p['program'] in (24,25,26,27,28,29,30,31) for p in a.parts.values())
    return a


def electronic_voice(a,name):
    """Detuned harmonic oscillators with a stable fundamental and soft top end.

    The lead has a sustained body rather than the short decay of the rejected
    piano lead. The chord/figure voices are gated separately to avoid a guitar
    wall or a single static stock-saw patch.
    """
    n=round((a.seconds(a.end)+2.5)*SR);signal=np.zeros((n,2),np.float32)
    is_lead=name=='Wide unison melody'
    is_low=name=='Lower synth melody'
    is_figure=name=='Flowing synth figure'
    for e in a.events:
        if e['part']!=name:continue
        first=round(a.seconds(e['beat'])*SR)
        hold=a.seconds(e['beat']+e['length'])-a.seconds(e['beat'])
        release=.065 if is_figure else .09
        length=min(n-first,round((hold+release)*SR));t=np.arange(length)/SR
        frequency=440*2**((e['pitch']-69)/12)
        attack=.006 if is_figure else .012
        env=(1-np.exp(-t/attack))*np.clip((hold+release-t)/release,0,1)
        if is_figure:env*=.45+.55*np.exp(-t/.065)
        elif not is_lead and not is_low:env*=.66+.34*np.exp(-t/.09)
        velocity=(e['velocity']/95)**1.1
        vibrato=.0019*np.sin(2*np.pi*4.7*t)*np.clip((t-.16)/.25,0,1) if is_lead else np.zeros_like(t)
        phase_time=t+vibrato/(2*np.pi*4.7)
        for ch in range(2):
            voice=np.zeros(length)
            detunes=(-6,0,5) if ch==0 else (-5,0,6)
            if not is_lead:detunes=(-3,3)
            for detune in detunes:
                f=frequency*2**(detune/1200)
                phase=2*np.pi*f*phase_time
                wave=np.sin(phase)
                for h in range(2,10 if is_lead else 6):
                    # Harmonic rolloff avoids an abrasive buzzy upper register.
                    amp=(.75 if is_lead else .5)/(h**1.35)
                    if h%2==0:amp*=.7
                    wave+=amp*np.sin(h*phase+.12*(h-1))
                voice+=wave/len(detunes)
            if is_lead:voice=.83*voice+.17*np.sin(2*np.pi*frequency*t)
            pan=a.parts[name]['pan']/127
            pan_gain=math.cos(pan*math.pi/2) if ch==0 else math.sin(pan*math.pi/2)
            signal[first:first+length,ch]+=voice*env*velocity*.16*pan_gain
    a.parts[name].update(render_gain=1.,raw_rms_db=None,instrument='Custom band-limited unison synthesizer; GM MIDI proxy')
    return signal


def soft_peak_control(x):
    threshold=.57;ceiling=10**(-1/20)
    magnitude=np.abs(x)
    above=threshold+(ceiling-threshold)*np.tanh(np.maximum(0,magnitude-threshold)/(ceiling-threshold))
    return np.sign(x)*np.where(magnitude<=threshold,magnitude,above)


def render(a):
    v2.validate(a)
    n=round((a.seconds(a.end)+2.5)*SR)
    mix=np.zeros((n,2),np.float32);send=np.zeros_like(mix)
    music=np.zeros_like(mix);lead=np.zeros_like(mix);backing=np.zeros_like(mix);drums=None
    electronic={'Wide unison melody','Lower synth melody','Pulsing synth chords','Flowing synth figure'}
    for name,part in a.parts.items():
        if name=='Wide minor harmony':signal=v4.synth_harmony(a,name)
        elif name in electronic:signal=electronic_voice(a,name)
        else:signal=eng.render_part(a,name)
        signal=v2.normalize_active(a,name,signal)
        if name=='Chopped break drums':
            signal=v2.normalize_active(a,name,v2.process_break(a,signal));drums=signal.copy()
        else:
            music+=signal
            if name in ('Wide unison melody','Lower synth melody'):lead+=signal
            elif name!='Exposed piano melody':backing+=signal
        mix+=signal;send+=signal*part['wet']
        print('allseeingeye v5: '+name,flush=True)
    mix+=eng.short_room(send)
    drop=round(a.seconds(16)*SR);end=round(a.seconds(a.end)*SR)
    previous=v2.read_wav(OUT/'previous_v4'/'allseeingeye.wav')
    old_rms=float(np.sqrt(np.mean(previous[drop:end]**2)))
    target_rms=old_rms*10**(2/20)
    # Raise the actual post-drop RMS by 2 dB relative to v4, with gentle peak control.
    sample=mix[drop:end:8]
    low,high=.01,20.
    for _ in range(28):
        trial=(low+high)/2
        if np.sqrt(np.mean(soft_peak_control(sample*trial)**2))<target_rms:low=trial
        else:high=trial
    gain=(low+high)/2
    mix=soft_peak_control(mix*gain).astype(np.float32)
    intro_gain=10**(-4.5/20)
    mix[:drop]=previous[:drop]*intro_gain
    mix[-round(.8*SR):]*=np.linspace(1,0,round(.8*SR))[:,None]
    highest=max(p['render_gain'] for p in a.parts.values())
    for p in a.parts.values():p['expression']=max(1,min(127,round(127*(p['render_gain']/highest)**(1/3))))
    midi=eng.midi_export(a)
    eng.save_wave(OUT/'allseeingeye.wav',mix)
    exported=v2.read_wav(OUT/'allseeingeye.wav')
    assert np.max(np.abs(exported[:drop]-previous[:drop]*intro_gain))<=1/32767
    assert not np.any(drums[:drop]) and not np.any(backing[:drop])
    def rms(x):return float(np.sqrt(np.mean(x[drop:end]**2)))
    report=dict(slug='allseeingeye',name='Allseeingeye',version=5,description=a.description,
        duration_seconds=round(len(mix)/SR,3),drop_seconds=round(a.seconds(16),3),post_drop_bpm=186,
        peak_dbfs=round(float(20*np.log10(np.max(np.abs(mix)))),2),
        rms_dbfs=round(float(20*np.log10(np.sqrt(np.mean(mix**2)))),2),
        intro_change_db=round(float(20*np.log10(np.sqrt(np.mean(exported[:drop]**2))/np.sqrt(np.mean(previous[:drop]**2)))),2),
        post_drop_change_db=round(20*math.log10(rms(exported)/old_rms),2),
        intro_notes_and_timing_unchanged=True,verified_theme_statements=len(a.statements),
        guitar_parts_removed=True,metallic_parts_absent=True,
        music_to_drums_rms_db=round(20*math.log10(rms(music)/rms(drums)),2),
        backing_to_drums_rms_db=round(20*math.log10(rms(backing)/rms(drums)),2),
        lead_to_drums_rms_db=round(20*math.log10(rms(lead)/rms(drums)),2),**midi)
    assert abs(report['intro_change_db']+4.5)<.05 and abs(report['post_drop_change_db']-2)<.1
    assert report['music_to_drums_rms_db']>3 and report['lead_to_drums_rms_db']>0
    (OUT/'allseeingeye_score.json').write_text(json.dumps(dict(title=a.title,version=5,tempos=a.tempos,end=a.end,
        parts=a.parts,events=a.events,markers=a.markers,statements=a.statements,drum_audio_edits=a.edits,
        master_gain=gain,intro_change_db=-4.5,post_drop_change_db=2,
        reference='https://dmdokuro.bandcamp.com/track/universal-collapse',
        processing={'electronic_voices':'Custom soft-top unison oscillators, sustained lead, independent gated figure',
        'master':'Static gain plus gentle peak soft knee; post-drop RMS matched to v4 plus 2 dB'}),indent=2),encoding='utf-8')
    return report


def main():
    report=render(build())
    reports=json.loads((OUT/'validation.json').read_text())
    reports=[r for r in reports if r['slug']!='allseeingeye']+[report]
    (OUT/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    (OUT/'README.md').write_text('''# Blockbound - Homeward themes

Current exports: melody, adventure1, adventure2, adventure3, allseeingeye, each as WAV and MIDI.
Exploration tracks remain revision 2. Allseeingeye is revision 5, an electronic boss arrangement.

Allseeingeye: 69.7 seconds, with the drop at 10.435 seconds and 186 BPM thereafter.
The piano intro has the same notes and timing, reduced 4.5 dB from revision 4.
The section after the drop is raised 2 dB RMS relative to revision 4, with gentle peak control.
The guitars are replaced by a wide custom electronic lead, a lower synth layer, pulsing chords
and a flowing synth figure. Piano countermelody, minor harmony, bass and chopped breaks remain.
There are no metallic/glass effects. Power comes from layered music and dynamic contrast.

Broad inspiration: Universal Collapse by DM DOKURO, https://dmdokuro.bandcamp.com/track/universal-collapse
The original Homeward melody and newly written countermelody are retained; no reference recording or transcription is used.

Audio: 44.1 kHz, 16-bit stereo WAV. MIDI has separate named parts and tempo/section markers.
The custom synth instruments use General MIDI proxies; synthesis and drum edits are baked into WAV.
Use compose_allseeingeye_v5.py to rebuild this boss. Earlier exports are in previous_v1 through previous_v4.
The current ZIP includes all current audio and MIDI files. validation.json records the volume and export checks.
Sample source: existing GeneralUser GS by S. Christian Collins; license in .music-tools/GeneralUser-LICENSE.txt.
''',encoding='utf-8')
    with zipfile.ZipFile(OUT/'Blockbound_Homeward_Themes.zip','w',zipfile.ZIP_DEFLATED) as z:
        for slug in ('melody','adventure1','adventure2','adventure3','allseeingeye'):
            for ext in ('.wav','.mid'):z.write(OUT/(slug+ext),slug+ext)
        for name in ('README.md','validation.json'):z.write(OUT/name,name)
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
