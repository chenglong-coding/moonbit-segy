"""Independent struct/segyio fixtures and NumPy dataset-QC oracle.

No MoonBit statistics feed the expected results. Variable traces/rev2/int24
are struct fixtures, not claimed as segyio support. Only --evidence writes a
persistent result. Run after the release JS bridge is built.
"""
import argparse
import base64
import csv
import importlib.metadata
import io
import json
import platform
import struct
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np
import segyio

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--evidence', type=Path)
args = parser.parse_args()
host = subprocess.Popen(['node', 'tools/oracle-host.mjs'], cwd=ROOT,
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding='utf-8')
rng = np.random.default_rng(20260924)
cases = checks = cli_checks = 0


def ask(data, options=None, reject=False):
    global checks
    host.stdin.write(json.dumps({'data': base64.b64encode(data).decode(),
                                'options': {'command': 'qc', **(options or {})}})+'\n')
    host.stdin.flush()
    line = host.stdout.readline()
    assert line, 'bridge stopped unexpectedly'
    answer = json.loads(line)
    if reject:
        assert not answer['ok'], 'invalid QC request accepted'
        checks += 1
        return
    assert answer['ok'], answer.get('error')
    return answer['result']


def fixture(rows, code=6, order='big', revision=1, encoding='ascii'):
    """Pack standard binary/trace fields independently of the library writer."""
    e = '>' if order == 'big' else '<'
    payload = bytearray(('C 1 INDEPENDENT QC FIXTURE SEG-Y_REV'+str(revision)+'.0').ljust(3200).encode(encoding)+bytes(400))
    struct.pack_into(e+'HH', payload, 3216, rows[0].get('dt', 2000), 0)
    struct.pack_into(e+'H', payload, 3220, len(rows[0]['values']))
    struct.pack_into(e+'H', payload, 3224, code)
    payload[3500] = revision
    if revision == 2:
        struct.pack_into(e+'I', payload, 3296, 0x01020304)
        struct.pack_into(e+'Q', payload, 3512, len(rows))
        struct.pack_into(e+'Q', payload, 3520, 3600)
    metadata = []
    for i, row in enumerate(rows):
        offset = len(payload)
        head = bytearray(240)
        fields = {'sequence_line': 101+i, 'sequence_file': i+1, 'field_record': i//3+1,
                  'ensemble': i % 3+10, 'identification': 1, 'weighting': 0, **row.get('fields', {})}
        for name, pos, typ in [('sequence_line',0,'i'),('sequence_file',4,'i'),('field_record',8,'i'),
                               ('ensemble',20,'i'),('identification',28,'h'),('weighting',168,'h')]:
            struct.pack_into(e+typ, head, pos, fields[name])
        struct.pack_into(e+'HH', head, 114, len(row['values']), row.get('dt', 2000))
        if code == 7:
            raw = b''.join(int(v).to_bytes(3,order,signed=True) for v in row['values'])
            values = [int(v) for v in row['values']]
        else:
            typ = {2:'i',3:'h',5:'f',6:'d',8:'b',9:'q'}[code]
            raw = struct.pack(e+str(len(row['values']))+typ, *row['values'])
            values = list(struct.unpack(e+str(len(row['values']))+typ, raw))
        payload.extend(head+raw)
        metadata.append({'trace':i, 'header_offset':offset, 'sample_offset':offset+240,
                         **fields, 'samples':len(values), 'interval_us':float(row.get('dt',2000)),
                         'values':values, 'integer':code not in (5,6)})
    return bytes(payload), metadata


def stats(values):
    if not len(values):
        return None
    a = np.asarray(values, dtype=float)
    scale = float(np.max(np.abs(a)))
    normal = a / scale if scale else a
    return {'samples':len(a), 'minimum':float(a.min()), 'maximum':float(a.max()),
            'mean':float(np.mean(normal)*scale), 'rms':float(np.sqrt(np.mean(normal**2))*scale),
            'standard_deviation':float(np.std(normal,ddof=0)*scale)}


def first(mask):
    found = np.flatnonzero(mask)
    return int(found[0]) if len(found) else None


