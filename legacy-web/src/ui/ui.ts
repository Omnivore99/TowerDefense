// DOM HUD, menus, base screen and all input handling.
import {
  BASE_INTEGRITY, BASE_SQUARES, BUILDINGS, BUILDING_FX, EARLY_CALL_BONUS, EARLY_CALL_WINDOW, GROUPS, HARMONY,
  MODES, SIZES, TOWERS, TOWER_TYPES, UNDO_SECONDS, type BuildingId, type Group, type ModeId, type TowerType,
} from '../balance';
import type { AudioEngine } from '../audio/audio';
import { PIECE_CSS, hexCss, suitColor } from '../render/palette';
import type { Renderer } from '../render/renderer';
import { buildingMult, canBuild, goldenBase, hasBuilding, isHarmony } from '../sim/base';
import type { Game, GameEvent, Settings, Source } from '../sim/game';
import { cellIdx, inGrid } from '../sim/map';
import { BASE_DEFS, buildingArt } from './baseArt';
import { FAMILIES, GLYPH_LABEL, type Family, type Orient } from '../sim/pieces';
import { allRecipes } from '../sim/towers';
import { SUIT_SYMBOL, type Suit } from '../sim/waves';
import { drawPieceIcon } from './pieceIcon';
import { loadMetrics } from '../save';

export interface Shell {
  newRun(mode: ModeId, seed?: number): void;
  quitToTitle(): void;
  saveNow(): void;
  settingsChanged(): void;
}

const $ = <T extends HTMLElement = HTMLElement>(root: ParentNode, sel: string) => root.querySelector(sel) as T;
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);
const SUIT_CSS = (s: Suit) => hexCss(suitColor(s, 'medium'));
const FAMILY_KIND: Record<Family, string> = { Hook: 'J / L', Block: 'O', Bar: 'I', Tee: 'T', Skew: 'S / Z' };

export class UI {
  game: Game;
  root: HTMLElement;
  selected: Source | null = null;
  orient: Orient = { rot: 0, mirror: false };
  smiteMode = false;
  modal: string | null = null;
  paused = false;
  private pointer = { sx: 0, sy: 0, over: false, cx: -1, cy: -1, fx: 0, fy: 0 };
  private press: { kind: 'slot' | 'canvas'; x: number; y: number; id: number; moved: boolean; button: number; pan: boolean; lx: number; ly: number } | null = null;
  private toasts: { el: HTMLElement; t: number }[] = [];
  private touches = new Set<number>();
  private sigs: Record<string, string> = {};
  private bannerT = 0;
  private tipMsg: { text: string; t: number } | null = null;
  private baseSel: { building: BuildingId | null } = { building: null };

  constructor(
    root: HTMLElement,
    game: Game,
    private renderer: Renderer,
    private audio: AudioEngine,
    public settings: Settings,
    private shell: Shell,
  ) {
    this.root = root;
    this.game = game;
    this.build();
    this.bindInput();
  }

  setGame(g: Game) {
    this.game = g;
    this.selected = null;
    this.sigs = {};
    this.closeModal();
  }

  // ================================================================ DOM skeleton
  private build() {
    this.root.innerHTML = `
      <div id="top" class="panel">
        <div class="board-label"><b id="boardLabel"></b><span id="phaseLabel"></span></div>
        <div class="integrity" id="integrity" title="Base integrity"></div>
        <div class="res"><span class="ess" title="Essence: build at the base">◆ <b id="essence">0</b></span><span class="ore" title="Ore: converts to Essence at the base">⬢ <b id="ore">0</b></span></div>
        <div class="next" id="nextWave"></div>
        <div class="spacer"></div>
        <button id="btnSpeed" title="Game speed">1×</button>
        <button id="btnBook" title="Recipe book (B)">Recipes</button>
        <button id="btnElem" title="Bestiary: the periodic table of monsters (E)">Bestiary</button>
        <button id="btnPause" title="Pause (P)">❚❚</button>
      </div>
      <div id="left" class="panel">
        <div class="qhead must">MUST USE <span id="mustCount"></span></div>
        <div class="slots" id="must"></div>
        <div class="more" id="mustMore"></div>
        <div class="qhead">MAY USE <span id="mayLock" class="lock">locked</span></div>
        <div class="slots" id="may"></div>
        <div class="qhead">HOLD <span class="key">H</span></div>
        <div class="slots" id="hold"></div>
        <div id="extras"></div>
        <div class="keys">R / right-click rotate · F mirror<br>Wheel zoom · drag to pan<br>Esc undo (${UNDO_SECONDS}s) / cancel</div>
      </div>
      <div id="card" class="panel hidden"></div>
      <div id="tooltip" class="hidden"></div>
      <div id="readyWrap" class="hidden"><button id="btnReady"><span id="readyText">Ready ▶</span><span id="readyBonus"></span></button></div>
      <div id="bossBar" class="hidden"><div class="bb-name" id="bbName"></div><div class="bb-track"><div class="bb-fill" id="bbFill"></div><div class="bb-shield" id="bbShield"></div></div></div>
      <div id="toasts"></div>
      <div id="tutorial" class="panel hidden"></div>
      <div id="banner"></div>
      <div id="modal" class="hidden"><div class="modal-box" id="modalBox"></div></div>`;
    $(this.root, '#btnPause').onclick = () => this.openPause();
    $(this.root, '#btnBook').onclick = () => this.openBook();
    $(this.root, '#btnElem').onclick = () => this.openBestiary();
    $(this.root, '#btnSpeed').onclick = () => {
      this.settings.speed = this.settings.speed === 1 ? 2 : this.settings.speed === 2 ? 3 : 1;
      this.shell.settingsChanged();
    };
    $(this.root, '#btnReady').onclick = () => this.game.ready();
  }

  // ================================================================ per-frame update
  update(dt: number) {
    const g = this.game;
    this.setText('#boardLabel', `Board ${g.boardNo}`);
    const phaseTxt = g.phase === 'wave' ? ` · Wave ${g.waveIndex} of ${g.wavesInBoard}` : g.phase === 'calm' ? (g.waveIndex === 0 ? ' · Build' : ` · Calm · ${g.waveIndex}/${g.wavesInBoard} waves`) : g.phase === 'reveal' ? ' · Lightning strikes a new road' : '';
    this.setText('#phaseLabel', phaseTxt);
    this.setText('#essence', String(Math.floor(g.base.essence)));
    this.setText('#ore', String(Math.floor(g.base.ore)));
    this.setText('#btnSpeed', `${this.settings.speed}×`);
    this.updateIntegrity();
    this.updateNextWave();
    this.updateQueues();
    this.updateExtras();
    this.updateReady();
    this.updateBossBar();
    this.updateToasts(dt);
    const ul = g.undoLeft();
    this.renderer.undoMark = ul > 0 && g.lastPlace ? { cells: g.lastPlace.cells, frac: ul / UNDO_SECONDS } : null;
    this.updateTutorial();
    this.updateCard();
    this.updateTooltip(dt);
    if (this.bannerT > 0) {
      this.bannerT -= dt;
      if (this.bannerT <= 0) $(this.root, '#banner').classList.remove('show');
    }
    // keep the selection valid
    if (this.selected && !g.getPiece(this.selected)) {
      this.selected = g.must.length && g.canPlacePieces() ? { zone: 'must', index: 0 } : null;
      this.refreshGhost();
    }
  }

