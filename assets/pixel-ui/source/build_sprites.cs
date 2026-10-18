// Draws Blockbound's pixel-art UI kit, pixel by pixel.
//
// Run build_sprites.ps1 - it compiles this with the .NET Framework that ships
// with Windows, so nothing has to be installed. Keep the syntax at C# 5: that
// is what Windows PowerShell's Add-Type compiles.
//
// Everything is drawn at 1x - one pixel here is one texel in game. Roblox shows
// them with ResampleMode.Pixelated and SliceScale (or plain sizing) at 3x.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text;

namespace PixelUI
{
    public class Spr
    {
        public int W, H;
        public int[] Px;

        public Spr(int w, int h) { W = w; H = h; Px = new int[w * h]; }

        public void Set(int x, int y, int c) { if (x >= 0 && y >= 0 && x < W && y < H) Px[y * W + x] = c; }
        public int Get(int x, int y) { return (x >= 0 && y >= 0 && x < W && y < H) ? Px[y * W + x] : 0; }

        public void Rect(int x, int y, int w, int h, int c)
        {
            for (int j = y; j < y + h; j++) for (int i = x; i < x + w; i++) Set(i, j, c);
        }
        public void HLine(int x0, int x1, int y, int c) { for (int i = x0; i <= x1; i++) Set(i, y, c); }
        public void VLine(int x, int y0, int y1, int c) { for (int j = y0; j <= y1; j++) Set(x, j, c); }

        // How far each row steps in at a corner: the pixel-art rounded corner.
        static readonly int[][] Cuts = { new int[0], new[] { 1 }, new[] { 2, 1 }, new[] { 3, 1, 1 }, new[] { 4, 2, 1, 1 } };

        public void RRect(int x, int y, int w, int h, int c, int r)
        {
            int[] cut = Cuts[r];
            for (int j = 0; j < h; j++)
            {
                int inset = 0;
                if (j < cut.Length) inset = cut[j];
                else if (h - 1 - j < cut.Length) inset = cut[h - 1 - j];
                for (int i = inset; i < w - inset; i++) Set(x + i, y + j, c);
            }
        }

        public void Art(string[] rows, Dictionary<char, int> pal, int ox, int oy)
        {
            for (int j = 0; j < rows.Length; j++)
                for (int i = 0; i < rows[j].Length; i++)
                {
                    int c;
                    if (pal.TryGetValue(rows[j][i], out c)) Set(ox + i, oy + j, c);
                }
        }

        // Fills every pixel more than half covered by the shape (4x4 samples).
        public void Fill(Func<double, double, bool> inside, int c)
        {
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    int n = 0;
                    for (int j = 0; j < 4; j++)
                        for (int i = 0; i < 4; i++)
                            if (inside(x + (i + 0.5) / 4.0, y + (j + 0.5) / 4.0)) n++;
                    if (n >= 8) Set(x, y, c);
                }
        }

