-- Four new spells, timed from the supplied reference clips.
local Plan = {}
Plan.VioletTempest = {windup=.65, strikes={.65,.84,1.08}, radius=11, damage={10,10,28}, duration=3.1}
Plan.CelestialLance = {windup=.8, speed=105, range=95, radius=1.1, damage=36, splash=7, duration=4.3}
Plan.WraithfireOrb = {windup=.65, speed=56, range=85, radius=1.8, damage=32, splash=10, duration=5.4}
Plan.RiftMaelstrom = {windup=.8, ticks={.8,1.2,1.6,2}, collapse=2.4, radius=12, damage=7, finalDamage=28, duration=4.5}
function Plan.duration() return 5.4 end
return Plan
