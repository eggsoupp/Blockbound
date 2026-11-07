"""Read saved VOX/GLB bytes independently, validate, and render exported animation.

No geometry generators are called. Preview quads and skinning are decoded from
the delivered GLBs. Shared render() only draws the resulting world-space faces.
"""
from pathlib import Path
import io, itertools, json, math, struct, zipfile
import numpy as np
from PIL import Image, ImageDraw
import build_wings as bw

ROOT=Path(__file__).resolve().parents[1]


class Reader:
    def __init__(self,b):self.b=b;self.pos=0
    def ints(self,n=1):
        r=struct.unpack_from('<'+'i'*n,self.b,self.pos);self.pos+=n*4
        return r[0] if n==1 else r
    def string(self):
        n=self.ints();assert n>=0
        s=self.b[self.pos:self.pos+n].decode('utf8');self.pos+=n;return s
    def dic(self):
        out={}
        for _ in range(self.ints()):
            key=self.string();value=self.string();out[key]=value
        return out


def read_vox(path):
    b=path.read_bytes();assert b[:4]==b'VOX ';assert b[8:12]==b'MAIN'
    assert struct.unpack_from('<i',b,16)[0]==len(b)-20
    pos=20;models=[];sizes=[];trns={};groups={};shapes={};layers={}
    while pos<len(b):
        tag=b[pos:pos+4];n,children=struct.unpack_from('<ii',b,pos+4);assert children==0
        raw=b[pos+12:pos+12+n];assert len(raw)==n;r=Reader(raw)
        if tag==b'SIZE':
            size=np.array(r.ints(3));assert np.all((size>0)&(size<=256));sizes.append(size)
        elif tag==b'XYZI':
            count=r.ints();pts=np.frombuffer(raw[4:],np.uint8).reshape(-1,4).astype(int)
            assert len(pts)==count and count>0
            assert np.all(pts[:,:3]<sizes[-1]);assert np.all((pts[:,3]>0)&(pts[:,3]<=len(bw.RGB)))
            assert len(np.unique(pts[:,:3],axis=0))==count
            models.append(pts)
        elif tag==b'nTRN':
            id=r.ints();attrs=r.dic();child,reserved,layer,frames=r.ints(4)
            assert reserved==-1 and frames==1
            frame=r.dic();assert '_r' not in frame
            translation=np.array(list(map(int,frame.get('_t','0 0 0').split())))
            trns[id]=(child,translation,attrs,layer)
        elif tag==b'nGRP':
            id=r.ints();r.dic();count=r.ints();groups[id]=list(r.ints(count)) if count!=1 else [r.ints()]
        elif tag==b'nSHP':
            id=r.ints();r.dic();assert r.ints()==1;shapes[id]=r.ints();r.dic()
        elif tag==b'LAYR':
            id=r.ints();layers[id]=r.dic();assert r.ints()==-1
        elif tag==b'RGBA':
            assert len(raw)==1024
            assert [tuple(v[:3]) for v in np.frombuffer(raw,np.uint8).reshape(-1,4)[:len(bw.RGB)]]==bw.RGB
        pos+=12+n
    assert pos==len(b);assert len(models)==len(sizes)
    out={};seen=set()
    def walk(id,translation,name=''):
        assert id not in seen;seen.add(id)
        if id in trns:
            child,t,attrs,layer=trns[id]
            if layer>=0:assert layer in layers
            walk(child,translation+t,attrs.get('_name',name))
        elif id in groups:
            for child in groups[id]:walk(child,translation,name)
        else:
            mid=shapes[id];p=models[mid].copy();p[:,:3]+=translation-sizes[mid]//2
            assert name not in out;out[name]=p
    walk(0,np.zeros(3,dtype=int))
    assert len(out)==len(models)
    return out


def read_glb(path):
    b=path.read_bytes();assert b[:4]==b'glTF'
    version,length=struct.unpack_from('<II',b,4);assert version==2 and length==len(b)
    n,tag=struct.unpack_from('<I4s',b,12);assert tag==b'JSON'
    doc=json.loads(b[20:20+n]);off=20+n
    size,tag=struct.unpack_from('<I4s',b,off);assert tag==b'BIN\0'
    blob=b[off+8:];assert len(blob)==size and len(blob)-doc['buffers'][0]['byteLength']<4
    def acc(id):
        a=doc['accessors'][id];v=doc['bufferViews'][a['bufferView']]
        count=a['count'];nc={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        dtype={5126:'<f4',5123:'<u2',5125:'<u4'}[a['componentType']]
        offset=v.get('byteOffset',0)+a.get('byteOffset',0)
        assert offset%4==0 and offset+count*nc*np.dtype(dtype).itemsize<=len(blob)
        x=np.frombuffer(blob,dtype,offset=offset,count=count*nc).reshape(count,nc).copy()
        assert np.isfinite(x).all()
        if 'min' in a:assert np.allclose(x.min(0),a['min'])
        if 'max' in a:assert np.allclose(x.max(0),a['max'])
        return x
    for i in range(len(doc['accessors'])):acc(i)
    return doc,acc


def rotation(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])


