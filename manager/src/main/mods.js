// Installed mods: UE4SS itself, MogHub and its plugins, other UE4SS mods and pak mods, and switching them on or off.
// The rules match MogHub's own list in the game (moghub/runtime/MogHub/Scripts/kit/others.lua), so both agree:
//   MogHub plugin: a folder in ue4ss\Mods with moghub.lua; off = "Folder = 0" under [Plugins] in MogHub\config.ini
//   UE4SS mod: a folder in ue4ss\Mods; on = enabled.txt in it, or "Name : 1" in ue4ss\Mods\mods.txt
//   pak mod: <name>.pak (+ .utoc / .ucas) in Content\Paks\~mods (or a subfolder, or Content\Paks); off = .pak.disabled
// Mods installed by the manager from its catalog are recorded in <game>\moghub-manager.json (catalog id, version, files).
const fs = require('fs');
const path = require('path');
const { paths } = require('./game');

const BASE_GAME_PAKS = new Set(['ffrs-windows', 'ffrs-windows_0_p', 'global']);
const OUR_PAKS = new Set(['zzz_moghub_9_p', 'zzz_moghub_p']);   // (1.0.0 named it zzz_MogHub_P)
const NOT_MODS = new Set(['shared', 'Keybinds']);
const REGISTRY = 'moghub-manager.json';

