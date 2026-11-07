# Exports each <Name>Wings.vox pair as greedy-merged boxes per rig piece, in
# Roblox axes, for roblox/BuildWings.lua.
#
#   powershell -ExecutionPolicy Bypass -File export_wings.ps1
#
# Source axes (README): X lateral (L_ = -X), +Y rearward, +Z up, voxel centres
# relative to Frame's origin. Roblox: X = x, Y = z, Z = y, so the wings sit on
# +Z, behind a character that faces -Z, and L_ stays on the wearer's left.
#
# Each piece's world voxels come from the scene graph: the piece's nTRN `_t`
# is lo + size // 2 (build_wings.py save_vox), so lo = t - size // 2.
# The whole scene is lifted 40 on Z for MagicaVoxel, but on the ROOT node: the
# pieces' own translations are already Frame-relative, so nothing is removed.
#
# Output: data/<Name>.lua, a ModuleScript source:
#   return { name, colors = "r,g,b;...", pieces = { { name, parent, pivot = {x,y,z},
#            boxes = "x,y,z,w,h,d,c;..." } } }
# Box x/y/z are the minimum voxel corner in Roblox axes; c indexes colors.
# Pivots come from rigging.json, converted the same way.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $PSScriptRoot "data"
New-Item -ItemType Directory -Force $outDir | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

public static class WingVox {
    class Model { public int sx, sy, sz; public List<int[]> vox = new List<int[]>(); }

    static string ReadStr(BinaryReader r) { int n = r.ReadInt32(); return Encoding.UTF8.GetString(r.ReadBytes(n)); }
    static Dictionary<string,string> ReadDict(BinaryReader r) {
        var d = new Dictionary<string,string>(); int n = r.ReadInt32();
        for (int i = 0; i < n; i++) { var k = ReadStr(r); d[k] = ReadStr(r); }
        return d;
    }

    // pieceName -> list of {x,y,z,colourIndex} in SOURCE axes, Frame-relative.
    public static Dictionary<string, List<int[]>> Read(string path, out int[] palette) {
        var bytes = File.ReadAllBytes(path);
        var r = new BinaryReader(new MemoryStream(bytes));
        r.ReadBytes(8); r.ReadBytes(4); int mc = r.ReadInt32(); int mk = r.ReadInt32();
        var models = new List<Model>();
        palette = new int[256 * 3];
        var trnName = new Dictionary<int,string>(); var trnChild = new Dictionary<int,int>(); var trnT = new Dictionary<int,int[]>();
        var shpModel = new Dictionary<int,int>();
        Model cur = null;
        while (r.BaseStream.Position < bytes.Length) {
            string id = Encoding.ASCII.GetString(r.ReadBytes(4));
            int n = r.ReadInt32(); int m = r.ReadInt32();
            long start = r.BaseStream.Position;
            if (id == "SIZE") { cur = new Model(); cur.sx = r.ReadInt32(); cur.sy = r.ReadInt32(); cur.sz = r.ReadInt32(); models.Add(cur); }
            else if (id == "XYZI") { int c = r.ReadInt32(); for (int i = 0; i < c; i++) { var b = r.ReadBytes(4); cur.vox.Add(new int[] { b[0], b[1], b[2], b[3] }); } }
            else if (id == "RGBA") { for (int i = 0; i < 256; i++) { var b = r.ReadBytes(4); palette[i*3] = b[0]; palette[i*3+1] = b[1]; palette[i*3+2] = b[2]; } }
            else if (id == "nTRN") {
                int nid = r.ReadInt32(); var attr = ReadDict(r); int child = r.ReadInt32(); r.ReadInt32(); r.ReadInt32(); int frames = r.ReadInt32();
                int[] t = new int[] {0,0,0};
                for (int f = 0; f < frames; f++) { var fd = ReadDict(r); if (fd.ContainsKey("_t")) { var p = fd["_t"].Split(' '); t = new int[] { int.Parse(p[0]), int.Parse(p[1]), int.Parse(p[2]) }; } }
                trnName[nid] = attr.ContainsKey("_name") ? attr["_name"] : ""; trnChild[nid] = child; trnT[nid] = t;
            }
            else if (id == "nSHP") { int nid = r.ReadInt32(); ReadDict(r); int cnt = r.ReadInt32(); int model = r.ReadInt32(); shpModel[nid] = model; }
            r.BaseStream.Position = start + n;
            if (id == "MAIN") r.BaseStream.Position = start + n; // children follow
        }
        var result = new Dictionary<string, List<int[]>>();
        foreach (var kv in trnChild) {
            if (!shpModel.ContainsKey(kv.Value)) continue;
            var model = models[shpModel[kv.Value]];
            var t = trnT[kv.Key];
            int lx = t[0] - model.sx / 2, ly = t[1] - model.sy / 2, lz = t[2] - model.sz / 2;
            var list = new List<int[]>();
            foreach (var v in model.vox) list.Add(new int[] { v[0] + lx, v[1] + ly, v[2] + lz, v[3] });
            result[trnName[kv.Key]] = list;
        }
        return result;
    }

