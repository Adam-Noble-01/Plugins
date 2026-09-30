# Na SketchUp MCP

**Lets AI agents inspect, model and present the SketchUp 2026 model that is open on your PC.** It works with any MCP client (Claude Code, Claude Desktop, Codex / GPT-6 Astra, Cursor, VS Code, Gemini CLI) through 44 tools. Every SketchUp API call it makes is checked against SketchUp's official API index, so no API is invented.

Built by Noble Architecture in the Na__ plugin style.

## What an Agent Can Do

- **See the model.** It can list the outliner, search entities by type, name, tag, material or attribute, and read full details: world placement, geometry, attributes and definitions. It measures bounds, areas, volumes and lengths and runs ray tests. `view_capture` returns images of the model, so the agent can check its own work.
- **Model.** It can draw lines, rectangles, circles, arcs, polygons and faces with holes, and make nine manifold primitives. It builds meshes with EntitiesBuilder, runs push/pull and Follow Me, and does solid booleans (union, subtract, intersect, trim, split, outer shell). It can soften, reverse, intersect and merge faces, and move, rotate, scale, mirror and array entities.
- **Organise and present.** Groups and components, tags and tag folders, materials (colours, textures and PBR), scenes, styles, environments, section planes, text, dimensions, guides and images. It can also save, save a copy, export and import.
- **Use your component library.** With Na Noble3d Modelling Tools loaded, `asset_library` browses the Component Editor Tools library, allocates the next free code and checks names against your convention. `asset_library_edit` saves, renames, moves, archives and tidies it. Every change is journaled and can be reverted.
- **Everything else.** `ruby_eval` runs Ruby with the model's undo and safety rules. `ruby_api_lookup` answers from the official API index, and can confirm against the live SketchUp.

## Quick Start

1. The plugin is already in the Plugins folder (`Na__SketchUpMcp__Loader__.rb` + this folder). Start or restart SketchUp. The bridge starts on its own; see **Extensions > Na SketchUp MCP**.
2. Add the server to your client. **Extensions > Na SketchUp MCP > Status Dialog > Connect an agent** has ready-made snippets. The full instructions for each client are in [`85__Docs__AgentReference/Na__SketchUpMcp__ClientSetup__.md`](85__Docs__AgentReference/Na__SketchUpMcp__ClientSetup__.md). For Claude Code:
   ```bash
   claude mcp add sketchup --scope user --env PYTHONUTF8=1 -- python "C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins\Na__SketchUpMcp__Modules__\30__McpServer__Python\Na__SketchUpMcp__Server__Main__.py"
   ```
3. Ask: *"Look at my SketchUp model and tell me what's in it."*

It needs Python 3.9+ and no packages. Claude's **Add custom connector** dialog only accepts remote HTTPS servers, so use the local setup above. Don't publish the bridge through a tunnel.

## How It Works

```
 MCP client (Claude, Codex, Cursor, VS Code, Gemini ...)
      |  stdio, MCP 2024-11-05 ... 2025-11-25 and 2026-07-28
 Python MCP server         30__McpServer__Python   (stdlib only)
      |  TCP 127.0.0.1, one JSON line each way, per-session token
 Ruby bridge in SketchUp   04__ / 06__ / 10__       (non-blocking UI.start_timer pump)
      |
 SketchUp Ruby API, main thread
```

- **Tools.** One JSON registry (`02__Plugin__CoreAppData/..ToolRegistry__.json`) defines every tool: its schema, description, timeout, undo behaviour and the SketchUp API it depends on. The Python server publishes it; the Ruby bridge routes and checks against it.
- **Windows.** Each SketchUp window is a separate process with its own bridge, and it writes a connection file giving its port and token. The server finds every window, and `sketchup_status` lets the agent pick one.
- **Units and coordinates.** Everything is world coordinates in mm (or the unit asked for), degrees and persistent ids. That holds at every nesting depth, including inside open, rotated and scaled groups, following SketchUp's rule for the active context.

## Safety

