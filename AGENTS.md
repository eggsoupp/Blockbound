# VFX authoring

- Build ability effects from the VFX asset packs supplied in Roblox Studio: ParticleEmitters, Beams, Trails, and authored effect textures/flipbooks.
- Do not simulate flashes, warning circles, shockwaves, speed streaks, or cosmetic debris with visible Parts. Invisible emitter hosts are fine. Physical ability objects explicitly requested by the user, such as a dirt-and-stone meteor, may use blocks.
- Inspect effects in an actual running client script and iterate visually; a direct MCP execution context can fail to render particles that work in normal gameplay.
