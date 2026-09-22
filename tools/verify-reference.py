"""segyio interoperability plus independent struct/CP037/NumPy references.

Use Python 3.12 with tools/requirements.txt after release bridge build.
Variable traces and restricted rev2 are checked by struct, not misrepresented
as segyio support. Test fixtures are generated in a disposable unique directory.
"""
import argparse
import base64
import hashlib
import importlib.metadata
import json
import platform
import struct
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
import segyio

ROOT=Path(__file__).resolve().parents[1]
args_parser=argparse.ArgumentParser()
args_parser.add_argument('--evidence',type=Path)
args=args_parser.parse_args()
host=subprocess.Popen(['node','tools/oracle-host.mjs'],cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8')
checks=cases=0
start=time.perf_counter()
rng=np.random.default_rng(20260922)


def ask(data=b'',command='inspect',action='report',reject=False,**options):
    global checks
    options['command']=command
    host.stdin.write(json.dumps(dict(data=base64.b64encode(data).decode(),action=action,options=options))+'\n')
    host.stdin.flush()
    line=host.stdout.readline()
    assert line,'bridge stopped'
    answer=json.loads(line)
    if reject:
        assert not answer['ok'],'invalid input accepted'
        checks+=1
        return
    assert answer['ok'],answer.get('error')
    result=answer['result']
    return base64.b64decode(result['bytes']) if action in ['create','transform'] else result


def close(a,b,label,rtol=2e-6,atol=1e-7):
    global checks
    np.testing.assert_allclose(a,b,rtol=rtol,atol=atol,err_msg=label)
    checks+=1


def fixture(order='big',code=5,revision=1,counts=(4,3),encoding='ASCII',unknown=False):
    """Independent binary packer for layouts segyio cannot fully represent."""
    e='>' if order=='big' else '<'
    ext='((SEG: EndText))'.ljust(3200)
    codec='ascii' if encoding=='ASCII' else 'cp037'
    text=('C 1 STRUCT FIXTURE SEG-Y_REV'+str(revision)+'.0').ljust(3200).encode(codec)
    binary=bytearray(400)
    struct.pack_into(e+'H',binary,16,2000)
    struct.pack_into(e+'H',binary,20,counts[0])
    struct.pack_into(e+'H',binary,24,code)
    struct.pack_into(e+'H',binary,300,revision<<8)
    struct.pack_into(e+'H',binary,302,int(len(set(counts))==1 and revision!=0))
    if revision!=0:
        struct.pack_into(e+'h',binary,304,-1 if unknown else 1)
    if revision==2:
        struct.pack_into(e+'I',binary,68,counts[0])
        struct.pack_into(e+'d',binary,72,2000)
        struct.pack_into(e+'I',binary,96,0x01020304)
        struct.pack_into(e+'Q',binary,312,len(counts))
        struct.pack_into(e+'Q',binary,320,6800)
    payload=bytearray(text+binary+(ext.encode(codec) if revision!=0 else b''))
    all_values=[]
    for i,n in enumerate(counts):
        head=bytearray(240)
        struct.pack_into(e+'i',head,4,i+1)
        struct.pack_into(e+'i',head,20,i//2+11)
        struct.pack_into(e+'h',head,70,-100)
        struct.pack_into(e+'i',head,72,12345+i)
        struct.pack_into(e+'H',head,88,1)
        struct.pack_into(e+'H',head,114,n)
        struct.pack_into(e+'H',head,116,2000)
        if code==6:
            values=[1.0000000000003+j/7 for j in range(n)]
            samples=struct.pack(e+str(n)+'d',*values)
        elif code==7:
            values=[-8388608,8388607]+[-57]*(n-2)
            samples=b''.join(v.to_bytes(3,order,signed=True) for v in values)
        elif code==9:
            values=[-(2**63),2**63-1]+[2**53+1]*(n-2)
            samples=struct.pack(e+str(n)+'q',*values)
        else:
            values=[float(j-i) for j in range(n)]
            samples=struct.pack(e+str(n)+'f',*values)
        payload.extend(head+samples)
        all_values.append(values)
    return bytes(payload),all_values


try:
    with tempfile.TemporaryDirectory(prefix='moon-segy-reference-') as temp:
        temp=Path(temp)
        # segyio 1.9.14 does not implement 24-bit code 7; use struct below.
        for endian in ['big','little']:
            for code in [1,2,3,5,6,8,9]:
                values=np.array([[-7,1,12,4,-3,2],[2,4,6,8,10,12],[0,0,0,0,0,0]],dtype=np.float32)
                source=temp/f'source-{endian}-{code}.sgy'
                spec=segyio.spec();spec.samples=list(range(6));spec.tracecount=3;spec.format=code;spec.endian=endian
                with segyio.create(str(source),spec) as f:
                    f.text[0]=segyio.tools.create_text_header({1:'INDEPENDENT SEGYIO FIXTURE'})
                    f.bin.update({segyio.BinField.Interval:2000,segyio.BinField.Samples:6,segyio.BinField.SEGYRevision:256,segyio.BinField.TraceFlag:1})
                    for i,row in enumerate(values):
                        f.header[i]={segyio.TraceField.TRACE_SEQUENCE_FILE:i+1,segyio.TraceField.TRACE_SAMPLE_COUNT:6,
                                     segyio.TraceField.TRACE_SAMPLE_INTERVAL:2000,segyio.TraceField.CDP:10+i//2,
                                     segyio.TraceField.SourceGroupScalar:-100,segyio.TraceField.SourceX:12345+i}
                        dtype={1:np.float32,2:np.int32,3:np.int16,5:np.float32,6:np.float64,8:np.int8,9:np.int64}[code]
                        f.trace[i]=row.astype(dtype)
                data=source.read_bytes()
                report=ask(data,'validate')
                assert (report['endian'],report['sample_code'],report['trace_count'])==(endian,code,3);checks+=1
                for i,row in enumerate(values):
                    trace=ask(data,'trace',trace=i)
                    close([float(x) for x in trace['samples']],row,'segyio -> MoonBit')
                    stats=ask(data,'stats',trace=i,clip_threshold=10)
                    close(stats['mean'],float(np.mean(row,dtype=np.float64)),'mean')
                    close(stats['rms'],float(np.sqrt(np.mean(row.astype(float)**2))),'RMS')
                    assert stats['dead']==bool(np.all(row==0));checks+=1
                close(ask(data,'coordinate',trace=0,field='source_x'),123.45,'coordinate scaling')
                assert ask(data,'groups',field='ensemble')==[{'value':10,'indices':[0,1]},{'value':11,'indices':[2]}];checks+=1
                selected=ask(data,'select',action='transform',traces=[2,0])
                dest=temp/'selected.sgy';dest.write_bytes(selected)
                with segyio.open(str(dest),endian=endian,ignore_geometry=True) as f:
                    close(f.trace.raw[:],values[[2,0]],'MoonBit selection -> segyio')
                cut=ask(data,'window',action='transform',first=1,count=3)
                dest.write_bytes(cut)
                with segyio.open(str(dest),endian=endian,ignore_geometry=True) as f:
                    close(f.trace.raw[:],values[:,1:4],'MoonBit window -> segyio')
                    assert f.header[0][segyio.TraceField.DelayRecordingTime]==2;checks+=1
                generated=ask(action='create',sample_code=code,endian=endian,revision=1,interval_us=2000,
                              traces=[dict(samples=[int(x) for x in row],fields={'ensemble':20+i}) for i,row in enumerate(values)])
                dest.write_bytes(generated)
                with segyio.open(str(dest),endian=endian,ignore_geometry=True) as f:
                    close(f.trace.raw[:],values,'MoonBit create -> segyio')
                converted=ask(data,'convert',action='transform',sample_code=5)
                dest.write_bytes(converted)
                with segyio.open(str(dest),endian=endian,ignore_geometry=True) as f:
                    close(f.trace.raw[:],values,'sample conversion')
                assert ask(data,'copy',action='transform')==data;checks+=1
                cases+=1

        # Fixed/variable, versions, text encodings and exact non-float32 samples.
        for revision in [0,1,2]:
            for endian in ['big','little']:
                for encoding in ['ASCII','EBCDIC']:
                    for counts in [(4,4),(4,3)]:
                        for code in [5,6,7,9]:
                            data,values=fixture(endian,code,revision,counts,encoding)
                            report=ask(data,'validate')
                            assert report['text_encoding']==encoding;checks+=1
                            for i,row in enumerate(values):
                                result=ask(data,'trace',trace=i)
                                if code in [7,9]:
                                    assert [int(x) for x in result['samples']]==row;checks+=1
                                else:
                                    close(result['samples'],row,'struct values',rtol=0,atol=1e-14)
                            assert ask(data,'copy',action='transform')==data;checks+=1
                            selected=ask(data,'select',action='transform',traces=[1])
                            first=3600+(3200 if revision else 0)
                            e='>' if endian=='big' else '<'
                            assert struct.unpack_from(e+'H',selected,first+114)[0]==counts[1];checks+=1
                            assert selected[first+240:]==data[-counts[1]*({5:4,6:8,7:3,9:8}[code]):];checks+=1
                            if code==9:
                                ask(data,'stats',trace=0,reject=True)
                                csv=ask(data,'csv',traces=[0])['text']
                                assert str(2**63-1) in csv;checks+=1
                            cases+=1
        for encoding in ['ASCII','EBCDIC']:
            data,_=fixture(encoding=encoding,unknown=True)
            assert ask(data)['trace_count']==2;checks+=1;cases+=1

        # Entire CP037 mapping, including control bytes, independent Python codec.
        cp=bytes(range(256))*12+bytes(range(128))
        data,_=fixture(encoding='EBCDIC')
        report=ask(cp+data[3200:],text_encoding='EBCDIC')
        assert report['text']==cp.decode('cp037');checks+=1;cases+=1
        encoded=ask(action='create',sample_code=5,interval_us=1000,text_encoding='EBCDIC',
                    text=cp.decode('cp037'),traces=[{'samples':[1]}])
        assert encoded[:3200]==cp;checks+=1
        for endian in ['big','little']:
            made=ask(action='create',revision=2,endian=endian,sample_code=6,interval_us=0.25,traces=[{'samples':[1,2,3]}])
            assert made[3500:3502]==bytes([2,0]);checks+=1
            assert b'SEG-Y_REV2.0' in made[:3200];checks+=1
            e='>' if endian=='big' else '<'
            close(struct.unpack_from(e+'d',made,3272)[0],0.25,'rev2 canonical interval',rtol=0,atol=0)
            close(ask(made,'trace',trace=0)['times_seconds'],[0,0.25e-6,0.5e-6],'rev2 submicrosecond',rtol=0,atol=1e-20)
            cases+=1

        # Randomized moderate IBM values, not just values exactly representable in binary.
        sample=(rng.normal(size=400)*10**rng.uniform(-20,20,size=400)).astype(np.float32)
        generated=ask(action='create',sample_code=1,interval_us=1000,traces=[{'samples':sample.astype(float).tolist()}])
        dest=temp/'random-ibm.sgy';dest.write_bytes(generated)
        with segyio.open(str(dest),ignore_geometry=True) as f:
            close(f.trace[0],sample,'IBM randomized mantissas',rtol=2e-6,atol=0)
        cases+=1

        data,_=fixture()
        svg=ask(data,'svg',trace=0)['text']
        ET.fromstring(svg);checks+=1
        for size in [0,3199,3599,6799,len(data)-1]:
            ask(data[:size],reject=True);cases+=1
        for i in range(200):
            damaged=bytearray(data)
            struct.pack_into('>H',damaged,3224,int(rng.choice([0,4,13,14,17,65535])))
            ask(bytes(damaged),reject=True);cases+=1
        rev2,_=fixture(revision=2)
        for offset,fmt,value in [(3506,'I',1),(3528,'i',-1),(3520,'Q',2**50),(3512,'Q',9999999)]:
            damaged=bytearray(rev2);struct.pack_into('>'+fmt,damaged,offset,value)
            ask(bytes(damaged),reject=True);cases+=1
        damaged=bytearray(data);struct.pack_into('>I',damaged,6800+240,0x7fc00000)
        ask(bytes(damaged),'validate',reject=True)
        assert ask(bytes(damaged),'copy',action='transform')==damaged;checks+=1;cases+=1

        bulk=ask(action='create',sample_code=5,interval_us=2000,
                 traces=[{'samples':rng.normal(size=1000).tolist()} for _ in range(64)])
        begin=time.perf_counter()
        result=ask(bulk,'validate')
        elapsed=time.perf_counter()-begin
        assert result['trace_count']==64;checks+=1
    source_hashes={}
    for file in sorted(ROOT.rglob('*')):
        if any(p in {'_build','.git','.mooncakes','work','__pycache__','evidence'} for p in file.relative_to(ROOT).parts):continue
        if file.is_file() and file.suffix in {'.mbt','.mbti','.mjs','.py','.pkg','.mod'}:
            source_hashes[file.relative_to(ROOT).as_posix()]=hashlib.sha256(file.read_bytes()).hexdigest()
    evidence=dict(status='passed',cases=cases,checks=checks,seed=20260922,elapsed_seconds=time.perf_counter()-start,
                  versions=dict(python=platform.python_version(),numpy=np.__version__,segyio=importlib.metadata.version('segyio'),
                                node=subprocess.check_output(['node','--version'],text=True).strip(),platform=platform.platform()),
                  benchmark=dict(traces=64,samples_per_trace=1000,bytes=len(bulk),operation='scan + finite validation + JSON IPC',seconds=elapsed),
                  source_sha256=source_hashes,
                  limits=['segyio fixed trace interoperability only; code 7, variable/rev2 verified by independent struct',
                          'CP037 only, not every EBCDIC variant','no unknown trace-header remapping/extensions',
                          'raw amplitude statistics, not physical acquisition calibration'])
    if args.evidence:
        args.evidence.parent.mkdir(parents=True,exist_ok=True)
        args.evidence.write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf8',newline='\n')
    print(json.dumps({k:v for k,v in evidence.items() if k!='source_sha256'},indent=2))
finally:
    host.stdin.close()
    try:host.wait(timeout=10)
    except subprocess.TimeoutExpired:host.kill();host.wait()