  private setText(sel: string, s: string) {
    const el = $(this.root, sel);
    if (el && el.textContent !== s) el.textContent = s;
  }
  private sig(key: string, v: string): boolean {
    if (this.sigs[key] === v) return false;
    this.sigs[key] = v;
    return true;
  }

  private updateIntegrity() {
    const g = this.game;
    if (!this.sig('int', `${g.integrity}|${g.buffer}`)) return;
    let h = '';
    for (let i = 0; i < BASE_INTEGRITY; i++) h += `<i class="${i < g.integrity ? 'on' : ''}"></i>`;
    for (let i = 0; i < g.buffer; i++) h += `<i class="buf"></i>`;
    $(this.root, '#integrity').innerHTML = h;
  }

  private updateNextWave() {
    const g = this.game;
    const w = g.phase === 'wave' ? g.wave : g.nextWavePreview();
    const key = w ? `${w.board}-${w.index}-${g.phase}` : 'none';
    if (!this.sig('next', key)) return;
    const el = $(this.root, '#nextWave');
    if (!w) { el.innerHTML = ''; return; }
    const c = { mite: 0, small: 0, medium: 0, large: 0, giant: 0, champion: 0, boss: 0 } as Record<string, number>;
    let balloons = 0;
    const groups = new Map<Group, string>();
    for (const e of w.enemies) { c[e.size]++; if (e.arch === 'balloon') balloons++; if (e.group !== 'nonmetal') groups.set(e.group, e.element); }
    const parts: string[] = [];
    if (c.mite) parts.push(`${c.mite} swarm`);
    parts.push(`${c.small} S`, `${c.medium} M`, `${c.large} L`);
    if (c.giant) parts.push(`${c.giant} Giant`);
    if (c.champion) parts.push('<b class="champ">SUB-BOSS</b>');
    if (c.boss) parts.push('<b class="champ">BOSS</b>');
    if (balloons) parts.push(`${balloons} Balloon`);
    const chips = [...groups].map(([gr, el]) => `<span class="elchip" style="--c:${hexCss(GROUPS[gr].color)}" title="${esc(GROUPS[gr].name)}: ${esc(GROUPS[gr].ability)}">${esc(el)}</span>`).join('');
    el.innerHTML = `<span class="lbl">${g.phase === 'wave' ? 'Now' : 'Next'}</span> ${parts.join(' · ')} ${chips} <span class="suit" style="color:${SUIT_CSS(w.dominant)}" title="Dominant suit: ${w.dominant}. Weak to ${weakTo(w.dominant)}">${SUIT_SYMBOL[w.dominant]}</span>`;
  }

  private updateQueues() {
    const g = this.game;
    const sel = this.selected ? `${this.selected.zone}${this.selected.index}` : '';
    const locked = g.mayLocked;
    const must = g.must.slice(0, 3);
    const key = `${must.map((p) => p.id).join(',')}|${g.must.length}|${g.may.map((p) => p?.id ?? 0).join(',')}|${g.hold?.id ?? 0}|${sel}|${locked}|${g.holdLocked}`;
    if (!this.sig('queues', key)) return;
    const mk = (container: string, zone: Source['zone'], pieces: (import('../sim/pieces').Piece | null)[], n: number, lock: boolean) => {
      const el = $(this.root, container);
      if (el.children.length !== n) {
        el.innerHTML = '';
        for (let i = 0; i < n; i++) {
          const d = document.createElement('div');
          d.className = 'slot';
          d.dataset.zone = zone;
          d.dataset.index = String(i);
          d.innerHTML = '<canvas></canvas>';
          d.addEventListener('pointerdown', (e) => this.slotDown(e, zone, i));
          el.appendChild(d);
        }
      }
      [...el.children].forEach((child, i) => {
        const d = child as HTMLElement;
        const p = pieces[i] ?? null;
        d.classList.toggle('empty', !p);
        d.classList.toggle('locked', lock && !!p);
        d.classList.toggle('sel', sel === `${zone}${i}`);
        d.title = p ? pieceTitle(p) : '';
        drawPieceIcon(d.querySelector('canvas')!, p, lock);
      });
    };
    mk('#must', 'must', must, 3, false);
    mk('#may', 'may', g.may, g.may.length, locked);
    mk('#hold', 'hold', [g.hold], 1, locked);
    this.setText('#mustCount', g.must.length ? `${g.must.length}` : '');
    $(this.root, '#mustMore').textContent = g.must.length > 3 ? `+${g.must.length - 3} more waiting` : '';
    $(this.root, '#mayLock').style.visibility = locked ? 'visible' : 'hidden';
    $(this.root, '#left').classList.toggle('has-must', g.must.length > 0);
  }

  private updateExtras() {
    const g = this.game;
    const key = `${hasBuilding(g.base, 'recycler')}|${hasBuilding(g.base, 'shapeFactory')}|${g.shapeFactoryUsed}|${g.canSmite()}|${this.smiteMode}|${hasBuilding(g.base, 'smite')}|${g.base.smiteCharge}`;
    if (!this.sig('extras', key)) return;
    const el = $(this.root, '#extras');
    let h = '';
    if (hasBuilding(g.base, 'recycler')) h += `<button class="wide" id="btnRecycle" title="Recycle the selected piece">♻ Recycle +${(BUILDING_FX.recycler * buildingMult(g.base, 'recycler')).toFixed(1)}◆</button>`;
    if (hasBuilding(g.base, 'shapeFactory'))
      h += `<div class="qhead">SHAPE FACTORY</div><div class="fams">${FAMILIES.map((f) => `<button data-fam="${f}" ${g.shapeFactoryUsed ? 'disabled' : ''} title="Next piece: ${f} (${FAMILY_KIND[f]})">${FAMILY_KIND[f].split(' ')[0]}</button>`).join('')}</div>`;
    if (hasBuilding(g.base, 'smite'))
      h += `<button class="wide smite ${this.smiteMode ? 'on' : ''}" id="btnSmite" ${g.canSmite() ? '' : 'disabled'}>☄ Smite ${g.canSmite() ? 'ready' : `${Math.min(g.base.smiteCharge, 3)}/3`}</button>`;
    el.innerHTML = h;
    const rc = el.querySelector('#btnRecycle') as HTMLButtonElement | null;
    if (rc) rc.onclick = () => { if (this.selected && g.recycle(this.selected)) this.afterPlace(); };
    el.querySelectorAll<HTMLButtonElement>('[data-fam]').forEach((b) => (b.onclick = () => { if (g.chooseFamily(b.dataset.fam as Family)) this.audio.ui(); }));
    const sm = el.querySelector('#btnSmite') as HTMLButtonElement | null;
    if (sm) sm.onclick = () => { this.smiteMode = !this.smiteMode; };
  }

