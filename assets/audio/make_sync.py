import json
from pathlib import Path
r=Path(__file__).resolve().parents[2];out=Path(__file__).parent
paths=json.loads((out/'changed-files.json').read_text())
lines=['local definitions = {']
for rel in paths:
 p=r/rel;bits=p.relative_to(r/'src').parts;name=bits[-1].replace('.client.lua','').replace('.lua','')
 cls='LocalScript' if p.name.endswith('.client.lua') else 'ModuleScript'
 lines.append('{path='+json.dumps('/'.join((*bits[:-1],name)))+',class='+json.dumps(cls)+',source='+json.dumps(p.read_text(),ensure_ascii=False)+'},')
lines+=['}', '''local errors = {}
for _, def in ipairs(definitions) do
    local fn, err = loadstring(def.source, def.path)
    if not fn then table.insert(errors, {path=def.path,error=err}) end
end
if #errors > 0 then return {errors=errors} end
local updated = {}
for _, def in ipairs(definitions) do
    local bits = string.split(def.path, "/")
    local parent = game:GetService(table.remove(bits, 1))
    local name = table.remove(bits)
    for _, bit in ipairs(bits) do parent = parent:FindFirstChild(bit); assert(parent, def.path) end
    local target = parent:FindFirstChild(name)
    if not target then target=Instance.new(def.class);target.Name=name;target.Parent=parent end
    assert(target.ClassName == def.class, def.path)
    target.Source = def.source
    table.insert(updated, def.path)
end
return {updated=updated, syntaxErrors=errors}''']
(out/'sync.luau').write_text('\n'.join(lines))
print('Prepared source sync with syntax validation')
