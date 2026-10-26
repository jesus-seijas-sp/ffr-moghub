"""Write the data file MogHub Logbook ships: IDs, conditions and string-table keys only, no game text.

Run from plugins/logbook:  python tools/export_data.py
Reads the game's tables, dumped with tools/ffr-dump (plugins/bestiary/tools/ffr-dump) into extracted/json/Datatable:
  Map/Gimmick/TreasureBox/   tree FFRS/Content/Datatable/Map/Gimmick/TreasureBox     (chests per map)
  Request/                   tree FFRS/Content/Datatable/Request                     (side quests)
  Scenario/                  tree FFRS/Content/Datatable/Scenario                    (chapter names)
  UI/Colosseum/              tree FFRS/Content/Datatable/UI/Colosseum                (Colosseum rank battles)
  Event/CollectMedal/        tree FFRS/Content/Datatable/Event/Data/CollectMedal     (tablet shard rewards)
and, from the Bestiary's dump (plugins/bestiary/extracted/json/Datatable), the map tables (Map/MapData, DT_MapIslandData)
and its data file's map -> area grouping, so areas are the same places in both plugins.
Chests and item spots placed in the levels (the save records both by their placement's unique id; item spots, the
sparkling pickups, have no table of their own), found with ffr-dump in extracted/placements:
  chestactors.jsonl          find FFRS/Content/Map/ .umap TreasureBox
  fielditems.jsonl           find FFRS/Content/Map/ .umap BP_MapGimmick_FieldItem
Writes data/logbook_data.json and data/logbook_data.lua:
  areas       list of {key, name [table, key], region, maps [ids], chests [{map, id, uid, item, num, gil, trap}],
              spots [{map, uid, item, num, gil, shard}]}, by region; each region starts with its world map ("Field")
  regions     region number -> island name [table, key]
  quests      list of {id, name, requester, region, accept, stages [{cond, goal}]}: conditions in the game's own
              syntax, evaluated at runtime with CPP_BFL_Condition:IsMeetCondition
  shards      {item, rewards [{num, cond, room}]}: tablet shards handed to the collector, and what each count unlocks
  colosseum   list of {id, name, rank, level, cond, locked}: rank battles; {colosseum:<id>}==3 means cleared
  chapters    chapter number -> name [table, key]
"""
import collections, glob, json, os, re, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'bestiary', 'tools'))
from lua_table import lua  # noqa: E402

DT = 'extracted/json/Datatable'
BDT = '../bestiary/extracted/json/Datatable'
BESTIARY = json.load(open('../bestiary/data/bestiary_data.json', encoding='utf8'))
MAP_NAMES = '/Game/Datatable/Strings/Map/ST_MAP_NAME.ST_MAP_NAME'
FIELD_NAME = ['/Game/Datatable/Strings/UI/UI_Common/ST_UI_QuestMenu.ST_UI_QuestMenu', 'QuestMapWorld']   # "Field"
WORLD_MAP = 1000
SHARD = 25004


def rows(path):
    d = json.load(open(path, encoding='utf8'))
    if isinstance(d, dict):
        return d.get('Rows', d)
    return next((e['Rows'] for e in d if 'Rows' in e), {})


def ref(t):
    return [t['TableId'], t['Key']] if t and t.get('TableId') and t.get('Key') else None


# ---------- areas: the Bestiary's grouping (maps sharing a display name are one area), with every map's chests ----------
maps = {}
for f in glob.glob(BDT + '/Map/MapData/DT_MapData_*.json'):
    for rk, v in rows(f).items():
        maps[v['ID']] = {'row': rk, 'type': v['MapType'].split('::')[-1], 'island': v.get('island', '').split('::')[-1]}
island_name = {v['IslandType'].split('::')[-1]: v['Name'].get('Key') for v in rows(BDT + '/Map/DT_MapIslandData.json').values()}
region_of_prefix = {}                                   # '01Gra' -> 1
for mid, m in maps.items():
    p = m['row'][:5]
    if re.fullmatch(r'\d\d[A-Z][a-z]{2}', p):
        region_of_prefix[p] = int(p[:2])

area_of = {int(k): v for k, v in BESTIARY['mapArea'].items()}


# ---------- placements: which map a level belongs to, chests' unique ids, item spots ----------
LEVEL = re.compile(r'(Dng|Town|Wld|Event)_\w+')
level_maps, row_map = collections.defaultdict(set), {}


def level_names(x, out):
    if isinstance(x, dict):
        for y in x.values():
            level_names(y, out)
    elif isinstance(x, list):
        for y in x:
            level_names(y, out)
    elif isinstance(x, str) and LEVEL.fullmatch(x.split('.')[-1]):
        out.add(x.split('.')[-1])