  private updateReady() {
    const g = this.game;
    const show = g.phase === 'calm';
    $(this.root, '#readyWrap').classList.toggle('hidden', !show);
    if (!show) return;
    const left = EARLY_CALL_WINDOW - g.phaseT;
    const early = left > 0 && !(g.isTutorial && g.waveIndex === 0);
    this.setText('#readyText', g.waveIndex === 0 ? 'Ready ▶' : `Next wave ▶`);
    this.setText('#readyBonus', early ? ` +${EARLY_CALL_BONUS}◆ ${Math.ceil(left)}s` : '');
    $(this.root, '#btnReady').classList.toggle('pulse', g.isTutorial && g.tutorial?.step === 3);
  }

  private updateBossBar() {
    const g = this.game;
    const boss = g.enemies.find((e) => e.boss) ?? g.enemies.find((e) => e.champion);
    const el = $(this.root, '#bossBar');
    el.classList.toggle('hidden', !boss);
    if (!boss) return;
    const gr = GROUPS[boss.group];
    this.setText('#bbName', `${boss.boss ? 'BOSS' : 'Sub-boss'} · ${boss.element} ${gr.name}${boss.group !== 'nonmetal' ? ` · ${gr.ability}` : ''}`);
    ($(this.root, '#bbFill')).style.width = `${Math.max(0, (boss.hp / boss.maxHp) * 100).toFixed(1)}%`;
    ($(this.root, '#bbShield')).style.width = `${Math.min(100, (boss.shield / boss.maxHp) * 100).toFixed(1)}%`;
  }

  toast(html: string, color = '#ffe08a', time = 3.2) {
    const box = $(this.root, '#toasts');
    const el = document.createElement('div');
    el.className = 'toast';
    el.style.setProperty('--c', color);
    el.innerHTML = html;
    box.appendChild(el);
    this.toasts.push({ el, t: time });
    while (this.toasts.length > 4) this.toasts.shift()!.el.remove();
  }
  private updateToasts(dt: number) {
    for (const t of this.toasts) {
      t.t -= dt;
      if (t.t < 0.4) t.el.classList.add('out');
      if (t.t <= 0) t.el.remove();
    }
    this.toasts = this.toasts.filter((t) => t.t > 0);
  }

  private updateTutorial() {
    const g = this.game;
    const el = $(this.root, '#tutorial');
    const t = g.tutorial;
    el.classList.toggle('hidden', !t);
    if (t && this.sig('tut', t.text)) el.innerHTML = `<span class="tut-step">Tutorial</span>${esc(t.text)}`;
  }

  private updateCard() {
    const g = this.game;
    const el = $(this.root, '#card');
    const t = g.towers.find((x) => x.id === this.renderer.selectedTower) ?? (g.batteryTower?.id === this.renderer.selectedTower ? g.batteryTower : null);
    if (!t) { el.classList.add('hidden'); return; }
    el.classList.remove('hidden');
    const s = t.stats;
    const key = `${t.id}|${t.pieces.length}|${t.kills}|${s?.dps.toFixed(1)}`;
    if (!this.sig('card', key)) return;
    if (!t.type || !s) {
      const core = t.pieces.filter((p) => p.layer === 0 && p.piece.kind[0] !== 'c').length;
      el.innerHTML = `<div class="c-title">Unfinished pile</div><div class="c-sub">Needs ${3 - core} more core piece${3 - core === 1 ? '' : 's'} (caps do not count).</div><div class="c-sub">The families of the first three core pieces decide the tower. Open the Recipe book (B) to plan.</div>`;
      return;
    }
    const def = TOWERS[t.type];
    el.innerHTML = `
      <div class="c-title">${t.type}${s.pure ? ' ★' : ''}</div>
      <div class="c-sub">${esc(t.hint)}</div>
      <div class="c-stats">
        <div><span>DPS</span><b>${s.dps.toFixed(1)}</b></div>
        <div><span>Range</span><b>${s.range.toFixed(1)}</b></div>
        <div><span>Rate</span><b>${(1 / s.interval).toFixed(2)}/s</b></div>
        <div><span>Stories</span><b>${t.layers.length}${s.pure ? ' +1' : ''}</b></div>
        <div><span>Element</span><b style="color:${s.color ? PIECE_CSS[s.color] : '#aab'}">${s.color ?? 'hybrid'}</b></div>
        <div><span>Kills</span><b>${t.kills}</b></div>
      </div>
      <div class="c-note">${esc(def.note)}${def.air ? ' · hits Balloons' : ''}</div>
      <div class="c-bonus">${s.bonuses.map((b) => `<div class="${b.good ? 'good' : 'bad'}">${esc(b.label)}</div>`).join('')}
      ${t.pieces.filter((p) => p.piece.glyph).map((p) => `<div class="good">Glyph: ${GLYPH_LABEL[p.piece.glyph!]}</div>`).join('')}</div>`;
  }

