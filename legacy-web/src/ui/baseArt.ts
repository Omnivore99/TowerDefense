// Vector art for the ten base buildings. Each is drawn in a 100 x 100 box and scaled into its Fibonacci square.
import type { BuildingId } from '../balance';

/** Shared gradients and filters; include once per base SVG. */
export const BASE_DEFS = `<defs>
  <linearGradient id="gMetal" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5b6382"/><stop offset=".45" stop-color="#c9d0e3"/><stop offset="1" stop-color="#4a5070"/></linearGradient>
  <linearGradient id="gWall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a5478"/><stop offset="1" stop-color="#252b45"/></linearGradient>
  <linearGradient id="gWallWarm" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7a6648"/><stop offset="1" stop-color="#3d3020"/></linearGradient>
  <linearGradient id="gRoof" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e0a94a"/><stop offset="1" stop-color="#8a5a22"/></linearGradient>
  <linearGradient id="gRoofBlue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6aa0e8"/><stop offset="1" stop-color="#2a4a88"/></linearGradient>
  <linearGradient id="gGold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff3c0"/><stop offset=".5" stop-color="#ffd36b"/><stop offset="1" stop-color="#a87a22"/></linearGradient>
  <linearGradient id="gGreen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6fe0a0"/><stop offset="1" stop-color="#1f6a4a"/></linearGradient>
  <radialGradient id="gGlow"><stop offset="0" stop-color="#fff6d0" stop-opacity="1"/><stop offset=".4" stop-color="#ffd36b" stop-opacity=".7"/><stop offset="1" stop-color="#ffd36b" stop-opacity="0"/></radialGradient>
  <radialGradient id="gGlowBlue"><stop offset="0" stop-color="#ffffff"/><stop offset=".35" stop-color="#9fd8ff" stop-opacity=".8"/><stop offset="1" stop-color="#5aa8ff" stop-opacity="0"/></radialGradient>
  <radialGradient id="gGlowCyan"><stop offset="0" stop-color="#e8ffff"/><stop offset=".4" stop-color="#7ff0ff" stop-opacity=".7"/><stop offset="1" stop-color="#3fb8c8" stop-opacity="0"/></radialGradient>
  <radialGradient id="gGlowRed"><stop offset="0" stop-color="#fff"/><stop offset=".3" stop-color="#ff6b6b" stop-opacity=".8"/><stop offset="1" stop-color="#ff3b3b" stop-opacity="0"/></radialGradient>
  <radialGradient id="gDome" cx=".35" cy=".3"><stop offset="0" stop-color="#e6ecff"/><stop offset=".5" stop-color="#8a96c0"/><stop offset="1" stop-color="#3a4266"/></radialGradient>
  <radialGradient id="gSmoke"><stop offset="0" stop-color="#cfd3dc" stop-opacity=".75"/><stop offset="1" stop-color="#cfd3dc" stop-opacity="0"/></radialGradient>
</defs>`;

const ground = (w = 80) => `<ellipse cx="50" cy="92" rx="${w / 2}" ry="6" fill="#000" opacity=".35"/>`;
const windows = (x: number, y: number, cols: number, rows: number, w: number, h: number, gx: number, gy: number, color = '#ffd98a') => {
  let s = '';
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++)
      s += `<rect class="win" style="animation-delay:${((r * 7 + c * 3) % 11) * 0.37}s" x="${x + c * gx}" y="${y + r * gy}" width="${w}" height="${h}" rx="0.8" fill="${color}"/>`;
  return s;
};
const smoke = (x: number, y: number, n = 3, r = 7) => {
  let s = '';
  for (let i = 0; i < n; i++) s += `<circle class="puff" style="animation-delay:${i * (2.4 / n)}s" cx="${x}" cy="${y}" r="${r}" fill="url(#gSmoke)"/>`;
  return s;
};
const rivets = (x: number, y: number, n: number, gap: number) => {
  let s = '';
  for (let i = 0; i < n; i++) s += `<circle cx="${x + i * gap}" cy="${y}" r="1.2" fill="#e6ebff" opacity=".6"/>`;
  return s;
};

