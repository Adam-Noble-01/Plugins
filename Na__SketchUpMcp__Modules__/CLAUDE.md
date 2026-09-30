@AGENTS.md

## Claude Code Notes

- The global SketchUp coordinate rule in `~/.claude/CLAUDE.md` is what `06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Coordinates__.rb` implements. Change the helper, not the handlers.
- `../.mcp.json` registers this server for sessions opened in the Plugins folder. Once it is approved, the tools are `mcp__sketchup__*`: use them for zero-trace live checks instead of guessing SketchUp behaviour.
