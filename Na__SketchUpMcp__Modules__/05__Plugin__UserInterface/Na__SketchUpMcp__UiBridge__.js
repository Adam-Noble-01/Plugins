(function() {
    'use strict';

    // =============================================================================
    // NA SKETCHUP MCP - STATUS DIALOG UI BRIDGE
    //
    // FILE       : Na__SketchUpMcp__UiBridge__.js
    // PURPOSE    : Render the state object Ruby pushes, send button/toggle actions
    //              back through sketchup.na_action, copy client setup snippets
    //
    // STATE SHAPE (Na__SketchUpMcp__CoreAppLogic__DialogManager__.rb na_full_state):
    //   { bridge:{running,host,port,pid,clients,requests,started_at,version,
    //             read_only_mode,allow_ruby_eval,auto_start,counters},
    //     sketchup:{version,model}, self_test:{checked,unavailable_tools,tool_count},
    //     activity:[{time,tool,ms,ok,message}], clients:{claude_code,...} }
    // =============================================================================

    // -----------------------------------------------------------------------------
    // REGION | Constants And State
    // -----------------------------------------------------------------------------

    var NA_CLIENT_TABS = [
        { key: 'claude_code', label: 'Claude Code', hint: 'Run once in a terminal. Registers the server for every project (user scope).' },
        { key: 'claude_desktop', label: 'Claude Desktop', hint: 'Claude Desktop > Settings > Developer > Edit Config: merge this in, then quit Claude from the tray and reopen it. (Add custom connector only takes remote URLs.)' },
        { key: 'codex', label: 'Codex / GPT', hint: 'Append to %USERPROFILE%\\.codex\\config.toml (Codex CLI, IDE extension, ChatGPT desktop Codex).' },
        { key: 'cursor', label: 'Cursor / Gemini', hint: 'Cursor: .cursor\\mcp.json. Gemini CLI: .gemini\\settings.json. Windsurf: mcp_config.json.' },
        { key: 'vscode', label: 'VS Code', hint: 'Save as .vscode\\mcp.json in a workspace (GitHub Copilot agent mode).' }
    ];

    var naState = { activeClientTab: 'claude_code', clients: {} };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Small DOM Helpers
    // -----------------------------------------------------------------------------

    function na__Element(id) {
        return document.getElementById(id);
    }

    function na__Text(value) {
        return value === null || value === undefined ? '' : String(value);
    }

    function Na__SketchUpMcp__SetStatus(text, variant) {
        var statusElement = na__Element('naSuMcpStatus');
        if (!statusElement) {
            return;
        }
        statusElement.textContent = na__Text(text);
        statusElement.className = 'naSuMcp__Status naSuMcp__Status--' + (variant || 'info');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Rendering - Bridge Card, Toggles, Self-Test
    // -----------------------------------------------------------------------------

    function na__RenderBridge(bridge, sketchup) {
        var dot = na__Element('naSuMcpStatusDot');
        var title = na__Element('naSuMcpStatusTitle');
        var running = bridge && bridge.running;

        dot.className = 'naSuMcp__Dot ' + (running ? (bridge.read_only_mode ? 'naSuMcp__Dot--readonly' : 'naSuMcp__Dot--on') : 'naSuMcp__Dot--off');
        title.textContent = running ? (bridge.read_only_mode ? 'Bridge running (read-only)' : 'Bridge running') : 'Bridge stopped';

        var counters = bridge.counters || {};
        var facts = [
            ['Address', running ? bridge.host + ':' + bridge.port : '-'],
            ['SketchUp PID', bridge.pid],
            ['Model', sketchup.model || '(untitled)'],
            ['SketchUp', sketchup.version],
            ['Bridge', bridge.version],
            ['Requests', na__Text(bridge.requests) + ' (' + na__Text(counters.ok || 0) + ' ok, ' + na__Text(counters.failed || 0) + ' failed)'],
            ['Since', bridge.started_at || '-']
        ];

        var list = na__Element('naSuMcpFacts');
        list.innerHTML = '';
        for (var index = 0; index < facts.length; index += 1) {
            var term = document.createElement('dt');
            term.textContent = facts[index][0];
            var detail = document.createElement('dd');
            detail.textContent = na__Text(facts[index][1]);
            list.appendChild(term);
            list.appendChild(detail);
        }

        na__Element('naSuMcpReadOnly').checked = !!bridge.read_only_mode;
        na__Element('naSuMcpEval').checked = !!bridge.allow_ruby_eval;
        na__Element('naSuMcpAutoStart').checked = !!bridge.auto_start;
    }

    function na__RenderSelfTest(selfTest) {
        var element = na__Element('naSuMcpSelfTest');
        if (!selfTest) {
            element.textContent = 'Not run yet.';
            return;
        }
        var unavailable = selfTest.unavailable_tools || [];
        element.textContent = selfTest.tool_count + ' tools; ' + selfTest.checked + ' SketchUp API dependencies probed live. ' +
            (unavailable.length ? 'Unavailable here: ' + unavailable.join(', ') + '.' : 'Every tool is available in this SketchUp.');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Rendering - Client Setup Tabs
    // -----------------------------------------------------------------------------

    function na__RenderClientTabs() {
        var bar = na__Element('naSuMcpClientTabs');
        bar.innerHTML = '';
        NA_CLIENT_TABS.forEach(function(tab) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'naSuMcp__TabButton' + (tab.key === naState.activeClientTab ? ' naSuMcp__TabButton--active' : '');
            button.textContent = tab.label;
            button.onclick = function() {
                naState.activeClientTab = tab.key;
                na__RenderClientTabs();
            };
            bar.appendChild(button);
        });

        var active = NA_CLIENT_TABS.filter(function(tab) { return tab.key === naState.activeClientTab; })[0];
        na__Element('naSuMcpClientHint').textContent = active ? active.hint : '';
        na__Element('naSuMcpClientSnippet').textContent = na__Text(naState.clients[naState.activeClientTab]);
    }

    function Na__SketchUpMcp__CopySnippet() {
        var text = na__Text(naState.clients[naState.activeClientTab]);
        var area = document.createElement('textarea');
        area.value = text;
        document.body.appendChild(area);
        area.select();
        var copied = false;
        try {
            copied = document.execCommand('copy');
        } catch (error) {
            copied = false;
        }
        document.body.removeChild(area);
        Na__SketchUpMcp__SetStatus(copied ? 'Copied to the clipboard.' : 'Copy failed: select the text and press Ctrl+C.', copied ? 'success' : 'error');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Rendering - Activity Log
    // -----------------------------------------------------------------------------

    function na__ActivityRow(entry) {
        var row = document.createElement('tr');
        if (!entry.ok) {
            row.className = 'naSuMcp__Row--failed';
        }
        [entry.time, entry.tool, entry.ms, (entry.ok ? 'ok' : 'FAILED') + (entry.message ? ' - ' + entry.message : '')].forEach(function(value) {
            var cell = document.createElement('td');
            cell.textContent = na__Text(value);
            row.appendChild(cell);
        });
        return row;
    }

    function na__RenderActivity(entries) {
        var body = na__Element('naSuMcpActivityRows');
        body.innerHTML = '';
        (entries || []).forEach(function(entry) {
            body.appendChild(na__ActivityRow(entry));
        });
    }

    function Na__SketchUpMcp__AppendActivity(entry, bridge) {
        var body = na__Element('naSuMcpActivityRows');
        if (!body) {
            return;
        }
        body.insertBefore(na__ActivityRow(entry), body.firstChild);
        while (body.children.length > 100) {
            body.removeChild(body.lastChild);
        }
        if (bridge && naState.sketchup) {
            na__RenderBridge(bridge, naState.sketchup);
        }
        Na__SketchUpMcp__SetStatus('Last: ' + entry.tool + (entry.ok ? ' ok' : ' FAILED') + ' (' + entry.ms + ' ms)', entry.ok ? 'success' : 'error');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Entry Points From Ruby And Buttons
    // -----------------------------------------------------------------------------

    function Na__SketchUpMcp__Render(state) {
        if (!state || !state.bridge) {
            return;
        }
        naState.sketchup = state.sketchup || {};
        naState.clients = state.clients || {};
        na__RenderBridge(state.bridge, naState.sketchup);
        na__RenderSelfTest(state.self_test);
        na__RenderClientTabs();
        na__RenderActivity(state.activity);
        Na__SketchUpMcp__SetStatus(state.bridge.running ? 'Listening for agents.' : 'Bridge stopped. Press Start.', state.bridge.running ? 'success' : 'info');
    }

    function Na__SketchUpMcp__Action(actionName) {
        if (!window.sketchup || !window.sketchup.na_action) {
            Na__SketchUpMcp__SetStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        Na__SketchUpMcp__SetStatus('Working: ' + actionName + '...', 'info');
        window.sketchup.na_action(String(actionName), '{}');
    }

    document.addEventListener('DOMContentLoaded', function() {
        na__RenderClientTabs();
        if (window.sketchup && window.sketchup.na_ready) {
            window.sketchup.na_ready();
        }
    });

    window.Na__SketchUpMcp__Render = Na__SketchUpMcp__Render;
    window.Na__SketchUpMcp__AppendActivity = Na__SketchUpMcp__AppendActivity;
    window.Na__SketchUpMcp__Action = Na__SketchUpMcp__Action;
    window.Na__SketchUpMcp__CopySnippet = Na__SketchUpMcp__CopySnippet;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
