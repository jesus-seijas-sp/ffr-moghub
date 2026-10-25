using Newtonsoft.Json.Linq;
using UAssetAPI;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

// menu-pak: adds MogHub's scene rows to the game's main-menu table and registers their gameplay tags.
//   menu-pak <legacyRoot> <outRoot> --usmap <Mappings.usmap>
// <legacyRoot> holds the two tables extracted with `retoc to-legacy`; the edited copies are written under <outRoot>
// at the same paths, ready for `retoc to-zen`. Rows: "Mods" (MogHub's own screen) and MogHub1..3 (spare entries plugins
// claim at run time; their names are set by MogHub). Each opens the game's Help layout, which MogHub rebuilds.
// Based on uasset-json from FFR Bestiary by Law19902 (MIT).
static class Program
{
    const string MENU_TABLE = "FFRS/Content/UI/MainMenu/Data/DT_MainMenuScene";
    const string TAG_TABLE = "FFRS/Plugins/DebugMenuWidget/Content/Data/GameplayTag/DM_DT_GameplayTag_Option";
    const string LAYOUT = "/Game/UI/MainMenu/Help/Widget/WBP_HelpLayout.WBP_HelpLayout_C";
    // must match runtime/MogHub/Scripts/kit/menu.lua
    static readonly (string Row, string Tag, string Name)[] ROWS = {
        ("MogHub_Mods", "UI.MainMenu.Scene.Mods", "Mods"),
        ("MogHub_1", "UI.MainMenu.Scene.MogHub1", "Mod 1"),
        ("MogHub_2", "UI.MainMenu.Scene.MogHub2", "Mod 2"),
        ("MogHub_3", "UI.MainMenu.Scene.MogHub3", "Mod 3"),
    };

    static int Main(string[] argv)
    {
        var args = argv.ToList();
        int u = args.IndexOf("--usmap");
        if (u < 0 || u + 1 >= args.Count) { Console.Error.WriteLine("usage: menu-pak <legacyRoot> <outRoot> --usmap <file>"); return 2; }
        var map = new Usmap(args[u + 1]);
        args.RemoveRange(u, 2);
        if (args.Count != 2) { Console.Error.WriteLine("usage: menu-pak <legacyRoot> <outRoot> --usmap <file>"); return 2; }
        Edit(args[0], args[1], MENU_TABLE, map, AddMenuRows);
        Edit(args[0], args[1], TAG_TABLE, map, AddTagRows);
        return 0;
    }

    static void Edit(string inRoot, string outRoot, string rel, Usmap map, Action<JObject> change)
    {
        var asset = new UAsset(Path.Combine(inRoot, rel + ".uasset"), EngineVersion.VER_UE5_6, map);
        var doc = JObject.Parse(asset.SerializeJson(false));
        change(doc);
        var edited = UAsset.DeserializeJson(doc.ToString());
        edited.Mappings = map;
        var path = Path.Combine(outRoot, rel + ".uasset");
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        edited.Write(path);
        Console.WriteLine($"wrote {path}");
    }

    static JArray Rows(JObject d) => (JArray)d["Exports"]!.First(e => e["Table"] != null)["Table"]!["Data"]!;
    static JObject Prop(JToken parent, string name) => (JObject)parent["Value"]!.First(p => (string?)p["Name"] == name);
    static string Tag(JToken row) => (string)Prop(Prop(row, "SceneTag"), "TagName")["Value"]!;

    // New names must sit inside the first NamesReferencedFromExportDataCount entries: retoc drops the names after
    // that block (they are only used by the import table) when it converts to the game's zen format.
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

    static void LiteralText(JObject p, string key, string text)
    {
        p["HistoryType"] = "Base"; p["TableId"] = null; p["Namespace"] = "MogHub"; p["Value"] = key;
        p["CultureInvariantString"] = text;
    }

    // a copy of the Journal row for each of ours: our tag and name, the Help layout, no open hotkey, always enabled,
    // inserted before System (the menu shows the entries the kit puts in DisplaySceneList, in that order)
    static void AddMenuRows(JObject d)
    {
        var table = Rows(d);
        var template = table.First(r => Tag(r) == "UI.MainMenu.Scene.Journal");
        int dot = LAYOUT.LastIndexOf('.');
        foreach (var (rowName, tag, name) in ROWS)
        {
            if (table.Any(r => (string?)r["Name"] == rowName)) throw new Exception(rowName + " row already there");
            var row = (JObject)template.DeepClone();
            row["Name"] = rowName;
            Prop(Prop(row, "SceneTag"), "TagName")["Value"] = tag;
            LiteralText(Prop(row, "SceneTitle"), "SceneTitle_" + rowName, name);
            LiteralText(Prop(row, "EntryName"), "EntryName_" + rowName, name);
            Prop(row, "OpenInputActionName")["Value"] = "None";
            var path = (JObject)Prop(Prop(row, "LayoutData"), "LayoutWidget")["Value"]!["AssetPath"]!;
            path["PackageName"] = LAYOUT[..dot]; path["AssetName"] = LAYOUT[(dot + 1)..];
            int system = table.ToList().FindIndex(r => Tag(r) == "UI.MainMenu.Scene.System");
            table.Insert(system < 0 ? table.Count : system, row);
            AddNames(d, "None", rowName, tag, "MogHub", "SceneTitle_" + rowName, "EntryName_" + rowName, LAYOUT[..dot], LAYOUT[(dot + 1)..]);
        }
        Console.WriteLine("menu rows: " + string.Join(", ", table.Select(r => Tag(r))));
    }

    // DM_DT_GameplayTag_Option (in DefaultGameplayTags.ini's GameplayTagTableList) registers our tags
    static void AddTagRows(JObject d)
    {
        var table = Rows(d);
        foreach (var (_, tag, _) in ROWS)
        {
            var name = tag.Replace('.', '_');
            if (table.Any(r => (string?)r["Name"] == name)) throw new Exception("tag row " + name + " already there");
            var row = (JObject)table[0].DeepClone();
            row["Name"] = name;
            Prop(row, "Tag")["Value"] = tag;
            table.Add(row);
            AddNames(d, name, tag);
        }
        Console.WriteLine("tag rows: " + string.Join(", ", table.Select(r => (string?)r["Name"])));
    }
}