def trace_result(meta, weighted, dead, clip):
    raw = meta['values']
    # Compare Python integers BEFORE any float conversion.
    integer_range = np.array([meta['integer'] and abs(x)>2**53 for x in raw])
    nonfinite = np.array([not meta['integer'] and not np.isfinite(x) for x in raw])
    negative = weighted and meta['weighting'] < 0
    factor = 2.0**(-meta['weighting']) if weighted and not negative else 1.0
    with np.errstate(under='ignore', over='ignore', invalid='ignore'):
        amplitudes = np.array(raw, dtype=float)*factor
    eligible = ~integer_range & ~nonfinite
    lost = eligible & ((amplitudes == 0) & (np.array(raw) != 0) | ~np.isfinite(amplitudes))
    if negative:
        lost[:] = False
    flags = []
    if np.any(nonfinite): flags.append('nonfinite_samples')
    if np.any(integer_range): flags.append('integer_range_samples')
    if negative: flags.append('negative_weighting')
    if np.any(lost): flags.append('weighting_range')
    complete = not flags
    s = stats(amplitudes) if complete else None
    if complete:
        s.update(dead=bool(np.max(np.abs(amplitudes)) <= dead),
                 clipped_samples=int(np.sum(np.abs(amplitudes) >= clip)) if clip else 0,
                 clipping_checked=clip > 0)
        if s['dead']: flags.append('dead_amplitude')
        if s['clipped_samples']: flags.append('clip_threshold')
    if meta['identification'] == 2: flags.append('header_dead')
    result = {k:v for k,v in meta.items() if k not in ('values','integer')}
    result.update(flags=flags, nonfinite_samples=int(np.sum(nonfinite)), first_nonfinite_sample=first(nonfinite),
                  integer_range_samples=int(np.sum(integer_range)), first_integer_range_sample=first(integer_range),
                  weighting_range_samples=int(np.sum(lost)), first_weighting_range_sample=first(lost), statistics=s)
    return result, amplitudes if complete else np.array([])


def summary(items):
    results = [r for r, _ in items]
    values = np.concatenate([v for _,v in items])
    good = [r['statistics'] for r in results if r['statistics'] is not None]
    return {'traces':len(items), 'samples':sum(r['samples'] for r in results),
            'analyzed_traces':len(good), 'analyzed_samples':len(values),
            'problem_traces':sum(bool(r['flags']) for r in results),
            'nonfinite_samples':sum(r['nonfinite_samples'] for r in results),
            'integer_range_samples':sum(r['integer_range_samples'] for r in results),
            'negative_weighting_traces':sum('negative_weighting' in r['flags'] for r in results),
            'weighting_range_samples':sum(r['weighting_range_samples'] for r in results),
            'dead_traces':sum(s['dead'] for s in good), 'header_dead_traces':sum(r['identification']==2 for r in results),
            'clipped_traces':sum(s['clipped_samples']>0 for s in good),
            'clipped_samples':sum(s['clipped_samples'] for s in good),
            'minimum_samples':min(r['samples'] for r in results), 'maximum_samples':max(r['samples'] for r in results),
            'minimum_interval_us':min(r['interval_us'] for r in results), 'maximum_interval_us':max(r['interval_us'] for r in results),
            'statistics':stats(values)}


def expected(metadata, options):
    selected = options.get('traces', list(range(len(metadata))))
    weighted, dead, clip = options.get('weighted',False), options.get('dead_threshold',0.0), options.get('clip_threshold',0.0)
    items = [trace_result(metadata[i],weighted,dead,clip) for i in selected]
    total = summary(items)
    problems = [r for r,_ in items if r['flags']]
    budget = options.get('max_details',256)
    groups = []
    if options.get('group_by'):
        field = options['group_by']
        for value in dict.fromkeys(metadata[i][field] for i in selected):
            members = [(r,v) for r,v in items if r[field]==value]
            groups.append({'value':value,'first_trace':members[0][0]['trace'],'summary':summary(members)})
    return {'status':'issues' if problems else 'clear', 'source_trace_count':len(metadata),
            'weighted':weighted,'dead_threshold':float(dead),'clip_threshold':float(clip),'clipping_checked':clip>0,
            'group_by':options.get('group_by'), 'summary':total,'groups':groups,'details':problems[:budget],
            'max_details':budget,'details_truncated':len(problems)>budget}


