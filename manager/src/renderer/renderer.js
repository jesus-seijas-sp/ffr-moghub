'use strict';
/* MogHub Manager: the installed mods (switch on / off), the mods it can install and update (the catalog), settings. */
const $ = (id) => document.getElementById(id);

// h('div', { class: 'x', onclick: fn }, child, 'text', ...)
function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c !== null && c !== undefined && c !== false) el.append(c.nodeType ? c : String(c));
  return el;
}

function status(msg, kind = '') {
  const s = $('status');
  s.textContent = msg;
  s.className = `win status ${kind}`;
}

let info = { valid: false };
let installed = [];

// ---------- game ----------
async function refreshGame() {
  info = await window.api.gameInfo();
  const g = $('game');
  g.replaceChildren();
  if (!info.valid) {
    g.append(h('span', { class: 'bad' }, 'Game not found. '), 'Choose its folder in Settings.');
  } else {
    g.append(info.dir, info.build ? `   (build ${info.build})` : '');
    if (info.running) g.append('   ', h('span', { class: 'warn' }, 'The game is running: close it to switch pak and UE4SS mods.'));
  }
  $('gameDir').textContent = info.dir || 'Not found';
}

// ---------- installed ----------
const GROUPS = [
  { title: 'Core', kinds: ['ue4ss-loader', 'moghub'] },
  { title: 'MogHub plugins', kinds: ['plugin'] },
  { title: 'UE4SS mods', kinds: ['ue4ss'] },
  { title: 'Pak mods', kinds: ['pak'] },
];
const KIND = { 'ue4ss-loader': 'Mod loader', moghub: 'Mod framework', plugin: 'MogHub plugin', ue4ss: 'UE4SS mod', pak: 'Pak mod' };

function installedRow(m) {
  const missing = (m.kind === 'ue4ss-loader' || m.kind === 'moghub') && !m.installed;
  const ver = h('span', { class: `ver${m.outdated ? ' new' : ''}` },
    m.version ? `v${m.version}` : '', m.outdated ? `  →  v${m.latest}` : '');
  let control;
  if (m.fixed) control = h('span', { class: 'ver' }, missing ? 'Not installed' : 'Installed');
  else control = h('button', { class: `cmd switch${m.on ? ' on' : ''}`, onclick: () => toggle(m) }, m.on ? 'On' : 'Off');
  const name = h('span', { class: 'name' }, m.name,
    m.outdated ? h('span', { class: 'badge update' }, 'Update available') : null,
    m.kind === 'pak' && !m.zen ? h('span', { class: 'badge' }, 'old format') : null);
  const sub = [KIND[m.kind], m.where, m.author ? `by ${m.author}` : '', m.files && m.files.length > 1 ? m.files.join('  ') : '']
    .filter(Boolean).join('  ·  ');
  return h('div', { class: `row${m.on || m.fixed ? '' : ' off'}` }, name, ver, control, h('div', { class: 'sub' }, sub));
}

function renderInstalled() {
  const list = $('installedList');
  list.replaceChildren();
  if (!info.valid) { list.append(h('div', { class: 'empty' }, 'Choose the game folder in Settings.')); return; }
  for (const g of GROUPS) {
    const items = installed.filter((m) => g.kinds.includes(m.kind));
    if (!items.length) continue;
    list.append(h('div', { class: 'group' }, g.title), ...items.map(installedRow));
  }
  const outdated = installed.filter((m) => m.outdated).length;
  const others = installed.filter((m) => !m.fixed).length;
  $('installedHint').textContent = `${others} mod${others === 1 ? '' : 's'} installed` +
    (outdated ? `, ${outdated} with an update (see Available)` : '') + '. Changes take effect the next time the game starts.';
}

async function refreshInstalled() {
  installed = await window.api.scanMods();
  renderInstalled();
  // then which of them have an update in the mod list
  const updates = await window.api.modUpdates();
  if (!updates) return;
  for (const m of installed) Object.assign(m, updates[m.id] || {});
  renderInstalled();
}

async function toggle(m) {
  const r = await window.api.setEnabled(m.id, !m.on);
  if (!r.ok) { status(r.error, 'error'); return; }
  status(`${m.name} switched ${m.on ? 'off' : 'on'}. It takes effect the next time the game starts.`, 'ok');
  await refreshInstalled();
}

// ---------- available (the catalog) ----------
const SOURCE = { github: 'GitHub', 'github-release': 'GitHub', nexus: 'Nexus Mods' };
const CATALOG_KIND = { loader: 'Mod loader', framework: 'Mod framework', plugin: 'MogHub plugin', ue4ss: 'UE4SS mod', pak: 'Pak mod' };
let busy = false;

