# Failed-placement silence and dirt sound replacement

Both locally invalid clicks and rejected server requests are now silent. Placement audio plays only in the successful server-confirmation branch, using preloaded local 2D sounds. This intentionally removes speculative audio: a server-rejected click cannot play the success sound. Network validation must complete first; there is no extra audio-loading delay.

Successful server replies now include the confirmed item and cell centre, preventing rapid requests from stealing each other's material sound or losing their acknowledgement feedback.

Soft placement uses Pro Sound Effects' Rock Hit Dirt Impact 14, Roblox Creator Store asset 9118598279, instead of the magic poof. This is an existing public library asset used by reference, not a new public upload of the user's private assets. It loaded in the running client (source duration 0.37525 seconds). Playback uses a short 0.22-second excerpt at pitch 1.12 and full-level local output.

Runtime checks used a real invalid-slot request and observed zero hard, soft, or denial plays. Event-driven confirmation checks separately exercised the actual client handler with two material confirmations and a refusal, without inventory changes. Source compilation and whitespace checks passed. No live experience version was published.
