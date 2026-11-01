-- Four new spells, timed from the supplied reference clips.
local Plan = {}
Plan.VioletTempest = {windup=.75, strikes={.75,.94,1.18}, radius=21, damage={14,14,46}, duration=4.8}
Plan.CelestialLance = {windup=1.65, speed=125, range=140, radius=2.4, damage=72, splash=18, duration=7}
Plan.WraithfireOrb = {windup=1.3, speed=65, range=120, radius=3.2, damage=68, splash=21, duration=8}
Plan.RiftMaelstrom = {windup=.85, ticks={.85,1.45,2.05,2.65}, collapse=3.2, radius=22, damage=10, finalDamage=42, duration=6.2}
function Plan.duration() return 8 end
return Plan
