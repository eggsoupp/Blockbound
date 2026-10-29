// Item icon atlas builder. Run through build_item_atlas.ps1.
//
// icons.txt is read top to bottom; every `pack` and `icon` line takes the next
// slot on the atlas, so the list is APPEND-ONLY: adding at the end never moves
// an icon, and an older upload keeps drawing everything it already had.
//
//   ramp <name> <outline> <dark> <base> <light> <highlight>    five hex colours
//   pack <icon> <sheet> <column> <row>     a 16x16 cell from sheets/<sheet>.png
//   tint <icon> <sheet> <column> <row> <ramp>   that cell recoloured to a ramp
//   template <name> [flat] [<ramp> <ramp> <ramp>]   then 16 rows, then `end`
//   icon <icon> <template> [<ramp> [<ramp> [<ramp>]]]
//
// A template row is either 8 characters - the LEFT half, mirrored to make the
// right, so the icon is symmetric by construction - or 16 for a full row.
//   .            empty
//   o 1 2 3 4    first ramp: its outline, dark, base, light, highlight
//   p a b c d    second ramp, same order
//   q e f g h    third ramp, same order
//   w            white glint, x near-black
// Light comes from the top left: on a mirrored row the right half is drawn one
// shade darker (4->3, 3->2, 2->1, w->4) unless the template says `flat`.
// Every empty pixel touching a drawn one (4-neighbour) becomes that pixel's
// ramp outline, so templates draw only the inside of the shape.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text;

namespace ItemIcons
{
	public static class Builder
	{
		const int Cell = 16, Pitch = 20, Pad = 2, Columns = 25, AtlasWidth = 512;

		class Template { public string Name; public bool Flat; public string[] Ramps = new string[3]; public string[] Rows; }

		static Color Hex(string s) { return ColorTranslator.FromHtml("#" + s); }
		static double Luma(Color c) { return (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) / 255.0; }

