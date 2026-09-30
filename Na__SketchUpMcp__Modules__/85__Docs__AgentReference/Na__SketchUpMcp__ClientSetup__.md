# Na SketchUp MCP - Client Setup
# =============================================================================

The server is a local stdio program. Every MCP client that can run local servers can use it: Claude Code, Claude Desktop, Codex (GPT models, including GPT-6 Astra), Cursor, VS Code, Gemini CLI and others.

```
python "<Plugins>\Na__SketchUpMcp__Modules__\30__McpServer__Python\Na__SketchUpMcp__Server__Main__.py"
```

- **Python.** It needs Python 3.9 or newer and no packages (standard library only). On this PC `python` is `C:\Users\adamw\AppData\Local\Programs\Python\Python312\python.exe`. If a client says it cannot find `python`, use that full path instead.
- **SketchUp.** The bridge starts with SketchUp. You can switch it with **Extensions > Na SketchUp MCP > Bridge Running**. The MCP server starts fine without SketchUp; `sketchup_status` then tells the agent SketchUp isn't connected.
- **Ready-made snippets.** **Extensions > Na SketchUp MCP > Status Dialog > Connect an agent** shows each snippet below with this PC's path filled in and a Copy button.
- **Paths.** Every snippet below uses this PC's path. JSON accepts forward slashes, and Python reads them fine on Windows.

## 1. Check the Server Before Adding It

```bash
python "C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__SketchUpMcp__Modules__/30__McpServer__Python/Na__SketchUpMcp__Server__Main__.py" --check
```

This prints the tool count and every SketchUp window whose bridge it can reach, then exits.

## 2. Claude Code

**User scope (every project):**
```bash
claude mcp add sketchup --scope user --env PYTHONUTF8=1 -- python "C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins\Na__SketchUpMcp__Modules__\30__McpServer__Python\Na__SketchUpMcp__Server__Main__.py"
```

- **Project scope.** The Plugins folder has a `.mcp.json`, so any Claude Code session opened there offers the server. Claude Code asks you to approve it the first time.
- **Check it.** `claude mcp list` should show `sketchup` as connected. The tools appear as `mcp__sketchup__<tool>`.

## 3. Claude Desktop

Open **Settings > Developer > Edit Config**. That opens `claude_desktop_config.json`, including for Microsoft Store installs. Add:

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "python",
      "args": ["C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__SketchUpMcp__Modules__/30__McpServer__Python/Na__SketchUpMcp__Server__Main__.py"],
      "env": { "PYTHONUTF8": "1" }
    }
  }
}
```

Quit Claude Desktop completely (tray icon > Quit) and start it again.

**Why "Add custom connector" does not work for this server**
- That dialog (Settings > Connectors) only takes **remote** servers at a public HTTPS address.
- This server is deliberately local: it talks to the SketchUp on this PC through 127.0.0.1 only.
- **Do not publish it through a tunnel** (ngrok, Cloudflare Tunnel and the like). Anyone who can reach it can edit your models and, with Ruby eval on, run code on this PC.
- Use the Developer config above instead.
- Trimble's own **SketchUp connector for Claude** is a different product. It is remote, and it works on SketchUp models in Trimble's cloud. It cannot edit the model open on your desktop.

## 4. Codex (OpenAI GPT models, including GPT-6 Astra)

```bash
codex mcp add sketchup --env PYTHONUTF8=1 -- python "C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins\Na__SketchUpMcp__Modules__\30__McpServer__Python\Na__SketchUpMcp__Server__Main__.py"
```

Then raise the timeouts in `~/.codex/config.toml`. The Codex defaults are 10 s to start and 60 s per tool; big captures and batches need longer. The whole entry should read:

```toml
[mcp_servers.sketchup]
command = "python"
args = ['C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins\Na__SketchUpMcp__Modules__\30__McpServer__Python\Na__SketchUpMcp__Server__Main__.py']
startup_timeout_sec = 20
tool_timeout_sec = 300

