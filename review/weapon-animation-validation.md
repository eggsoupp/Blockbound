# Weapon animation integration

Mappings: HeavySword → Blade, Lance → Glaive, Sword → LightAxe.

Each class uses all five published light attacks. Contact, swing sound, and recovery times are taken from the purchased clips' Hit, Swing, and Reset markers. Damage and animation playback share a server-owned timeline. Attack speed scales both. Equipped idle/run/walk clips are mapped where the pack supplies them; existing gaits remain for missing clips.

Input sends only the equipped Tool and a press/release boolean. The server validates equipment, life state, cooldown, and weapon classification, and chooses the animation, targets, damage, and combo index. Warming tracks before accepting an attack prevents a cold asset fetch from consuming its windup.

The existing generous 220° arc, near-side body allowance, and close-range facing forgiveness are retained. The contact window is sampled at 30 Hz for up to 0.12 animation seconds after Hit (ending before Reset). Each enemy can be damaged only once per swing, and the target cap is shared across the entire window. Putting the tool away cancels pending hits; swapping tools preserves recovery.

## Validation

Studio Play tests ran in ordinary server Scripts and client LocalScripts, without mouse/keyboard automation:

- All 15 attack steps: correct class, combo index, damage, and marker-derived delay; maximum timing error under 0.018 seconds.
- Side and touching-behind targets hit; distant-behind and out-of-range targets missed.
- A target entering during the contact window was hit once.
- Unequipping during windup cancelled damage; malformed input did not deal damage.
- Holding at 1.25× speed produced exactly five correctly timed hits and stopped on release; active animation tracks were at their contact poses.
- A separate unmodified EnemyService test reduced a real GreenSlime's health from 25 to 20 through normal Tool activation.
- All seven changed/new Luau sources compiled in Studio; project JSON and diff whitespace checks passed.

Full measurements are in weapon-animation-validation.json. To repeat the deterministic tests, temporarily place weapon-animation-integration.server.luau in ServerScriptService and its client companion in StarterPlayerScripts, then Play. The hold test likewise uses its server/client companion files in those locations, after the main test finishes. These harnesses temporarily substitute EnemyService targeting/damage and restore them on completion. Remove the harnesses after testing; they are outside the Rojo project and are not game content.

Existing Studio warnings about unrelated VFX/audio assets were outside this change.
