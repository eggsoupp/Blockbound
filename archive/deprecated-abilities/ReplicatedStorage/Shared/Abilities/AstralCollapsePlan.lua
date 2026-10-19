-- Arrow-circle reinterpretation: six counter-orbiting shards collapse in three beats.
local Plan={Count=6, Radius=14, Damage=40, Hits={1.9,2.15,2.4}}
function Plan.duration() return 6 end
function Plan.shard(index,elapsed)
 local reveal=math.clamp((elapsed-(index-1)*.1)/.3,0,1)
 local collapse=math.clamp((elapsed-1.05)/.85,0,1)
 local radius=14*(1-collapse^2)
 local direction=if index%2==0 then -1 else 1
 local angle=index*math.pi/3+direction*(elapsed*1.8+collapse^2*3)
 return Vector3.new(math.cos(angle)*radius,3+(7+index*.7)*(1-collapse),math.sin(angle)*radius),reveal*(1-collapse^5)
end
return Plan
