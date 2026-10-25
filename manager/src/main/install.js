// Installing, updating and uninstalling catalog mods.
//   source github           the repository's archive (codeload.github.com), then the entry's folders out of it
//   source github-release   a release asset (a zip), all of it
//   install [{ from, to }]  from: a folder or file inside the source ('' = all of it); to: relative to the game folder
//   exclude                 paths (relative to a from folder) not installed
//   keep                    paths (relative to a to folder) the player owns: never overwritten (config.ini, saves)
//   create                  empty files to create (MogHub's enabled.txt)
//   iniSet                  ini values to set afterwards (UE4SS's engine version)
// What was installed is recorded in <game>\moghub-manager.json, so an uninstall removes exactly those files.
const fs = require('fs');
const path = require('path');
const unzip = require('./unzip');
const { loadRegistry, saveRegistry, iniSet } = require('./mods');

async function download(url, what) {
  const res = await fetch(url, { headers: { 'User-Agent': 'MogHub-Manager' } });
  if (!res.ok) throw new Error(`${what} could not be downloaded (${res.status})`);
  return Buffer.from(await res.arrayBuffer());
}

// the files of a source: Map(path inside the source -> () => Buffer), downloaded once per call of sourceFiles
const archives = new Map();           // repository archives within one install (several mods share ffr-moghub)
async function sourceFiles(source, progress) {
  if (source.type === 'github') {
    const key = `${source.repo}@${source.ref}`;
    if (!archives.has(key)) {
      progress(`Downloading ${source.repo}…`);
      const zip = await download(`https://codeload.github.com/${source.repo}/zip/refs/heads/${source.ref}`, source.repo);
      archives.set(key, zip);
    }
    const files = new Map();
    for (const e of unzip.entries(archives.get(key))) {
      if (e.isDir) continue;
      const inner = e.name.replace(/^[^/]+\//, '');         // the archive's top folder: <repo>-<ref>/
      files.set(inner, e.data);
    }
    return files;
  }
  if (source.type === 'github-release') {
    progress(`Looking for ${source.repo}'s release…`);
    const res = await fetch(`https://api.github.com/repos/${source.repo}/releases/tags/${source.tag}`, { headers: { 'User-Agent': 'MogHub-Manager' } });
    if (!res.ok) throw new Error(`${source.repo}'s release could not be read (${res.status})`);
    const asset = (await res.json()).assets.find((a) => new RegExp(source.asset).test(a.name));
    if (!asset) throw new Error(`${source.repo}'s release has no file matching ${source.asset}`);
    progress(`Downloading ${asset.name}…`);
    const files = new Map();
    for (const e of unzip.entries(await download(asset.browser_download_url, asset.name))) if (!e.isDir) files.set(e.name, e.data);
    return files;
  }
  throw new Error('This mod is not available for automatic install: get it from its page.');
}

const norm = (p) => p.replace(/\\/g, '/').replace(/^\/+|\/+$/g, '');
const under = (p, dir) => !dir || p === dir || p.startsWith(dir + '/');

// installs one mod (not its requirements); returns the list of files written, relative to the game folder
async function installOne(gameDir, mod, progress) {
  return installFrom(gameDir, mod, await sourceFiles(mod.source, progress), progress);
}

// the copying part of installOne, from the source's files: Map(path inside the source -> () => Buffer)
function installFrom(gameDir, mod, files, progress = () => {}) {
  const written = [];
  const exclude = (mod.exclude || []).map(norm), keep = (mod.keep || []).map(norm);
  progress(`Installing ${mod.name}…`);
  for (const rule of mod.install) {
    const from = norm(rule.from), to = norm(rule.to);
    let matched = 0;
    for (const [inner, data] of files) {
      if (!under(inner, from)) continue;
      const rel = from && inner !== from ? inner.slice(from.length + 1) : (inner === from ? path.posix.basename(inner) : inner);
      if (exclude.some((x) => under(rel, x))) continue;
      // a file rule ("from" is the file itself) installs to "to" as the file's own path
      const dest = inner === from ? path.join(gameDir, to) : path.join(gameDir, to, rel);
      matched++;
      if (keep.some((k) => under(rel, k)) && fs.existsSync(dest)) continue;   // the player's own: left alone
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(dest, data());
      written.push(path.relative(gameDir, dest));
    }
    if (!matched) throw new Error(`${mod.name}: nothing found at "${rule.from}" in its source`);
  }
  for (const c of mod.create || []) {
    const dest = path.join(gameDir, c);
    if (!fs.existsSync(dest)) { fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, ''); }
    written.push(path.relative(gameDir, dest));
  }
  for (const s of mod.iniSet || []) iniSet(path.join(gameDir, s.file), s.section, s.key, s.value);
  return written;
}

// installs or updates a mod and, first, any requirement that isn't installed yet; `statusOf(id)` gives a catalog
// entry with its state (catalog.status)
async function install(gameDir, id, statusOf, progress = () => {}) {
  archives.clear();
  const done = [];
  const visit = async (modId, asRequirement) => {
    const mod = statusOf(modId);
    if (!mod) throw new Error(`"${modId}" is not in the mod list`);
    if (asRequirement && mod.installed) return;
    for (const req of mod.requires || []) await visit(req, true);
    const written = await installOne(gameDir, mod, progress);
    const reg = loadRegistry(gameDir);
    const before = (reg.mods[mod.id] || {}).files || [];
    // files the previous version had and this one doesn't: removed (unless the player owns them)
    for (const f of before) {
      if (!written.includes(f) && fs.existsSync(path.join(gameDir, f))) fs.rmSync(path.join(gameDir, f), { force: true });
    }
    reg.mods[mod.id] = { name: mod.name, version: mod.version, source: mod.source, files: written, installedAt: new Date().toISOString() };
    saveRegistry(gameDir, reg);
    done.push(`${mod.name} ${mod.version}`);
  };
  await visit(id, false);
  archives.clear();
  return done;
}

// removes what the manager installed for a mod (files the player made, like config.ini, stay)
function uninstall(gameDir, id) {
  const reg = loadRegistry(gameDir);
  const entry = reg.mods[id];
  if (!entry) throw new Error('This mod was not installed by MogHub Manager: remove it by hand.');
  const dirs = new Set();
  for (const f of entry.files) {
    const p = path.join(gameDir, f);
    fs.rmSync(p, { force: true });
    for (let d = path.dirname(p); d.startsWith(gameDir) && d !== gameDir; d = path.dirname(d)) dirs.add(d);
  }
  // folders left empty, deepest first
  for (const d of [...dirs].sort((a, b) => b.length - a.length)) {
    try { if (!fs.readdirSync(d).length) fs.rmdirSync(d); } catch { /* not empty or gone */ }
  }
  delete reg.mods[id];
  saveRegistry(gameDir, reg);
}

module.exports = { install, uninstall, installOne, installFrom };