  private updateTooltip(dt: number) {
    const el = $(this.root, '#tooltip');
    if (this.tipMsg) {
      this.tipMsg.t -= dt;
      if (this.tipMsg.t <= 0) this.tipMsg = null;
    }
    const gh = this.renderer.ghost;
    if (!this.pointer.over || (!gh && !this.tipMsg)) { el.classList.add('hidden'); return; }
    let h = '';
    if (gh) {
      const pv = gh.pv;
      if (!pv.ok) h = `<div class="bad">${esc(pv.reason ?? 'Cannot place here')}</div>`;
      else {
        if (pv.kind === 'tower' || pv.kind === 'story') {
          if (pv.resultType) h += `<div class="t-type">${pv.resultType}${pv.kind === 'story' ? ` · story ${(pv.layer ?? 0) + 1}` : ''}</div><div class="t-dps">${pv.dps?.toFixed(1)} DPS · range ${pv.range?.toFixed(0)}</div>`;
          else h += `<div class="t-type">Pile: ${pv.needs} more core piece${pv.needs === 1 ? '' : 's'}</div>`;
          if (pv.resultType && pv.hint) h += `<div class="t-hint">${esc(pv.hint)}</div>`;
        }
        h += pv.gained.map((s) => `<div class="good">+ ${esc(s)}</div>`).join('');
        h += pv.lost.map((s) => `<div class="bad">− ${esc(s)}</div>`).join('');
      }
    } else if (this.tipMsg) h = `<div class="bad">${esc(this.tipMsg.text)}</div>`;
    if (!h) { el.classList.add('hidden'); return; }
    el.classList.remove('hidden');
    if (el.innerHTML !== h) el.innerHTML = h;
    const x = Math.min(window.innerWidth - el.offsetWidth - 8, this.pointer.sx + 22);
    const y = Math.min(window.innerHeight - el.offsetHeight - 8, this.pointer.sy + 18);
    el.style.transform = `translate(${x}px, ${y}px)`;
  }

  banner(text: string, sub = '', time = 1.8) {
    const el = $(this.root, '#banner');
    el.innerHTML = `<div class="b-main">${esc(text)}</div>${sub ? `<div class="b-sub">${esc(sub)}</div>` : ''}`;
    el.classList.remove('show');
    void el.offsetWidth;
    el.classList.add('show');
    this.bannerT = time;
  }

  // ================================================================ events
  handleEvents(events: GameEvent[]) {
    const g = this.game;
    for (const e of events) {
      switch (e.t) {
        case 'phase':
          if (e.phase === 'reveal') { this.banner(`Board ${g.boardNo}`, g.isTutorial ? 'Tutorial' : `${g.wavesInBoard} wave${g.wavesInBoard > 1 ? 's' : ''} · ${SUIT_SYMBOL[g.dominant]} ${g.dominant} dominant`, 2.4); this.closeModal(); }
          if (e.phase === 'cleared') this.openCleared();
          if (e.phase === 'lost') this.openLost();
          if (e.phase === 'victory') this.openVictory();
          if (e.phase === 'base') this.openBase();
          if (e.phase === 'calm' && g.waveIndex > 0) this.banner('Calm', 'Build freely. Pieces arrive only during waves.', 1.4);
          break;
        case 'waveStart': this.banner(`Wave ${e.index} of ${g.wavesInBoard}`, '', 1.2); break;
        case 'discover': {
          const gr = GROUPS[e.group];
          this.toast(`<span class="tk">${esc(e.element)}</span><div><b>New element: ${esc(e.element)}</b><br><span>${esc(gr.name)}${e.group !== 'nonmetal' ? ` · ${esc(gr.ability)}` : ''}</span></div>`, hexCss(gr.color));
          break;
        }
        case 'champion': this.banner(e.boss ? 'The Boss arrives' : 'A sub-boss approaches', e.boss ? '' : 'It summons swarms. Kill it for loot.', 1.8); break;
        case 'loot': this.toast(`<span class="tk">★</span><div><b>Loot!</b><br><span>+${e.essence} ◆ · +${e.ore} ⬢${e.golden ? ' · a golden piece' : ''}</span></div>`); break;
        case 'strike': if (e.destroys > 0) this.toast(`<span class="tk">⚡</span><div><b>The bolt was forced through</b><br><span>${e.destroys} blocking piece${e.destroys > 1 ? 's' : ''} will return to your tray</span></div>`, '#bfe8ff'); break;
        case 'undo': this.tipMsg = { text: 'Undone', t: 0.8 }; break;
        case 'reject': this.tipMsg = { text: e.reason, t: 1.2 }; break;
        case 'piece':
          if (e.zone === 'must' && (!this.selected || this.selected.zone !== 'must') && g.canPlacePieces() && !this.modal) {
            this.selected = { zone: 'must', index: 0 };
            this.refreshGhost();
          }
          break;
        case 'early': this.banner(`Early call +${EARLY_CALL_BONUS} ◆`, '', 1); break;
      }
    }
  }

  // ================================================================ input
  private get canvas() {
    return this.renderer.app.canvas as HTMLCanvasElement;
  }

  private bindInput() {
    const cv = this.canvas;
    cv.addEventListener('contextmenu', (e) => e.preventDefault());
    cv.addEventListener('pointerdown', (e) => this.canvasDown(e));
    window.addEventListener('pointermove', (e) => this.move(e));
    window.addEventListener('pointerup', (e) => this.up(e));
    window.addEventListener('pointercancel', (e) => { this.touches.delete(e.pointerId); this.press = null; });
    cv.addEventListener('wheel', (e) => {
      e.preventDefault();
      const r = cv.getBoundingClientRect();
      const k = Math.exp(-Math.max(-120, Math.min(120, e.deltaMode === 1 ? e.deltaY * 33 : e.deltaY)) * 0.0022);
      this.renderer.zoomAt(e.clientX - r.left, e.clientY - r.top, k);
      this.updatePointer(e as unknown as PointerEvent);
      this.refreshGhost();
    }, { passive: false });
    window.addEventListener('keydown', (e) => this.key(e));
  }

  private slotDown(e: PointerEvent, zone: Source['zone'], index: number) {
    e.preventDefault();
    this.audio.start();
    const g = this.game;
    if (!g.getPiece({ zone, index })) {
      if (g.mayLocked && zone !== 'must') this.flashTip('Place your MUST USE pieces first');
      return;
    }
    (e.target as HTMLElement).releasePointerCapture?.(e.pointerId);
    this.selected = { zone, index };
    this.renderer.selectedTower = 0;
    this.audio.ui();
    this.press = { kind: 'slot', x: e.clientX, y: e.clientY, id: e.pointerId, moved: false, button: 0, pan: false, lx: e.clientX, ly: e.clientY };
    this.refreshGhost();
  }

  private canvasDown(e: PointerEvent) {
    this.audio.start();
    if (e.pointerType === 'touch') {
      this.touches.add(e.pointerId);
      if (this.touches.size >= 2) { this.rotate(1); this.press = null; return; } // two-finger tap rotates
    }
    this.updatePointer(e);
    if (e.button === 2) { if (this.selected) this.rotate(1); return; }
    // middle button always pans; left-drag pans when nothing is selected
    const pan = e.button === 1 || (!this.selected && !this.smiteMode);
    if (e.button === 1) e.preventDefault();
    this.press = { kind: 'canvas', x: e.clientX, y: e.clientY, id: e.pointerId, moved: false, button: e.button, pan, lx: e.clientX, ly: e.clientY };
  }

