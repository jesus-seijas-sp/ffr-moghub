"""Adds the Libra+ fields (lua_table.unit_extras) to the existing data file, from DT_UnitParameter
alone - for when the full recon dump export_data.py reads isn't at hand. export_data.py writes the same fields.

usage (from plugins/bestiary): python tools/add_unit_extras.py
  needs extracted/json/Datatable/Unit/DT_UnitParameter.json:
  tools/ffr-dump json FFRS/Content/Datatable/Unit/DT_UnitParameter.DT_UnitParameter extracted/json/Datatable/Unit/DT_UnitParameter.json
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lua_table import unit_extras, write_lua  # noqa: E402

table = json.load(open('extracted/json/Datatable/Unit/DT_UnitParameter.json', encoding='utf8'))
rows = next(e['Rows'] for e in table if 'Rows' in e) if isinstance(table, list) else table['Rows']
by_id = {str(v['ID']): v for v in rows.values()}
data = json.load(open('data/bestiary_data.json', encoding='utf8'))
n = 0
for uid, stats in data['stats'].items():
    if uid in by_id:
        stats.pop('boss', None)
        stats.update(unit_extras(by_id[uid]))
        n += 1
json.dump(data, open('data/bestiary_data.json', 'w', encoding='utf8'), indent=1)
write_lua(data)
print(f'{n} of {len(data["stats"])} units updated; wrote data/bestiary_data.json and .lua')
