// npx tsx src/bots/tune.ts 246,500,... [seeds] [skill]
import { H_B } from '../balance';
import { formatTable, runSkill } from './harness';
const hb = process.argv[2].split(',').map(Number);
hb.forEach((v, i) => (H_B[i] = v));
const n = Number(process.argv[3] ?? 4);
const skill = (process.argv[4] ?? 'average') as 'average';
const seeds = Array.from({ length: n }, (_, i) => 1000 + i * 7919);
console.log(hb.join(','));
console.log(formatTable([runSkill(skill, 'normal', seeds)]));