  private move(e: PointerEvent) {
    this.updatePointer(e);
    const pr = this.press;
    if (pr && Math.hypot(e.clientX - pr.x, e.clientY - pr.y) > 8) pr.moved = true;
    if (pr && pr.kind === 'canvas' && pr.pan && pr.moved && this.touches.size < 2) {
      this.renderer.panBy(e.clientX - pr.lx, e.clientY - pr.ly);
      this.canvas.style.cursor = 'grabbing';
    }
    if (pr) { pr.lx = e.clientX; pr.ly = e.clientY; }
    if (this.smiteMode) this.renderer.smiteAim = this.pointer.over ? { x: this.pointer.fx, y: this.pointer.fy, r: BUILDING_FX.smiteRadius } : null;
    else this.renderer.smiteAim = null;
    this.refreshGhost();
  }

  private up(e: PointerEvent) {
    this.touches.delete(e.pointerId);
    const p = this.press;
    this.press = null;
    if (!p || p.id !== e.pointerId) return;
    this.canvas.style.cursor = '';
    this.updatePointer(e);
    const g = this.game;
    if (p.kind === 'canvas' && p.pan && p.moved) return;
    if (p.kind === 'canvas' && p.button === 1) return;
    if (p.kind === 'slot') {
      if (p.moved && this.pointer.over && this.selected) this.tryPlace();
      return;
    }
    if (!this.pointer.over) return;
    if (this.smiteMode) {
      if (g.smite(this.pointer.fx, this.pointer.fy)) this.smiteMode = false;
      this.renderer.smiteAim = null;
      return;
    }
    if (this.selected && g.canPlacePieces()) {
      if (e.pointerType === 'touch' && !p.moved) { /* tap moves the ghost; a second tap places */ }
      this.tryPlace();
      return;
    }
    // select a tower
    const { cx, cy } = this.pointer;
    const id = inGrid(cx, cy) ? g.towerAt[cellIdx(cx, cy)] : 0;
    const coreHit = g.batteryTower && Math.hypot(this.pointer.fx - g.batteryTower.cx, this.pointer.fy - g.batteryTower.cy) < 3;
    this.renderer.selectedTower = id || (coreHit ? g.batteryTower!.id : 0);
  }

  private updatePointer(e: PointerEvent) {
    this.pointer.sx = e.clientX;
    this.pointer.sy = e.clientY;
    const el = document.elementFromPoint(e.clientX, e.clientY);
    this.pointer.over = el === this.canvas && !this.modal;
    const r = this.canvas.getBoundingClientRect();
    const w = this.renderer.toWorld(e.clientX - r.left, e.clientY - r.top);
    this.pointer.fx = w.x;
    this.pointer.fy = w.y;
    this.pointer.cx = Math.floor(w.x);
    this.pointer.cy = Math.floor(w.y);
  }

  private tryPlace() {
    const g = this.game;
    if (!this.selected) return;
    const pv = g.place(this.selected, this.orient, this.pointer.cx, this.pointer.cy);
    if (pv.ok) this.afterPlace();
  }

  private afterPlace() {
    const g = this.game;
    this.selected = g.must.length ? { zone: 'must', index: 0 } : null;
    this.refreshGhost();
  }

  private rotate(dir: number) {
    this.orient = { ...this.orient, rot: (this.orient.rot + dir + 4) % 4 };
    this.audio.ui();
    this.refreshGhost();
  }

  private flashTip(text: string) {
    this.tipMsg = { text, t: 1.4 };
    this.audio.reject();
  }

  refreshGhost() {
    const g = this.game;
    const piece = this.selected ? g.getPiece(this.selected) : null;
    if (!piece || !this.pointer.over || !g.canPlacePieces() || this.modal) { this.renderer.ghost = null; return; }
    const pv = g.preview(piece, this.orient, this.pointer.cx, this.pointer.cy);
    this.renderer.ghost = { piece, pv, range: pv.range ?? 0 };
  }

  private zoomBy(k: number) {
    const r = this.canvas.getBoundingClientRect();
    const px = this.pointer.over ? this.pointer.sx - r.left : r.width / 2, py = this.pointer.over ? this.pointer.sy - r.top : r.height / 2;
    this.renderer.zoomAt(px, py, k);
  }

  private key(e: KeyboardEvent) {
    if ((e.target as HTMLElement)?.tagName === 'INPUT') return;
    this.audio.start();
    const g = this.game;
    const k = e.key.toLowerCase();
    if (this.modal) {
      if (k === 'escape' || (k === 'p' && this.modal === 'pause') || (k === 'b' && this.modal === 'book') || (k === 'e' && this.modal === 'elements')) {
        if (this.modal === 'pause' || this.modal === 'book' || this.modal === 'elements') this.closeModal();
      }
      return;
    }
    switch (k) {
      case 'r': this.rotate(e.shiftKey ? -1 : 1); break;
      case 'f': this.orient = { ...this.orient, mirror: !this.orient.mirror }; this.audio.ui(); this.refreshGhost(); break;
      case ' ': e.preventDefault(); if (this.selected && this.pointer.cx >= 0) this.tryPlace(); break;
      case 'h':
        if (this.selected && g.holdSwap(this.selected)) {
          this.audio.ui();
          this.selected = g.must.length ? { zone: 'must', index: 0 } : null;
          this.refreshGhost();
        } else this.flashTip(g.holdLocked ? 'Hold is used: place a piece first' : 'Select a piece to hold');
        break;
      case 'escape':
        if (g.undoLeft() > 0 && g.undo()) { this.audio.ui(); this.refreshGhost(); }
        else if (this.smiteMode) { this.smiteMode = false; this.renderer.smiteAim = null; }
        else if (this.selected) { this.selected = null; this.refreshGhost(); }
        else if (this.renderer.selectedTower) this.renderer.selectedTower = 0;
        else this.openPause();
        break;
      case 'p': this.openPause(); break;
      case 'b': this.openBook(); break;
      case 'e': this.openBestiary(); break;
      case 'z': if (e.ctrlKey || e.metaKey) { if (g.undo()) this.refreshGhost(); } break;
      case 'enter': g.ready(); break;
      case '1': case '2': case '3': case '4': {
        const i = Number(k) - 1;
        const src: Source = g.mayLocked ? { zone: 'must', index: i } : { zone: 'may', index: i };
        if (g.getPiece(src)) { this.selected = src; this.refreshGhost(); }
        break;
      }
      case '+': case '=': this.zoomBy(1.2); break;
      case '-': case '_': this.zoomBy(1 / 1.2); break;
      case 'arrowleft': case 'a': this.renderer.panBy(60, 0); break;
      case 'arrowright': case 'd': this.renderer.panBy(-60, 0); break;
      case 'arrowup': case 'w': this.renderer.panBy(0, 60); break;
      case 'arrowdown': case 's': this.renderer.panBy(0, -60); break;
      case '0': this.renderer.zoom = 1; this.renderer.pan = { x: 0, y: 0 }; break;
    }
  }