def transforms(doc,acc,clip=None,time=0):
    local=[np.eye(4) for n in doc['nodes']]
    for i,n in enumerate(doc['nodes']):local[i][:3,3]=n.get('translation',[0,0,0])
    if clip is not None:
        anim=next(a for a in doc['animations'] if a['name']==clip)
        for ch in anim['channels']:
            s=anim['samplers'][ch['sampler']];t=acc(s['input']).ravel();vals=acc(s['output'])
            assert np.all(np.diff(t)>0);assert np.allclose(np.linalg.norm(vals,axis=1),1,atol=1e-6)
            idx=int(np.clip(np.searchsorted(t,time,side='right')-1,0,len(t)-2))
            fac=np.clip((time-t[idx])/(t[idx+1]-t[idx]),0,1)
            a,b=vals[idx],vals[idx+1]
            if a@b<0:b=-b
            dot=np.clip(a@b,-1,1);theta=math.acos(dot)
            q=a*(1-fac)+b*fac if theta<1e-5 else (a*math.sin((1-fac)*theta)+b*math.sin(fac*theta))/math.sin(theta)
            q/=np.linalg.norm(q);local[ch['target']['node']][:3,:3]=rotation(q)
    global_m={}
    def walk(i,parent):
        assert i not in global_m
        global_m[i]=parent@local[i]
        for j in doc['nodes'][i].get('children',[]):walk(j,global_m[i])
    for i in doc['scenes'][0]['nodes']:walk(i,np.eye(4))
    return global_m


