#!/usr/bin/env node
import fs from 'node:fs';
import {report,transform,new_file} from '../_build/js/release/build/cmd/bridge/bridge.js';
const usage=`Usage: node tools/segy.mjs COMMAND INPUT [OPTIONS.json] [OUTPUT]
       node tools/segy.mjs create OPTIONS.json OUTPUT
Reports: inspect validate trace stats groups find coordinate csv svg
Writes: copy select filter window convert (OUTPUT required)
Reports print JSON or exported text unless OUTPUT is supplied.
OPTIONS is a JSON file, not inline JSON. Existing outputs are never overwritten.`;
function read(file,limit) {
  const fd=fs.openSync(file,'r');
  try {
    const stat=fs.fstatSync(fd);
    if (!stat.isFile() || stat.size>limit) throw new Error(`input must be a file <=${limit} bytes`);
    const buffer=Buffer.alloc(stat.size+1);
    let size=0,got;
    while(size<buffer.length && (got=fs.readSync(fd,buffer,size,buffer.length-size,null))) size+=got;
    if(size>stat.size) throw new Error('file grew during read; retry a stable file');
    return buffer.subarray(0,size);
  } finally {fs.closeSync(fd);}
}
function options(file) {
  const o=file?JSON.parse(read(file,8_000_000).toString('utf8')):{};
  if(!o || typeof o!=='object' || Array.isArray(o)) throw new Error('options must be an object');
  return o;
}
function save(file,data) {fs.writeFileSync(file,data,{flag:'wx'});}
try {
  const args=process.argv.slice(2);
  if(args.length===1 && ['--help','-h'].includes(args[0])) console.log(usage);
  else if(args[0]==='create') {
    if(args.length!==3) throw new Error(usage);
    save(args[2],Buffer.from(new_file(JSON.stringify(options(args[1])))));
  } else {
    if(args.length<2 || args.length>4) throw new Error(usage);
    const [command,input,opts,output]=args;
    const o=options(opts); o.command=command;
    const data=read(input,268_435_456);
    if(['copy','select','filter','window','convert'].includes(command)) {
      if(!output) throw new Error('binary transformation requires OUTPUT');
      save(output,Buffer.from(transform(data,JSON.stringify(o))));
    } else {
      const result=JSON.parse(report(data,JSON.stringify(o)));
      const text=['csv','svg'].includes(command)?result.text:JSON.stringify(result,null,2)+'\n';
      if(output) save(output,text); else process.stdout.write(text);
    }
  }
} catch(error) {console.error(`segy: ${error.message}`);process.exitCode=2;}
