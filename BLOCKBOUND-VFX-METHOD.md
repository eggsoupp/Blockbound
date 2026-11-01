# Blockbound VFX Production Method

Use this document as a reusable instruction set when asked to create or improve Roblox VFX. Reading or reviewing this document does not itself authorize building effects, changing Studio, installing tools, or running the bootstrap task below. Follow the user's current request.

## Purpose

Produce visually deliberate, functioning Roblox effects using clear references, appropriate assets, timed layers, and inspection in a running client. Support combat abilities, auras, environmental effects, and cinematic sequences without applying the same composition to every request.

Deliver the requested effect, rather than a tutorial or large framework, unless the user asks for those. Research unfamiliar techniques as needed. Save verified findings so future sessions can reuse them; a prompt does not permanently train the model.

## Blockbound constraints

- Follow the project's current AGENTS.md and existing implementation conventions.
- Build ability effects from the VFX packs supplied in Studio: ParticleEmitters, Beams, Trails, and authored textures/flipbooks.
- Do not simulate flashes, warning circles, shockwaves, speed streaks, or cosmetic debris with visible Parts. Invisible emitter hosts are allowed.
- Physical ability objects explicitly requested by the user, such as a dirt-and-stone meteor, may use blocks. Do not generalize that exception to cosmetic geometry.
- If the target appearance needs an asset or technique outside these constraints, identify the missing requirement and propose a compatible approach. Do not silently substitute visible geometry.
- Test particles through an actual running client script. Direct MCP execution alone is not a reliable particle-rendering check.

## 1. Establish the visual target

Use the request and available context to establish:

- Gameplay purpose and activation or hit trigger.
- Style, palette, silhouette, scale, direction, and intended intensity.
- Camera distance, environment, target devices, and expected simultaneous casts.
- Important animation markers, attachment points, and duration.

Make reasonable assumptions for routine choices. Ask only when missing information materially affects the result, and continue independent work while waiting.

Prefer a short reference clip for motion and still frames for shape and color. Record what should be borrowed: timing, weight, silhouette, motion, or layering. Create an original effect rather than copying another game's exact assets.

When useful, generate a storyboard showing anticipation, release, impact, and aftermath at a consistent scale and gameplay camera angle. For auras, show activation, idle, movement, and deactivation instead. Use existing references directly when they are sufficient; image generation is optional.

A concept image communicates appearance. It is not automatically an importable texture, a valid flipbook, or proof that the design works in 3D.

Before implementation, state a few observable visual targets, such as:

- The hit reads immediately at normal combat distance.
- A sharp initial burst leads into slower dust decay.
- The target and gameplay telegraph remain visible.
- The effect fits the character's scale and the reference palette.

## 2. Inspect tools and select assets

Inspect the relevant supplied packs before creating new assets. Preview candidate textures and effects; names alone are insufficient. Reuse existing catalogue entries when they remain accurate.

For assets actually evaluated or used, preserve:

| Field | Record |
| --- | --- |
| Identity | Stable Studio path or verified asset ID and source pack |
| Appearance | Preview image or captured effect, with its file path |
| Purpose | Smoke, impact, slash, ring, sparks, beam, or another concrete role |
| Configuration | Relevant orientation, texture layout, playback, and timing notes |
| Status | Visually verified, inspected only, unavailable, or placeholder |

The original method names VFX Forge v2.4.0-rc1. Treat its installation, version, and capabilities as unverified until inspected. Use available Studio tools or the plugin UI to establish what it can actually do. Do not invent APIs or assume its internals are accessible. Use Forge where it helps; native Roblox authoring remains a valid route.

Verify unfamiliar engine properties and import constraints against current official documentation. Research the systems needed for the current effect, rather than writing an exhaustive Roblox textbook first.

## 3. Decompose the effect and plan its timing

Create a compact layer timeline before implementing a complex effect:

| Layer | Asset and system | Start or trigger | Duration | Motion and appearance |
| --- | --- | --- | --- | --- |
| Anticipation | Selected telegraph asset | Before release | Ability-specific | Establish direction and scale |
| Main action | Selected beam, trail, or emitter | Release or animation marker | Ability-specific | Define the main silhouette |
| Impact | Selected burst assets | Confirmed impact | Brief | Fast readable accent |
| Residual | Selected dust, smoke, or energy | After impact | Slower decay | Settle and fade without hiding play |

These are possible roles, not mandatory layers. Simple effects may need only one or two. Cinematics and auras need timelines suited to their behavior.

