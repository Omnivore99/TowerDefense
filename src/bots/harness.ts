// Balance harness: runs full 7-board runs with bots and reports per-board metrics.
import { BOARDS, type ModeId } from '../balance';
import { Game } from '../sim/game';
import { Bot, type Skill } from './bots';

export interface BoardRow { board: number; clear: number; hpLost: number; danger: number; runs: number }
export interface HarnessResult { skill: Skill; mode: ModeId; rows: BoardRow[]; seconds: number }

const MAX_STEPS_PER_BOARD = 60 * 60 * 40;

export function runSkill(skill: Skill, mode: ModeId, seeds: number[], onProgress?: (msg: string) => void): HarnessResult {
  const t0 = Date.now();
  const acc = Array.from({ length: BOARDS }, (_, i) => ({ board: i + 1, clears: 0, hp: 0, dangerT: 0, waveT: 0, runs: 0 }));
  for (const seed of seeds) {
    const g = new Game(seed, mode, { tutorial: false });
    const bot = new Bot(g, skill, seed ^ 0xb07);
    let steps = 0;
    let board = 1;
    for (;;) {
      bot.act();
      g.step();
      g.events.length = 0;
      steps++;
      if (g.phase === 'lost' || g.phase === 'victory' || g.phase === 'cleared' || steps > MAX_STEPS_PER_BOARD) {
        const m = g.allMetrics[g.allMetrics.length - 1];
        if (m && m.attempt === 1 && m.board === board) {
          const a = acc[board - 1];
          a.runs++;
          a.clears += m.cleared ? 1 : 0;
          a.hp += m.baseLost;
          a.dangerT += m.dangerTime;
          a.waveT += m.waveTime;
        }
        if (g.phase === 'victory' || steps > MAX_STEPS_PER_BOARD) break;
        if (g.phase === 'lost') {
          if (g.attempt >= 3) {
            // give up on this board but keep the run going so later boards get data
            if (g.boardNo >= BOARDS) break;
            g.phase = 'cleared';
          } else { g.retryBoard(); steps = 0; continue; }
        }
        bot.act(); // enterBase
        bot.act(); // shop + next board
        board = g.boardNo;
        steps = 0;
        onProgress?.(`${skill} seed ${seed}: board ${board}`);
      }
    }
  }
  return {
    skill, mode, seconds: (Date.now() - t0) / 1000,
    rows: acc.map((a) => ({ board: a.board, runs: a.runs, clear: a.runs ? a.clears / a.runs : 0, hpLost: a.runs ? a.hp / a.runs : 0, danger: a.waveT ? a.dangerT / a.waveT : 0 })),
  };
}

export function formatTable(results: HarnessResult[]): string {
  const pct = (v: number) => `${Math.round(v * 100)}%`.padStart(5);
  const lines: string[] = [];
  for (const r of results) {
    lines.push(`\n${r.skill.toUpperCase()} on ${r.mode} (${r.seconds.toFixed(1)} s)`);
    lines.push('board | runs | clear | base HP lost | danger');
    for (const row of r.rows) lines.push(`  ${row.board}   |  ${String(row.runs).padStart(2)}  | ${pct(row.clear)} |    ${pct(row.hpLost)}     | ${pct(row.danger)}`);
  }
  return lines.join('\n');
}