- **Localhost only.** Every connection needs a random token created for that session and compared in constant time. A connection whose first line isn't JSON is dropped, which blocks browser-based attacks.
- **Undo.** Every model change is **one undo step** (`MCP: <Tool>`). A failed call is rolled back, and `batch_execute` is atomic by default.
- **User switches.** The status dialog has **Read-Only Mode** and **Allow Ruby Eval**. SketchUp's status bar and the dialog's activity log show every call.
- **No overwrites.** File tools never overwrite a file or discard unsaved work unless the agent passes an explicit flag, and the agent is told to do that only when you asked. Exporter and importer summary dialogs are forced off, and during Ruby eval modal dialogs are answered automatically, so SketchUp can't hang.

## Validation

| Check | Result (v1.0.3) |
|---|---|
| Offline "no invented API" validator | 44 tools, 176 API dependencies, 4,361 method calls, 214 constants and 44 routes checked against 2,087 SketchUp methods (up to 2026.1) plus the Ruby 3.2.2 core names. This includes the 7 Component Editor Tools files the library tools run |
| Live API self-test at bridge start | 176 of 176 dependencies present in SketchUp Pro 26.2.243 |
| Ruby, run with SketchUp's own Ruby 3.2.2 | 44 of 44 files compile; 50 bridge-core checks pass (linear maths, units, params, and the socket server over real TCP). The library seam passes 76 checks in its own suite |
| Python MCP server | 24 protocol tests against a fake bridge |
| Live, in SketchUp 2026.2 (zero-trace batches) | Primitive volumes match their formulas exactly. A box placed at a world point inside a 45° group, inside a 30°-rotated, moved, 2×1.5×1-scaled group, lands exactly there. Booleans, extrusion direction, `move_to`, captures and Reload Plugin Data all work |

For developers and coding agents, [`AGENTS.md`](AGENTS.md) gives the layout, the rules, the commands and how to add a tool.

## Prior Art

A survey in September 2026 looked at about 40 SketchUp MCP projects on GitHub. The full notes are in the devlog.

- **Trimble.** Trimble's **SketchUp connector for Claude** (April 2026) is a remote connector that works on cloud models. It cannot edit the model open on your desktop. There is no official local MCP.
- **[mhyrr/sketchup-mcp](https://github.com/mhyrr/sketchup-mcp)** is the project most others copy. It has no licence file, a blocking `client.gets` on SketchUp's UI thread, and boolean code that calls API that doesn't exist. It has no undo operations and throws results away. It was studied, not used.
- **Ideas adopted** (no code was copied):
  - [zinin/sketchup-mcp2](https://github.com/zinin/sketchup-mcp2): a non-blocking timer pump with a re-entrancy guard; never retrying calls that change the model; the correct `cutter.subtract(target)` order.
  - [Ringophilia/Ringo-Sketchup-MCP](https://github.com/Ringophilia/Ringo-Sketchup-MCP): a per-user session token and newline-delimited JSON; Ruby eval behind a switch.
  - [dcc-mcp/dcc-mcp-sketchup](https://github.com/dcc-mcp/dcc-mcp-sketchup): constant-time token comparison and zero-timeout `IO.select`.
  - [CyrusStudio's fork](https://github.com/CyrusStudio/sketchup-mcp): guarding against timer re-entry.
  - LItterBoy-GB's fork: auto-answering modal dialogs during eval.
  - cmjang's fork: API lookup before eval, and images returned inline.
  - [blender-mcp](https://github.com/ahujasid/mcp-for-blender): the lessons it learnt the hard way about framing and UTF-8.
- **What this server adds.**
  - One tool registry with a validator, so no API is invented.
  - World coordinates at every nesting depth.
  - One undo step per call and atomic batches with references between steps.
  - Discovery of several SketchUp windows at once.
  - A live API self-test when the bridge starts.
  - Both MCP protocol eras.
  - Agent docs for every major client.

## Licences

The API index is derived from SketchUp's [ruby-api-stubs](https://github.com/SketchUp/ruby-api-stubs) (MIT). See [`85__Docs__AgentReference/Na__SketchUpMcp__ThirdPartyNotices__.md`](85__Docs__AgentReference/Na__SketchUpMcp__ThirdPartyNotices__.md). SketchUp is a trademark of Trimble Inc.; this is an independent plugin.