Give each layer a purpose, attachment or coordinate space, emission behavior, and size, color, opacity, and movement curves. Establish the dominant silhouette and timing before adding fine detail. Avoid brightness or particle density that obscures the composition.

## 4. Implement the smallest complete effect

Use existing project playback and configuration systems where practical. Keep important timing, scale, color, and emission settings easy to tune. Do not build a universal editor or sequencing framework just to deliver one ability.

- Keep cosmetic rendering on the client where appropriate; preserve server authority over gameplay and damage.
- Synchronize release and impact with the project's actual ability events or animation markers.
- Handle position, orientation, attachment, movement, and interrupted activation explicitly.
- Give emitters, hosts, tasks, connections, lights, and camera changes bounded lifetimes and reliable cleanup.
- Support repeat playback without accumulating instances or connections.
- Use pooling when observed usage justifies it, rather than adding it automatically.
- Make optional camera and post-processing effects proportionate to gameplay and restore any state they change.

Do not invent texture IDs, plugin functions, uploaded assets, or test results. Identify placeholders clearly.

## 5. Create missing assets only when needed

First determine why the supplied assets cannot achieve the target. If custom asset creation is within the user's scope, use an available tool suited to the missing component.

For generated textures, request isolated effect components with appropriate alpha, clean edges, and padding. Check the imported appearance; a black background is not equivalent to transparency.

For flipbooks, verify temporal consistency, frame order, grid layout, padding, alpha, and playback in Roblox. Do not assume an image generator produces a coherent animation merely because it returns a grid of pictures. Prefer authored or simulated sequences when consistency is inadequate.

Verify the actual creation and import path before depending on Blender, EmberGen, image tools, or other external software. Do not assume they are installed, connected, or fully controllable. Save source files when practical. Do not claim an asset has been uploaded until confirmed.

## 6. Inspect in a running client and iterate

Trigger the effect through its real gameplay path or a small client preview harness. Inspect it at gameplay distance, not only in a close editor view.

Capture useful frames across its timeline and review playback for pacing. Isolated screenshots can assess composition but cannot establish smooth motion. If only still captures are available, inspect multiple moments and report that limitation.

Review:

- Silhouette, palette, scale, and match to the visual target.
- Anticipation, release, impact timing, and decay.
- Character alignment and movement at relevant viewing angles.
- Target visibility, telegraph readability, and environmental contrast.
- Repeated casts, overlapping effects, and interrupted playback.
- Cleanup, errors, and network behavior relevant to the change.

Fix the largest visible weakness first. Describe concrete changes: shorten a flash, delay smoke, sharpen a silhouette, reduce coverage, or adjust direction. Re-run the affected sequence after material changes.

Use a proportional review loop: implement, inspect, revise, then verify the revision. Continue when a clear fix is available. If progress depends on missing assets, inaccessible rendering, or a design decision, preserve the usable result and explain the specific limitation instead of claiming perfection or iterating indefinitely.

## 7. Verify performance and completion

Consider peak concurrent effects, particle lifetimes and counts, screen coverage, overlapping transparency, texture memory, and update work. Reuse textures where possible. Provide simpler quality variants when the game's needs justify them.

Measure performance when the tools allow it, documenting the tested scene and device or environment. Do not call an effect mobile-optimized based only on appearance or desktop testing.

An effect is ready when it meets the agreed visual targets, plays correctly through the intended client path, handles relevant interruption and cleanup, and has no known blocking defects within the tested scope.

Report separately:

- What was built and where its assets and scripts live.
- What was visually inspected, including captures when available.
- What functionality and performance were checked.
- Remaining limitations or untested conditions.

## 8. Preserve proven knowledge

Save concise project-local records of verified asset choices, useful configurations, final references or captures, and effect-specific implementation notes. Follow an existing documentation structure when available.

Distinguish verified techniques from experiments. Update records when an asset path or technique changes. Store working prefabs and scripts alongside notes where appropriate; descriptions alone cannot reproduce an effect.

Add reusable helpers only after a concrete need appears. Build teaching material only when requested, using the actual working effect as the example.

## Optional bootstrap task

Run this only when the user requests initial VFX setup or a first demonstration:

1. Inspect relevant supplied packs, existing playback code, and accessible Forge functionality.
2. Create a small illustrated catalogue of assets needed for one representative Blockbound ability.
3. Establish that ability's reference and observable visual targets.
4. Build and visually refine the effect in a running client.
5. Verify relevant repeat playback, cancellation, and cleanup behavior.
6. Save the effect, captures, configurations, and verified findings for reuse.

Expand to other effect families after this first workflow succeeds. Do not automatically build five unrelated demonstrations, a textbook, or a large development environment.
