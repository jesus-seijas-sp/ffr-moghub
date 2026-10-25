// Refreshes the latest version of every mod in catalog/catalog.json - run it from time to time, then commit:
//   versionFrom.file + pattern / ini + key   a file of this repository (what a GitHub install downloads from main)
//   versionFrom.asset                        the release asset's name (github-release sources)
//   versionFrom.nexus                        the mod's version on Nexus Mods (public API, no account needed)
// usage (from the repository root): node tools/update_catalog.js [--check]   (--check: report only, write nothing)
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const CATALOG = path.join(ROOT, 'catalog', 'catalog.json');
const check = process.argv.includes('--check');

function iniValue(text, key) {
  const m = new RegExp(`^\\s*${key}\\s*=\\s*(.*?)\\s*$`, 'm').exec(text);
  return m ? m[1] : null;
}

async function fromRepo(v) {
  const text = fs.readFileSync(path.join(ROOT, v.file || v.ini), 'utf8');
  if (v.ini) return iniValue(text, v.key);
  const m = new RegExp(v.pattern).exec(text);
  return m ? m[1] : null;
}

async function fromRelease(mod) {
  const { repo, tag, asset } = mod.source;
  const res = await fetch(`https://api.github.com/repos/${repo}/releases/tags/${tag}`, { headers: { 'User-Agent': 'moghub-catalog' } });
  if (!res.ok) throw new Error(`GitHub answered ${res.status}`);
  const release = await res.json();
  const file = release.assets.find((a) => new RegExp(asset).test(a.name));
  if (!file) throw new Error('no release asset matches ' + asset);
  const m = new RegExp(mod.versionFrom.asset).exec(file.name);
  return m ? m[1] : null;
}

// every mod's version on Nexus Mods for a game, fetched once per run: { game: Map(modId -> version) }
const nexusVersions = {};
async function fromNexus(mod) {
  const { game, modId } = mod.source;
  if (!nexusVersions[game]) {
    const versions = new Map();
    for (let offset = 0; ; offset += 50) {
      const query = `query { mods(filter: { gameDomainName: [{ value: "${game}" }] }, count: 50, offset: ${offset}) { totalCount nodes { modId version } } }`;
      const res = await fetch('https://api.nexusmods.com/v2/graphql', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Application-Name': 'MogHub catalog' },
        body: JSON.stringify({ query }),
      });
      if (!res.ok) throw new Error(`Nexus Mods answered ${res.status}`);
      const { mods } = (await res.json()).data;
      for (const n of mods.nodes) versions.set(n.modId, n.version);
      if (mods.nodes.length < 50 || versions.size >= mods.totalCount) break;
    }
    nexusVersions[game] = versions;
  }
  if (!nexusVersions[game].has(modId)) throw new Error(`mod ${modId} not found on Nexus Mods`);
  return nexusVersions[game].get(modId);
}

(async () => {
  const catalog = JSON.parse(fs.readFileSync(CATALOG, 'utf8'));
  let changed = 0, failed = 0;
  for (const mod of catalog.mods) {
    const v = mod.versionFrom || {};
    try {
      const latest = v.nexus ? await fromNexus(mod) : v.asset ? await fromRelease(mod) : (v.file || v.ini) ? await fromRepo(v) : null;
      if (!latest) { console.log(`?  ${mod.id}: no version found`); failed++; continue; }
      if (latest !== mod.version) {
        console.log(`*  ${mod.id}: ${mod.version} -> ${latest}`);
        mod.version = latest;
        changed++;
      } else {
        console.log(`   ${mod.id}: ${latest}`);
      }
    } catch (e) {
      console.log(`!  ${mod.id}: ${e.message}`);
      failed++;
    }
  }
  if (changed && !check) {
    catalog.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(CATALOG, JSON.stringify(catalog, null, 2) + '\n');
    console.log(`${changed} version(s) updated in catalog/catalog.json: commit and push it.`);
  } else {
    console.log(changed ? `${changed} version(s) would change.` : 'Every version is current.');
  }
  process.exit(failed ? 1 : 0);
})();