def compare(actual, wanted, label='qc'):
    if isinstance(wanted,dict):
        assert isinstance(actual,dict) and actual.keys()==wanted.keys(), (label,actual.keys(),wanted.keys())
        for k in wanted: compare(actual[k],wanted[k],label+'.'+k)
    elif isinstance(wanted,list):
        assert isinstance(actual,list) and len(actual)==len(wanted), label
        for i,(a,b) in enumerate(zip(actual,wanted)): compare(a,b,f'{label}[{i}]')
    elif isinstance(wanted,float):
        assert type(actual) in (float,int) and np.isfinite(actual), (label,actual)
        # Ordinary cancellation to zero has roundoff; nonzero tiny values must
        # still pass relative error instead of being swallowed by absolute atol.
        np.testing.assert_allclose(actual,wanted,rtol=3e-10,atol=1e-12 if wanted==0 or abs(wanted)>1e-250 else 0,err_msg=label)
    else:
        assert type(actual) is type(wanted) and actual==wanted,(label,actual,wanted)


def case(data, metadata, options):
    global cases, checks
    result = ask(data,options)
    compare(result,expected(metadata,options))
    cases += 1
    checks += 1
    return result


def cli(command, source, options, status, scratch, output=None):
    global cli_checks
    config = scratch/'options.json'
    config.write_text(json.dumps(options),encoding='utf-8')
    argv = ['node','tools/segy.mjs',command,str(source),str(config)]
    if output: argv.append(str(output))
    result = subprocess.run(argv,cwd=ROOT,text=True,capture_output=True,timeout=15)
    assert result.returncode==status,(result.returncode,status,result.stderr)
    cli_checks += 1
    return result