const exists = (p) => fs.existsSync(p);
const read = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
const dirs = (p) => { try { return fs.readdirSync(p, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort(byName); } catch { return []; } };
const files = (p) => { try { return fs.readdirSync(p, { withFileTypes: true }).filter((d) => d.isFile()).map((d) => d.name).sort(byName); } catch { return []; } };
function byName(a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : a.toLowerCase() > b.toLowerCase() ? 1 : 0; }

// key = value lines (sections ignored), as MogHub reads its ini files
function ini(text) {
  const out = {};
  for (const line of (text || '').replace(/^﻿/, '').split(/\r?\n/)) {
    const m = /^\s*([\w.-]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (m && !/^\s*[;#]/.test(line)) out[m[1]] = m[2];
  }
  return out;
}

// sets key = value under [section] of an ini file, keeping its layout (adds the section or the line when missing)
function iniSet(file, section, key, value) {
  const lines = (read(file) || '').split(/\r?\n/);
  let inSection = false, sectionEnd = -1, done = false;
  for (let i = 0; i < lines.length; i++) {
    const s = /^\s*\[(.+)\]\s*$/.exec(lines[i]);
    if (s) { if (inSection) break; inSection = s[1].trim().toLowerCase() === section.toLowerCase(); if (inSection) sectionEnd = i; continue; }
    if (!inSection) continue;
    if (lines[i].trim()) sectionEnd = i;
    const m = /^\s*([\w.-]+)\s*=/.exec(lines[i]);
    if (m && m[1] === key) { lines[i] = `${key} = ${value}`; done = true; break; }
  }
  if (!done) {
    if (sectionEnd >= 0) lines.splice(sectionEnd + 1, 0, `${key} = ${value}`);
    else { while (lines.length && !lines[lines.length - 1].trim()) lines.pop(); lines.push('', `[${section}]`, `${key} = ${value}`); }
  }
  fs.writeFileSync(file, lines.join('\r\n').replace(/(\r\n)*$/, '\r\n'));
}

// mods.txt: "Name : 1" lines
function modsTxt(p) {
  const out = {};
  for (const line of (read(path.join(p.mods, 'mods.txt')) || '').split(/\r?\n/)) {
    const m = /^\s*([^;#:][^:]*?)\s*:\s*(\d)\s*$/.exec(line);
    if (m) out[m[1]] = m[2] === '1';
  }
  return out;
}

function loadRegistry(gameDir) {
  try { return JSON.parse(fs.readFileSync(path.join(gameDir, REGISTRY), 'utf8')); } catch { return { mods: {} }; }
}
function saveRegistry(gameDir, reg) {
  fs.writeFileSync(path.join(gameDir, REGISTRY), JSON.stringify(reg, null, 2));
}

// the registry entry a scanned mod belongs to: the one whose files include the mod's main file
function registryEntry(reg, gameDir, mainFile) {
  const rel = path.relative(gameDir, mainFile).toLowerCase();
  for (const [key, e] of Object.entries(reg.mods || {})) {
    if ((e.files || []).some((f) => f.toLowerCase() === rel || rel.startsWith(f.toLowerCase().replace(/[\\/]$/, '') + path.sep))) return { key, ...e };
  }
  return null;
}

function scanPaks(out, dir, where) {
  const names = files(dir);
  const present = new Set(names.map((n) => n.toLowerCase()));
  for (const f of names) {
    let m = /^(.*)\.pak\.disabled$/i.exec(f);
    const disabled = !!m;
    if (!m) m = /^(.*)\.pak$/i.exec(f);
    if (!m) continue;
    const base = m[1];
    if (BASE_GAME_PAKS.has(base.toLowerCase()) || OUR_PAKS.has(base.toLowerCase())) continue;
    const parts = ['.pak', '.utoc', '.ucas', '.sig'].filter((e) => present.has((base + e).toLowerCase()) || (e === '.pak' && disabled)).map((e) => base + e);
    out.push({ kind: 'pak', id: `pak:${path.join(dir, base)}`, name: base, on: !disabled, path: path.join(dir, base + '.pak'),
      where, files: parts, zen: present.has(`${base}.utoc`.toLowerCase()) });
  }
}

// everything installed, in list order: UE4SS, MogHub, its plugins, other UE4SS mods, paks
function scan(gameDir) {
  const p = paths(gameDir);
  const reg = loadRegistry(gameDir);
  const out = [];
  // UE4SS's version: the first line of its log ("UE4SS - v3.0.1 Beta #0 ...")
  const ue4ssLog = /UE4SS - v([\d.]+)/.exec(read(path.join(p.ue4ss, 'UE4SS.log')) || '');
  out.push({ kind: 'ue4ss-loader', id: 'ue4ss', name: 'UE4SS', on: exists(path.join(p.win64, 'dwmapi.dll')) && exists(p.ue4ss),
    installed: exists(p.ue4ss), where: 'FFRS\\Binaries\\Win64', fixed: true, version: ue4ssLog ? ue4ssLog[1] : '' });
  const moghub = path.join(p.mods, 'MogHub');
  const hubConfig = ini(read(path.join(moghub, 'config.ini')));
  // MogHub's version: kit.VERSION in its core
  const hubVersion = /VERSION\s*=\s*"([^"]+)"/.exec(read(path.join(moghub, 'Scripts', 'kit', 'core.lua')) || '');
  out.push({ kind: 'moghub', id: 'moghub', name: 'MogHub', version: hubVersion ? hubVersion[1] : '',
    installed: exists(path.join(moghub, 'Scripts', 'main.lua')),
    on: exists(path.join(moghub, 'enabled.txt')), where: 'ue4ss\\Mods\\MogHub', path: moghub, fixed: true,
    pakInstalled: ['zzz_MogHub_9_P.utoc', 'zzz_MogHub_P.utoc'].some((f) => exists(path.join(p.modPaks, f))) });   // 1.0.0 named it zzz_MogHub_P
  const listed = modsTxt(p);
  const plugins = [], others = [];
  for (const folder of dirs(p.mods)) {
    const dir = path.join(p.mods, folder);
    if (folder === 'MogHub' || NOT_MODS.has(folder)) continue;
    if (exists(path.join(dir, 'moghub.lua'))) {
      const m = ini(read(path.join(dir, 'moghub.ini')));
      plugins.push({ kind: 'plugin', id: `plugin:${folder}`, name: m.Name || folder, folder, version: m.Version || '',
        author: m.Author || '', description: m.Description || '', path: dir, where: `ue4ss\\Mods\\${folder}`,
        on: hubConfig[folder] === undefined || !/^(0|false|no|off)$/i.test(hubConfig[folder]) });
    } else if (exists(path.join(dir, 'Scripts', 'main.lua')) || exists(path.join(dir, 'enabled.txt')) || folder in listed
               || exists(path.join(dir, 'dlls', 'main.dll'))) {
      others.push({ kind: 'ue4ss', id: `ue4ss:${folder}`, name: folder, path: dir, where: `ue4ss\\Mods\\${folder}`,
        on: exists(path.join(dir, 'enabled.txt')) || listed[folder] === true });
    }
  }
  const paks = [];
  scanPaks(paks, p.modPaks, 'Content\\Paks\\~mods');
  for (const sub of dirs(p.modPaks)) scanPaks(paks, path.join(p.modPaks, sub), `Content\\Paks\\~mods\\${sub}`);
  scanPaks(paks, p.paks, 'Content\\Paks');
  for (const m of [...plugins, ...others, ...paks]) {
    const e = registryEntry(reg, gameDir, m.path);
    if (e) { m.catalogId = e.key; if (!m.version) m.version = e.version; }
    out.push(m);
  }
  return out;
}

// switches a mod on or off; returns { ok } or { ok: false, error }. Pak and UE4SS changes need the game closed to be
// safe for every format (MogHub in the game can switch the new-format paks while playing).
function setEnabled(gameDir, mod, on) {
  const p = paths(gameDir);
  try {
    if (mod.kind === 'plugin') {
      iniSet(path.join(p.mods, 'MogHub', 'config.ini'), 'Plugins', mod.folder, on ? '1' : '0');
    } else if (mod.kind === 'ue4ss') {
      const flag = path.join(mod.path, 'enabled.txt');
      if (on) fs.writeFileSync(flag, ''); else fs.rmSync(flag, { force: true });
      const txt = path.join(p.mods, 'mods.txt');
      const text = read(txt);
      if (text && new RegExp(`^\\s*${mod.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:`, 'm').test(text)) {
        fs.writeFileSync(txt, text.replace(new RegExp(`^(\\s*${mod.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:\\s*)\\d`, 'm'), `$1${on ? 1 : 0}`));
      }
    } else if (mod.kind === 'pak') {
      const from = mod.path + (on ? '.disabled' : ''), to = mod.path + (on ? '' : '.disabled');
      fs.renameSync(from, to);
    } else {
      return { ok: false, error: 'This one is always on.' };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.code === 'EBUSY' || e.code === 'EPERM' ? 'The file is in use: close the game first.' : e.message };
  }
}

module.exports = { scan, setEnabled, loadRegistry, saveRegistry, ini, iniSet, REGISTRY };
