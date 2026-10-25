// Tests against a fake game folder: scanning every kind of mod, switching them, the ini editing and version compare.
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const game = require('../src/main/game');
const mods = require('../src/main/mods');
const { compareVersions } = require('../src/main/versions');
const installer = require('../src/main/install');

let failed = 0;
function test(name, fn) {
  try { fn(); console.log(`ok   ${name}`); } catch (e) { failed++; console.log(`FAIL ${name}\n     ${e.message}`); }
}

function touch(p, text = '') { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text); }

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'moghub-manager-test-'));
const p = game.paths(root);
touch(path.join(p.win64, 'FFRS-Win64-Shipping.exe'));
touch(path.join(p.win64, 'dwmapi.dll'));
touch(path.join(p.ue4ss, 'UE4SS.log'), '[x] UE4SS - v3.0.1 Beta #0 - Git SHA #1\n');
touch(path.join(p.mods, 'MogHub', 'Scripts', 'main.lua'));
touch(path.join(p.mods, 'MogHub', 'Scripts', 'kit', 'core.lua'), 'local kit = { VERSION = "0.1.0", plugins = {} }\n');
touch(path.join(p.mods, 'MogHub', 'enabled.txt'));
touch(path.join(p.mods, 'MogHub', 'config.ini'), '; MogHub settings\r\n\r\n[General]\r\nDebug = 0\r\n\r\n[Plugins]\r\n; plugins switched off\r\n');
touch(path.join(p.mods, 'MogHubTrainer', 'moghub.lua'));
touch(path.join(p.mods, 'MogHubTrainer', 'moghub.ini'), 'Name = MogHub Trainer\nVersion = 0.4.0\nAuthor = me\n');
touch(path.join(p.mods, 'BattlePace', 'Scripts', 'main.lua'));
touch(path.join(p.mods, 'BattlePace', 'enabled.txt'));
touch(path.join(p.mods, 'Listed', 'Scripts', 'main.lua'));
touch(path.join(p.mods, 'mods.txt'), 'Listed : 1\r\nOther : 0\r\n');
touch(path.join(p.mods, 'shared', 'types.lua'));
for (const f of ['FFRS-Windows.pak', 'FFRS-Windows.utoc', 'Extra_P.pak']) touch(path.join(p.paks, f));
for (const f of ['MRP_P.pak', 'MRP_P.utoc', 'MRP_P.ucas', 'Old_P.pak', 'zzz_MogHub_P.pak', 'zzz_MogHub_P.utoc']) touch(path.join(p.modPaks, f));
touch(path.join(p.modPaks, 'Sub', 'Off_P.pak.disabled'));
touch(path.join(p.modPaks, 'Sub', 'Off_P.utoc'));

test('the game folder is recognised', () => assert.ok(game.isGameDir(root)));

const byName = () => Object.fromEntries(mods.scan(root).map((m) => [m.name, m]));
test('scan finds every kind and leaves out the game, MogHub and libraries', () => {
  const s = byName();
  assert.deepStrictEqual(Object.keys(s).sort(),
    ['BattlePace', 'Extra_P', 'MogHub Trainer', 'Listed', 'MRP_P', 'MogHub', 'Off_P', 'Old_P', 'UE4SS'].sort());
  assert.strictEqual(s.UE4SS.version, '3.0.1');
  assert.strictEqual(s.MogHub.version, '0.1.0');
  assert.strictEqual(s.MogHub.pakInstalled, true);
  assert.strictEqual(s['MogHub Trainer'].version, '0.4.0');
  assert.strictEqual(s['MogHub Trainer'].on, true);
  assert.strictEqual(s.BattlePace.on, true);
  assert.strictEqual(s.Listed.on, true);
  assert.strictEqual(s.MRP_P.on, true);
  assert.deepStrictEqual(s.MRP_P.files, ['MRP_P.pak', 'MRP_P.utoc', 'MRP_P.ucas']);
  assert.strictEqual(s.Old_P.zen, false);
  assert.strictEqual(s.Off_P.on, false);
});

test('switching a plugin writes MogHub\'s [Plugins] section', () => {
  assert.ok(mods.setEnabled(root, byName()['MogHub Trainer'], false).ok);
  const text = fs.readFileSync(path.join(p.mods, 'MogHub', 'config.ini'), 'utf8');
  assert.match(text, /\[Plugins\]\r\n; plugins switched off\r\nMogHubTrainer = 0\r\n/);
  assert.match(text, /\[General\]\r\nDebug = 0/);
  assert.strictEqual(byName()['MogHub Trainer'].on, false);
  assert.ok(mods.setEnabled(root, byName()['MogHub Trainer'], true).ok);
  assert.strictEqual(byName()['MogHub Trainer'].on, true);
});