		public static string Run(string root, string luaPath)
		{
			var ramps = new Dictionary<string, Color[]>();
			var templates = new Dictionary<string, Template>();
			var slots = new List<KeyValuePair<string, Bitmap>>();
			var sheets = new Dictionary<string, Bitmap>();
			var names = new HashSet<string>();

			string[] lines = File.ReadAllLines(Path.Combine(root, "source", "icons.txt"));
			for (int i = 0; i < lines.Length; i++)
			{
				string line = lines[i].Trim();
				int hash = line.IndexOf('#');
				if (hash >= 0) line = line.Substring(0, hash).Trim();
				if (line.Length == 0) continue;
				string[] w = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
				string where = "icons.txt line " + (i + 1);
				switch (w[0])
				{
					case "ramp":
						if (w.Length != 7) throw new Exception(where + ": ramp needs a name and 5 colours");
						ramps[w[1]] = new[] { Hex(w[2]), Hex(w[3]), Hex(w[4]), Hex(w[5]), Hex(w[6]) };
						break;
					case "template":
					{
						var t = new Template { Name = w[1] };
						int r = 0;
						for (int k = 2; k < w.Length; k++) { if (w[k] == "flat") t.Flat = true; else if (w[k] == "-") r++; else t.Ramps[r++] = w[k]; }
						var rows = new List<string>();
						while (true)
						{
							i++;
							string row = lines[i].Trim();
							if (row == "end") break;
							if (row.Length != 8 && row.Length != 16) throw new Exception("icons.txt line " + (i + 1) + ": template " + t.Name + " row is " + row.Length + " wide");
							rows.Add(row);
						}
						if (rows.Count != Cell) throw new Exception(where + ": template " + t.Name + " has " + rows.Count + " rows");
						t.Rows = rows.ToArray();
						templates[t.Name] = t;
						break;
					}
					case "pack":
					{
						if (!names.Add(w[1])) throw new Exception(where + ": duplicate icon " + w[1]);
						Bitmap sheet;
						if (!sheets.TryGetValue(w[2], out sheet)) { sheet = new Bitmap(Path.Combine(root, "sheets", w[2] + ".png")); sheets[w[2]] = sheet; }
						var bmp = new Bitmap(Cell, Cell, PixelFormat.Format32bppArgb);
						int sx = int.Parse(w[3]) * Cell, sy = int.Parse(w[4]) * Cell;
						for (int y = 0; y < Cell; y++) for (int x = 0; x < Cell; x++) bmp.SetPixel(x, y, sheet.GetPixel(sx + x, sy + y));
						slots.Add(new KeyValuePair<string, Bitmap>(w[1], bmp));
						break;
					}
					case "tint":
					{
						// A pack sprite recoloured: each pixel's brightness, ranked within
						// the sprite, picks a level of the ramp - same shape and shading,
						// new material.
						if (!names.Add(w[1])) throw new Exception(where + ": duplicate icon " + w[1]);
						Bitmap sheet;
						if (!sheets.TryGetValue(w[2], out sheet)) { sheet = new Bitmap(Path.Combine(root, "sheets", w[2] + ".png")); sheets[w[2]] = sheet; }
						Color[] r;
						if (!ramps.TryGetValue(w[5], out r)) throw new Exception(where + ": no ramp " + w[5]);
						int sx = int.Parse(w[3]) * Cell, sy = int.Parse(w[4]) * Cell;
						double lo = 1, hi = 0;
						for (int y = 0; y < Cell; y++) for (int x = 0; x < Cell; x++)
						{
							Color c = sheet.GetPixel(sx + x, sy + y);
							if (c.A < 128) continue;
							double l = Luma(c); if (l < lo) lo = l; if (l > hi) hi = l;
						}
						var bmp = new Bitmap(Cell, Cell, PixelFormat.Format32bppArgb);
						for (int y = 0; y < Cell; y++) for (int x = 0; x < Cell; x++)
						{
							Color c = sheet.GetPixel(sx + x, sy + y);
							if (c.A < 128) continue;
							double t = hi > lo ? (Luma(c) - lo) / (hi - lo) : 0.5;
							int level = t < 0.14 ? 0 : t < 0.36 ? 1 : t < 0.58 ? 2 : t < 0.82 ? 3 : 4;
							bmp.SetPixel(x, y, r[level]);
						}
						slots.Add(new KeyValuePair<string, Bitmap>(w[1], bmp));
						break;
					}
					case "icon":
					{
						if (!names.Add(w[1])) throw new Exception(where + ": duplicate icon " + w[1]);
						Template t;
						if (!templates.TryGetValue(w[2], out t)) throw new Exception(where + ": no template " + w[2]);
						var use = new Color[3][];
						for (int k = 0; k < 3; k++)
						{
							string name = (3 + k < w.Length) ? w[3 + k] : t.Ramps[k];
							if (name == null) continue;
							if (!ramps.TryGetValue(name, out use[k])) throw new Exception(where + ": no ramp " + name);
						}
						slots.Add(new KeyValuePair<string, Bitmap>(w[1], Draw(t, use, where)));
						break;
					}
					default:
						throw new Exception(where + ": unknown line '" + w[0] + "'");
				}
			}

			int rowsUsed = (slots.Count + Columns - 1) / Columns;
			int height = rowsUsed * Pitch + Pad;
			var atlas = new Bitmap(AtlasWidth, height, PixelFormat.Format32bppArgb);
			var lua = new StringBuilder();
			for (int n = 0; n < slots.Count; n++)
			{
				int ox = Pad + (n % Columns) * Pitch, oy = Pad + (n / Columns) * Pitch;
				var bmp = slots[n].Value;
				for (int y = 0; y < Cell; y++) for (int x = 0; x < Cell; x++) atlas.SetPixel(ox + x, oy + y, bmp.GetPixel(x, y));
				lua.AppendFormat("\t\t{0} = {{ offset = Vector2.new({1}, {2}), size = Vector2.new({3}, {3}) }},\n", slots[n].Key, ox, oy, Cell);
			}
			atlas.Save(Path.Combine(root, "atlas", "item_icons_atlas.png"), ImageFormat.Png);
			Preview(slots, Path.Combine(root, "atlas", "preview.png"));

			string text =
				"--[[\n\tItemSprites\n\n" +
				"\tGENERATED by assets/item-icons/source/build_item_atlas.ps1 from\n" +
				"\tassets/item-icons/source/icons.txt - do not edit by hand. The atlas's\n" +
				"\tasset id is not here: it is Theme.ItemAtlas, so regenerating never loses it.\n\n" +
				"\tAn item names one of these with `sprite` in ItemDefinitions, and\n" +
				"\tShared.UI.ItemThumbnails draws it off the atlas. Icons with no item yet\n" +
				"\tare art waiting for one.\n\n" +
				"\t  offset, size  where the sprite sits on the atlas, in texels\n]]\n\n" +
				"return {\n\tAtlasSize = Vector2.new(" + AtlasWidth + ", " + height + "),\n\tSprites = {\n" + lua + "\t},\n}\n";
			File.WriteAllText(luaPath, text, new UTF8Encoding(false));
			return slots.Count + " icons, atlas " + AtlasWidth + "x" + height;
		}

