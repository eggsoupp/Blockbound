# Rebuilds atlas/item_icons_atlas.png, atlas/preview.png and
# src/ReplicatedStorage/Shared/UI/ItemSprites.lua from source/icons.txt.
#   powershell -ExecutionPolicy Bypass -File assets/item-icons/source/build_item_atlas.ps1
#
# icons.txt is APPEND-ONLY - see the header of build_item_atlas.cs. After a
# rebuild, upload the atlas and put its id in Theme.ItemAtlas.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$repo = Split-Path -Parent (Split-Path -Parent $root)
Add-Type -Path (Join-Path $here 'build_item_atlas.cs') -ReferencedAssemblies System.Drawing
[ItemIcons.Builder]::Run($root, (Join-Path $repo 'src/ReplicatedStorage/Shared/UI/ItemSprites.lua'))