test('switching UE4SS mods uses enabled.txt and keeps mods.txt in step', () => {
  assert.ok(mods.setEnabled(root, byName().BattlePace, false).ok);
  assert.ok(!fs.existsSync(path.join(p.mods, 'BattlePace', 'enabled.txt')));
  assert.ok(mods.setEnabled(root, byName().Listed, false).ok);
  assert.match(fs.readFileSync(path.join(p.mods, 'mods.txt'), 'utf8'), /^Listed : 0\r$/m);
  assert.strictEqual(byName().Listed.on, false);
  assert.ok(mods.setEnabled(root, byName().Listed, true).ok);
  assert.strictEqual(byName().Listed.on, true);
});

test('switching paks renames only the .pak', () => {
  assert.ok(mods.setEnabled(root, byName().MRP_P, false).ok);
  assert.ok(fs.existsSync(path.join(p.modPaks, 'MRP_P.pak.disabled')));
  assert.ok(fs.existsSync(path.join(p.modPaks, 'MRP_P.utoc')));
  assert.ok(mods.setEnabled(root, byName().Off_P, true).ok);
  assert.ok(fs.existsSync(path.join(p.modPaks, 'Sub', 'Off_P.pak')));
});

test('registry entries mark scanned mods as installed from the catalog', () => {
  mods.saveRegistry(root, { mods: { 'nexus-37': { version: '1.0', name: 'MRP Multiplier',
    files: [path.join('FFRS', 'Content', 'Paks', '~mods', 'MRP_P.pak')] } } });
  mods.setEnabled(root, byName().MRP_P, true);
  assert.strictEqual(byName().MRP_P.catalogId, 'nexus-37');
  assert.strictEqual(byName().MRP_P.version, '1.0');
  mods.saveRegistry(root, { mods: {} });
});

test('installing copies folders and files by the rules, keeps the player\'s files, skips excluded ones', () => {
  const plugin = path.join(p.mods, 'MogHubBestiary');
  touch(path.join(plugin, 'config.ini'), 'mine');
  const src = new Map(Object.entries({
    'plugins/bestiary/runtime/MogHubBestiary/moghub.lua': 'code', 'plugins/bestiary/runtime/MogHubBestiary/moghub.ini': 'Version = 0.2.0',
    'plugins/bestiary/runtime/MogHubBestiary/config.ini': 'default', 'plugins/bestiary/runtime/MogHubBestiary/lang/en.ini': 'template',
    'plugins/bestiary/runtime/MogHubBestiary/lang/ja.ini': 'ja', 'plugins/bestiary/data/bestiary_data.lua': 'data', 'other/x.txt': 'no',
  }).map(([k, v]) => [k, () => Buffer.from(v)]));
  const mod = { name: 'MogHub Bestiary', install: [
    { from: 'plugins/bestiary/runtime/MogHubBestiary', to: 'FFRS/Binaries/Win64/ue4ss/Mods/MogHubBestiary' },
    { from: 'plugins/bestiary/data/bestiary_data.lua', to: 'FFRS/Binaries/Win64/ue4ss/Mods/MogHubBestiary/Scripts/bestiary_data.lua' } ],
    exclude: ['lang/en.ini'], keep: ['config.ini'], create: ['FFRS/Binaries/Win64/ue4ss/Mods/MogHubBestiary/flag.txt'] };
  const written = installer.installFrom(root, mod, src);
  assert.strictEqual(fs.readFileSync(path.join(plugin, 'config.ini'), 'utf8'), 'mine');
  assert.ok(!fs.existsSync(path.join(plugin, 'lang', 'en.ini')));
  assert.strictEqual(fs.readFileSync(path.join(plugin, 'lang', 'ja.ini'), 'utf8'), 'ja');
  assert.strictEqual(fs.readFileSync(path.join(plugin, 'Scripts', 'bestiary_data.lua'), 'utf8'), 'data');
  assert.ok(fs.existsSync(path.join(plugin, 'flag.txt')));
  assert.strictEqual(written.length, 5);   // moghub.lua, moghub.ini, ja.ini, bestiary_data.lua, flag.txt
});

test('versions compare part by part', () => {
  assert.strictEqual(compareVersions('1.0', '1.0.0'), 0);
  assert.strictEqual(compareVersions('1.10', '1.9'), 1);
  assert.strictEqual(compareVersions('v2', '1.9.9'), 1);
  assert.strictEqual(compareVersions('1.0', '1.0b'), -1);
  assert.strictEqual(compareVersions('0.3.0', '0.4.0'), -1);
});

fs.rmSync(root, { recursive: true, force: true });
console.log(failed ? `${failed} failed` : 'all passed');
process.exit(failed ? 1 : 0);
