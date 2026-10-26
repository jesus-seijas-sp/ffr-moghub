using Newtonsoft.Json.Linq;
using UAssetAPI;
using UAssetAPI.ExportTypes;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

// hide-pak: a widget of the game hidden for good, as a standalone pak (no UE4SS) - the Field Kit's "Hide key guide"
// for players who want only that.
//   hide-pak dump <asset.uasset> --usmap <Mappings.usmap>                  exports, their class and properties
//   hide-pak hide <legacyRoot> <outRoot> <rel> <exports> --usmap <file>    sets each export's Visibility to Collapsed
//                                                                          (<exports>: names separated by commas)
// <legacyRoot> holds the asset extracted with `retoc to-legacy`; the edited copy is written under <outRoot> at the
// same path, ready for `retoc to-zen`. Based on menu-pak (moghub/tools).
static class Program
{
    static int Main(string[] argv)
    {
        var args = argv.ToList();
        int u = args.IndexOf("--usmap");
        if (u < 0 || u + 1 >= args.Count) return Usage();
        var map = new Usmap(args[u + 1]);
        args.RemoveRange(u, 2);
        if (args.Count == 2 && args[0] == "dump") return Dump(args[1], map);
        if (args.Count == 2 && args[0] == "json") { Console.WriteLine(new UAsset(args[1], EngineVersion.VER_UE5_6, map).SerializeJson(true)); return 0; }
        if (args.Count == 5 && args[0] == "hide") return Hide(args[1], args[2], args[3], args[4], map);
        return Usage();
    }

    static int Usage()
    {
        Console.Error.WriteLine("usage: hide-pak dump <asset> --usmap <file> | hide-pak hide <legacyRoot> <outRoot> <rel> <export> --usmap <file>");
        return 2;
    }

    static int Dump(string path, Usmap map)
    {
        var asset = new UAsset(path, EngineVersion.VER_UE5_6, map);
        for (int i = 0; i < asset.Exports.Count; i++)
        {
            var e = asset.Exports[i];
            string cls = e.GetExportClassType().ToString();
            string outer = e.OuterIndex.IsExport() ? e.OuterIndex.ToExport(asset).ObjectName.ToString() : "-";
            string props = e is NormalExport n ? string.Join(", ", n.Data.Select(p => p.Name.ToString() + "=" + Short(p.RawValue))) : "";
            Console.WriteLine($"{i + 1,3} {e.ObjectName} [{cls}] in {outer}: {props}");
        }
        return 0;
    }

    static string Short(object? v)
    {
        var s = v?.ToString() ?? "null";
        return s.Length > 40 ? s[..40] + "..." : s;
    }

    static int Hide(string inRoot, string outRoot, string rel, string exportNames, Usmap map)
    {
        var asset = new UAsset(Path.Combine(inRoot, rel + ".uasset"), EngineVersion.VER_UE5_6, map);
        var doc = JObject.Parse(asset.SerializeJson(false));
        AddNames(doc, "Visibility");
        foreach (var exportName in exportNames.Split(','))
        {
            var export = doc["Exports"]!.FirstOrDefault(e => (string?)e["ObjectName"] == exportName)
                         ?? throw new Exception($"no export {exportName}");
            Collapse((JArray)export["Data"]!);
        }
        var edited = UAsset.DeserializeJson(doc.ToString());
        edited.Mappings = map;
        var path = Path.Combine(outRoot, rel + ".uasset");
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        edited.Write(path);
        Console.WriteLine($"wrote {path}: {exportNames} collapsed");
        return 0;
    }

    static void Collapse(JArray data)
    {
        data.Where(p => (string?)p["Name"] == "Visibility").ToList().ForEach(p => p.Remove());
        data.Add(new JObject                              // TEnumAsByte<ESlateVisibility>: a byte, Collapsed = 1
        {
            ["$type"] = "UAssetAPI.PropertyTypes.Objects.BytePropertyData, UAssetAPI",
            ["ByteType"] = "Byte",
            ["EnumType"] = null,
            ["Value"] = 1,
            ["Name"] = "Visibility",
            ["ArrayIndex"] = 0,
            ["PropertyGuid"] = null,
            ["IsZero"] = false,
            ["PropertyTagFlags"] = "None",
            ["PropertyTypeName"] = null,
            ["PropertyTagExtensions"] = "NoExtension",
        });
    }

    // New names must sit inside the first NamesReferencedFromExportDataCount entries: retoc drops the names after
    // that block when it converts to the game's zen format (see menu-pak).
    static void AddNames(JObject d, params string[] names)
    {
        var map = (JArray)d["NameMap"]!;
        foreach (var n in names)
        {
            if (map.Any(x => (string?)x == n)) continue;
            int at = (int)d["NamesReferencedFromExportDataCount"]!;
            map.Insert(at, n);
            d["NamesReferencedFromExportDataCount"] = at + 1;
        }
    }
}
