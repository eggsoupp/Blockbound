# VoxelNest skybox conversion

Purchased source: `C:/Users/Elias/Downloads/Voxel_skybox_full.zip`.
Original files are preserved in `original/`. Do not redistribute purchased assets.

Run `convert.py` using the bundled Python runtime with OpenEXR installed in
`build/skybox/python`. Outputs are six 2048px PNG faces per sky in `converted/`.
The source horizontal-strip order is +X, -X, +Y, -Y, +Z, -Z, mapped to Roblox
Rt, Lf, Up, Dn, Bk, Ft. Confirm seams and orientation in Studio before final use.
True EXR images are converted from linear to sRGB at -1 stop exposure. Files
whose contents are PNG retain their authored colors despite their EXR extension.

Suggested first preset: Cloudy Bright Day.
Upload its six images through Roblox Studio, then assign their asset IDs to the
matching SkyboxRt/Lf/Up/Dn/Bk/Ft properties on a Sky inside Lighting.

Status: Cloudy Bright Day is applied in BlockBound with group-owned uploads.
The strip's side faces do not map to same-named Sky properties: use
SkyboxRt = Bk.png, SkyboxFt = Rt.png, SkyboxBk = Lf.png, SkyboxLf = Ft.png
(Up unchanged). This was confirmed seamless at the zenith in a running client.
`apply-cloudy-day.luau` records this mapping and checks loading first.
