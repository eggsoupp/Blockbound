# Rebuilds sprites/, atlas/, sprites.json and preview.html from build_sprites.cs.
#   powershell -ExecutionPolicy Bypass -File assets/pixel-ui/source/build_sprites.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Add-Type -Path (Join-Path $here 'build_sprites.cs') -ReferencedAssemblies System.Drawing
[PixelUI.Builder]::Run($root)
