// Procedural Web Audio: every pitch comes from one pentatonic scale so overlapping sounds never clash.
import type { GameEvent, Phase } from '../sim/game';

const BASE = 130.81; // C3
const PENTA = [0, 2, 4, 7, 9]; // C D E G A
export function penta(step: number, octave = 0): number {
  const o = Math.floor(step / 5) + octave;
  const s = ((step % 5) + 5) % 5;
  return BASE * Math.pow(2, o + PENTA[s] / 12);
}
const PAD_CHORDS = [
  [0, 2, 3, 6], // C E G D'
  [-1, 2, 3, 5], // A, E G C'
  [1, 4, 5, 7], // D A C' E'
  [-2, 1, 4, 7], // G, D A E'
];

export class AudioEngine {
  ctx: AudioContext | null = null;
  master!: GainNode;
  sfx!: GainNode;
  music!: GainNode;
  private padGain!: GainNode;
  private drumGain!: GainNode;
  private noiseBuf!: AudioBuffer;
  private volume = 0.7;
  private lastShot = new Map<string, number>();
  private nextBeat = 0;
  private beat = 0;
  private chordIdx = 0;
  private wave = false;
  private padNodes: { osc: OscillatorNode[]; g: GainNode } | null = null;

  start() {
    if (this.ctx) { void this.ctx.resume(); return; }
    try {
      const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      this.ctx = new AC();
    } catch { return; }
    const c = this.ctx;
    this.master = c.createGain();
    this.master.gain.value = this.volume;
    const comp = c.createDynamicsCompressor();
    comp.threshold.value = -16;
    comp.ratio.value = 4;
    this.master.connect(comp).connect(c.destination);
    this.sfx = c.createGain(); this.sfx.gain.value = 0.55; this.sfx.connect(this.master);
    this.music = c.createGain(); this.music.gain.value = 0.32; this.music.connect(this.master);
    this.padGain = c.createGain(); this.padGain.gain.value = 0.5; this.padGain.connect(this.music);
    this.drumGain = c.createGain(); this.drumGain.gain.value = 0; this.drumGain.connect(this.music);
    this.noiseBuf = c.createBuffer(1, c.sampleRate, c.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    this.nextBeat = c.currentTime + 0.1;
  }

  setVolume(v: number) {
    this.volume = v;
    if (this.ctx) this.master.gain.setTargetAtTime(v, this.ctx.currentTime, 0.05);
  }

  // ------------------------------------------------------------ primitives
  private tone(freq: number, dur: number, type: OscillatorType, vol: number, when = 0, out?: AudioNode, glide?: number) {
    const c = this.ctx;
    if (!c) return;
    const t = c.currentTime + when;
    const o = c.createOscillator();
    const g = c.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (glide) o.frequency.exponentialRampToValueAtTime(glide, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(out ?? this.sfx);
    o.start(t);
    o.stop(t + dur + 0.05);
  }
  private noise(dur: number, vol: number, freq: number, q = 1, when = 0, type: BiquadFilterType = 'lowpass', out?: AudioNode) {
    const c = this.ctx;
    if (!c) return;
    const t = c.currentTime + when;
    const s = c.createBufferSource();
    s.buffer = this.noiseBuf;
    const f = c.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    const g = c.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f).connect(g).connect(out ?? this.sfx);
    s.start(t, Math.random() * 0.5);
    s.stop(t + dur + 0.05);
  }
  private limited(key: string, gap: number): boolean {
    const now = this.ctx?.currentTime ?? 0;
    if (now - (this.lastShot.get(key) ?? -1) < gap) return false;
    this.lastShot.set(key, now);
    return true;
  }

  // ------------------------------------------------------------ sounds
  click(step: number) { this.tone(penta(step, 2), 0.12, 'triangle', 0.25); this.tone(penta(step, 3), 0.06, 'sine', 0.08); }
  thud(size: number) {
    this.tone(90 - size * 8, 0.22, 'sine', 0.5, 0, undefined, 40);
    this.noise(0.12, 0.25, 600 - size * 60, 0.8);
  }
  chord() { [0, 2, 4].forEach((s, i) => this.tone(penta(s + 5, 1), 0.9, 'triangle', 0.16, i * 0.03)); this.tone(penta(10, 1), 1.2, 'sine', 0.1, 0.12); }
  bonus() { [0, 1, 2, 3, 4, 5].forEach((s, i) => this.tone(penta(s + 7, 1), 0.3, 'sine', 0.12, i * 0.05)); }
  arpeggio(n: number) {
    const len = Math.min(8, 3 + Math.floor(Math.log2(n)));
    for (let i = 0; i < len; i++) this.tone(penta(i + 5 + Math.min(5, Math.floor(n / 5)), 1), 0.25, 'square', 0.05, i * 0.06);
  }
  kill(size: string, combo: number) {
    if (!this.limited('kill', 0.03)) return;
    const step = 5 + (combo % 10);
    this.tone(penta(step, size === 'small' ? 2 : 1), 0.14, 'sine', 0.18);
    this.noise(0.08, 0.12, 2400, 1, 0, 'bandpass');
  }
  shot(kind: string) {
    const gaps: Record<string, number> = { bullet: 0.07, hitscan: 0.1, lob: 0.15, homing: 0.15, pierce: 0.1, cone: 0.15, virus: 0.2, puddle: 0.2, ricochet: 0.1, tank: 0.2 };
    if (!this.limited(kind, gaps[kind] ?? 0.1)) return;
    const r = Math.floor(Math.random() * 5);
    switch (kind) {
      case 'bullet': this.tone(penta(r + 10, 1), 0.05, 'square', 0.04); break;
      case 'hitscan': this.noise(0.12, 0.2, 3000, 2, 0, 'highpass'); this.tone(penta(r + 5, 1), 0.1, 'sawtooth', 0.05); break;
      case 'lob': case 'puddle': this.tone(penta(r, 1), 0.18, 'sine', 0.12, 0, undefined, penta(r, 0)); break;
      case 'homing': this.noise(0.25, 0.08, 900, 1); break;
      case 'pierce': this.tone(penta(r + 8, 1), 0.2, 'sawtooth', 0.05, 0, undefined, penta(r + 3, 1)); break;
      case 'cone': this.noise(0.18, 0.06, 1200, 0.5); break;
      case 'virus': this.tone(penta(r + 6, 1), 0.2, 'triangle', 0.05, 0, undefined, penta(r + 8, 1)); break;
      default: this.tone(penta(r + 7, 1), 0.06, 'triangle', 0.05);
    }
  }
  zap() { if (this.limited('zap', 0.12)) { this.noise(0.1, 0.12, 4000, 3, 0, 'bandpass'); } }
  boom(big = false) { if (!this.limited('boom', 0.06)) return; this.tone(big ? 70 : 110, 0.3, 'sine', 0.35, 0, undefined, 35); this.noise(big ? 0.5 : 0.25, 0.3, big ? 500 : 900); }
  leak() { this.tone(penta(-5, 0), 0.5, 'sawtooth', 0.12, 0, undefined, penta(-10, 0)); this.noise(0.3, 0.2, 300); }
  reject() { this.tone(penta(0, 0), 0.08, 'square', 0.06); this.tone(penta(-1, 0), 0.1, 'square', 0.06, 0.07); }
  seal() { this.tone(penta(2, 1), 0.2, 'triangle', 0.15); this.noise(0.15, 0.1, 1500, 1); }
  ui() { this.tone(penta(7, 2), 0.05, 'sine', 0.08); }
  coin() { this.tone(penta(9, 2), 0.08, 'triangle', 0.1); this.tone(penta(11, 2), 0.12, 'triangle', 0.1, 0.06); }
  fanfare() { [0, 2, 4, 5, 7, 9].forEach((s, i) => this.tone(penta(s + 5, 1), 0.5, 'triangle', 0.14, i * 0.09)); }
  build() { [0, 2, 4].forEach((s, i) => this.tone(penta(s + 3, 1), 1.2, 'sine', 0.14, i * 0.02)); }
  revealCrackle() { if (this.limited('crackle', 0.05)) this.noise(0.05, 0.05, 5000, 4, 0, 'bandpass'); }

  // ------------------------------------------------------------ music
  setPhase(p: Phase) {
    this.wave = p === 'wave';
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.drumGain.gain.setTargetAtTime(this.wave ? 0.9 : 0, t, 0.8);
    this.padGain.gain.setTargetAtTime(this.wave ? 0.35 : 0.6, t, 1.2);
  }

  /** Call every frame: schedules the pad and percussion a little ahead. */
  tick() {
    const c = this.ctx;
    if (!c) return;
    const spb = 60 / 96 / 2; // eighth notes at 96 BPM
    while (this.nextBeat < c.currentTime + 0.15) {
      const t = this.nextBeat - c.currentTime;
      if (this.beat % 32 === 0) this.padChord(t);
      if (this.wave) {
        if (this.beat % 4 === 0) this.kick(t);
        if (this.beat % 2 === 1) this.noise(0.04, 0.06, 7000, 1, t, 'highpass', this.drumGain);
        if (this.beat % 8 === 4) this.noise(0.12, 0.12, 1800, 1, t, 'bandpass', this.drumGain);
        if (this.beat % 2 === 0) {
          const ch = PAD_CHORDS[this.chordIdx];
          this.tone(penta(ch[(this.beat / 2) % 4], 0), 0.2, 'triangle', 0.05, t, this.drumGain);
        }
      } else if (this.beat % 6 === 0 && Math.random() < 0.5) {
        const ch = PAD_CHORDS[this.chordIdx];
        this.tone(penta(ch[Math.floor(Math.random() * 4)] + 5, 1), 1.6, 'sine', 0.03, t, this.padGain);
      }
      this.nextBeat += spb;
      this.beat++;
    }
  }

  private kick(when: number) {
    this.tone(120, 0.18, 'sine', 0.5, when, this.drumGain, 45);
  }

  private padChord(when: number) {
    const c = this.ctx!;
    this.chordIdx = (this.chordIdx + 1) % PAD_CHORDS.length;
    const t = c.currentTime + when;
    if (this.padNodes) {
      const old = this.padNodes;
      old.g.gain.setTargetAtTime(0.0001, t, 1.0);
      old.osc.forEach((o) => o.stop(t + 4));
    }
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.setTargetAtTime(0.06, t, 1.2);
    const f = c.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 900;
    g.connect(f).connect(this.padGain);
    const osc = PAD_CHORDS[this.chordIdx].map((s, i) => {
      const o = c.createOscillator();
      o.type = i % 2 ? 'triangle' : 'sawtooth';
      o.frequency.value = penta(s, 0);
      o.detune.value = (i - 1.5) * 6;
      o.connect(g);
      o.start(t);
      return o;
    });
    this.padNodes = { osc, g };
  }

  // ------------------------------------------------------------ game events
  handle(events: GameEvent[], pieceCountOf: (towerId: number) => number) {
    if (!this.ctx) return;
    for (const e of events) {
      switch (e.t) {
        case 'place':
          this.click(e.towerId ? pieceCountOf(e.towerId) : 0);
          setTimeout(() => this.thud(e.size), 236);
          break;
        case 'activate': setTimeout(() => this.chord(), 300); break;
        case 'bonus': setTimeout(() => this.bonus(), 450); break;
        case 'shot': this.shot(e.kind); break;
        case 'bolt': this.zap(); break;
        case 'explode': this.boom(e.r > 2); break;
        case 'mine': this.boom(true); break;
        case 'kill': this.kill(e.size, 0); break;
        case 'combo': this.arpeggio(e.n); break;
        case 'leak': this.leak(); break;
        case 'reject': case 'sealReject': this.reject(); break;
        case 'seal': this.seal(); break;
        case 'phase': this.setPhase(e.phase); if (e.phase === 'cleared' || e.phase === 'victory') this.fanfare(); break;
        case 'early': case 'recycle': case 'ore': this.coin(); break;
        case 'build': this.build(); break;
        case 'smite': this.boom(true); break;
        case 'piece': if (e.zone === 'must') this.ui(); break;
      }
    }
  }
}
