"""Each area's enemy level range, from its random encounters (what you meet walking around, bosses left out): the
level range MogHub Bestiary shows in an area's panel.

An area's random encounters are its maps' encounter tables, DT_<map row>_<n>_Encount (rows: battle group ids), and on
the world map DT_<region>_Wld_..._Encount for the island the region is on. Battle groups list their units
(DT_BattleGroup), units have a level (DT_UnitParameter).

Used by export_data.py; run on its own (from plugins/bestiary) to add the ranges to the existing data file:
  python tools/area_levels.py
Needs, under extracted/json/Datatable (tools/ffr-dump tree FFRS/Content/Datatable/<dir> extracted/json/Datatable/<dir>):
  Encount/ (every table), Map/MapData/, Map/DT_MapIslandData.json, Unit/DT_UnitParameter.json
"""
import glob
import json
import os
import re
import sys

DT = 'extracted/json/Datatable'


def rows(path):
    d = json.load(open(path, encoding='utf8'))
    if isinstance(d, dict):
        return d.get('Rows', d)
    return next(e['Rows'] for e in d if 'Rows' in e)


def table_area(name, map_ids, map_area, region_area):
    """the area an encounter table belongs to, from its name: 01Gra_41_01, Dng_04Dir_41_2, 05Old_Dng_43 and
    02Lan_Dng_40_01 are map rows <region>_<map>; <region>_Wld_... is the region's island; Bounty tables (special
    fights) and anything else unrecognised: None"""
    tokens = name.split('_')
    region = next((t for t in tokens if re.fullmatch(r'\d\d[A-Z][a-z]+', t)), None)
    if not region or 'Bounty' in tokens:
        return None
    rest = tokens[tokens.index(region) + 1:]
    if 'Wld' in rest:
        return region_area.get(region)
    number = next((t for t in rest if re.fullmatch(r'\d\d', t)), None)
    mid = map_ids.get(region + '_' + number) if number else None
    if mid is not None:
        return map_area.get(str(mid))
    # a floor number with no map row of its own (10Cry_Dng_01: Crystal Tower floors): the region's area, when all
    # of the region's maps are one area
    areas = {map_area.get(str(i)) for k, i in map_ids.items() if re.fullmatch(region + r'_\d\d', k)} - {None}
    return areas.pop() if len(areas) == 1 else None


def area_levels(dt, map_area):
    """{area key: [min level, max level]}; map_area: map id (str) -> area key, as in the data file"""
    units = {v['ID']: v for v in rows(dt + '/Unit/DT_UnitParameter.json').values()}
    groups = {v['ID']: v['UnitIdList'] for v in rows(dt + '/Encount/DT_BattleGroup.json').values()}
    map_ids = {}
    world = None
    for f in glob.glob(dt + '/Map/MapData/DT_MapData_*.json'):
        for key, v in rows(f).items():
            map_ids[key] = v['ID']
            if v.get('worldMapIslandLevelList'):
                world = v
    island_name = {v['IslandType']: v['Name'].get('Key') for v in rows(dt + '/Map/DT_MapIslandData.json').values()}
    region_area = {}                                    # '04Dir' -> 'island:MAP_NAME_004'
    for isl in (world or {}).get('worldMapIslandLevelList') or []:
        for sub in isl['subLevelNameList']:
            m = re.match(r'Wld_(\d\d[A-Za-z]+)_', sub)
            if m and island_name.get(isl['IslandType']):
                region_area.setdefault(m.group(1), 'island:' + island_name[isl['IslandType']])

    levels = {}
    for f in glob.glob(dt + '/Encount/*/DT_*_Encount.json'):
        area = table_area(os.path.basename(f)[3:-len('_Encount.json')], map_ids, map_area, region_area)
        if not area:
            continue
        for r in rows(f).values():
            if not r.get('encountRatio'):
                continue
            for uid in groups.get(r['battleGroupId'], []):
                u = units.get(uid)
                if not u or u.get('IsBoss') or u.get('Category') == 'eUnitCategory::Boss':
                    continue
                lv = u['Level']
                lo, hi = levels.get(area, (lv, lv))
                levels[area] = [min(lo, lv), max(hi, lv)]
    return dict(sorted(levels.items()))


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from lua_table import write_lua
    data = json.load(open('data/bestiary_data.json', encoding='utf8'))
    data['areaLevel'] = area_levels(DT, data['mapArea'])
    json.dump(data, open('data/bestiary_data.json', 'w', encoding='utf8'), indent=1)
    write_lua(data)
    listed = set(data['areaOrder'])
    print(f"{len(data['areaLevel'])} areas with random encounters ({len(listed & set(data['areaLevel']))} of the "
          f"{len(listed)} listed areas); wrote data/bestiary_data.json and .lua")