for f in glob.glob(BDT + '/Map/MapData/DT_MapData_*.json'):
    for rk, v in rows(f).items():
        row_map[rk] = v['ID']
        names = set()
        level_names(v, names)
        for n in names:
            level_maps[n].add(v['ID'])


def map_of(package):
    """the map a level package is part of: named in a map's level lists, or by its folder (Dng_01Gra_43_01_EV -> 01Gra_43)"""
    stem = package.rsplit('/', 1)[-1].rsplit('.', 1)[0]
    if stem.startswith('Wld_'):
        return WORLD_MAP
    ids = level_maps.get(stem)
    if ids and len(ids) == 1:
        return next(iter(ids))
    s = re.sub(r'_(EV|GD|BG|FG|SD)$', '', re.sub(r'^(Dng|Town|Event)_', '', stem))
    while s:
        if s in row_map:
            return row_map[s]
        if '_' not in s:
            return None
        s = s.rsplit('_', 1)[0]


def placements(name):
    path = 'extracted/placements/' + name
    return [json.loads(line) for line in open(path, encoding='utf8')] if os.path.exists(path) else []


chest_uid = {}                                          # (map, table id) -> unique id
loose = collections.defaultdict(list)                  # chests with their contents on the placement, no table row
                                                        # (Grandshelt Castle's upper floor holds its chests this way)
for r in placements('chestactors.jsonl'):
    p, t = r['obj']['Properties'], r['obj']['Properties'].get('m_TreasureBoxData')
    if p.get('m_IsOpen') and not t:
        continue                                        # chests placed already open: scenery
    if t:
        chest_uid[(t['mapId'], t['ID'])] = p.get('m_UniqueId', 0)
        continue
    mid = map_of(r['package'])
    if mid and mid != WORLD_MAP and not r['package'].split('.')[0].endswith('_EV'):   # (event scenes' props left out)
        loose[mid].append({'map': mid, 'id': p.get('m_Id', 0), 'uid': p.get('m_UniqueId', 0), 'item': p.get('m_ItemId', 0),
                           'num': p.get('m_ItemNum', 1), 'gil': p.get('m_Money', 0), 'trap': bool(p.get('m_IsTrap'))})

spots = collections.defaultdict(list)                   # map (or ('field', region)) -> item spots
for r in placements('fielditems.jsonl'):
    p = r['obj']['Properties']
    if p.get('VisibleCondition') or p.get('m_FlagCondition'):
        continue                                        # props of a story or quest scene, not pickups
    shard = r['type'].startswith('BP_MapGimmick_FieldItem_Medal')
    mid = map_of(r['package'])
    s = {'map': mid, 'uid': p['m_UniqueId'], 'item': SHARD if shard else p.get('m_ItemId', 0), 'num': p.get('m_ItemNum', 1),
         'gil': p.get('m_Money', 0), 'shard': shard}
    island = re.search(r'Wld_(\d\d)[A-Z]', r['package'])
    spots[('field', int(island.group(1))) if mid == WORLD_MAP and island else mid].append(s)
for l in spots.values():
    l.sort(key=lambda s: s['uid'])

chests = collections.defaultdict(list)
for f in sorted(glob.glob(DT + '/Map/Gimmick/TreasureBox/DT_*.json')):
    for v in rows(f).values():
        if v['ID'] < 0 or (v['mapId'], v['ID']) not in chest_uid:
            continue                                    # rows no level places (the save never records them)
        chests[v['mapId']].append({'map': v['mapId'], 'id': v['ID'], 'uid': chest_uid[(v['mapId'], v['ID'])],
                                   'item': v['ItemId'], 'num': v['ItemNum'], 'gil': v['Money'], 'trap': v['IsTrap']})
for mid, l in loose.items():
    have = {c['uid'] for c in chests[mid]}
    chests[mid] += [c for c in l if c['uid'] not in have]

areas = {}
for mid, m in maps.items():
    key = area_of.get(mid)
    if not key or not key.startswith('name:'):
        continue                                        # world map islands and unnamed stages: no chests of their own
    if m['type'] not in ('Town', 'Dungeon') and not chests.get(mid):
        continue
    region = int(m['row'][:2]) if m['row'][:2].isdigit() else 0
    a = areas.setdefault(key, {'key': key, 'name': [MAP_NAMES, key[5:]], 'region': region, 'maps': [], 'chests': [],
                               'spots': []})
    if region and (not a['region'] or region < a['region']):
        a['region'] = region
    a['maps'].append(mid)
