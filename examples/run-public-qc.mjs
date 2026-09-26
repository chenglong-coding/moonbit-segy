import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {report} from '../_build/js/release/build/cmd/bridge/bridge.js';
const [output,...extra]=process.argv.slice(2);
if(!output||extra.length)throw Error('Usage: node examples/run-public-qc.mjs NEW_OUTPUT_DIRECTORY');
const source=new URL('./public/usgs-06c01-first300.seg',import.meta.url),fd=fs.openSync(source,'r'),size=975600,buffer=Buffer.alloc(size+1);
let length=0;
try{
 if(!fs.fstatSync(fd).isFile())throw Error('Expected a regular source excerpt');
 while(length<buffer.length){const n=fs.readSync(fd,buffer,length,buffer.length-length,null);if(!n)break;length+=n;}
}finally{fs.closeSync(fd);}
if(length!==size)throw Error('Changed or incomplete source excerpt');
const data=buffer.subarray(0,length),hash=createHash('sha256').update(data).digest('hex');
if(hash!=='bcaafd0f7e6d416a0552ab265cce2330810c3242c6ba265ee21fbdc39349b604')throw Error('Unexpected source excerpt hash');
const options=JSON.parse(fs.readFileSync(new URL('./public/quality.json',import.meta.url),'utf8'));
const qc=JSON.parse(report(data,JSON.stringify({command:'qc',...options})));
const csv=JSON.parse(report(data,JSON.stringify({command:'qc-csv',...options}))).text;
if(qc.summary.traces!==300||qc.summary.dead_traces!==36||qc.format_assumptions.length!==1)throw Error('Unexpected public QC result');
fs.mkdirSync(output);
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(qc,null,2)+'\n',{flag:'wx'});
fs.writeFileSync(path.join(output,'issues.csv'),csv,{flag:'wx'});
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify({source:'https://pubs.usgs.gov/ds/259/segy/06c01.seg',attribution:'U.S. Geological Survey, Data Series 259',sourceByteRangeHalfOpen:[0,size],inputSha256:hash,options,
 formatAssumptions:qc.format_assumptions,csvSha256:createHash('sha256').update(csv).digest('hex'),scope:'First 300 traces only; 36 zero-amplitude traces under the stated threshold; no inference of fault cause, calibrated amplitude or CRS'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:path.resolve(output),traces:qc.summary.traces,zeroAmplitudeTraces:qc.summary.dead_traces,completeSurvey:false}));
