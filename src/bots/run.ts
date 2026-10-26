// npm run bots [-- --seeds 10 --mode normal --skill average]
import { type ModeId } from '../balance';
import { type Skill } from './bots';
import { formatTable, runSkill } from './harness';

const args = process.argv.slice(2);
const arg = (k: string, d: string) => {
  const i = args.indexOf(`--${k}`);
  return i >= 0 ? args[i + 1] : d;
};
const n = Number(arg('seeds', '6'));
const mode = arg('mode', 'normal') as ModeId;
const skills = (arg('skill', 'novice,average,expert').split(',')) as Skill[];
const seeds = Array.from({ length: n }, (_, i) => 1000 + i * 7919);
const results = skills.map((s) => runSkill(s, mode, seeds, (m) => process.stderr.write(`\r${m}        `)));
process.stderr.write('\n');
console.log(formatTable(results));
if (args.includes('--json')) console.log(JSON.stringify(results));