function availableRow(m) {
  const needs = (m.requires || []).map((id) => (catalog.find((c) => c.id === id) || { name: id }).name);
  let state, buttons = [];
  if (m.installed && m.outdated) {
    state = h('span', { class: 'ver new' }, `v${m.local}  →  v${m.version}`);
    if (m.installable) buttons.push(h('button', { class: 'cmd', onclick: () => doInstall(m, 'Updating') }, 'Update'));
  } else if (m.installed) {
    state = h('span', { class: 'ver' }, `v${m.local || m.version}  ·  installed`);
  } else {
    state = h('span', { class: 'ver' }, `v${m.version}`);
    if (m.installable) buttons.push(h('button', { class: 'cmd', onclick: () => doInstall(m, 'Installing') }, 'Install'));
  }
  if (m.managed) buttons.push(h('button', { class: 'cmd', onclick: () => doUninstall(m) }, 'Uninstall'));
  if (m.homepage) buttons.push(h('button', { class: 'cmd', onclick: () => window.api.openUrl(m.homepage) }, 'Page'));
  const name = h('span', { class: 'name' }, m.name,
    m.installed && m.outdated ? h('span', { class: 'badge update' }, 'Update available') : null,
    m.installed && !m.outdated ? h('span', { class: 'badge installed' }, 'Installed') : null);
  const sub = [CATALOG_KIND[m.kind] || m.kind, `by ${m.author}`, `from ${SOURCE[m.source.type] || m.source.type}`,
    needs.length ? `needs ${needs.join(', ')}` : ''].filter(Boolean).join('  ·  ');
  return h('div', { class: 'row avail' }, name, state, h('span', { class: 'meta' }, ...buttons),
    h('div', { class: 'sub' }, sub), h('div', { class: 'desc' }, m.description || ''));
}

let catalog = [];
function renderAvailable() {
  const list = $('availableList');
  list.replaceChildren();
  if (!catalog.length) { list.append(h('div', { class: 'empty' }, 'The mod list is empty.')); return; }
  list.append(...catalog.map(availableRow));
  const updates = catalog.filter((m) => m.installed && m.outdated).length;
  $('availableHint').textContent = updates ? `${updates} update${updates === 1 ? '' : 's'} available.`
    : 'The mods MogHub Manager can install and keep up to date.';
}

async function loadCatalog(force) {
  const r = await window.api.catalogStatus(force);
  if (r.error) { $('availableList').replaceChildren(h('div', { class: 'empty' }, r.error)); return; }
  catalog = r.mods;
  renderAvailable();
}

async function doInstall(m, verb) {
  if (busy) return;
  busy = true;
  status(`${verb} ${m.name}…`);
  const r = await window.api.install(m.id);
  busy = false;
  if (!r.ok) { status(r.error, 'error'); return; }
  status(`Installed: ${r.done.join(', ')}. It takes effect the next time the game starts.`, 'ok');
  await loadCatalog(false);
  await refreshInstalled();
}

async function doUninstall(m) {
  if (busy || !confirm(`Uninstall ${m.name}? Its settings and saved data stay in the game folder.`)) return;
  const r = await window.api.uninstall(m.id);
  if (!r.ok) { status(r.error, 'error'); return; }
  status(`${m.name} uninstalled.`, 'ok');
  await loadCatalog(false);
  await refreshInstalled();
}

window.api.onProgress((msg) => status(msg));

// ---------- tabs and buttons ----------
for (const b of document.querySelectorAll('.tab-btn')) {
  b.addEventListener('click', () => {
    for (const x of document.querySelectorAll('.tab-btn')) x.classList.toggle('active', x === b);
    for (const t of document.querySelectorAll('.tab')) t.classList.toggle('active', t.id === `tab-${b.dataset.tab}`);
    if (b.dataset.tab === 'available') loadCatalog(false);
  });
}
$('btnRescan').addEventListener('click', async () => { await refreshGame(); await refreshInstalled(); status('Refreshed.'); });
$('btnReloadCatalog').addEventListener('click', () => loadCatalog(true));
$('btnPickGame').addEventListener('click', async () => {
  const r = await window.api.pickGame();
  if (!r) return;
  if (r.error) { status(r.error, 'error'); return; }
  await refreshGame();
  await refreshInstalled();
  status('Game folder set.', 'ok');
});
$('btnOpenGame').addEventListener('click', () => window.api.openFolder(''));

// the game's running state changes while the window is open
setInterval(async () => {
  const was = info.running;
  await refreshGame();
  if (was !== info.running) renderInstalled();
}, 5000);

(async () => {
  await refreshGame();
  const start = new URLSearchParams(location.search).get('tab');
  if (start) document.querySelector(`.tab-btn[data-tab="${start}"]`)?.click();
  await refreshInstalled();
  status(info.valid ? 'Ready.' : 'The game was not found: choose its folder in Settings.', info.valid ? '' : 'error');
})();
