const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const fs = require('fs');
const path = require('path');
const game = require('./game');
const mods = require('./mods');
const catalog = require('./catalog');
const installer = require('./install');

let win;

// ---------- settings: the game folder (later the Nexus API key) ----------
const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
function loadSettings() { try { return JSON.parse(fs.readFileSync(settingsFile(), 'utf8')); } catch { return {}; } }
function saveSettings(patch) {
  const s = { ...loadSettings(), ...patch };
  fs.mkdirSync(path.dirname(settingsFile()), { recursive: true });
  fs.writeFileSync(settingsFile(), JSON.stringify(s, null, 2));
  return s;
}

// the game folder: env override (testing) > remembered > detected through Steam
function gameDir() {
  if (process.env.MOGHUB_GAME_DIR) return process.env.MOGHUB_GAME_DIR;
  const remembered = loadSettings().gameDir;
  if (game.isGameDir(remembered)) return remembered;
  const found = game.detect();
  if (found) saveSettings({ gameDir: found });
  return found;
}

ipcMain.handle('game:info', async () => {
  const dir = gameDir();
  return { dir, valid: game.isGameDir(dir), build: dir ? game.buildId(dir) : null, running: await game.isRunning() };
});

ipcMain.handle('game:pick', async () => {
  const r = await dialog.showOpenDialog(win, {
    title: 'Choose the FINAL FANTASY RESONANCE folder (the one that holds FFRS)',
    defaultPath: gameDir() || app.getPath('home'),
    properties: ['openDirectory'],
  });
  if (r.canceled) return null;
  let dir = r.filePaths[0];
  // a folder inside the game (FFRS, Binaries...) is fine too: walk up to the game folder
  for (let d = dir; d && d !== path.dirname(d); d = path.dirname(d)) if (game.isGameDir(d)) { dir = d; break; }
  if (!game.isGameDir(dir)) return { error: 'That folder does not hold the game (FFRS\\Binaries\\Win64\\FFRS-Win64-Shipping.exe).' };
  saveSettings({ gameDir: dir });
  return { dir };
});

// ---------- the catalog (the mod list in the ffr-moghub repository) ----------
let catalogCache = null, catalogAt = 0;
async function getCatalog(force) {
  if (!force && catalogCache && Date.now() - catalogAt < 10 * 60 * 1000) return catalogCache;
  catalogCache = await catalog.fetchCatalog();
  catalogAt = Date.now();
  return catalogCache;
}

ipcMain.handle('catalog:status', async (_e, force) => {
  const dir = gameDir();
  if (!game.isGameDir(dir)) return { error: 'Choose the game folder in Settings first.' };
  try { return { mods: catalog.status(dir, await getCatalog(force)) }; } catch (e) { return { error: e.message }; }
});

// installs (or updates) a catalog mod, with what it needs; progress lines go to the window
ipcMain.handle('catalog:install', async (_e, id) => {
  const dir = gameDir();
  if (await game.isRunning()) return { ok: false, error: 'Close the game first.' };
  try {
    const list = catalog.status(dir, await getCatalog());
    const done = await installer.install(dir, id, (mid) => list.find((m) => m.id === mid),
      (msg) => win.webContents.send('progress', msg));
    return { ok: true, done };
  } catch (e) { return { ok: false, error: e.message }; }
});

ipcMain.handle('catalog:uninstall', async (_e, id) => {
  const dir = gameDir();
  if (await game.isRunning()) return { ok: false, error: 'Close the game first.' };
  try { installer.uninstall(dir, id); return { ok: true }; } catch (e) { return { ok: false, error: e.message }; }
});

// ---------- installed mods ----------

ipcMain.handle('mods:scan', () => {
  const dir = gameDir();
  return game.isGameDir(dir) ? mods.scan(dir) : [];
});

// the update check, after the list is on screen (it needs the catalog): { [mod id]: { latest, outdated, catalogId } }
// for installed mods the catalog knows (recorded by the manager, or found where the catalog installs them); null offline
ipcMain.handle('mods:updates', async () => {
  const dir = gameDir();
  if (!game.isGameDir(dir)) return {};
  let list;
  try { list = catalog.status(dir, await getCatalog()); } catch { return null; }
  const out = {};
  for (const m of mods.scan(dir)) {
    const c = list.find((x) => x.id === m.catalogId
      || (x.detect && m.path && path.join(dir, x.detect.path).toLowerCase().startsWith(m.path.toLowerCase() + path.sep))
      || (x.id === 'ue4ss' && m.kind === 'ue4ss-loader'));
    if (c && c.installed) out[m.id] = { latest: c.version, outdated: c.outdated, catalogId: c.id };
  }
  return out;
});

ipcMain.handle('mods:setEnabled', async (_e, id, on) => {
  const dir = gameDir();
  const mod = mods.scan(dir).find((m) => m.id === id);
  if (!mod) return { ok: false, error: 'That mod is not installed any more.' };
  if ((mod.kind === 'pak' || mod.kind === 'ue4ss') && await game.isRunning()) {
    return { ok: false, error: 'Close the game first: it keeps its mods open while it runs.' };
  }
  return mods.setEnabled(dir, mod, on);
});

ipcMain.handle('open:url', (_e, url) => {
  if (/^https:\/\/(www\.)?nexusmods\.com\//.test(url) || /^https:\/\/github\.com\//.test(url)) shell.openExternal(url);
});
ipcMain.handle('open:folder', (_e, rel) => {
  const dir = gameDir();
  if (dir) shell.openPath(rel ? path.join(dir, rel) : dir);
});

// ---------- window ----------
function createWindow() {
  win = new BrowserWindow({
    width: 1280, height: 800, minWidth: 960, minHeight: 600,
    backgroundColor: '#07081a',
    title: 'MogHub Manager',
    icon: path.join(__dirname, '..', '..', 'build', 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  // MOGHUB_TAB (testing / screenshots): the tab to open on
  win.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'), { query: { tab: process.env.MOGHUB_TAB || '' } });
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());