        // Shades a flat shape lit from the top-left: bright top edge, dark
        // bottom-right edge, and a lighter upper-left half.
        public void Bevel(int baseC, int light, int dark, int hi, int lo, double cx, double cy)
        {
            int[] orig = (int[])Px.Clone();
            Func<int, int, bool> on = (x, y) => x >= 0 && y >= 0 && x < W && y < H && orig[y * W + x] == baseC;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    if (!on(x, y)) continue;
                    bool top = !on(x, y - 1), left = !on(x - 1, y), bottom = !on(x, y + 1), right = !on(x + 1, y);
                    int c;
                    if (top && !bottom) c = hi;
                    else if ((bottom || right) && !top && !left) c = lo;
                    else if (left && !right) c = light;
                    else
                    {
                        double d = (x + 0.5 - cx) + (y + 0.5 - cy);
                        c = d < -1.0 ? light : (d > 1.5 ? dark : baseC);
                    }
                    Px[y * W + x] = c;
                }
        }

        // Rings everything drawn so far with a 1px outline.
        public void Outline(int c)
        {
            int[] orig = (int[])Px.Clone();
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    if (orig[y * W + x] != 0) continue;
                    bool near = false;
                    for (int j = -1; j <= 1 && !near; j++)
                        for (int i = -1; i <= 1; i++)
                        {
                            int nx = x + i, ny = y + j;
                            if (nx >= 0 && ny >= 0 && nx < W && ny < H && orig[ny * W + nx] != 0) { near = true; break; }
                        }
                    if (near) Px[y * W + x] = c;
                }
        }

        public Spr FlipX()
        {
            var s = new Spr(W, H);
            for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) s.Px[y * W + x] = Px[y * W + (W - 1 - x)];
            return s;
        }

        // Multiplies every pixel by a colour - what Roblox's ImageColor3 does.
        public Spr Tint(int c)
        {
            var s = new Spr(W, H);
            int tr = (c >> 16) & 255, tg = (c >> 8) & 255, tb = c & 255;
            for (int i = 0; i < Px.Length; i++)
            {
                int p = Px[i];
                if (p == 0) continue;
                int a = (p >> 24) & 255, r = ((p >> 16) & 255) * tr / 255, g = ((p >> 8) & 255) * tg / 255, b = (p & 255) * tb / 255;
                s.Px[i] = (a << 24) | (r << 16) | (g << 8) | b;
            }
            return s;
        }

        public void Blit(Spr src, int ox, int oy)
        {
            for (int y = 0; y < src.H; y++) for (int x = 0; x < src.W; x++) Set(ox + x, oy + y, src.Px[y * src.W + x]);
        }

        public byte[] Png()
        {
            using (var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
            {
                for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) bmp.SetPixel(x, y, Color.FromArgb(Px[y * W + x]));
                using (var ms = new MemoryStream())
                {
                    bmp.Save(ms, ImageFormat.Png);
                    return ms.ToArray();
                }
            }
        }
    }

    public class Pal
    {
        public int O, H, L, F, M, S, D;
        public Pal(string o, string h, string l, string f, string m, string s, string d)
        {
            O = Builder.C(o); H = Builder.C(h); L = Builder.C(l); F = Builder.C(f); M = Builder.C(m); S = Builder.C(s); D = Builder.C(d);
        }
    }

    public class Entry
    {
        public string Name, Group, Note;
        public Spr S;
        public int[] Slice; // Roblox SliceCenter: minX, minY, maxX, maxY
        public bool Upload = true;
    }

    public static class Builder
    {
        public static int C(string hex) { return unchecked((int)(0xFF000000u | Convert.ToUInt32(hex.TrimStart('#'), 16))); }

        // --- Palette -------------------------------------------------------
        static readonly int OL = C("2b1810");  // outer outline
        static readonly int OL2 = C("3b2416"); // inner outlines

        // Frame wood, light to dark.
        static readonly int WH = C("b77d47"), WL = C("9a6136"), W = C("8a5530"), WS = C("693d22"), WD = C("4f2c18");
        // Recessed wood (window interiors, dark slots, tracks).
        static readonly int WF = C("6b4026"), WFD = C("4a2a17"), WFS = C("5a3520"), WFL = C("7d4c2c");
        // Parchment.
        static readonly int PL = C("f8ebc8"), P = C("efdcae"), PS = C("dcc08a"), PD = C("c6a06a"), PE = C("a87c4c");

        static readonly Pal Green = new Pal("1d3d2b", "a8ecbb", "7dd49c", "52b87f", "44a06d", "348758", "266443");
        static readonly Pal GreenHover = new Pal("1d3d2b", "c4f5d2", "98e2b2", "6dcc95", "5ab581", "3f9864", "2d714c");
        static readonly Pal Red = new Pal("3e1513", "f6b3a0", "e57f6b", "d4573f", "bb4733", "9c3528", "74251c");
        static readonly Pal RedHover = new Pal("3e1513", "fcc9b8", "ef9783", "e26c53", "cc5a44", "ac4030", "822b20");
        static readonly Pal Tan = new Pal("3b2414", "fff6dc", "f5e2b6", "e7cf99", "d6bb82", "b8945c", "8f6b3d");
        static readonly Pal TanHover = new Pal("3b2414", "fffbea", "fbedc9", "f2dcae", "e3ca95", "c7a46b", "9d7746");
        static readonly Pal Grey = new Pal("2f2b27", "d8d3c8", "c4bfb3", "aaa59a", "9a958a", "807b72", "625e57");

        static readonly List<Entry> All = new List<Entry>();

        static void Add(string group, string name, Spr s, int[] slice, string note)
        {
            All.Add(new Entry { Group = group, Name = name, S = s, Slice = slice, Note = note });
        }
        static void AddPreview(string name, Spr s, int[] slice = null)
        {
            All.Add(new Entry { Group = "preview", Name = name, S = s, Slice = slice, Upload = false, Note = "Preview only - not uploaded." });
        }

        // --- Windows and panels -------------------------------------------

        static Spr Frame(bool parchment)
        {
            var s = new Spr(32, 32);
            s.RRect(0, 0, 32, 32, OL, 3);
            s.RRect(1, 1, 30, 30, W, 2);
            s.HLine(3, 28, 1, WH);
            s.VLine(1, 3, 28, WL);
            s.VLine(29, 2, 29, WS);
            s.VLine(30, 3, 28, WS);
            s.HLine(2, 29, 29, WS);
            s.HLine(3, 28, 30, WD);
            s.RRect(5, 5, 22, 22, OL, 1);
            if (parchment)
            {
                s.Rect(6, 6, 20, 20, P);
                s.HLine(6, 25, 6, PD);
                s.HLine(6, 25, 7, PS);
                s.VLine(6, 8, 25, PS);
                s.VLine(25, 8, 25, PS);
                s.HLine(7, 24, 25, PS);
            }
            else
            {
                s.Rect(6, 6, 20, 20, WF);
                s.HLine(6, 25, 6, WFD);
                s.HLine(6, 25, 7, WFS);
                s.VLine(6, 8, 25, WFS);
                s.VLine(25, 8, 25, WFS);
                s.HLine(7, 24, 25, WFS);
            }
            return s;
        }

        static Spr Inset(bool parchment)
        {
            var s = new Spr(16, 16);
            s.RRect(0, 0, 16, 16, OL2, 2);
            if (parchment)
            {
                s.RRect(1, 1, 14, 14, P, 1);
                s.HLine(2, 13, 1, PD);
                s.HLine(1, 14, 2, PS);
                s.VLine(1, 2, 13, PS);
                s.VLine(14, 3, 13, PL);
                s.HLine(2, 13, 14, PL);
            }
            else
            {
                s.RRect(1, 1, 14, 14, WF, 1);
                s.HLine(2, 13, 1, WFD);
                s.HLine(1, 14, 2, WFS);
                s.VLine(1, 2, 13, WFS);
                s.VLine(14, 3, 13, WFL);
                s.HLine(2, 13, 14, WFL);
            }
            return s;
        }

        static Spr Header()
        {
            var s = new Spr(24, 14);
            s.RRect(0, 0, 24, 14, Green.O, 2);
            s.RRect(1, 1, 22, 12, Green.H, 1);
            s.Rect(2, 2, 20, 9, Green.F);
            s.HLine(2, 21, 2, Green.L);
            s.HLine(2, 21, 10, Green.M);
            s.HLine(2, 21, 11, Green.S);
            s.HLine(2, 21, 12, Green.D);
            return s;
        }

        static Spr Tooltip()
        {
            var s = new Spr(12, 12);
            s.RRect(0, 0, 12, 12, OL, 1);
            s.Rect(1, 1, 10, 10, C("a77a4a"));
            s.Rect(2, 2, 8, 8, C("33200f"));
            s.HLine(2, 9, 2, C("45301c"));
            return s;
        }

        // --- Buttons --------------------------------------------------------

        static Spr Button(Pal p, bool pressed)
        {
            var s = new Spr(16, 14);
            if (!pressed)
            {
                s.RRect(0, 0, 16, 14, p.O, 2);
                s.RRect(1, 1, 14, 12, p.F, 1);
                s.HLine(2, 13, 1, p.H);
                s.VLine(1, 2, 9, p.L);
                s.VLine(14, 2, 9, p.M);
                s.HLine(1, 14, 10, p.S);
                s.HLine(1, 14, 11, p.S);
                s.HLine(2, 13, 12, p.D);
            }
            else
            {
                // Pushed down two texels: shift the label down with it.
                s.RRect(0, 2, 16, 12, p.O, 2);
                s.RRect(1, 3, 14, 10, p.F, 1);
                s.HLine(2, 13, 3, p.D);
                s.VLine(1, 4, 11, p.M);
                s.VLine(14, 4, 11, p.M);
                s.HLine(2, 13, 12, p.S);
            }
            return s;
        }

        static readonly string[] CloseGlyph = {
            "XX.XX",
            ".XXX.",
            "..X..",
            ".XXX.",
            "XX.XX",
        };

        static Spr Close(Pal p, bool pressed)
        {
            var s = new Spr(13, 13);
            var glyph = new Dictionary<char, int> { { 'X', C("3a2215") } };
            if (!pressed)
            {
                s.RRect(0, 0, 13, 13, p.O, 2);
                s.RRect(1, 1, 11, 11, p.F, 1);
                s.HLine(2, 10, 1, p.H);
                s.HLine(1, 11, 9, p.S);
                s.HLine(1, 11, 10, p.S);
                s.HLine(2, 10, 11, p.D);
                s.Art(CloseGlyph, glyph, 4, 2);
            }
            else
            {
                s.RRect(0, 2, 13, 11, p.O, 2);
                s.RRect(1, 3, 11, 9, p.F, 1);
                s.HLine(2, 10, 3, p.D);
                s.HLine(2, 10, 11, p.S);
                s.Art(CloseGlyph, glyph, 4, 4);
            }
            return s;
        }

        // --- Slots ----------------------------------------------------------

        static Spr Slot(bool dark)
        {
            var s = new Spr(16, 16);
            int o, sd, sm, f, sl;
            if (dark) { o = C("2e1a0e"); sd = C("3a2113"); sm = C("472918"); f = C("573420"); sl = C("74462a"); }
            else { o = C("9c7045"); sd = C("bb915a"); sm = C("cfb078"); f = C("e0c690"); sl = C("f4e4bb"); }
            s.RRect(0, 0, 16, 16, o, 1);
            s.Rect(1, 1, 14, 14, f);
            s.HLine(1, 14, 1, sd);
            s.HLine(2, 14, 2, sm);
            s.VLine(1, 2, 14, sd);
            s.VLine(2, 3, 13, sm);
            s.HLine(3, 14, 14, sl);
            s.VLine(14, 3, 13, sl);
            return s;
        }

        // White so ImageColor3 can paint it: gold for selection, rarity colours.
        static Spr SlotHighlight()
        {
            var s = new Spr(16, 16);
            s.RRect(0, 0, 16, 16, C("ffffff"), 1);
            s.Rect(1, 1, 14, 14, C("d2d2d2"));
            s.Rect(2, 2, 12, 12, 0);
            // Corner ticks so it still reads on a busy item picture.
            int t = C("ffffff");
            s.Set(2, 2, t); s.Set(13, 2, t); s.Set(2, 13, t); s.Set(13, 13, t);
            return s;
        }

        // --- Controls -------------------------------------------------------

        static Spr Input()
        {
            var s = new Spr(12, 12);
            s.RRect(0, 0, 12, 12, OL2, 1);
            s.Rect(1, 1, 10, 10, C("fbf1d6"));
            s.HLine(1, 10, 1, C("c8a670"));
            s.HLine(1, 10, 2, C("e9d7ab"));
            s.VLine(1, 2, 10, C("e9d7ab"));
            return s;
        }

        static Spr Checkbox(bool on)
        {
            var s = new Spr(11, 11);
            s.RRect(0, 0, 11, 11, OL2, 1);
            s.Rect(1, 1, 9, 9, C("fbf1d6"));
            s.HLine(1, 9, 1, C("c8a670"));
            s.HLine(1, 9, 2, C("e9d7ab"));
            s.VLine(1, 2, 9, C("e9d7ab"));
            if (on)
            {
                s.Art(new[] {
                    "......K",
                    ".....KK",
                    "K...KK.",
                    "KK.KK..",
                    ".KKK...",
                    "..K....",
                }, new Dictionary<char, int> { { 'K', C("2a8553") } }, 2, 2);
            }
            return s;
        }

        static Spr Toggle(bool on)
        {
            var s = new Spr(20, 11);
            s.RRect(0, 1, 20, 9, OL2, 2);
            s.RRect(1, 2, 18, 7, on ? Green.F : WF, 1);
            s.HLine(2, 17, 2, on ? Green.D : WFD);
            s.HLine(2, 17, 3, on ? Green.S : WFS);
            int kx = on ? 9 : 0;
            s.RRect(kx, 0, 11, 11, OL2, 2);
            s.RRect(kx + 1, 1, 9, 9, Tan.F, 1);
            s.HLine(kx + 2, kx + 8, 1, Tan.H);
            s.VLine(kx + 1, 2, 7, Tan.L);
            s.HLine(kx + 1, kx + 9, 8, Tan.S);
            s.HLine(kx + 2, kx + 8, 9, Tan.D);
            s.VLine(kx + 4, 3, 6, Tan.S);
            s.VLine(kx + 6, 3, 6, Tan.S);
            return s;
        }

        static Spr SliderTrack()
        {
            var s = new Spr(12, 8);
            s.RRect(0, 0, 12, 8, OL2, 2);
            s.RRect(1, 1, 10, 6, WF, 1);
            s.HLine(2, 9, 1, WFD);
            s.HLine(1, 10, 2, WFS);
            s.HLine(2, 9, 6, WFL);
            return s;
        }

        static Spr SliderFill()
        {
            var s = new Spr(12, 8);
            s.RRect(0, 0, 12, 8, OL2, 2);
            s.RRect(1, 1, 10, 6, Green.F, 1);
            s.HLine(2, 9, 1, Green.H);
            s.HLine(1, 10, 5, Green.M);
            s.HLine(2, 9, 6, Green.S);
            return s;
        }

        static Spr SliderKnob()
        {
            var s = new Spr(9, 13);
            s.RRect(0, 0, 9, 13, OL2, 2);
            s.RRect(1, 1, 7, 11, Tan.F, 1);
            s.HLine(2, 6, 1, Tan.H);
            s.VLine(1, 2, 8, Tan.L);
            s.HLine(1, 7, 9, Tan.S);
            s.HLine(1, 7, 10, Tan.S);
            s.HLine(2, 6, 11, Tan.D);
            s.VLine(3, 3, 7, Tan.S);
            s.VLine(5, 3, 7, Tan.S);
            return s;
        }

        static Dictionary<char, int> GreenArt()
        {
            return new Dictionary<char, int> {
                { 'O', Green.O }, { 'H', Green.H }, { 'L', Green.L }, { 'F', Green.F }, { 'M', Green.M }, { 'S', Green.S },
                { 'd', WFD }, { 'w', WF }, { 'l', WFL }, { 'K', OL2 },
            };
        }

        static Spr FromArt(int w, int h, string[] rows, Dictionary<char, int> pal)
        {
            var s = new Spr(w, h);
            s.Art(rows, pal, 0, 0);
            return s;
        }

        static Spr Divider()
        {
            var s = new Spr(16, 5);
            s.HLine(3, 12, 2, PE);
            s.HLine(3, 12, 3, PL);
            foreach (int cx in new[] { 1, 14 })
            {
                s.Set(cx, 1, PE); s.Set(cx - 1, 2, PE); s.Set(cx, 2, PD); s.Set(cx + 1, 2, PE); s.Set(cx, 3, PE);
            }
            return s;
        }

        // Top tabs. The active one is taller and open at the bottom, so laid
        // over the top edge of an inset_parchment it joins onto it.
        static Spr Tab(bool active)
        {
            var s = new Spr(16, 14);
            if (active)
            {
                s.RRect(0, 0, 16, 18, OL2, 2);
                s.RRect(1, 1, 14, 18, P, 1);
                s.HLine(2, 13, 1, PL);
                s.VLine(1, 2, 11, PL);
                // The last two rows run edge to edge: they cover the inset's top
                // shading, so the tab and the panel read as one piece.
                s.HLine(0, 15, 12, P);
                s.HLine(0, 15, 13, P);
            }
            else
            {
                s.RRect(0, 2, 16, 18, OL2, 2);
                s.RRect(1, 3, 14, 18, C("d4b47c"), 1);
                s.HLine(2, 13, 3, C("e6cc98"));
                s.HLine(1, 14, 13, C("c4a26b"));
            }
            return s;
        }

        static Spr Row(int kind)
        {
            var s = new Spr(16, 12);
            if (kind == 2)
            {
                s.RRect(0, 0, 16, 12, Green.O, 1);
                s.Rect(1, 1, 14, 10, Green.L);
                s.Rect(2, 2, 12, 8, C("fbf3dc"));
                s.HLine(2, 13, 2, C("e7f6e2"));
            }
            else
            {
                s.RRect(0, 0, 16, 12, kind == 1 ? C("8f6b3d") : C("b48a55"), 1);
                s.Rect(1, 1, 14, 10, kind == 1 ? C("fbf0d4") : C("f4e4bd"));
                s.HLine(1, 14, 10, kind == 1 ? C("ead4a3") : C("e3cb98"));
            }
            return s;
        }

        static Spr Badge()
        {
            var s = new Spr(9, 9);
            s.RRect(0, 0, 9, 9, OL, 2);
            s.RRect(1, 1, 7, 7, C("5a3520"), 1);
            s.HLine(2, 6, 1, C("7a4a2a"));
            return s;
        }

        // --- Icons ------------------------------------------------------------

        static bool InPoly(double[] xs, double[] ys, double px, double py)
        {
            bool inside = false;
            for (int i = 0, j = xs.Length - 1; i < xs.Length; j = i++)
                if (((ys[i] > py) != (ys[j] > py)) && (px < (xs[j] - xs[i]) * (py - ys[i]) / (ys[j] - ys[i]) + xs[i]))
                    inside = !inside;
            return inside;
        }

        static double SegDist(double px, double py, double ax, double ay, double bx, double by)
        {
            double dx = bx - ax, dy = by - ay;
            double t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            double qx = ax + t * dx - px, qy = ay + t * dy - py;
            return Math.Sqrt(qx * qx + qy * qy);
        }

        static Spr Star(bool earned)
        {
            var s = new Spr(17, 17);
            double cx = 8.5, cy = 9.1, R = 7.2, r = 3.2;
            var xs = new double[10];
            var ys = new double[10];
            for (int k = 0; k < 10; k++)
            {
                double a = (-90 + k * 36) * Math.PI / 180, rad = (k % 2 == 0) ? R : r;
                xs[k] = cx + rad * Math.Cos(a);
                ys[k] = cy + rad * Math.Sin(a);
            }
            int b = earned ? C("f5b83a") : C("b59a74");
            s.Fill((x, y) => InPoly(xs, ys, x, y), b);
            if (earned) s.Bevel(b, C("ffd35c"), C("dc8f22"), C("fff1b8"), C("b5661a"), cx, cy);
            else s.Bevel(b, C("c8b08a"), C("9c825f"), C("dccbaa"), C("826a4b"), cx, cy);
            s.Outline(C("4a2a12"));
            return s;
        }

        static Spr ArrowRight()
        {
            var s = new Spr(8, 11);
            var xs = new[] { 1.2, 1.2, 6.9 };
            var ys = new[] { 1.2, 9.8, 5.5 };
            s.Fill((x, y) => InPoly(xs, ys, x, y), Green.F);
            s.Bevel(Green.F, Green.L, Green.M, Green.H, Green.S, 3.5, 5.5);
            s.Outline(Green.O);
            return s;
        }

        static Spr Check()
        {
            var s = new Spr(11, 11);
            s.Fill((x, y) => SegDist(x, y, 2.3, 5.6, 4.6, 7.9) < 1.1 || SegDist(x, y, 4.6, 7.9, 8.8, 3.0) < 1.1, Green.F);
            s.Bevel(Green.F, Green.L, Green.M, Green.H, Green.S, 5.5, 5.5);
            s.Outline(Green.O);
            return s;
        }

        static Spr BigX()
        {
            var s = new Spr(15, 15);
            int b = C("5a6f96");
            s.Fill((x, y) =>
            {
                double dx = x - 7.5, dy = y - 7.5;
                if (Math.Abs(dx) > 5.4 || Math.Abs(dy) > 5.4) return false;
                return Math.Abs(dx - dy) < 2.3 || Math.Abs(dx + dy) < 2.3;
            }, b);
            s.Bevel(b, C("7d93ba"), C("46587c"), C("a9bddc"), C("33405d"), 7.5, 7.5);
            s.Outline(C("1e2433"));
            return s;
        }

        static Spr Gem()
        {
            var s = new Spr(9, 9);
            int b = C("3fae95");
            s.Fill((x, y) => Math.Abs(x - 4.5) + Math.Abs(y - 4.5) <= 3.6, b);
            s.Bevel(b, C("74d4bd"), C("2c8a74"), C("c2f2e6"), C("1f6a58"), 4.5, 4.5);
            s.Outline(C("173a33"));
            return s;
        }

        static Spr Search()
        {
            var s = new Spr(11, 11);
            int brown = C("6b4026");
            s.Fill((x, y) => Math.Sqrt((x - 4.6) * (x - 4.6) + (y - 4.6) * (y - 4.6)) < 1.9, C("cfe9ef"));
            s.Fill((x, y) =>
            {
                double d = Math.Sqrt((x - 4.6) * (x - 4.6) + (y - 4.6) * (y - 4.6));
                return (d >= 1.9 && d < 3.5) || SegDist(x, y, 6.9, 6.9, 9.0, 9.0) < 1.0;
            }, brown);
            s.Outline(OL2);
            return s;
        }

        // --- Preview-only item pictures (the game uses its own) ---------------

        static Spr Block()
        {
            return FromArt(13, 13, new[] {
                "......O......",
                "....OOHOO....",
                "..OOGHGGGOO..",
                "OOGGGGGGGGGOO",
                "OggGGGGGGGggO",
                "OLLggGGGggDDO",
                "OLLLLggODDDDO",
                "OLLLLLODDDDDO",
                "OLLLLLODDDDDO",
                "OLLLLLODDDDDO",
                "..OOLLODDOO..",
                "....OOOOO....",
                ".............",
            }, new Dictionary<char, int> {
                { 'O', OL }, { 'H', C("a6e07a") }, { 'G', C("79c24f") }, { 'g', C("559a3a") },
                { 'L', C("a8743f") }, { 'D', C("7a5230") },
            });
        }

        static Spr Sword()
        {
            var s = new Spr(14, 14);
            int light = C("e8eef5"), dark = C("9aa7b8"), gold = C("d9a43a"), grip = C("6b4026");
            for (int y = 1; y <= 7; y++) { s.Set(12 - y, y, light); s.Set(13 - y, y, dark); }
            s.Set(12, 1, light);
            s.Set(2, 6, gold); s.Set(3, 7, gold); s.Set(4, 8, gold); s.Set(5, 9, gold); s.Set(6, 10, gold);
            s.Set(3, 9, grip); s.Set(2, 10, grip);
            s.Set(1, 11, gold);
            s.Outline(OL);
            return s;
        }

        static Spr Ingot()
        {
            return FromArt(12, 12, new[] {
                "............",
                "............",
                "...OOOOOOO..",
                "..OHHHHHHSO.",
                ".OHYYYYYYSSO",
                "OOOOOOOOOSSO",
                "OYYYYYYYOSO.",
                "OSSSSSSSOO..",
                "OOOOOOOOO...",
                "............",
                "............",
                "............",
            }, new Dictionary<char, int> { { 'O', OL }, { 'H', C("ffd79a") }, { 'Y', C("ee9440") }, { 'S', C("a85a22") } });
        }

        static Spr Potion()
        {
            return FromArt(12, 12, new[] {
                "............",
                "....OOOO....",
                "....OKKO....",
                "....OGGO....",
                "...OOGGOO...",
                "..OGGGGGGO..",
                ".OGWRRRRRRO.",
                ".ORRRRRRRRO.",
                ".ORRRRRRDRO.",
                ".ORRRRRDDRO.",
                "..ODDDDDDO..",
                "...OOOOOO...",
            }, new Dictionary<char, int> {
                { 'O', OL }, { 'K', C("9c6438") }, { 'G', C("d8eef0") }, { 'W', C("ffffff") },
                { 'R', C("d9573f") }, { 'D', C("93301f") },
            });
        }

        // --- Build --------------------------------------------------------------

        static void BuildAll()
        {
            var g = GreenArt();

            Add("window", "frame_parchment", Frame(true), new[] { 8, 8, 24, 24 }, "Main window: wood frame, parchment inside.");
            Add("window", "frame_wood", Frame(false), new[] { 8, 8, 24, 24 }, "Main window with a wooden inside, for windows split into insets.");
            Add("window", "inset_parchment", Inset(true), new[] { 4, 4, 12, 12 }, "Recessed parchment section inside a window.");
            Add("window", "inset_wood", Inset(false), new[] { 4, 4, 12, 12 }, "Recessed wood section inside a window.");
            Add("window", "header", Header(), new[] { 5, 5, 19, 9 }, "Green title banner over a window's top edge.");
            Add("window", "tooltip", Tooltip(), new[] { 4, 4, 8, 8 }, "Dark hover tooltip.");

            int[] btn = { 4, 4, 12, 10 };
            Add("button", "button_green", Button(Green, false), btn, "Primary action. Label text dark.");
            Add("button", "button_green_hover", Button(GreenHover, false), btn, "");
            Add("button", "button_green_pressed", Button(Green, true), btn, "Pressed: move the label down 2 texels.");
            Add("button", "button_red", Button(Red, false), btn, "Destructive action (drop, delete, quit).");
            Add("button", "button_red_hover", Button(RedHover, false), btn, "");
            Add("button", "button_red_pressed", Button(Red, true), btn, "");
            Add("button", "button_tan", Button(Tan, false), btn, "Secondary action, unselected tabs.");
            Add("button", "button_tan_hover", Button(TanHover, false), btn, "");
            Add("button", "button_tan_pressed", Button(Tan, true), btn, "");
            Add("button", "button_disabled", Button(Grey, false), btn, "Unavailable action.");
            Add("button", "close", Close(Tan, false), null, "Window close button, over the top-right corner.");
            Add("button", "close_hover", Close(TanHover, false), null, "");
            Add("button", "close_pressed", Close(Tan, true), null, "");

            int[] slot = { 4, 4, 12, 12 };
            Add("slot", "slot", Slot(false), slot, "Item slot on parchment.");
            Add("slot", "slot_dark", Slot(true), slot, "Item slot on wood.");
            Add("slot", "slot_highlight", SlotHighlight(), slot, "Overlay laid on a slot. White: tint with ImageColor3 (selection gold, rarity).");

            Add("control", "input", Input(), new[] { 4, 4, 8, 8 }, "Text box (search).");
            Add("control", "checkbox_off", Checkbox(false), null, "");
            Add("control", "checkbox_on", Checkbox(true), null, "");
            Add("control", "toggle_off", Toggle(false), null, "");
            Add("control", "toggle_on", Toggle(true), null, "");
            Add("control", "slider_track", SliderTrack(), new[] { 3, 3, 9, 5 }, "Slider / progress bar background.");
            Add("control", "slider_fill", SliderFill(), new[] { 3, 3, 9, 5 }, "Slider / progress bar fill, same shape as the track.");
            Add("control", "slider_knob", SliderKnob(), null, "");
            Add("control", "scroll_track", FromArt(6, 8, new[] {
                ".KKKK.", "KddddK", "KwwwwK", "KwwwwK", "KwwwwK", "KwwwwK", "KllllK", ".KKKK.",
            }, g), new[] { 0, 3, 6, 5 }, "Behind a ScrollingFrame's bar.");
            Add("control", "scroll_top", FromArt(6, 3, new[] { ".OOOO.", "OHHHHO", "OLFFMO" }, g), null, "ScrollingFrame.TopImage");
            Add("control", "scroll_mid", FromArt(6, 2, new[] { "OLFFMO", "OLFFMO" }, g), null, "ScrollingFrame.MidImage");
            Add("control", "scroll_bottom", FromArt(6, 3, new[] { "OLFFMO", "OSSSSO", ".OOOO." }, g), null, "ScrollingFrame.BottomImage");
            Add("control", "divider", Divider(), new[] { 4, 0, 12, 5 }, "Engraved line across parchment.");
            Add("control", "tab_idle", Tab(false), new[] { 4, 4, 12, 10 }, "Top tab, not selected.");
            Add("control", "tab_active", Tab(true), new[] { 4, 4, 12, 10 }, "Top tab, selected. Overlap the inset below by 3 texels.");
            Add("control", "row", Row(0), new[] { 4, 4, 12, 8 }, "List entry (recipes).");
            Add("control", "row_hover", Row(1), new[] { 4, 4, 12, 8 }, "");
            Add("control", "row_selected", Row(2), new[] { 4, 4, 12, 8 }, "");
            Add("control", "badge", Badge(), new[] { 3, 3, 6, 6 }, "Count pill. Light text.");

            Add("icon", "icon_star", Star(true), null, "");
            Add("icon", "icon_star_empty", Star(false), null, "");
            Add("icon", "icon_arrow_left", ArrowRight().FlipX(), null, "");
            Add("icon", "icon_arrow_right", ArrowRight(), null, "");
            Add("icon", "icon_check", Check(), null, "");
            Add("icon", "icon_x", BigX(), null, "");
            Add("icon", "icon_gem", Gem(), null, "List bullet.");
            Add("icon", "icon_search", Search(), null, "");

            AddPreview("preview_block", Block());
            AddPreview("preview_sword", Sword());
            AddPreview("preview_ingot", Ingot());
            AddPreview("preview_potion", Potion());
            AddPreview("preview_slot_highlight_gold", SlotHighlight().Tint(C("ffd84a")), slot);
            AddPreview("preview_slot_highlight_rare", SlotHighlight().Tint(C("3484ec")), slot);
        }

        static string Lua3(int c)
        {
            return "Color3.fromRGB(" + ((c >> 16) & 255) + ", " + ((c >> 8) & 255) + ", " + (c & 255) + ")";
        }

        static string SliceJson(int[] s)
        {
            return s == null ? "null" : "[" + s[0] + "," + s[1] + "," + s[2] + "," + s[3] + "]";
        }

        public static void Run(string root)
        {
            All.Clear();
            BuildAll();

            string spritesDir = Path.Combine(root, "sprites");
            string atlasDir = Path.Combine(root, "atlas");
            Directory.CreateDirectory(spritesDir);
            Directory.CreateDirectory(atlasDir);
            foreach (string old in Directory.GetFiles(spritesDir, "*.png")) File.Delete(old);

            var manifest = new StringBuilder();
            manifest.Append("{\n  \"scale\": 3,\n  \"note\": \"Sizes are in texels. slice is Roblox SliceCenter (minX, minY, maxX, maxY); null means not sliced.\",\n  \"sprites\": [\n");
            bool first = true;
            foreach (var e in All)
            {
                if (!e.Upload) continue;
                File.WriteAllBytes(Path.Combine(spritesDir, e.Name + ".png"), e.S.Png());
                if (!first) manifest.Append(",\n");
                first = false;
                manifest.Append("    { \"name\": \"" + e.Name + "\", \"group\": \"" + e.Group + "\", \"w\": " + e.S.W + ", \"h\": " + e.S.H +
                    ", \"slice\": " + SliceJson(e.Slice) + ", \"note\": \"" + e.Note.Replace("\"", "'") + "\" }");
            }
            manifest.Append("\n  ]\n}\n");
            File.WriteAllText(Path.Combine(root, "sprites.json"), manifest.ToString());

            // Atlas: every upload sprite on one sheet, 2px apart, for a single upload.
            const int atlasW = 256, pad = 2;
            var order = new List<Entry>();
            foreach (var e in All) if (e.Upload) order.Add(e);
            order.Sort((a, b) => b.S.H != a.S.H ? b.S.H.CompareTo(a.S.H) : string.CompareOrdinal(a.Name, b.Name));
            var pos = new Dictionary<string, int[]>();
            int cx = pad, cy = pad, rowH = 0;
            foreach (var e in order)
            {
                if (cx + e.S.W + pad > atlasW) { cx = pad; cy += rowH + pad; rowH = 0; }
                pos[e.Name] = new[] { cx, cy };
                cx += e.S.W + pad;
                rowH = Math.Max(rowH, e.S.H);
            }
            int atlasH = cy + rowH + pad;
            var atlas = new Spr(atlasW, atlasH);
            var atlasJson = new StringBuilder();
            atlasJson.Append("{\n  \"image\": \"pixel_ui_atlas.png\",\n  \"note\": \"rect is ImageRectOffset (x, y) and ImageRectSize (w, h). slice is relative to the rect.\",\n  \"sprites\": {\n");
            first = true;
            foreach (var e in order)
            {
                int[] p = pos[e.Name];
                atlas.Blit(e.S, p[0], p[1]);
                if (!first) atlasJson.Append(",\n");
                first = false;
                atlasJson.Append("    \"" + e.Name + "\": { \"rect\": [" + p[0] + "," + p[1] + "," + e.S.W + "," + e.S.H + "], \"slice\": " + SliceJson(e.Slice) + " }");
            }
            atlasJson.Append("\n  }\n}\n");
            File.WriteAllBytes(Path.Combine(atlasDir, "pixel_ui_atlas.png"), atlas.Png());
            File.WriteAllText(Path.Combine(atlasDir, "atlas.json"), atlasJson.ToString());

            // Preview page: the template with every sprite inlined, so it opens anywhere.
            var js = new StringBuilder();
            js.Append("const SPRITES = {\n");
            foreach (var e in All)
            {
                js.Append("  " + e.Name + ": { w: " + e.S.W + ", h: " + e.S.H + ", slice: " + SliceJson(e.Slice) +
                    ", group: \"" + e.Group + "\", note: \"" + e.Note.Replace("\"", "'") + "\", uri: \"data:image/png;base64," + Convert.ToBase64String(e.S.Png()) + "\" },\n");
            }
            js.Append("};");
            string template = File.ReadAllText(Path.Combine(Path.Combine(root, "source"), "preview.template.html"));
            File.WriteAllText(Path.Combine(root, "preview.html"), template.Replace("/*@SPRITES@*/", js.ToString()));

            // The game's copy of the same facts: where each sprite is on the atlas,
            // how it slices, and the colours its drawn stand-in uses if the art
            // cannot load.
            var lua = new StringBuilder();
            lua.Append("--[[\n\tPixelSprites\n\n\tGENERATED by assets/pixel-ui/source/build_sprites.ps1 - do not edit by hand;\n" +
                "\tchange the generator and run it again. The asset ids are not here: they are\n" +
                "\tin Theme.Pixel, so regenerating never loses them.\n\n" +
                "\t  offset, size  where the sprite sits on the atlas, in texels\n" +
                "\t  slice         its SliceCenter, relative to the sprite (nil: not sliced)\n" +
                "\t  fill, edge    the stand-in's colours, drawn when the art will not load\n]]\n\n");
            lua.Append("return {\n\tAtlasSize = Vector2.new(" + atlasW + ", " + atlasH + "),\n\tSprites = {\n");
            foreach (var e in All)
            {
                if (!e.Upload) continue;
                int[] p = pos[e.Name];
                lua.Append("\t\t" + e.Name + " = { offset = Vector2.new(" + p[0] + ", " + p[1] + "), size = Vector2.new(" + e.S.W + ", " + e.S.H + ")");
                if (e.Slice != null)
                    lua.Append(", slice = Rect.new(" + e.Slice[0] + ", " + e.Slice[1] + ", " + e.Slice[2] + ", " + e.Slice[3] + ")");
                int fill = e.S.Get(e.S.W / 2, e.S.H / 2);
                if (fill != 0) lua.Append(", fill = " + Lua3(fill));
                int edge = 0;
                for (int x = 0; x < e.S.W && edge == 0; x++) edge = e.S.Get(x, e.S.H / 2);
                if (edge != 0) lua.Append(", edge = " + Lua3(edge));
                if (e.Group == "icon") lua.Append(", icon = true");
                lua.Append(" },\n");
            }
            lua.Append("\t},\n}\n");
            string repo = Path.GetFullPath(Path.Combine(root, Path.Combine("..", "..")));
            string luaPath = Path.Combine(repo, Path.Combine("src", Path.Combine("ReplicatedStorage", Path.Combine("Shared", Path.Combine("UI", "PixelSprites.lua")))));
            File.WriteAllText(luaPath, lua.ToString().Replace("\r\n", "\n"), new UTF8Encoding(false));

            int uploads = 0;
            foreach (var e in All) if (e.Upload) uploads++;
            Console.WriteLine("Wrote " + uploads + " sprites, atlas " + atlasW + "x" + atlasH + ", preview.html");
        }
    }
}
