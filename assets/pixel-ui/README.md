# Pixel UI kit

Blockbound's wood-and-parchment pixel-art UI: windows, buttons, slots, controls
and icons. Open **preview.html** in a browser to see every screen built from
these sprites at in-game scale. It is self-contained (the sprites are inlined),
so it opens straight from disk.

## What's here

| Path | What it is |
| --- | --- |
| `sprites/*.png` | 49 sprites at 1x, the files to upload |
| `atlas/pixel_ui_atlas.png` | The same sprites on one 256×77 sheet, with `atlas.json` rects |
| `sprites.json` | Every sprite's size, SliceCenter and purpose |
| `preview.html` | The review page |
| `source/` | The generator. Edit `build_sprites.cs`, then rerun it |

Rebuild everything after changing the generator:

```
powershell -ExecutionPolicy Bypass -File assets/pixel-ui/source/build_sprites.ps1
```

It uses the .NET Framework built into Windows, so nothing needs installing.

## Using them in Roblox

- Everything is drawn at **1x: one PNG pixel is one texel**. Show it at **3x**,
  so a texel is 3px at 1080p, the scale the preview uses.
- Set `ResampleMode = Enum.ResamplerMode.Pixelated` on every ImageLabel and
  ImageButton, or the art blurs.
- Sprites with a `slice` in `sprites.json` are 9-sliced: `ScaleType = Slice`,
  `SliceCenter = Rect.new(slice...)`, `SliceScale = 3`. They stretch to any
  size and the corners keep their shape.
- Sprites without a slice are shown at exactly 3× their size, for example
  `close` at 39×39.
- `slot_highlight` is white on purpose. Tint it with `ImageColor3`: gold for
  the selection, the rarity colour for rarity.
- `*_pressed` buttons are drawn two texels lower. Move the label down 6px while
  pressed so it moves with the button.
- Text: Roblox's built-in Arcade font (`rbxasset://fonts/families/PressStart2P.json`)
  is the font the preview uses.

## In the game

The kit is wired in through `Shared.UI.PixelUI`, and the generator also writes
`src/ReplicatedStorage/Shared/UI/PixelSprites.lua`, the atlas positions and
slices, every time it runs. The asset ids live in `Theme.Pixel`, so
regenerating never loses them.

To switch the art on:

1. In Studio, upload `atlas/pixel_ui_atlas.png` to the group, for example
   through the Asset Manager.
2. Put its **image** id in `Theme.Pixel.Atlas`.
3. Optional: upload `scroll_top`, `scroll_mid` and `scroll_bottom` on their own
   and list them in `Theme.Pixel.Images`. Scroll bars can't use an atlas.

If a sliced sprite ever draws wrongly off the atlas, upload just that file and
list it in `Theme.Pixel.Images`. A sprite listed there always wins over the
atlas. Until ids are filled in, the windows draw as flat frames in the kit's
colours.

## Palette

| Role | Colours |
| --- | --- |
| Outline | `#2b1810`, inner `#3b2416` |
| Frame wood | `#b77d47` `#9a6136` `#8a5530` `#693d22` `#4f2c18` |
| Recessed wood | `#7d4c2c` `#6b4026` `#5a3520` `#4a2a17` |
| Parchment | `#f8ebc8` `#efdcae` `#dcc08a` `#c6a06a` `#a87c4c` |
| Primary green | `#a8ecbb` `#7dd49c` `#52b87f` `#44a06d` `#348758` `#266443` |
| Text | ink `#3a2414`, heading teal `#2f5552`, on wood `#f6e7c1` |
