// The catalog: the mods MogHub Manager offers, kept in the ffr-moghub repository (catalog/catalog.json) with each mod's
// source, install rules and latest version (tools/update_catalog.js refreshes the versions). Here: fetching it and
// working out each mod's state in a game folder.
const fs = require('fs');
const path = require('path');
const { compareVersions } = require('./versions');
const { loadRegistry } = require('./mods');

const URL = 'https://raw.githubusercontent.com/jesus-seijas-sp/ffr-moghub/main/catalog/catalog.json';

// the catalog: from MOGHUB_CATALOG (a local file, for development) or the repository
async function fetchCatalog() {
  if (process.env.MOGHUB_CATALOG) return JSON.parse(fs.readFileSync(process.env.MOGHUB_CATALOG, 'utf8'));
  const res = await fetch(URL, { cache: 'no-store' });
  if (!res.ok) throw new Error(`the mod list could not be read (GitHub answered ${res.status})`);
  return res.json();
}

const read = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };

// the version installed in the game folder, from the entry's localVersion rule (or what the manager recorded)
function localVersion(gameDir, mod, reg) {
  const lv = mod.localVersion;
  if (lv && lv.ini) {
    const m = new RegExp(`^\\s*${lv.key}\\s*=\\s*(.*?)\\s*$`, 'm').exec(read(path.join(gameDir, lv.ini)) || '');
    if (m) return m[1];
  } else if (lv && lv.file) {
    const m = new RegExp(lv.pattern).exec(read(path.join(gameDir, lv.file)) || '');
    if (m) return m[1];
  }
  return reg.mods[mod.id] ? reg.mods[mod.id].version : null;
}

// each catalog mod with its state: installed, local version, outdated, and whether the manager can install it
function status(gameDir, catalog) {
  const reg = loadRegistry(gameDir);
  return catalog.mods.map((mod) => {
    const installed = !!reg.mods[mod.id] || (mod.detect && fs.existsSync(path.join(gameDir, mod.detect.path)));
    const local = installed ? localVersion(gameDir, mod, reg) : null;
    return {
      ...mod,
      installed,
      managed: !!reg.mods[mod.id],                         // installed by the manager: it can uninstall it
      local,
      outdated: installed && !!local && !!mod.version && compareVersions(local, mod.version) < 0,
      installable: mod.source.type === 'github' || mod.source.type === 'github-release',
    };
  });
}

module.exports = { URL, fetchCatalog, status, localVersion };