const ART: Record<BuildingId, string> = {
  blastDoor: `${ground(84)}
    <path d="M10 90 L10 40 Q50 8 90 40 L90 90 Z" fill="url(#gWall)" stroke="#11162a" stroke-width="2"/>
    <path d="M22 90 L22 50 Q50 26 78 50 L78 90 Z" fill="url(#gMetal)" stroke="#2a3050" stroke-width="2"/>
    <line x1="50" y1="34" x2="50" y2="90" stroke="#2a3050" stroke-width="2.5"/>
    ${[0, 1, 2, 3, 4, 5].map((i) => `<rect x="${22 + i * 9.3}" y="82" width="4.6" height="8" fill="${i % 2 ? '#1a1a1a' : '#ffd36b'}"/>`).join('')}
    ${rivets(28, 58, 4, 6)}${rivets(56, 58, 4, 6)}
    <circle class="blink" cx="50" cy="22" r="4" fill="#ff5d6c"/><circle cx="50" cy="22" r="10" fill="url(#gGlowRed)" class="blink"/>`,
  beacon: `${ground(60)}
    <path d="M30 90 L44 22 L56 22 L70 90 Z" fill="none" stroke="url(#gMetal)" stroke-width="4"/>
    <path d="M34 72 L66 72 M37 56 L63 56 M40 40 L60 40 M34 72 L63 56 L40 40 M66 72 L37 56 L60 40" stroke="#8a93b8" stroke-width="2" fill="none"/>
    <rect x="22" y="84" width="56" height="8" rx="2" fill="url(#gWall)"/>
    <circle class="pulse" cx="50" cy="16" r="12" fill="none" stroke="#7dffb0" stroke-width="2"/>
    <circle cx="50" cy="16" r="16" fill="url(#gGlow)"/>
    <circle cx="50" cy="16" r="6" fill="#7dffb0"/><circle cx="48" cy="14" r="2" fill="#fff"/>`,
  powerStation: `${ground(90)}
    <path d="M58 90 Q62 60 56 26 L84 26 Q78 60 86 90 Z" fill="url(#gWall)" stroke="#11162a" stroke-width="1.5"/>
    <ellipse cx="70" cy="26" rx="14" ry="4" fill="#1a1f35"/>${smoke(70, 20, 3, 9)}
    <rect x="8" y="48" width="50" height="42" rx="2" fill="url(#gWall)" stroke="#11162a" stroke-width="1.5"/>
    <rect x="8" y="44" width="50" height="7" fill="url(#gRoofBlue)"/>
    <circle cx="33" cy="66" r="12" fill="#0d1428" stroke="#5aa8ff" stroke-width="2"/>
    <circle class="core" cx="33" cy="66" r="14" fill="url(#gGlowBlue)"/>
    <path class="zap" d="M27 58 L35 64 L30 67 L39 75" stroke="#fff" stroke-width="2" fill="none" stroke-linejoin="round"/>
    ${windows(13, 82, 4, 1, 6, 4, 11, 0, '#9fd8ff')}`,
  recycler: `${ground(90)}
    <rect x="8" y="42" width="84" height="48" rx="3" fill="url(#gGreen)" stroke="#0f3a28" stroke-width="2"/>
    <path d="M8 42 L20 30 L80 30 L92 42 Z" fill="#2f8a5e"/>
    <g class="spin" style="transform-origin:50px 64px"><circle cx="50" cy="64" r="15" fill="#0f3a28"/>
      ${[0, 1, 2].map((k) => `<path d="M50 64 L${50 + Math.cos((k * 2 * Math.PI) / 3) * 13} ${64 + Math.sin((k * 2 * Math.PI) / 3) * 13} A13 13 0 0 1 ${50 + Math.cos((k * 2 * Math.PI) / 3 + 1.2) * 13} ${64 + Math.sin((k * 2 * Math.PI) / 3 + 1.2) * 13} Z" fill="#9dffc8"/>`).join('')}
      <circle cx="50" cy="64" r="4" fill="#0f3a28"/></g>
    <rect x="12" y="78" width="20" height="10" fill="#ffc94a" stroke="#6a4a10"/><rect x="68" y="78" width="20" height="10" fill="#5aa8ff" stroke="#203a70"/>`,
  research: `${ground(70)}
    <rect x="30" y="34" width="40" height="56" fill="url(#gWall)" stroke="#11162a" stroke-width="1.5"/>
    <path d="M26 36 A24 24 0 0 1 74 36 Z" fill="url(#gDome)" stroke="#11162a" stroke-width="1.5"/>
    <rect x="47" y="13" width="6" height="23" fill="#11162a"/>
    <g class="sweep" style="transform-origin:50px 30px"><rect x="48" y="2" width="4" height="22" rx="1" fill="url(#gMetal)"/></g>
    ${windows(35, 44, 3, 4, 6, 5, 11, 11, '#d0b8ff')}
    <rect x="22" y="86" width="56" height="5" fill="#1a1f35"/>
    <circle cx="50" cy="6" r="6" fill="url(#gGlowBlue)" class="blink"/>`,
  shapeFactory: `${ground(92)}
    <rect x="6" y="46" width="88" height="44" fill="url(#gWall)" stroke="#11162a" stroke-width="1.5"/>
    <path d="M6 46 L6 34 L28 46 L28 34 L50 46 L50 34 L72 46 L72 34 L94 46 Z" fill="url(#gRoofBlue)" stroke="#11162a" stroke-width="1"/>
    <g class="bob"><rect x="14" y="20" width="8" height="8" fill="#ff6b6b"/><rect x="22" y="20" width="8" height="8" fill="#ff6b6b"/><rect x="22" y="12" width="8" height="8" fill="#ff6b6b"/><rect x="30" y="20" width="8" height="8" fill="#ff6b6b"/></g>
    <g class="bob" style="animation-delay:.6s"><rect x="46" y="14" width="8" height="8" fill="#ffc94a"/><rect x="54" y="14" width="8" height="8" fill="#ffc94a"/><rect x="46" y="22" width="8" height="8" fill="#ffc94a"/><rect x="54" y="22" width="8" height="8" fill="#ffc94a"/></g>
    <g class="bob" style="animation-delay:1.2s"><rect x="70" y="10" width="8" height="8" fill="#4fe0a0"/><rect x="70" y="18" width="8" height="8" fill="#4fe0a0"/><rect x="78" y="18" width="8" height="8" fill="#4fe0a0"/><rect x="78" y="26" width="8" height="8" fill="#4fe0a0"/></g>
    <rect x="6" y="76" width="88" height="6" fill="#1a1f35"/>
    <g class="belt">${[0, 1, 2, 3, 4, 5, 6].map((i) => `<rect x="${10 + i * 12}" y="72" width="6" height="4" fill="${['#ff6b6b', '#ffc94a', '#4fe0a0', '#5aa8ff'][i % 4]}"/>`).join('')}</g>
    ${windows(12, 52, 6, 1, 8, 10, 14, 0)}`,
  harvesterHub: `${ground(88)}
    <rect x="10" y="62" width="80" height="28" rx="3" fill="url(#gWall)" stroke="#11162a" stroke-width="1.5"/>
    <path d="M18 62 A32 32 0 0 1 82 62 Z" fill="url(#gDome)" stroke="#11162a" stroke-width="1.5"/>
    <path d="M30 62 L36 40 L42 62 Z M46 62 L52 32 L58 62 Z M60 62 L66 44 L72 62 Z" fill="#3fb8c8" opacity=".9"/>
    <path d="M36 40 L42 62 L37 62 Z M52 32 L58 62 L53 62 Z" fill="#b8f6ff" opacity=".6"/>
    <circle cx="52" cy="48" r="24" fill="url(#gGlowCyan)" class="core"/>
    <path d="M10 76 L2 76 L2 90 M90 76 L98 76 L98 90" stroke="url(#gMetal)" stroke-width="4" fill="none"/>
    ${windows(18, 72, 5, 1, 7, 5, 14, 0, '#7ff0ff')}`,
  factory: `${ground(94)}
    <rect x="6" y="40" width="70" height="50" fill="url(#gWallWarm)" stroke="#2a2010" stroke-width="1.5"/>
    <path d="M6 40 L6 28 L23 40 L23 28 L40 40 L40 28 L57 40 L57 28 L76 40 Z" fill="url(#gRoof)" stroke="#2a2010" stroke-width="1"/>
    <rect x="80" y="14" width="10" height="76" fill="#5a4a36" stroke="#2a2010" stroke-width="1.5"/>
    <rect x="80" y="20" width="10" height="3" fill="#ff6b6b"/><rect x="80" y="30" width="10" height="3" fill="#fff"/>
    ${smoke(85, 10, 4, 9)}
    <rect x="18" y="62" width="30" height="28" fill="#1a1510"/>${[0, 1, 2, 3, 4].map((i) => `<line x1="18" y1="${66 + i * 5}" x2="48" y2="${66 + i * 5}" stroke="#4a3a28" stroke-width="1.5"/>`).join('')}
    ${windows(54, 50, 2, 2, 7, 7, 10, 12)}
    <g class="tank"><rect x="22" y="80" width="20" height="8" rx="3" fill="#6a5a2a"/><rect x="24" y="76" width="16" height="7" rx="2" fill="#ffd36b"/><rect x="38" y="78" width="10" height="2" fill="#8a6a2a"/></g>`,
  missileBattery: `${ground(94)}
    <rect x="6" y="66" width="88" height="24" rx="3" fill="url(#gWall)" stroke="#11162a" stroke-width="1.5"/>
    ${[0, 1, 2].map((i) => `<g transform="translate(${14 + i * 16} 66) rotate(32)"><rect x="-5" y="-38" width="10" height="38" rx="2" fill="url(#gMetal)" stroke="#2a3050"/>
      <path d="M-4 -38 L0 -48 L4 -38 Z" fill="#ff6b6b"/><rect x="-5" y="-6" width="10" height="4" fill="#ff6b6b"/></g>`).join('')}
    <rect x="70" y="50" width="4" height="16" fill="#8a93b8"/>
    <g class="sweep" style="transform-origin:72px 46px"><path d="M60 40 Q72 54 84 40 Z" fill="url(#gDome)" stroke="#11162a"/><line x1="72" y1="46" x2="72" y2="36" stroke="#e6ebff" stroke-width="1.5"/></g>
    <circle class="blink" cx="88" cy="72" r="2.5" fill="#7dffb0"/>
    ${windows(12, 76, 6, 1, 8, 4, 12, 0, '#ffb35c')}`,
  smite: `${ground(80)}
    <circle cx="50" cy="20" r="34" fill="url(#gGlow)" class="core"/>
    <path d="M28 90 L40 40 L60 40 L72 90 Z" fill="url(#gWallWarm)" stroke="#2a2010" stroke-width="1.5"/>
    <path d="M40 40 L46 12 L54 12 L60 40 Z" fill="url(#gGold)" stroke="#6a4a10" stroke-width="1"/>
    <path d="M50 2 L56 14 L44 14 Z" fill="#fff3c0"/>
    <g class="orbit" style="transform-origin:50px 26px"><ellipse cx="50" cy="26" rx="30" ry="7" fill="none" stroke="#ffd36b" stroke-width="1.5" opacity=".8"/><circle cx="80" cy="26" r="2.5" fill="#fff"/><circle cx="20" cy="26" r="2" fill="#ffd36b"/></g>
    ${windows(44, 52, 2, 3, 4, 6, 8, 11, '#fff3c0')}
    <path d="M20 90 L34 74 L66 74 L80 90 Z" fill="#3d3020" stroke="#2a2010"/>
    <rect class="beam" x="48" y="-40" width="4" height="42" fill="#fff3c0" opacity=".5"/>`,
};

/** SVG for a building inside its square (world units of the base SVG). */
export function buildingArt(id: BuildingId, x: number, y: number, size: number): string {
  const k = (size * 0.9) / 100;
  const ox = x + size * 0.05, oy = y + size * 0.02;
  return `<g transform="translate(${ox} ${oy}) scale(${k})">${ART[id]}</g>`;
}
