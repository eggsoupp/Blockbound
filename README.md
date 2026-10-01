# BlockBound Rojo source

This folder contains every Script, LocalScript, and ModuleScript exported from `blockbound(rbxlx).rbxlx`.

- `default.project.json` preserves the original Roblox hierarchy and script names for Rojo.
- `src/scripts` contains the exact script source text.
- `scripts-manifest.json` records each original Roblox path, class, source file, and SHA-256 hash.
- `$ignoreUnknownInstances` is enabled on containers so connecting Rojo to the original place does not delete non-code instances.

Use `rojo serve` from this directory, then connect with the Rojo Studio plugin.
