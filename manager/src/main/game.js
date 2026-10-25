// The game: where it is installed (Steam libraries on Windows and Linux), which build it is, and whether it is running.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile, execFileSync } = require('child_process');

const APP_ID = '3259780';
const GAME_EXE = 'FFRS-Win64-Shipping.exe';
const EXE_REL = path.join('FFRS', 'Binaries', 'Win64', GAME_EXE);

// a game folder is the one holding FFRS\Binaries\Win64\FFRS-Win64-Shipping.exe
const isGameDir = (dir) => !!dir && fs.existsSync(path.join(dir, EXE_REL));

function steamRoots(platform = process.platform) {
  const roots = [];
  if (platform === 'win32') {
    for (const [key, value] of [['HKCU\\Software\\Valve\\Steam', 'SteamPath'],
      ['HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam', 'InstallPath'], ['HKLM\\SOFTWARE\\Valve\\Steam', 'InstallPath']]) {
      try {
        const out = execFileSync('reg', ['query', key, '/v', value], { windowsHide: true, encoding: 'utf8' });
        const m = /REG_SZ\s+(.+)/.exec(out);
        if (m) roots.push(path.normalize(m[1].trim()));
      } catch { /* not there */ }
    }
    roots.push('C:\\Program Files (x86)\\Steam');
  } else {
    const home = os.homedir();
    roots.push(path.join(home, '.steam', 'steam'), path.join(home, '.local', 'share', 'Steam'),
      path.join(home, '.var', 'app', 'com.valvesoftware.Steam', '.local', 'share', 'Steam'),
      path.join(home, 'snap', 'steam', 'common', '.local', 'share', 'Steam'));
  }
  return [...new Set(roots)].filter((r) => fs.existsSync(r));
}

// every Steam library folder: the "path" entries of steamapps/libraryfolders.vdf
function libraries(roots = steamRoots()) {
  const libs = new Set();
  for (const root of roots) {
    libs.add(root);
    try {
      const vdf = fs.readFileSync(path.join(root, 'steamapps', 'libraryfolders.vdf'), 'utf8');
      for (const m of vdf.matchAll(/"path"\s+"([^"]+)"/g)) libs.add(path.normalize(m[1].replace(/\\\\/g, '\\')));
    } catch { /* no file */ }
  }
  return [...libs];
}

// the game folder: the install dir its appmanifest names, in whichever library has it
function detect() {
  for (const lib of libraries()) {
    const manifest = path.join(lib, 'steamapps', `appmanifest_${APP_ID}.acf`);
    let dir = path.join(lib, 'steamapps', 'common', 'FINAL FANTASY RESONANCE');
    try {
      const m = /"installdir"\s+"([^"]+)"/.exec(fs.readFileSync(manifest, 'utf8'));
      if (m) dir = path.join(lib, 'steamapps', 'common', m[1]);
    } catch { /* no manifest: try the usual name */ }
    if (isGameDir(dir)) return dir;
  }
  return null;
}

// the installed Steam build id (from the appmanifest next to the game's library), or null
function buildId(gameDir) {
  const manifest = path.join(gameDir, '..', '..', `appmanifest_${APP_ID}.acf`);
  try { return /"buildid"\s+"(\d+)"/.exec(fs.readFileSync(manifest, 'utf8'))[1]; } catch { return null; }
}

// resolves true while the game runs (natively on Windows, or under Proton / Wine on Linux)
function isRunning(platform = process.platform) {
  return new Promise((resolve) => {
    if (platform === 'win32') {
      execFile('tasklist', ['/FI', `IMAGENAME eq ${GAME_EXE}`, '/NH', '/FO', 'CSV'], { windowsHide: true }, (err, out) => {
        resolve(!err && out.toLowerCase().includes(GAME_EXE.toLowerCase()));
      });
    } else {
      execFile('ps', ['-eo', 'args'], (err, out) => resolve(!err && out.includes(GAME_EXE)));
    }
  });
}

// the folders mods live in, from the game folder
function paths(gameDir) {
  const win64 = path.join(gameDir, 'FFRS', 'Binaries', 'Win64');
  return {
    game: gameDir,
    win64,
    ue4ss: path.join(win64, 'ue4ss'),
    mods: path.join(win64, 'ue4ss', 'Mods'),
    paks: path.join(gameDir, 'FFRS', 'Content', 'Paks'),
    modPaks: path.join(gameDir, 'FFRS', 'Content', 'Paks', '~mods'),
  };
}

module.exports = { APP_ID, GAME_EXE, isGameDir, steamRoots, libraries, detect, buildId, isRunning, paths };