def exported_meshes(doc,acc,clip=None,time=0):
    t=transforms(doc,acc,clip,time);skin=doc['skins'][0];ibm=acc(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    result={}
    for node in doc['nodes']:
        if 'mesh' not in node:continue
        prim=doc['meshes'][node['mesh']]['primitives'][0];attrs=prim['attributes']
        p=acc(attrs['POSITION']);j=acc(attrs['JOINTS_0']);w=acc(attrs['WEIGHTS_0'])
        assert np.allclose(w.sum(1),1);assert np.all(w[:,0]==1);assert np.max(j)<len(skin['joints'])
        assert len(np.unique(j[:,0]))==1
        bone=skin['joints'][int(j[0,0])];mat=t[bone]@ibm[int(j[0,0])]
        posed=p@mat[:3,:3].T+mat[:3,3]
        # GLB (X,Z,-Y)*scale -> source voxel-space, for the shared renderer only.
        q=(posed[:,[0,2,1]]*[1,-1,1]/bw.SCALE).reshape(-1,4,3)
        uv=acc(attrs['TEXCOORD_0']);colors=np.rint(uv[::4,0]*64+.5).astype(int)
        result[node['name'].removesuffix('_Mesh')]=(q,colors,None,None)
    return result


def main():
    manifest=json.loads((ROOT/'rigging.json').read_text())
    report={'status':'passed','checks':['VOX byte bounds, palette, graph, model coordinates',
        'Individual parts reproduce assembled scenes; no detached voxel islands','GLB accessors, index bounds, winding, normals, surface areas',
        'Bind matrices reproduce VOX geometry bounds','Skin weights normalized and one bone per piece',
        'All joints animate; root fixed; flap loops; rigid transforms preserve edge lengths'],
        'files':{},'models':{}}
    for path in sorted(ROOT.rglob('*.vox')):
        vox=read_vox(path)
        report['files'][str(path.relative_to(ROOT))]={'parts':len(vox),'voxels':sum(len(v) for v in vox.values())}
    glbs={}
    for name,model in manifest['models'].items():
        vox=read_vox(ROOT/f'{name}.vox');doc,acc=read_glb(ROOT/'rigged'/f'{name}.glb')
        assert set(vox)==set(model['joints']);assert len(doc['skins'][0]['joints'])==len(vox)
        rest=exported_meshes(doc,acc)
        total=0;maxerr=0;areaerr=0
        for n,points in vox.items():
            part=read_vox(ROOT/'parts'/name/f'{n}.vox')[n]
            assert np.array_equal(part,points)
            todo=set(map(tuple,points[:,:3]));stack=[todo.pop()]
            steps=[s for s in itertools.product((-1,0,1),repeat=3) if s!=(0,0,0)]
            while stack:
                x,y,z=stack.pop()
                for dx,dy,dz in steps:
                    p=(x+dx,y+dy,z+dz)
                    if p in todo:todo.remove(p);stack.append(p)
            assert not todo,(name,n,'detached geometry')
            p=points[:,:3]-manifest['vox_scene_translation'];q=rest[n][0].reshape(-1,3)
            assert np.allclose(q.min(0),p.min(0)-.5);assert np.allclose(q.max(0),p.max(0)+.5)
        bind=transforms(doc,acc)
        skin=doc['skins'][0];ibm=acc(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        for k,j in enumerate(skin['joints']):
            maxerr=max(maxerr,float(np.max(np.abs(bind[j]@ibm[k]-np.eye(4)))))
        assert maxerr<1e-6
        for gm in doc['meshes']:
            prim=gm['primitives'][0];a=prim['attributes'];p=acc(a['POSITION']);idx=acc(prim['indices']).ravel()
            assert max(idx)<len(p) and len(idx)%3==0
            tris=p[idx].reshape(-1,3,3);cross=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]);areas=np.linalg.norm(cross,axis=1)*.5
            assert np.all(areas>0);normal=acc(a['NORMAL']);assert np.allclose(np.linalg.norm(normal,axis=1),1)
            assert np.all(np.sum(cross*normal[idx[::3]],axis=1)>0)
            partname=gm['name'].removesuffix('_Mesh')
            expected=model['parts'][partname]['surface_voxel_faces']*bw.SCALE**2
            areaerr=max(areaerr,float(abs(areas.sum()-expected)));assert abs(areas.sum()-expected)<1e-5
            total+=len(idx)//3
        # Assert exported animation really moves every non-frame mesh rigidly.
        moved=exported_meshes(doc,acc,'Flap',.3);start=exported_meshes(doc,acc,'Flap',0);end=exported_meshes(doc,acc,'Flap',1.2)
        for n in rest:
            rq=rest[n][0];mq=moved[n][0]
            assert np.allclose(start[n][0],end[n][0],atol=1e-5)
            assert np.allclose(np.linalg.norm(rq[:,1]-rq[:,0],axis=1),np.linalg.norm(mq[:,1]-mq[:,0],axis=1),atol=2e-5)
            if n=='Frame':assert np.allclose(rq,mq)
            else:assert np.max(abs(rq-mq))>.01
        # A three-pose contact sheet reconstructed from delivered GLB bytes.
        sheet=Image.new('RGB',(1800,520),(13,19,28));draw=ImageDraw.Draw(sheet)
        for i,(label,clip,t) in enumerate([('REST / BIND',None,0),('FLAP / MID-STROKE','Flap',.3),('FOLD / END','Fold',.8)]):
            im=bw.render(exported_meshes(doc,acc,clip,t),(600,470),bounds=([-85,-60],[85,40]));sheet.paste(im,(i*600,40))
            draw.text((i*600+20,8),label,font=bw.font(21,True),fill=(224,231,239))
        sheet.save(ROOT/'previews'/f'{name}_rig_check.png')
        report['models'][name]={'joints':len(vox),'triangles':total,'bind_max_error':maxerr,'surface_area_max_error':areaerr,'animations':['Flap','Fold']}
        glbs[name]=(doc,acc)
        print(name,'passed',flush=True)
    frames=[]
    for t in np.linspace(0,1.2,24,endpoint=False):
        canvas=Image.new('RGB',(1280,640),(12,17,27));d=ImageDraw.Draw(canvas)
        for i,(name,(doc,acc)) in enumerate(glbs.items()):
            im=bw.render(exported_meshes(doc,acc,'Flap',t),(320,278),bounds=([-85,-60],[85,40]))
            x=(i%4)*320;y=(i//4)*320+35;canvas.paste(im,(x,y));d.text((x+13,y-26),name.replace('Wings',' Wings'),font=bw.font(19,True),fill=(226,231,237))
        d.text((985,420),'EXPORTED GLB RIGS',font=bw.font(18,True),fill=(233,216,172))
        d.text((985,452),'24 frames / 1.2s loop',font=bw.font(16),fill=(158,177,196))
        frames.append(canvas)
    frames[0].save(ROOT/'previews'/'Flap_Rig_Preview.gif',save_all=True,append_images=frames[1:],duration=50,loop=0,optimize=False)
    (ROOT/'validation.json').write_text(json.dumps(report,indent=2))
    print('Validated',len(report['files']),'VOX files and',len(glbs),'rigged GLBs; rendered actual exported animation.')


if __name__=='__main__':main()