		static Bitmap Draw(Template t, Color[][] use, string where)
		{
			// ramp index (0-2) and level (0 outline .. 4 highlight), or -1 empty / -2 white / -3 black
			var ramp = new int[Cell, Cell];
			var level = new int[Cell, Cell];
			for (int y = 0; y < Cell; y++)
			{
				string row = t.Rows[y];
				for (int x = 0; x < Cell; x++)
				{
					bool mirrored = row.Length == 8 && x >= 8;
					char c = row.Length == 16 ? row[x] : row[x < 8 ? x : 15 - x];
					int r = -1, l = 0;
					switch (c)
					{
						case '.': r = -1; break;
						case 'w': r = -2; break;
						case 'x': r = -3; break;
						case 'o': r = 0; l = 0; break;
						case 'p': r = 1; l = 0; break;
						case 'q': r = 2; l = 0; break;
						default:
							if (c >= '1' && c <= '4') { r = 0; l = c - '0'; }
							else if (c >= 'a' && c <= 'd') { r = 1; l = c - 'a' + 1; }
							else if (c >= 'e' && c <= 'h') { r = 2; l = c - 'e' + 1; }
							else throw new Exception(where + ": template " + t.Name + " has '" + c + "'");
							break;
					}
					if (mirrored && !t.Flat)
					{
						if (r == -2) { r = 0; l = 4; }
						else if (r >= 0 && l >= 2) l -= 1;
					}
					if (r >= 0 && use[r] == null) throw new Exception(where + ": template " + t.Name + " needs ramp " + (r + 1));
					ramp[x, y] = r; level[x, y] = l;
				}
			}

			var bmp = new Bitmap(Cell, Cell, PixelFormat.Format32bppArgb);
			int[] dx = { 1, -1, 0, 0 }, dy = { 0, 0, 1, -1 };
			for (int y = 0; y < Cell; y++)
				for (int x = 0; x < Cell; x++)
				{
					int r = ramp[x, y];
					if (r == -2) { bmp.SetPixel(x, y, Color.White); continue; }
					if (r == -3) { bmp.SetPixel(x, y, Color.FromArgb(255, 18, 12, 20)); continue; }
					if (r >= 0) { bmp.SetPixel(x, y, use[r][level[x, y]]); continue; }
					// Empty: outline if it touches something drawn.
					for (int k = 0; k < 4; k++)
					{
						int nx = x + dx[k], ny = y + dy[k];
						if (nx < 0 || ny < 0 || nx >= Cell || ny >= Cell) continue;
						int nr = ramp[nx, ny];
						if (nr == -1) continue;
						Color edge = nr >= 0 ? use[nr][0] : Color.FromArgb(255, 18, 12, 20);
						bmp.SetPixel(x, y, edge);
						break;
					}
				}
			return bmp;
		}

		// 4x preview on a dark ground, with names, for checking the art by eye.
		static void Preview(List<KeyValuePair<string, Bitmap>> slots, string path)
		{
			const int s = 4, cols = 12, cw = 96, ch = 84;
			int rows = (slots.Count + cols - 1) / cols;
			var bmp = new Bitmap(cols * cw, rows * ch, PixelFormat.Format32bppArgb);
			using (var g = Graphics.FromImage(bmp))
			using (var font = new Font("Arial", 7))
			{
				g.Clear(Color.FromArgb(255, 58, 50, 46));
				g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
				g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
				for (int n = 0; n < slots.Count; n++)
				{
					int x = (n % cols) * cw, y = (n / cols) * ch;
					g.FillRectangle(new SolidBrush(Color.FromArgb(255, 216, 190, 140)), x + 14, y + 2, 68, 68);
					g.DrawImage(slots[n].Value, new Rectangle(x + 16, y + 4, Cell * s, Cell * s));
					g.DrawString(slots[n].Key, font, Brushes.White, x + 2, y + 71);
				}
			}
			bmp.Save(path, ImageFormat.Png);
		}
	}
}