[mcp_servers.sketchup.env]
PYTHONUTF8 = "1"
```

The single quotes make a TOML literal string, so the backslashes need no escaping.

**Instructions for Codex**
- Codex reads `AGENTS.md` from the folder it runs in, up to the repository root.
- When working on this plugin, run Codex inside `Na__SketchUpMcp__Modules__`; its `AGENTS.md` covers the codebase.
- When modelling from any other folder, install the skill (§8).

## 5. Cursor

In `~/.cursor/mcp.json` (all projects) or `.cursor/mcp.json` (one project):

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "python",
      "args": ["C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__SketchUpMcp__Modules__/30__McpServer__Python/Na__SketchUpMcp__Server__Main__.py"],
      "env": { "PYTHONUTF8": "1" }
    }
  }
}
```

If Cursor warns about too many tools, add `"--toolset", "core"` after the path in `args`. That keeps the 22 essential tools.

## 6. VS Code (Copilot Agent Mode)

Use `.vscode/mcp.json` for one workspace, or run **MCP: Open User Configuration** from the Command Palette for all of them:

```json
{
  "servers": {
    "sketchup": {
      "type": "stdio",
      "command": "python",
      "args": ["C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__SketchUpMcp__Modules__/30__McpServer__Python/Na__SketchUpMcp__Server__Main__.py"],
      "env": { "PYTHONUTF8": "1" }
    }
  }
}
```

## 7. Gemini CLI

In `~/.gemini/settings.json`, add the server. The `context` entry also makes Gemini read `AGENTS.md` files:

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "python",
      "args": ["C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__SketchUpMcp__Modules__/30__McpServer__Python/Na__SketchUpMcp__Server__Main__.py"],
      "env": { "PYTHONUTF8": "1" },
      "timeout": 300000
    }
  },
  "context": { "fileName": ["AGENTS.md", "GEMINI.md"] }
}
```

`timeout` is in milliseconds.

## 8. The Modelling Skill (Any Agent)

`85__Docs__AgentReference/Skills/sketchup-modelling/SKILL.md` is an Agent Skill in the open `SKILL.md` format. It tells an agent how to work with this server. Copy the `sketchup-modelling` folder to:

| Agent | Personal skills folder |
|---|---|
| Claude Code | `%USERPROFILE%\.claude\skills\` |
| Codex | `%USERPROFILE%\.agents\skills\` |

Agents that don't load skills still get the same rules from the server's own instructions and from the resource `sketchup://guide/agent`.

**Claude Code on Adam's PCs:** use the full expert skill instead. It adds his naming conventions, verified recipes and a learning memory. It lives in `D:\08__Cloud__Repo__AgentSkills__Private\10-mcp-sketchup-3d-modeling-expert\mcp-sketchup-3d-modeling-expert` and is linked into `%USERPROFILE%\.claude\skills\` as a junction. Don't install this bundled one beside it, because the two would overlap.

## 9. Options

| Option | Where | Effect |
|---|---|---|
| `--toolset core` | args | Only the 22 core tools (for clients that limit tool counts) |
| `--check` | args | Print tools and visible bridges, then exit |
| `NA_SKETCHUP_MCP_TOOLSET` | env | Same as `--toolset` |
| `NA_SKETCHUP_MCP_PID` | env | Always use the SketchUp process with this pid |
| `NA_SKETCHUP_MCP_HOST`, `_PORT`, `_TOKEN` | env | Connect to a bridge directly instead of using connection-file discovery |
| `NA_SKETCHUP_MCP_CONNECTIONS_DIR` | env | Read connection files from another folder |
| `NA_SKETCHUP_MCP_LOG` | env | `1` = log to stderr (the client's MCP log) |
| `PYTHONUTF8` | env | `1` = UTF-8 everywhere on Windows (keep it) |

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| The client can't start the server | Run the `--check` command from §1 in a terminal. If `python` is not found, put the full path to `python.exe` in `command`. |
| `sketchup_status` says not connected | SketchUp is closed, or the bridge is off. Tick **Extensions > Na SketchUp MCP > Bridge Running**. A model opened before the plugin was installed needs SketchUp restarted. |
| Calls go to the wrong model | Each SketchUp window is its own process. `sketchup_status` lists them; pass `select_pid`. |
| Model-changing calls are refused | The status dialog has **Read-Only Mode** on, or **Allow Ruby Eval** off. |
| A call timed out | SketchUp may still be working or showing a dialog. Look at SketchUp, then check the model before repeating the call. |
| New tools don't appear after an update | Use **Reload Plugin Data** in SketchUp, then restart the MCP server (or the client). |