for a in areas.values():
    a['maps'].sort()
    for mid in a['maps']:
        a['chests'] += sorted(chests.get(mid, []), key=lambda c: c['id'])
        a['spots'] += spots.get(mid, [])
# a region's name: the island its world-map area is (Bestiary islandArea keys are island:<MAP_NAME key>)
# (Grandshelt, Lanzelt and Kolobos share the name "Kingdom of Grandshelt": the runtime gives them one heading)
REGION_ISLAND = {1: 'Grandshelt', 2: 'Lanzelt', 3: 'Kolobos', 4: 'Dirnado', 5: 'Olderion', 6: 'Zoldaad',
                 7: 'MagiNationMysidia', 8: 'Gronoa', 9: 'Pharm', 10: 'LandOfTheCrystals'}
regions = {r: [MAP_NAMES, island_name[n]] for r, n in REGION_ISLAND.items() if island_name.get(n)}

# each island's world map ("Field"), listed first in its region: its item spots (the world map has no chests).
# Regions sharing a name share one Field entry, under the first of them.
fields = {}
for (_, region), l in sorted((k, l) for k, l in spots.items() if isinstance(k, tuple)):
    name = tuple(regions.get(region) or [region])
    f = fields.get(name)
    if not f:
        f = fields[name] = {'key': 'field:%d' % region, 'name': FIELD_NAME, 'region': region, 'maps': [WORLD_MAP],
                            'chests': [], 'spots': [], 'field': True}
        areas[f['key']] = f
    f['spots'] += l
area_list = sorted(areas.values(), key=lambda a: (a['region'] or 99, not a.get('field'), a['maps'][0]))
area_list = [a for a in area_list if a['region'] in regions]           # shared stages (battlefield, airship): none

# ---------- side quests ----------
quests = []
region_num = {n: r for r, n in REGION_ISLAND.items()}
region_num['Mysidia'] = 7                              # ERequestCategory names it without MagiNation
for v in sorted(rows(DT + '/Request/DT_RequestData.json').values(), key=lambda v: v['ID']):
    if not ref(v['Name']):
        continue
    cat = v['Category'].split('::')[-1]
    quests.append({
        'id': v['ID'], 'name': ref(v['Name']), 'requester': ref(v.get('Requester')), 'region': region_num.get(cat, 0),
        'accept': v.get('AcceptCondition') or '',
        'stages': [{'cond': p.get('Condition') or '', 'goal': ref(p.get('DestinationText'))} for p in v['ProgressList']],
    })
quests.sort(key=lambda q: (q['region'] or 99, q['id']))

# ---------- tablet shards ----------
shard_rows = rows(DT + '/Event/CollectMedal/DT_TalkEvent_CollectMedal.json')
shards = {'item': 25004, 'rewards': [{'num': v['Num'], 'cond': v['Condition'], 'room': ref(v.get('Text'))}
                                     for v in sorted(shard_rows.values(), key=lambda v: v['Num'])]}

# ---------- Colosseum ----------
colosseum = []
for f in glob.glob(DT + '/UI/Colosseum/RankBattle/DT_Colosseum_RankBattle_*.json'):
    for v in rows(f).values():
        colosseum.append({'id': v['ID'], 'name': ref(v['BattleName']), 'rank': v['Category'].split('::')[-1],
                          'level': v['RecommendedLevel'], 'cond': v.get('Condition') or '',
                          'locked': ref(v.get('UnopenedText'))})
colosseum.sort(key=lambda c: c['id'])

chapters = {v['ChapterNo']: ref(v['Name']) for v in rows(DT + '/Scenario/DT_ChapterData.json').values()}

out = {'gameBuild': 24250053, 'areas': area_list, 'regions': regions, 'quests': quests, 'shards': shards,
       'colosseum': colosseum, 'chapters': chapters}
os.makedirs('data', exist_ok=True)
json.dump(out, open('data/logbook_data.json', 'w', encoding='utf8'), indent=1, ensure_ascii=False)
with open('data/logbook_data.lua', 'w', encoding='utf8') as f:
    f.write('-- generated by tools/export_data.py from data/logbook_data.json; do not edit\nreturn ' + lua(out) + '\n')
print(f"{len(area_list)} areas ({sum(1 for a in area_list if a['chests'])} with chests, "
      f"{sum(len(a['chests']) for a in area_list)} chests, {sum(len(a['spots']) for a in area_list)} item spots, "
      f"{sum(s['shard'] for a in area_list for s in a['spots'])} of them tablet shards), {len(quests)} quests, {len(shards['rewards'])} shard rewards, "
      f"{len(colosseum)} Colosseum battles, {len(chapters)} chapters")
