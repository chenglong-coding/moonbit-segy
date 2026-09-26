"""Check a declared 300-trace USGS excerpt with struct, NumPy and segyio."""
from pathlib import Path
import argparse,base64,csv,datetime,hashlib,importlib.metadata,io,json,struct,subprocess,tempfile
import numpy as np
import segyio
ROOT=Path(__file__).resolve().parents[1]
SHA='bcaafd0f7e6d416a0552ab265cce2330810c3242c6ba265ee21fbdc39349b604'
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--evidence',type=Path,required=True);args=parser.parse_args()
 source=ROOT/'examples/public/usgs-06c01-first300.seg';data=source.read_bytes()
 assert len(data)==975600 and hashlib.sha256(data).hexdigest()==SHA
 samples=np.array([np.frombuffer(data,dtype='>i4',count=750,offset=3840+i*3240) for i in range(300)],dtype=np.int64)
 zero=np.flatnonzero(np.all(samples==0,axis=1)).tolist()
 assert len(zero)==36
 groups=np.array([struct.unpack_from('>i',data,3600+i*3240+12)[0] for i in range(300)])
 with segyio.open(str(source),'r',strict=False,ignore_geometry=True) as ref:
  assert ref.tracecount==300 and int(ref.format)==2 and ref.bin[segyio.BinField.Interval]==40
  # segyio 1.x presents samples as float32. Exact integers are separately checked
  # against struct below; this comparison does not claim float32 is lossless.
  for i in range(300):np.testing.assert_array_equal(ref.trace[i],samples[i].astype(np.float32))
 host=subprocess.Popen(['node','tools/oracle-host.mjs'],cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8')
 cases=0
 def ask(command,raw=data,action='report',reject=False,legacy=True,**options):
  nonlocal cases
  options={'command':command,'legacy_revision_one':legacy,**options}
  host.stdin.write(json.dumps({'data':base64.b64encode(raw).decode(),'action':action,'options':options})+'\n');host.stdin.flush()
  answer=json.loads(host.stdout.readline());cases+=1
  if reject:assert not answer['ok'];return
  assert answer['ok'],answer.get('error')
  return base64.b64decode(answer['result']['bytes']) if action=='transform' else answer['result']
 try:
  ask('inspect',legacy=False,reject=True)
  info=ask('inspect');assert info['revision']==1 and info['raw_revision_word']==1 and info['assumed_legacy_revision_one']
  assert info['trace_count']==300 and info['sample_code']==2
  for i,index in enumerate(info['index']):
   assert index==dict(header_offset=3600+i*3240,sample_offset=3840+i*3240,samples=750,interval_us=40)
  report=ask('qc',group_by='trace_in_record',max_details=100)
  assert report['status']=='issues' and len(report['format_assumptions'])==1
  assert report['summary']['samples']==225000 and report['summary']['dead_traces']==36
  assert [item['trace'] for item in report['details']]==zero
  for item in report['details']:
   assert item['header_offset']==3600+item['trace']*3240 and item['sample_offset']==3840+item['trace']*3240
   assert item['flags']==['dead_amplitude']
  def stats(actual,values):
   v=values.astype(np.float64).reshape(-1)
   expected=[float(v.min()),float(v.max()),float(v.mean()),float(np.sqrt(np.mean(v*v))),float(v.std())]
   np.testing.assert_allclose([actual[k] for k in ['minimum','maximum','mean','rms','standard_deviation']],expected,rtol=5e-12,atol=1e-4)
  stats(report['summary']['statistics'],samples)
  for group in report['groups']:
   selected=samples[groups==group['value']];assert group['summary']['traces']==100;stats(group['summary']['statistics'],selected)
  short=ask('qc',group_by='trace_in_record',max_details=3)
  assert short['summary']==report['summary'] and short['details_truncated'] and len(short['details'])==3
  exported=ask('csv',traces=list(range(300)))['text'];rows=0
  for row in csv.DictReader(io.StringIO(exported)):
   i,j=divmod(rows,750);assert int(row['trace'])==i and int(row['sample'])==j
   assert int(row['raw_amplitude'])==samples[i,j];rows+=1
  assert rows==225000
  assert ask('copy',action='transform')==data
  selected=ask('select',action='transform',traces=[12,42,0])
  assert selected[3500:3502]==b'\0\1'
  for i,original in enumerate([12,42,0]):
   assert selected[3840+i*3240:3840+i*3240+3000]==data[3840+original*3240:3840+original*3240+3000]
  assert ask('qc',raw=selected)['summary']['dead_traces']==2
  with tempfile.TemporaryDirectory(prefix='segy-usgs-') as td:
   path=Path(td)/'selection.seg';path.write_bytes(selected)
   with segyio.open(str(path),'r',strict=False,ignore_geometry=True) as ref:
    assert ref.tracecount==3
    for i,j in enumerate([12,42,0]):np.testing.assert_array_equal(ref.trace[i],samples[j].astype(np.float32))
  ask('qc',raw=data[:-1],reject=True)
  changed=bytearray(data);changed[3501]=2;ask('qc',raw=bytes(changed),reject=True)
 finally:
  host.stdin.close();assert host.wait(timeout=10)==0
 receipt=dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),inputSha256=SHA,inputBytes=len(data),sourceByteRangeHalfOpen=[0,len(data)],
  source='https://pubs.usgs.gov/ds/259/segy/06c01.seg',scope='Declared complete-trace excerpt from an earlier cached partial download, not entire 06c01; fresh retrieval returned HTTP403',
  reference='segyio '+importlib.metadata.version('segyio')+' plus independent struct/NumPy',exactIntegerOracle='Python struct/NumPy >i4, not segyio float32',
  traces=300,integerSamplesCompared=225000,zeroAmplitudeTraces=zero,groupCounts={str(int(g)):int(np.sum(groups==g)) for g in np.unique(groups)},checks=cases,
  formatAssumption='Explicit legacy big-endian revision word 0x0001; default strict reject; bytes retained',
  limitations=['QC thresholds do not diagnose instrument failures or geology','No physical amplitude calibration or CRS inference','No claim of user adoption or complete survey validation'])
 args.evidence.parent.mkdir(parents=True,exist_ok=True);args.evidence.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8');print(json.dumps(receipt))
if __name__=='__main__':main()
