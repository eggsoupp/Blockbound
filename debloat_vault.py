from pathlib import Path
import re, zipfile, json

root = Path(r'C:\Users\Elias\Downloads\LihFolk Vault V1 Lite')
vault = root / 'LihFolk Vault V1'
backup = Path(r'C:\Users\Elias\Documents\Blockbound\review\obsidian-original-notes.zip')
files = list(root.rglob('*.md'))
before = sum(p.stat().st_size for p in files)
backup.parent.mkdir(parents=True, exist_ok=True)
if backup.exists():
    raise SystemExit('Backup exists; refusing to overwrite originals')
with zipfile.ZipFile(backup, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, p.relative_to(root))

instructions = '''# Roblox reference vault
Do not preload this vault, its index, section hubs, or linked notes.
For a relevant Roblox task, search filenames first, then search text inside the most relevant section. Limit search output to matching lines.
Read only the relevant heading or excerpt from at most two notes initially. Expand only when the task requires it. Do not follow backlinks automatically.
These notes are condensed extracts, not verified documentation. Check current official documentation when API accuracy matters. Never invent APIs.
Prefer project-specific instructions and actual project code over generic advice here.
Keep code server-authoritative and validate client input.
Full original notes are backed up outside this vault at C:/Users/Elias/Documents/Blockbound/review/obsidian-original-notes.zip. Consult individual originals only when explicitly needed; never load the archive wholesale.
'''
changed = 0
for p in files:
    rel = p.relative_to(vault) if p.is_relative_to(vault) else p.relative_to(root)
    # Preserve executable skill definitions, licences and compact original notes.
    if '.claude' in rel.parts or '31 AI Skills for Roblox' in rel.parts or p.name == 'LICENSE.md':
        continue
    if p.name in ('AGENTS.md', 'CLAUDE.md'):
        p.write_text(instructions, encoding='utf-8'); continue
    if p.name in ('VAULT_INDEX.md', '00 Start Here.md'):
        continue
    text = p.read_text(encoding='utf-8-sig')
    if len(text) <= 2600:
        continue
    text = re.sub(r'\A---\s*\n.*?\n---\s*\n', '', text, flags=re.S)
    text = re.sub(r'^```[^\n]*\n.*?^```\s*$', '', text, flags=re.S | re.M)
    blocks = re.split(r'\n\s*\n', text)
    title = next((b for b in blocks if b.startswith('# ')), '# ' + p.stem)
    intro = next((b for b in blocks if not b.startswith(('#','|','-','!','>')) and len(b)>80), '')
    selected = []
    heading = ''
    for block in blocks:
        if block.startswith('#'):
            heading = block.lower()
        priority = any(k in heading for k in ('checklist','common mistake','pitfall','rules','when to','tradeoff','security','decision'))
        if priority and not block.startswith(('#','|')) and len(block) <= 900 and 'Connected notes' not in block:
            selected.append(block)
    out = title + '\n\n'
    if len(intro) <= 1100:
        out += intro + '\n\n'
    out += '## Practical rules (extracted)\n\n'
    for block in selected:
        if len(out) + len(block) < 2450:
            out += block + '\n\n'
    if not selected:
        for block in blocks:
            if block != intro and block != title and not block.startswith(('#','|','!')) and 40 < len(block) < 700 and len(out)+len(block)<2200:
                out += block + '\n\n'
    out += '_Condensed extract; full examples and context are in the external original-notes backup._\n'
    p.write_text(out, encoding='utf-8')
    changed += 1

sections = sorted(p.name for p in vault.iterdir() if p.is_dir() and re.match(r'\d',p.name))
navigation = '# Vault map\n\nSearch filenames or one relevant section. Do not read every note.\n\n' + '\n'.join('- ' + s for s in sections) + '\n'
(vault/'VAULT_INDEX.md').write_text(navigation, encoding='utf-8')
(vault/'00 Start Here.md').write_text(navigation, encoding='utf-8')
# The actual Obsidian root is one level above the content folder.
for name in ('CLAUDE.md','AGENTS.md'):
    (root/name).write_text(instructions, encoding='utf-8')
after = sum(p.stat().st_size for p in root.rglob('*.md'))
report = dict(notes_condensed=changed, before_bytes=before, after_bytes=after, reduction_percent=round(100*(1-after/before),1), backup=str(backup))
Path(r'C:\Users\Elias\Documents\Blockbound\review\obsidian-debloat-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