  // ================================================================ modals
  private openModal(name: string, html: string, cls = '') {
    this.modal = name;
    const m = $(this.root, '#modal');
    m.classList.remove('hidden');
    const box = $(this.root, '#modalBox');
    box.className = `modal-box ${cls}`;
    box.innerHTML = html;
    this.renderer.ghost = null;
    this.paused = name === 'pause' || name === 'book' || name === 'elements';
    return box;
  }
  closeModal() {
    this.modal = null;
    this.paused = false;
    $(this.root, '#modal').classList.add('hidden');
  }

  openPause() {
    const g = this.game;
    const s = this.settings;
    const box = this.openModal('pause', `
      <h2>Paused</h2>
      <div class="opt"><span>Seed</span><code id="seedCode">${g.seed}</code><button id="copySeed">Copy</button></div>
      <div class="opt"><span>Difficulty</span><select id="modeSel">${(Object.keys(MODES) as ModeId[]).map((m) => `<option value="${m}" ${m === g.mode ? 'selected' : ''}>${MODES[m].name} (HP ×${MODES[m].hp.toFixed(3)})</option>`).join('')}</select></div>
      <div class="opt"><span>Volume</span><input type="range" id="vol" min="0" max="1" step="0.05" value="${s.volume}"></div>
      <label class="opt"><span>Reduced motion</span><input type="checkbox" id="rm" ${s.reducedMotion ? 'checked' : ''}></label>
      <label class="opt"><span>Show ranges</span><input type="checkbox" id="sr" ${s.showRanges ? 'checked' : ''}></label>
      <div class="opt small">Difficulty changes apply from the next wave.</div>
      <div class="row">
        <button id="resume" class="primary">Resume</button>
        <button id="metrics">Export playtest JSON</button>
      </div>
      <div class="row">
        <button id="restart">New run</button>
        <button id="quit">Quit to title</button>
      </div>`);
    ($(box, '#resume') as HTMLButtonElement).onclick = () => this.closeModal();
    ($(box, '#copySeed') as HTMLButtonElement).onclick = () => { navigator.clipboard?.writeText(String(g.seed)).catch(() => {}); };
    ($(box, '#modeSel') as HTMLSelectElement).onchange = (e) => { g.mode = (e.target as HTMLSelectElement).value as ModeId; this.sigs.next = ''; this.shell.saveNow(); };
    ($(box, '#vol') as HTMLInputElement).oninput = (e) => { s.volume = Number((e.target as HTMLInputElement).value); this.shell.settingsChanged(); };
    ($(box, '#rm') as HTMLInputElement).onchange = (e) => { s.reducedMotion = (e.target as HTMLInputElement).checked; this.shell.settingsChanged(); };
    ($(box, '#sr') as HTMLInputElement).onchange = (e) => { s.showRanges = (e.target as HTMLInputElement).checked; this.shell.settingsChanged(); };
    ($(box, '#metrics') as HTMLButtonElement).onclick = () => exportMetrics(g, () => this.openPause());
    ($(box, '#restart') as HTMLButtonElement).onclick = () => this.openNewRun();
    ($(box, '#quit') as HTMLButtonElement).onclick = () => this.shell.quitToTitle();
  }

  openNewRun() {
    const box = this.openModal('newrun', `
      <h2>New run</h2>
      <p>Seven boards on one growing map. Your towers and base persist; each board, lightning strikes a new road that joins the old ones.</p>
      ${modeButtons(this.game.mode)}
      <div class="opt"><span>Seed (optional)</span><input id="seedIn" placeholder="random" inputmode="numeric"></div>
      <div class="row"><button id="back">Back</button></div>`);
    box.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach((b) => (b.onclick = () => {
      const v = ($(box, '#seedIn') as HTMLInputElement).value.trim();
      this.shell.newRun(b.dataset.mode as ModeId, v ? Number(v) >>> 0 : undefined);
    }));
    ($(box, '#back') as HTMLButtonElement).onclick = () => this.openPause();
  }

  openBook() {
    const g = this.game;
    const recipes = allRecipes();
    const byType = new Map<TowerType, string[]>();
    for (const r of recipes) byType.set(r.type, [...(byType.get(r.type) ?? []), r.hint.split(' = ')[0]]);
    const cards = TOWER_TYPES.map((t) => {
      const known = g.discovered.has(t);
      const def = TOWERS[t];
      return `<div class="rb ${known ? '' : 'unknown'}">
        <div class="rb-name">${known ? t : '???'}</div>
        <div class="rb-stats">${known ? `${def.dps} DPS · range ${def.range} · ${esc(def.note)}` : 'Not discovered yet'}</div>
        <div class="rb-rec">${known ? byType.get(t)!.map((s) => `<span>${esc(s)}</span>`).join('') : ''}</div>
      </div>`;
    }).join('');
    const box = this.openModal('book', `
      <h2>Recipe book <small>${g.discovered.size} / 13 discovered</small></h2>
      <p class="small">The families of a tower's first three core pieces decide its type. Families: Hook (J, L) · Block (O) · Bar (I) · Tee (T) · Skew (S, Z). Caps never count.</p>
      <div class="rb-grid">${cards}</div>
      <div class="row"><button id="closeBook" class="primary">Close</button></div>`, 'wide');
    ($(box, '#closeBook') as HTMLButtonElement).onclick = () => this.closeModal();
  }

  openBestiary() {
    const g = this.game;
    const groups = (Object.keys(GROUPS) as Group[]);
    const cols = groups.map((gr) => {
      const d = GROUPS[gr];
      const cells = d.symbols.map((sym) => {
        const known = g.discoveredElements.has(sym);
        return `<div class="el ${known ? 'known' : ''}" style="--c:${hexCss(d.color)}" title="${known ? `${sym} · ${esc(d.name)}` : 'Not met yet'}"><b>${known ? esc(sym) : '?'}</b></div>`;
      }).join('');
      const met = d.symbols.some((sym) => g.discoveredElements.has(sym));
      return `<div class="eg" style="--c:${hexCss(d.color)}">
        <div class="eg-head"><span class="eg-dot"></span>${esc(d.name)} <i>${d.fromBoard > 1 ? `from board ${d.fromBoard}` : ''}</i></div>
        <div class="eg-cells">${cells}</div>
        <div class="eg-ab">${met || gr === 'nonmetal' ? `<b>${esc(d.ability)}</b><br><span>Counter: ${esc(d.counter)}</span>` : '<span>Meet one to learn its power.</span>'}</div>
      </div>`;
    }).join('');
    const total = groups.reduce((s, gr) => s + GROUPS[gr].symbols.length, 0);
    const box = this.openModal('elements', `
      <h2>Bestiary <small>${g.discoveredElements.size} / ${total} elements met</small></h2>
      <p class="small">Every monster pack carries an element. Its group grants an ability. Tiers I to IV (shown by plates, horns and crowns) mean more health and more Essence. Sub-bosses summon swarms and drop loot.</p>
      <div class="ptable">${cols}</div>
      <div class="row"><button id="closeEl" class="primary">Close</button></div>`, 'wide');
    ($(box, '#closeEl') as HTMLButtonElement).onclick = () => this.closeModal();
  }

