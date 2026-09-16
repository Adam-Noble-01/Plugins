# Array presets library

The gallery starts empty. Save your own configurations in Array Builder's Preset Editor.

Each `Na__ArrayPreset__<uuid>__.json` stores schema version, identity, name, category,
description, timestamps and validated configuration. Object presets also reference
a portable `.skp` in `02__SourceObjects`, with the picked source's axis scales.
Copy this whole folder to transfer the gallery to another computer.

Updating a preset keeps its previous JSON as `.bak`. Archive moves the JSON to
`01__Archive`; restore it by moving it back to this folder. Source files are retained
so backups and archived recipes can still load. Missing or invalid records are
reported without preventing other presets from loading. Presets contain no model
path; the same recipe can be applied to different paths.
