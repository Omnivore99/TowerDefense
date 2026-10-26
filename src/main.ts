import { Application } from 'pixi.js';
import './ui/styles.css';
import { MODES, SIM_HZ, type ModeId } from './balance';
import { AudioEngine } from './audio/audio';
import { PAL } from './render/palette';
import { Renderer } from './render/renderer';
import { Game } from './sim/game';
import { randomSeed } from './sim/rng';
import { clearRun, loadMeta, loadRun, loadSettings, logMetrics, saveMeta, saveRun, saveSettings } from './save';
import { UI, modeButtons } from './ui/ui';
import { formatTable, runSkill } from './bots/harness';
import { Bot, type Skill } from './bots/bots';

const DT = 1 / SIM_HZ;

async function boot() {
  const params = new URLSearchParams(location.search);
  if (params.get('bots') === '1') return runBotsPage(params);

  const app = new Application();
  await app.init({ resizeTo: window, background: PAL.bg, antialias: true, autoDensity: true, resolution: Math.min(2, window.devicePixelRatio || 1), preference: 'webgl' });
  document.getElementById('stage')!.appendChild(app.canvas);
  const renderer = new Renderer(app);
  const audio = new AudioEngine();
  const settings = loadSettings();
  const meta = loadMeta();

  let game = new Game(randomSeed(), 'normal', { tutorial: false });
  game.phase = 'base'; // idle behind the title screen
  let running = false;
  let acc = 0;
  let loggedFor = '';

  const applySettings = () => {
    renderer.reducedMotion = settings.reducedMotion;
    renderer.showRanges = settings.showRanges;
    audio.setVolume(settings.volume);
    saveSettings(settings);
  };

  const saveNow = () => {
    if (!running) return;
    for (const t of game.discovered) if (!meta.discovered.includes(t)) meta.discovered.push(t);
    saveMeta(meta);
    if (game.phase === 'victory') { clearRun(); return; }
    saveRun({ seed: game.seed, mode: game.mode, board: game.boardNo, base: game.baseSnapshot, discovered: [...game.discovered], savedAt: Date.now() });
  };

  const startGame = (g: Game) => {
    game = g;
    (window as unknown as { __std: unknown }).__std = { game, ui, renderer, Bot, Game, start: startGame };
    for (const t of meta.discovered) game.discovered.add(t);
    running = true;
    acc = 0;
    ui.setGame(g);
    renderer.setBoard(g.board);
    title.classList.add('hidden');
    saveNow();
  };

  const shell = {
    newRun(mode: ModeId, seed?: number) {
      const tutorial = !meta.tutorialDone;
      startGame(new Game(seed ?? randomSeed(), mode, { tutorial }));
    },
    quitToTitle() {
      saveNow();
      running = false;
      ui.closeModal();
      showTitle();
    },
    saveNow,
    settingsChanged: applySettings,
  };

  const ui = new UI(document.getElementById('ui')!, game, renderer, audio, settings, shell);
  applySettings();

  // ---------------------------------------------------------------- title screen
  const title = document.getElementById('title')!;
  const showTitle = () => {
    const saved = loadRun();
    title.classList.remove('hidden');
    title.innerHTML = `
      <div class="title-box">
        <div class="logo"><svg viewBox="-0.2 -0.2 13.4 8.4"><g class="lsq">
          <rect x="0" y="0" width="8" height="8"/><rect x="8" y="0" width="5" height="5"/><rect x="10" y="5" width="3" height="3"/>
          <rect x="8" y="6" width="2" height="2"/><rect x="8" y="5" width="1" height="1"/><rect x="9" y="5" width="1" height="1"/></g>
          <path d="M 0 8 A 8 8 0 0 1 8 0 A 5 5 0 0 1 13 5 A 3 3 0 0 1 10 8 A 2 2 0 0 1 8 6 A 1 1 0 0 1 9 5 A 1 1 0 0 1 10 6"/></svg></div>
        <h1>Satisfying TD</h1>
        <p class="tag">Build towers from falling pieces. Grow a golden base. Breathe between waves.</p>
        ${saved ? `<button id="cont" class="primary big">Continue run · Board ${saved.board} · ${MODES[saved.mode].name}</button>` : ''}
        <div class="nr-label">${saved ? 'Or start a new run' : 'Start a run'}</div>
        ${modeButtons('normal')}
        <div class="opt"><span>Seed (optional)</span><input id="seedIn" placeholder="random" inputmode="numeric"></div>
        <label class="opt small"><input type="checkbox" id="tut" ${meta.tutorialDone ? '' : 'checked'}> Play the tutorial on board 1</label>
        <div class="help">Drag pieces from the left onto the board. Three touching tetrominoes become a tower; their families decide its type.
        Stack smaller pieces on top for stories. Drop pieces on glowing ore to harvest, or on the road for barriers and mines.</div>
      </div>`;
    const cont = title.querySelector('#cont') as HTMLButtonElement | null;
    if (cont && saved) cont.onclick = () => {
      audio.start();
      const g = new Game(saved.seed, saved.mode, { tutorial: false, base: saved.base, board: saved.board });
      for (const t of saved.discovered) g.discovered.add(t);
      startGame(g);
    };
    title.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach((b) => (b.onclick = () => {
      audio.start();
      const v = (title.querySelector('#seedIn') as HTMLInputElement).value.trim();
      const tut = (title.querySelector('#tut') as HTMLInputElement).checked;
      startGame(new Game(v ? Number(v) >>> 0 : randomSeed(), b.dataset.mode as ModeId, { tutorial: tut }));
    }));
  };
  showTitle();

  // ---------------------------------------------------------------- main loop
  let lastPhase = '';
  app.ticker.add((tk) => {
    const dt = Math.min(0.1, tk.deltaMS / 1000);
    if (running && !ui.paused) {
      acc += dt * settings.speed;
      let steps = 0;
      while (acc >= DT && steps < 12) { game.step(); acc -= DT; steps++; }
      if (steps >= 12) acc = 0;
    }
    const events = game.drainEvents();
    if (events.length) {
      renderer.handleEvents(events, game);
      audio.handle(events, (id) => game.towerById(id)?.pieces.length ?? 0);
      ui.handleEvents(events);
      for (const e of events) {
        if (e.t === 'phase' && (e.phase === 'cleared' || e.phase === 'lost' || e.phase === 'victory')) {
          const m = game.allMetrics[game.allMetrics.length - 1];
          const key = `${game.seed}-${m?.board}-${m?.attempt}`;
          if (m && key !== loggedFor) { logMetrics({ ...m, seed: game.seed, mode: game.mode }); loggedFor = key; }
          if (e.phase === 'cleared' && game.isTutorial) { meta.tutorialDone = true; saveMeta(meta); }
          saveNow();
        }
        if (e.t === 'activate') saveNow();
      }
    }
    if (game.phase !== lastPhase) { lastPhase = game.phase; }
    renderer.draw(game, acc / DT, dt);
    if (running) ui.update(dt);
    audio.tick();
  });
}

// ---------------------------------------------------------------- ?bots=1
function runBotsPage(params: URLSearchParams) {
  document.getElementById('title')!.classList.add('hidden');
  const out = document.createElement('pre');
  out.className = 'bots-out';
  out.textContent = 'Running balance harness… (headless, this takes a little while)';
  document.body.appendChild(out);
  const n = Number(params.get('seeds') ?? '3');
  const mode = (params.get('mode') ?? 'normal') as ModeId;
  const skills = (params.get('skill') ?? 'novice,average,expert').split(',') as Skill[];
  const seeds = Array.from({ length: n }, (_, i) => 1000 + i * 7919);
  const results: ReturnType<typeof runSkill>[] = [];
  let i = 0;
  const next = () => {
    if (i >= skills.length) {
      out.textContent = `Satisfying TD balance harness · ${n} seeds · ${mode}\nTargets on Normal: average loses 10–35% base HP and clears 80–95%; danger 10–25%; experts keep danger above 3%.\n` + formatTable(results);
      return;
    }
    out.textContent += `\n${skills[i]}…`;
    setTimeout(() => { results.push(runSkill(skills[i], mode, seeds)); i++; next(); }, 30);
  };
  next();
}

void boot();