  private openCleared() {
    const g = this.game;
    const m = g.metrics;
    const box = this.openModal('cleared', `
      <h2>Board ${g.boardNo} cleared!</h2>
      <div class="stats">
        <div><span>Base integrity</span><b>${g.integrity} / ${BASE_INTEGRITY}</b></div>
        <div><span>Kills</span><b>${m.kills}</b></div>
        <div><span>Peak combo</span><b>×${m.combosPeak}</b></div>
        <div><span>Essence</span><b>◆ ${Math.floor(g.base.essence)}</b></div>
      </div>
      <p>${g.boardNo <= 5 ? 'A new square of the golden spiral unlocks at your base.' : 'Spend your Essence at the base.'}</p>
      <div class="row"><button id="toBase" class="primary">Go to base ▶</button></div>`);
    ($(box, '#toBase') as HTMLButtonElement).onclick = () => g.enterBase();
  }

  private openLost() {
    const g = this.game;
    const box = this.openModal('lost', `
      <h2>The core fell</h2>
      <p>Board ${g.boardNo}, wave ${g.waveIndex} of ${g.wavesInBoard}. Your base is restored to how it was at the start of this board.</p>
      <div class="row"><button id="retry" class="primary">Retry board</button>${g.mode !== 'relaxed' ? '<button id="relax">Retry on Relaxed</button>' : ''}</div>
      <div class="row"><button id="newrun">New run</button></div>`);
    ($(box, '#retry') as HTMLButtonElement).onclick = () => { g.retryBoard(); this.shell.saveNow(); };
    const rx = box.querySelector('#relax') as HTMLButtonElement | null;
    if (rx) rx.onclick = () => { g.mode = 'relaxed'; g.retryBoard(); this.shell.saveNow(); };
    ($(box, '#newrun') as HTMLButtonElement).onclick = () => this.openNewRun();
  }

  private openVictory() {
    const g = this.game;
    const box = this.openModal('victory', `
      <h2>Golden run complete</h2>
      <p>All seven boards cleared on ${MODES[g.mode].name}. ${goldenBase(g.base) ? 'Your Golden Base shines.' : ''}</p>
      <div class="stats"><div><span>Recipes found</span><b>${g.discovered.size} / 13</b></div><div><span>Seed</span><b>${g.seed}</b></div></div>
      <div class="row"><button id="again" class="primary">New run</button><button id="title">Title</button></div>`);
    ($(box, '#again') as HTMLButtonElement).onclick = () => this.openNewRun();
    ($(box, '#title') as HTMLButtonElement).onclick = () => this.shell.quitToTitle();
  }

  // ---------------------------------------------------------------- base screen
  openBase(justBuilt = -1) {
    const g = this.game;
    const b = g.base;
    const SHORT: Record<BuildingId, string> = {
      blastDoor: 'Door', beacon: 'Beacon', powerStation: 'Power', recycler: 'Recycler', research: 'Research',
      shapeFactory: 'Shapes', harvesterHub: 'Hub', factory: 'Factory', missileBattery: 'Battery', smite: 'Smite',
    };
    const rects = BASE_SQUARES.map((s, i) => {
      const unlocked = i < b.unlocked;
      const id = b.buildings[i];
      const sel = this.baseSel.building;
      const fits = sel && !canBuild(b, i, sel);
      return `<g class="sq ${unlocked ? 'open' : 'locked'} ${id ? 'built' : ''} ${isHarmony(b, i) ? 'harmony' : ''} ${fits ? 'fits' : ''} ${i === justBuilt ? 'justbuilt' : ''}" data-sq="${i}">
        <rect x="${s.x + 0.06}" y="${s.y + 0.06}" width="${s.size - 0.12}" height="${s.size - 0.12}" rx="0.12"></rect>
        ${id ? `<g class="art ${i === justBuilt ? 'rise' : ''}">${buildingArt(id, s.x, s.y, s.size)}</g>` : ''}
        ${i === justBuilt ? scaffold(s.x, s.y, s.size) : ''}</g>`;
    }).join('');
    const labels = BASE_SQUARES.map((s, i) => {
      const unlocked = i < b.unlocked;
      const id = b.buildings[i];
      const name = id ? (s.size >= 3 ? BUILDINGS[id].name : SHORT[id]) : unlocked ? `${s.size}×${s.size}` : 'locked';
      const fs = Math.min(id ? 0.55 : 0.85, (s.size * 0.88) / Math.max(4, name.length * 0.62));
      const harm = isHarmony(b, i);
      const ty = id ? s.y + s.size - fs * 0.75 : s.y + s.size / 2;
      return `<text x="${s.x + s.size / 2}" y="${ty}" font-size="${fs}" dominant-baseline="middle" text-anchor="middle" class="${unlocked ? '' : 'lockt'} ${id ? 'blabel' : ''}">${esc(name)}</text>
        ${harm ? `<text x="${s.x + s.size / 2}" y="${id ? s.y + 0.32 : s.y + s.size / 2 + fs * 0.95}" font-size="${Math.min(0.4, fs * 0.7)}" text-anchor="middle" dominant-baseline="middle" class="harm">${s.size >= 2 ? 'Harmony' : '★'}</text>` : ''}`;
    }).join('');
    const sq = `${rects}<path class="spiral" d="M 0 8 A 8 8 0 0 1 8 0 A 5 5 0 0 1 13 5 A 3 3 0 0 1 10 8 A 2 2 0 0 1 8 6 A 1 1 0 0 1 9 5 A 1 1 0 0 1 10 6"></path><g class="labels">${labels}</g>`;
    const list = (Object.keys(BUILDINGS) as BuildingId[]).map((id) => {
      const d = BUILDINGS[id];
      const built = hasBuilding(b, id);
      const afford = b.essence >= d.cost;
      return `<button class="bld ${this.baseSel.building === id ? 'sel' : ''}" data-b="${id}" ${built ? 'disabled' : ''}>
        <span class="bn">${d.name} <i>${d.size}×${d.size}</i></span><span class="bc ${afford ? '' : 'poor'}">◆ ${d.cost}</span>
        <span class="be">${built ? 'Built' : esc(d.effect)}</span></button>`;
    }).join('');
    const nextUnlock = b.unlocked < BASE_SQUARES.length ? `Next square (${BASE_SQUARES[b.unlocked].size}×${BASE_SQUARES[b.unlocked].size}) unlocks after board ${b.unlocked - 1}.` : 'All squares unlocked.';
    const box = this.openModal('base', `
      <h2>The Base <small>after board ${g.boardNo}</small></h2>
      <div class="base-wrap">
        <div class="base-svg">
          <svg viewBox="-0.2 -0.2 13.4 8.4" preserveAspectRatio="xMidYMid meet">
            ${BASE_DEFS}${sq}
          </svg>
          <div class="small">${goldenBase(b) ? '<b class="gold">Golden Base: +8% damage to all towers</b>' : `Fill every square for a Golden Base (+8% damage). A building that exactly fits its square gains Harmony (+${(HARMONY * 100).toFixed(1)}%). ${nextUnlock}`}</div>
        </div>
        <div class="base-side">
          <div class="res-big"><span>◆ <b>${Math.floor(b.essence)}</b> Essence</span><span>⬢ <b>${Math.floor(b.ore)}</b> Ore</span>
          <button id="convert" ${b.ore >= 1 ? '' : 'disabled'}>Convert ore 1:1</button></div>
          <div class="hint">${this.baseSel.building ? `Now pick a glowing square for the ${BUILDINGS[this.baseSel.building].name}.` : 'Pick a building, then a square.'}</div>
          <div class="blist">${list}</div>
        </div>
      </div>
      <div class="row"><button id="nextBoard" class="primary">Continue to board ${g.boardNo + 1} ▶</button></div>`, 'wide base');
    box.querySelectorAll<HTMLButtonElement>('[data-b]').forEach((el) => (el.onclick = () => {
      const id = el.dataset.b as BuildingId;
      this.baseSel.building = this.baseSel.building === id ? null : id;
      this.audio.ui();
      this.openBase();
    }));
    box.querySelectorAll<SVGGElement>('[data-sq]').forEach((el) => el.addEventListener('click', () => {
      const i = Number(el.dataset.sq);
      if (!this.baseSel.building) return;
      const err = g.build(i, this.baseSel.building);
      if (err) { this.audio.reject(); el.classList.add('shake'); setTimeout(() => el.classList.remove('shake'), 400); return; }
      this.baseSel.building = null;
      this.shell.saveNow();
      this.openBase(i);
    }));
    ($(box, '#convert') as HTMLButtonElement).onclick = () => { g.convertOre(); this.audio.coin(); this.openBase(); };
    ($(box, '#nextBoard') as HTMLButtonElement).onclick = () => { g.nextBoard(); this.shell.saveNow(); };
  }
}