started = time.perf_counter()
try:
    for order in ['big','little']:
        for revision in [0,1,2]:
            for code in [2,3,5,6,7,8,9]:
                rows = [{'values':rng.integers(-10,11,size=n).tolist(), 'dt':500+500*(i%3),
                         'fields':{'weighting':i%3,'identification':2 if i==1 else 1}}
                        for i,n in enumerate([5,3,1,9])]
                rows[2]['values'] = [0]
                data, meta = fixture(rows,code,order,revision,'cp037' if revision==1 else 'ascii')
                for options in [{}, {'weighted':True,'clip_threshold':2.0,'dead_threshold':0.5,'group_by':'ensemble'},
                                {'traces':[3,1,0],'max_details':0,'group_by':'field_record','clip_threshold':3.0}]:
                    case(data,meta,options)
    # Raw nonfinite bits, legal wide integers, underflow, unsupported negative
    # weights, all-excluded groups and precise first locations.
    for order in ['big','little']:
        for code, rows in [
            (6,[{'values':[1.0,np.nan,np.inf,-np.inf]},{'values':[1.0,2.0,3.0]},
                {'values':[1.0,0.0],'fields':{'weighting':32767}},
                {'values':[1.0,0.0],'fields':{'weighting':-1}}]),
            (9,[{'values':[2**53+1,-2**63,2**63-1]},{'values':[2**53,-2**53,0]},
                {'values':[2**54]},{'values':[1,2]}]),
            (6,[{'values':[1.7976931348623157e308,-1.7976931348623157e308]},
                {'values':[1e-300,-1e-300]}]),
        ]:
            data,meta = fixture(rows,code,order)
            for weighted in [False,True]:
                case(data,meta,{'weighted':weighted,'group_by':'ensemble','clip_threshold':1.0,'max_details':2})
        data,meta = fixture([{'values':[np.nan,np.inf]},{'values':[np.nan]}],6,order)
        case(data,meta,{'group_by':'ensemble'})

    with tempfile.TemporaryDirectory(prefix='moon-segy-quality-') as temp:
        temp = Path(temp)
        # segyio-generated IEEE/IBM files provide an independent file writer,
        # including IBM32 normalization. Never relabel struct-only cases.
        for order in ['big','little']:
            for code in [1,5,6]:
                source = temp/'segyio.sgy'
                spec = segyio.spec(); spec.samples = list(range(4)); spec.tracecount = 3
                spec.format = code; spec.endian = order
                values = [[1.0,-2.0,0.0,3.0],[0.0]*4,[4.0]*4]
                with segyio.create(str(source),spec) as f:
                    f.text[0] = segyio.tools.create_text_header({1:'INDEPENDENT QC SEGYIO FIXTURE'})
                    f.bin.update({segyio.BinField.Interval:2000,segyio.BinField.Samples:4,segyio.BinField.SEGYRevision:256,segyio.BinField.TraceFlag:1})
                    for i,row in enumerate(values):
                        f.header[i] = {segyio.TraceField.TRACE_SEQUENCE_LINE:101+i,segyio.TraceField.TRACE_SEQUENCE_FILE:i+1,
                                       segyio.TraceField.FieldRecord:1,segyio.TraceField.CDP:i%3+10,segyio.TraceField.TraceIdentificationCode:1,
                                       segyio.TraceField.TRACE_SAMPLE_COUNT:4,segyio.TraceField.TRACE_SAMPLE_INTERVAL:2000}
                        f.trace[i] = np.array(row,dtype=np.float64 if code==6 else np.float32)
                _,meta = fixture([{'values':row} for row in values],code=6 if code==6 else 5,order=order)
                case(source.read_bytes(),meta,{'group_by':'ensemble','clip_threshold':3.0})
        data,meta = fixture([{'values':[1.0,2.0]},{'values':[np.nan,0.0]}, {'values':[0.0,0.0]}])
        source = temp/'qc.sgy'; source.write_bytes(data)
        options = {'group_by':'ensemble','clip_threshold':2.0}
        full = expected(meta,options)
        compare(json.loads(cli('qc',source,options,3,temp).stdout),full)
        csv_rows = list(csv.DictReader(io.StringIO(cli('qc-csv',source,options,3,temp).stdout)))
        assert len(csv_rows)==3
        for row,detail in zip(csv_rows,full['details']):
            for key in ['trace','header_offset','sample_offset','samples','nonfinite_samples','integer_range_samples']:
                assert int(row[key])==detail[key],key
            assert row['flags']==';'.join(detail['flags'])
            assert row['statistics_available']==str(detail['statistics'] is not None).lower()
        checks += 1
        cli('qc',source,{'traces':[0]},0,temp)
        cli('qc-csv',source,{'traces':[0]},0,temp)
        cli('qc',source,{'max_details':0},3,temp)
        report_file = temp/'report.json'
        cli('qc',source,options,3,temp,report_file)
        before = report_file.read_bytes()
        cli('qc',source,options,2,temp,report_file)
        assert before==report_file.read_bytes()
        cli('qc-csv',source,options,2,temp,source)
        for bad in [{'traces':[]},{'traces':[0,0]},{'traces':[3]},{'traces':[.1]},
                    {'max_details':-.1},{'max_details':-1},{'max_details':100001},{'max_details':2147483648},
                    {'max_groups':0},{'max_groups':100001},{'group_by':'ensemble','max_groups':1},
                    {'group_by':'typo'},{'weighted':'true'},{'dead_threshold':-1},{'clip_threshold':None},
                    {'clip_threshhold':2}]:
            ask(data,bad,reject=True)
        for command, opts in [('stats',{'trace':.5}),('trace',{'trace':0,'count':1.1}),
                              ('csv',{'traces':[0.1]}),('find',{'field':'ensemble','minimum':.1,'maximum':2}),
                              ('qc',{'traces':[.1]})]:
            cli(command,source,opts,2,temp)
        invalid = temp/'bad.sgy'; invalid.write_bytes(data[:-1])
        cli('qc',invalid,{},2,temp)
        bad_create = temp/'bad-create.json'
        bad_create.write_text(json.dumps({'interval_us':1000,'traces':[{'samples':[1],'fields':{'ensemble':1.5}}]}))
        p = subprocess.run(['node','tools/segy.mjs','create',str(bad_create),str(temp/'new.sgy')],cwd=ROOT,capture_output=True)
        assert p.returncode==2 and not (temp/'new.sgy').exists()
        cli_checks += 1

    measurements = []
    for trace_count in [100,1000]:
        data,meta = fixture([{'values':([0.0]*256 if i%5==0 else [1.0,-1.0]*128)} for i in range(trace_count)])
        options = {'group_by':'ensemble','clip_threshold':0.75,'max_details':8}
        then = time.perf_counter(); result = ask(data,options); elapsed = time.perf_counter()-then
        compare(result,expected(meta,options)); checks += 1
        measurements.append({'traces':trace_count,'samples_per_trace':256,'details':8,'roundtrip_seconds':elapsed})
    receipt = {'status':'passed','python':platform.python_version(),'numpy':np.__version__,
               'segyio':importlib.metadata.version('segyio'),'matrix_cases':cases,'checks':checks,'cli_checks':cli_checks,
               'seconds':time.perf_counter()-started,'measurements':measurements,
               'scope':'Synthetic raw/weighting-scaled amplitude QC; no physical calibration or geophysical interpretation.'}
    if args.evidence: args.evidence.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt))
finally:
    host.stdin.close()
    try: host.wait(timeout=10)
    except subprocess.TimeoutExpired: host.kill(); host.wait()