    // Greedy-merge one piece's voxels (Roblox axes) into boxes. Hidden voxels
    // may be swallowed by a box of any colour. Returns "x,y,z,w,h,d,c;..."
    public static string Boxes(List<int[]> vox, Dictionary<int,int> colourSlot, out int count) {
        int minx = int.MaxValue, miny = int.MaxValue, minz = int.MaxValue, maxx = int.MinValue, maxy = int.MinValue, maxz = int.MinValue;
        foreach (var v in vox) { minx = Math.Min(minx, v[0]); miny = Math.Min(miny, v[1]); minz = Math.Min(minz, v[2]); maxx = Math.Max(maxx, v[0]); maxy = Math.Max(maxy, v[1]); maxz = Math.Max(maxz, v[2]); }
        int sx = maxx - minx + 1, sy = maxy - miny + 1, sz = maxz - minz + 1;
        var g = new int[sx * sy * sz];
        Func<int,int,int,int> I = (x, y, z) => (x * sy + y) * sz + z;
        foreach (var v in vox) g[I(v[0]-minx, v[1]-miny, v[2]-minz)] = v[3];
        Func<int,int,int,bool> solid = (x, y, z) => x >= 0 && y >= 0 && z >= 0 && x < sx && y < sy && z < sz && g[I(x,y,z)] != 0;
        var hidden = new bool[g.Length]; var done = new bool[g.Length];
        for (int x = 0; x < sx; x++) for (int y = 0; y < sy; y++) for (int z = 0; z < sz; z++)
            if (g[I(x,y,z)] != 0 && solid(x+1,y,z) && solid(x-1,y,z) && solid(x,y+1,z) && solid(x,y-1,z) && solid(x,y,z+1) && solid(x,y,z-1)) hidden[I(x,y,z)] = true;
        Func<int,int,int,int,int,int,int,bool> fits = (x0, x1, y0, y1, z0, z1, col) => {
            for (int x = x0; x <= x1; x++) for (int y = y0; y <= y1; y++) for (int z = z0; z <= z1; z++) {
                int i = I(x,y,z); if (hidden[i] && g[i] != 0 && !done[i]) continue;
                if (g[i] != col || done[i]) return false;
            }
            return true;
        };
        var sb = new StringBuilder(); count = 0;
        for (int x = 0; x < sx; x++) for (int y = 0; y < sy; y++) for (int z = 0; z < sz; z++) {
            int i = I(x,y,z); if (g[i] == 0 || hidden[i] || done[i]) continue;
            int col = g[i]; int x1 = x, y1 = y, z1 = z;
            while (z1 + 1 < sz && fits(x, x, y, y, z1+1, z1+1, col)) z1++;
            while (y1 + 1 < sy && fits(x, x, y1+1, y1+1, z, z1, col)) y1++;
            while (x1 + 1 < sx && fits(x1+1, x1+1, y, y1, z, z1, col)) x1++;
            for (int a = x; a <= x1; a++) for (int b = y; b <= y1; b++) for (int c = z; c <= z1; c++) done[I(a,b,c)] = true;
            if (!colourSlot.ContainsKey(col)) colourSlot[col] = colourSlot.Count + 1;
            if (count > 0) sb.Append(';');
            sb.Append(x + minx).Append(',').Append(y + miny).Append(',').Append(z + minz).Append(',')
              .Append(x1 - x + 1).Append(',').Append(y1 - y + 1).Append(',').Append(z1 - z + 1).Append(',').Append(colourSlot[col]);
            count++;
        }
        return sb.ToString();
    }
}
"@

$rig = Get-Content (Join-Path $root "rigging.json") -Raw | ConvertFrom-Json
$lift = 0

foreach ($name in @("AngelWings", "BatWings", "DemonWings", "FairyWings", "FlameWings", "FrostWings", "LeafWings")) {
    $palette = $null
    $pieces = [WingVox]::Read((Join-Path $root "$name.vox"), [ref]$palette)
    $slots = New-Object 'System.Collections.Generic.Dictionary[int,int]'
    $joints = $rig.models.$name.joints
    $lines = New-Object System.Collections.Generic.List[string]
    $total = 0
    foreach ($j in $joints.PSObject.Properties) {
        $piece = $j.Name
        if (-not $pieces.ContainsKey($piece)) { throw "$name has no voxels for $piece" }
        # Source (x, y, z - lift) -> Roblox (x, z - lift, y)
        $list = New-Object 'System.Collections.Generic.List[int[]]'
        foreach ($v in $pieces[$piece]) { $list.Add([int[]]@($v[0], ($v[2] - $lift), $v[1], $v[3])) }
        $count = 0
        $boxes = [WingVox]::Boxes($list, $slots, [ref]$count)
        $total += $count
        $p = $j.Value.pivot
        $parent = if ($null -eq $j.Value.parent) { "nil" } else { '"' + $j.Value.parent + '"' }
        $lines.Add(('{{name="{0}",parent={1},pivot={{{2},{3},{4}}},voxels={5},boxes="{6}"}}' -f $piece, $parent, $p[0], $p[2], $p[1], $pieces[$piece].Count, $boxes))
    }
    $cols = @()
    foreach ($e in ($slots.GetEnumerator() | Sort-Object Value)) {
        $k = $e.Key - 1
        $cols += "{0},{1},{2}" -f $palette[$k*3], $palette[$k*3+1], $palette[$k*3+2]
    }
    $text = "-- Generated by assets/wing-accessories/roblox/export_wings.ps1 from $name.vox. Do not edit.`nreturn {name=`"$name`",colors=`"" + ($cols -join ';') + "`",pieces={`n" + ($lines -join ",`n") + "`n}}`n"
    [System.IO.File]::WriteAllText((Join-Path $outDir "$name.lua"), $text)
    "{0}: pieces={1} boxes={2} colors={3} bytes={4}" -f $name, $lines.Count, $total, $cols.Count, $text.Length
}