function scaffold(x: number, y: number, s: number): string {
  // scaffold rises, then blocks fall in like Tetris pieces, then a pop
  let h = `<g class="scaffold">`;
  for (let i = 0; i <= s; i += Math.max(0.5, s / 4)) h += `<line x1="${x + i}" y1="${y + s}" x2="${x + i}" y2="${y}"></line>`;
  h += `</g><g class="blocks">`;
  const n = Math.min(8, 2 + s);
  for (let i = 0; i < n; i++) {
    const bw = s / 3;
    const bx = x + ((i * 0.618 * s) % (s - bw)), by = y + s - bw * (1 + Math.floor(i / 3));
    h += `<rect class="blk" style="animation-delay:${0.3 + i * 0.12}s" x="${bx}" y="${Math.max(y, by)}" width="${bw}" height="${bw}" rx="0.05"></rect>`;
  }
  return h + '</g>';
}

function weakTo(s: Suit): 'red' | 'gold' | 'green' | 'blue' {
  return ({ hearts: 'green', clubs: 'red', diamonds: 'blue', spades: 'gold' } as const)[s];
}

function pieceTitle(p: import('../sim/pieces').Piece): string {
  const fam = p.kind[0] === 'c' ? 'Cap (fills holes, builds stories)' : `${p.kind} piece`;
  return `${p.golden ? 'Golden piece (any family, any colour)' : fam} · ${p.color}${p.glyph ? ` · glyph: ${GLYPH_LABEL[p.glyph]}` : ''}`;
}

export function modeButtons(current: ModeId): string {
  const d: Record<ModeId, string> = { relaxed: 'Enemy HP ×0.618. Calm and forgiving.', normal: 'The intended balance.', golden: 'Enemy HP ×1.618. For experts.' };
  return `<div class="modes">${(Object.keys(MODES) as ModeId[]).map((m) => `<button data-mode="${m}" class="mode ${m === current ? 'cur' : ''}"><b>${MODES[m].name}</b><span>${d[m]}</span></button>`).join('')}</div>`;
}

function exportMetrics(g: Game, onClose: () => void) {
  // Downloads are blocked in some hosts (e.g. sandboxed frames), so show the JSON to copy as well.
  const data = JSON.stringify({ exportedAt: new Date().toISOString(), seed: g.seed, mode: g.mode, thisRun: g.allMetrics, history: loadMetrics() }, null, 2);
  const box = document.getElementById('modalBox')!;
  box.innerHTML = `<h2>Playtest metrics</h2><p class="small">Base HP lost, danger time, backlog and combos per board. Copy this JSON and send it to the designer.</p>
    <textarea id="metricsTxt" readonly style="width:100%;height:240px;background:#0d1220;color:#e6ebff;border:1px solid rgba(140,160,230,.2);border-radius:8px;font:12px ui-monospace,monospace;user-select:text"></textarea>
    <div class="row"><button id="copyMetrics" class="primary">Copy JSON</button><button id="dlMetrics">Download file</button><button id="closeMetrics">Close</button></div>`;
  const ta = box.querySelector('#metricsTxt') as HTMLTextAreaElement;
  ta.value = data;
  (box.querySelector('#copyMetrics') as HTMLButtonElement).onclick = () => {
    navigator.clipboard?.writeText(data).catch(() => { ta.select(); });
    ta.select();
  };
  (box.querySelector('#dlMetrics') as HTMLButtonElement).onclick = () => {
    try {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([data], { type: 'application/json' }));
      a.download = `satisfying-td-playtest-${g.seed}.json`;
      a.click();
    } catch { ta.select(); }
  };
  (box.querySelector('#closeMetrics') as HTMLButtonElement).onclick = onClose;
}

export { SIZES };
