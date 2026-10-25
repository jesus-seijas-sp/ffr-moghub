# The mod catalog

`catalog.json` is the list of mods [MogHub Manager](https://github.com/jesus-seijas-sp/moghub-manager) offers: only the
mods listed here can be installed and updated from it. The manager reads it from this repository's `main` branch.

Refresh the latest versions from time to time, then commit and push:

```sh
node tools/update_catalog.js           # --check: report only
```

## An entry

| Field | What it is |
|---|---|
| `id`, `name`, `author`, `description`, `homepage` | Shown in the manager. `id` never changes (installs are recorded by it) |
| `kind` | `loader`, `framework`, `plugin`, `ue4ss` or `pak` |
| `version` | The latest version (written by `update_catalog.js`) |
| `source` | Where it comes from: `{ "type": "github", "repo": "owner/name", "ref": "main" }` (a folder of a repository), `{ "type": "github-release", "repo", "tag", "asset": "<regex>" }` (a release zip), or `{ "type": "nexus", "game", "modId" }` (listed with its page; not installed by the manager yet) |
| `requires` | Ids installed first when missing (`["moghub"]`) |
| `install` | `[{ "from": "<path in the source>", "to": "<path in the game folder>" }]`. `from` is a folder (its contents go into `to`) or a file (`to` is then the file's path); `""` is the whole source |
| `exclude` | Paths inside a `from` folder that are not installed (`lang/en.ini`, a template) |
| `keep` | Paths inside a `to` folder the player owns: never overwritten on update (`config.ini`, `saves`) |
| `create` | Empty files to create (MogHub's `enabled.txt`) |
| `iniSet` | `[{ "file", "section", "key", "value" }]` set after installing (UE4SS's engine version) |
| `detect` | `{ "path" }`: a file that shows the mod is installed (also when installed by hand) |
| `localVersion` | How to read the installed version: `{ "ini", "key" }` or `{ "file", "pattern" }` (regex, first group) |
| `versionFrom` | How `update_catalog.js` finds the latest version: `{ "ini", "key" }` / `{ "file", "pattern" }` (in this repository), `{ "asset": "<regex>" }` (the release asset's name), or `{ "nexus": true }` |

Uninstalling removes exactly the files the manager installed (recorded in `moghub-manager.json` in the game folder);
files the mod or the player created, such as `config.ini` and saves, stay.
