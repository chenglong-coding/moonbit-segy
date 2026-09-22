import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'moon-segy-cli-'));
let checks=0;
function run(args,ok=true) {
  const p=spawnSync(process.execPath,['tools/segy.mjs',...args],{encoding:'utf8',timeout:15000});
  assert.equal(p.status,ok?0:2,p.stderr);checks++;return p;
}
try {
  const input=path.join(scratch,'demo.sgy'),cut=path.join(scratch,'cut.sgy');
  run(['create','examples/create.json',input]);
  const report=JSON.parse(run(['validate',input]).stdout);
  assert.equal(report.trace_count,3);checks++;
  const bytes=fs.readFileSync(input);
  run(['create','examples/create.json',input],false);
  assert.deepEqual(fs.readFileSync(input),bytes);checks++;
  run(['window',input,'examples/window.json',cut]);
  assert.equal(JSON.parse(run(['trace',cut,'examples/trace.json']).stdout).samples.length,5);checks++;
  const stats=JSON.parse(run(['stats',input,'examples/stats.json']).stdout);
  assert.equal(stats.clipped_samples,2);checks++;
  assert.deepEqual(JSON.parse(run(['groups',input,'examples/groups.json']).stdout).map(g=>g.value),[10,20]);checks++;
  const svg=path.join(scratch,'trace.svg');
  run(['svg',input,'examples/trace.json',svg]);
  assert.ok(fs.readFileSync(svg,'utf8').includes('<polyline'));checks++;
  run(['copy',input,'examples/trace.json',input],false);
  const bad=path.join(scratch,'short.sgy');fs.writeFileSync(bad,bytes.subarray(0,3599));
  run(['validate',bad],false);
  console.log(JSON.stringify({status:'passed',checks}));
} finally {fs.rmSync(scratch,{recursive:true,force:true});}
