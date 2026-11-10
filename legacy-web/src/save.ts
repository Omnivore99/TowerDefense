// localStorage persistence. Every call is wrapped: storage may be missing or blocked.
import type { ModeId, TowerType } from './balance';
import type { BoardMetrics, RunSnapshot, Settings } from './sim/game';

const RUN_KEY = 'satisfying-td:run:v2';
const SETTINGS_KEY = 'satisfying-td:settings:v1';
const METRICS_KEY = 'satisfying-td:metrics:v1';
const META_KEY = 'satisfying-td:meta:v1';

export interface RunSave { v: 2; seed: number; mode: ModeId; board: number; snapshot: RunSnapshot; discovered: TowerType[]; elements: string[]; savedAt: number }
export interface Meta { tutorialDone: boolean; discovered: TowerType[]; elements?: string[] }

function read<T>(k: string): T | null {
  try {
    const s = localStorage.getItem(k);
    return s ? (JSON.parse(s) as T) : null;
  } catch {
    return null;
  }
}
function write(k: string, v: unknown) {
  try {
    localStorage.setItem(k, JSON.stringify(v));
  } catch {
    /* storage unavailable: the game still runs */
  }
}

export const loadRun = () => { const r = read<RunSave>(RUN_KEY); return r && r.v === 2 && r.snapshot ? r : null; };
export const saveRun = (r: RunSave) => write(RUN_KEY, r);
export const clearRun = () => {
  try { localStorage.removeItem(RUN_KEY); } catch { /* ignore */ }
};

export const defaultSettings = (): Settings => ({
  volume: 0.7,
  reducedMotion: typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches,
  showRanges: false,
  speed: 1,
});
export const loadSettings = (): Settings => ({ ...defaultSettings(), ...(read<Partial<Settings>>(SETTINGS_KEY) ?? {}) });
export const saveSettings = (s: Settings) => write(SETTINGS_KEY, s);

export const loadMeta = (): Meta => ({ tutorialDone: false, discovered: [], ...(read<Partial<Meta>>(META_KEY) ?? {}) });
export const saveMeta = (m: Meta) => write(META_KEY, m);

export function logMetrics(m: BoardMetrics & { seed: number; mode: ModeId }) {
  const all = read<unknown[]>(METRICS_KEY) ?? [];
  all.push({ ...m, at: new Date().toISOString() });
  write(METRICS_KEY, all.slice(-500));
}
export const loadMetrics = () => read<unknown[]>(METRICS_KEY) ?? [];
