# =============================================================================
# NA AGENT OUTLINER - TESTS - RUN CHECKS
# =============================================================================
#
# FILE       : Na__AgentOutliner__Tests__RunChecks__.py
# PURPOSE    : Run the Agent Outliner's offline suite on SketchUp's own Ruby
#              (no SketchUp process, no model), and with --mutate prove the
#              suite bites: each deliberate fault is patched into a copy of
#              the module under %TEMP%\aom and the suite must fail on it.
# CREATED    : 10-Nov-2026
#
# USAGE      : python Na__AgentOutliner__Tests__RunChecks__.py
#              python Na__AgentOutliner__Tests__RunChecks__.py --mutate
#
# NOTES:
# - Uses su_ruby.py from the sketchup-ruby-plugin-development-expert skill
#   (SketchUp 2026's Ruby 3.2 DLL: 2027's cannot be embedded through ctypes).
#   Set NA_SU_RUBY to its path if the skill is somewhere else.
# - Standard library only, Python 3.9+.
#
# =============================================================================

import os
import shutil
import subprocess
import sys
import tempfile

NA_TESTS  = os.path.dirname(os.path.abspath(__file__))
NA_MODULE = os.path.dirname(NA_TESTS)
NA_SUITE  = os.path.join(NA_TESTS, 'Na__AgentOutliner__Tests__Core__.rb.test')
NA_STORE  = os.path.join(NA_TESTS, 'Na__AgentOutliner__Tests__Store__.js.test')   # the page's data store, on node (0.1.16)

NA_SU_RUBY_CANDIDATES = [
    os.environ.get('NA_SU_RUBY', ''),
    os.path.join(os.path.expanduser('~'), '.claude', 'skills', 'sketchup-ruby-plugin-development-expert', 'scripts', 'su_ruby.py'),
    r'D:\08__Cloud__Repo__AgentSkills__Private\15-sketchup-ruby-plugin-development-expert\sketchup-ruby-plugin-development-expert\scripts\su_ruby.py',
]

# (what the fault is, the file, the exact text, its replacement)
NA_MUTATIONS = [
    ('actor: never sees the MCP on the stack', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__ActorDetect__.rb'),
     "agent ||= markers.any? { |marker| path.include?(marker) }", "agent ||= false"),
    ('tracker: hiding counts as a change', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__Tracker__.rb'),
     "fields.delete('visibility') unless", "fields.delete('visibility') if"),
    ('naming: prefixes stack instead of swapping', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Naming__.rb'),
     "text[entry['label'].length..-1].to_s.sub(/\\A_+/, '')", "text"),
    ('notes: the flag waits again after acknowledging', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Notes__.rb'),
     "has_entry = entries.any? { |entry| entry['kind'] == 'flag' && entry['flag'] == flag['id'] }", "has_entry = false"),
    ('walker: size ignores the instance scale', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Walker__.rb'),
     "scales = self.Na__Walker__AxisScales(entity.transformation)", "scales = [1.0, 1.0, 1.0]"),
    ('seam: reply does not acknowledge what it answers', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Main__.rb'),
     "acknowledged = reply ? self.na_acknowledge_targets(model, targets) : 0", "acknowledged = 0"),
    # 0.1.1
    ('threads: an agent\'s last word never waits on Adam', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "elsif status == 'open' && last_comment && last_comment['by'] == 'agent'", "elsif false"),
    ('flags: the type filter is ignored', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "next if flag_id && flag['id'] != flag_id", "next if false"),
    ('strip: the undo step keeps the dialog\'s name', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Naming__.rb'),
     "operation_name || 'Agent Outliner: Strip Prefix'", "'Agent Outliner: Strip Prefix'"),
    ('notes: every flag Adam sets waits for an agent (0.1.0)', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Notes__.rb'),
     "                self.na_flag_entry_waits?(entry)\n", "                true\n"),
    ('history: 0.1.0\'s long file names (past Windows\' 260 characters)', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__HistoryStore__.rb'),
     "File.join(self.Na__History__Folder, \"History__#{self.na_file_key(key)}.json\")",
     "File.join(self.Na__History__Folder, \"Na__AgentOutliner__History__#{key}__.json\")"),
    ('seam: a reload keeps the old action lists (0.1.0\'s guard)', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Main__.rb'),
     "remove_const(:NA_READ_ACTIONS) if const_defined?(:NA_READ_ACTIONS, false)\n"
     "        remove_const(:NA_EDIT_ACTIONS) if const_defined?(:NA_EDIT_ACTIONS, false)\n"
     "        NA_READ_ACTIONS = %w[summary inbox changes thread threads flags prefixes find tags tag_tree category_tree].freeze",
     "NA_READ_ACTIONS = %w[summary inbox changes thread threads flags prefixes find tags tag_tree category_tree].freeze unless defined?(NA_READ_ACTIONS)"),
    # 0.1.9: the waiting notice and the agents' picture folder
    ('notice: a thread write does not move the revision (a stale notice)', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Notes__.rb'),
     "            self.na_drop_if_empty(target)\n            self.Na__Notes__Touch\n", "            self.na_drop_if_empty(target)\n"),
    ('notice: an acknowledge does not move the revision', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__Tracker__.rb'),
     "            Na__AgentOutliner::Na__Notes.Na__Notes__Touch unless fresh.empty?", "            nil"),
    ('notice: an erased object is still counted', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Main__.rb'),
     "cache[:targets].all?(&:valid?)", "true"),
    ('chat: an agent\'s picture goes in Adam\'s folder', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__ChatCache__.rb'),
     "info  = self.na_store(bytes, NA_AGENT_PREFIX)", "info  = self.na_store(bytes)"),
    # 0.1.10: Send says who will see it
    ('send: a stale heartbeat counts as a watcher', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__HistoryStore__.rb'),
     "next unless data.is_a?(Hash) && now - data['beat'].to_f <= NA_WATCH_FRESH_S", "next unless data.is_a?(Hash)"),
    ('last call: the bridge starting counts as an agent calling', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__ActorDetect__.rb'),
     ".Na__ActivityLog__Entries.find { |entry| !NA_NOT_AGENT_CALLS.include?(entry['tool'].to_s) }", ".Na__ActivityLog__Entries.first"),
    # 0.1.11: watches on erased definitions, and who undid
    ('observers: watches on erased definitions are never pruned', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__Observers__.rb'),
     "alive = self.na_entities_alive?(entities)", "alive = true"),
    ('observers: detach asks an erased definition\'s entities to let go', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__Observers__.rb'),
     "next unless self.na_entities_alive?(entities)", "next if false"),
    ('tracker: a full pass keeps the dead watches', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__Tracker__.rb'),
     "Na__AgentOutliner::Na__Observers.Na__Observers__Prune(model)", "nil"),
    ('actor: an undo keeps an answer held from an operation', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__ActorDetect__.rb'),
     "@na_transaction = nil if @na_transaction", "nil"),
    ('actor: an undo reads the stack but does not hold it for its events', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__ActorDetect__.rb'),
     "self.na_hold_tick(pressed_by)", "pressed_by"),
    ('actor: a held tick answer never expires', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__ActorDetect__.rb'),
     "return @na_tick if @na_tick && (self.na_clock - @na_tick_at.to_f) <= NA_TICK_MAX_S", "return @na_tick if @na_tick"),
    ('actor: a lost clearing timer is never booked again', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__ActorDetect__.rb'),
     "if !@na_tick_timer || (now - @na_tick_timer_at.to_f) > NA_TICK_LOST_S", "if !@na_tick_timer"),
    # 0.1.14: reasoning effort on Adam's messages
    ('effort: the comment drops the effort', os.path.join('03__ModelData', 'Na__AgentOutliner__ModelData__Notes__.rb'),
     "entry['effort'] = effort if effort", "nil"),
    ('effort: the notice leaves the effort out', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Main__.rb'),
     "notice['effort']   = entry['effort'] if entry['effort']", "nil"),
    ('effort: a long-silent dispatcher still counts', os.path.join('04__ChangeTracking', 'Na__AgentOutliner__ChangeTracking__HistoryStore__.rb'),
     "next unless data.is_a?(Hash) && now - data['beat'].to_f <= NA_DISPATCH_FRESH_S", "next unless data.is_a?(Hash)"),
    ('notice: two messages in one second quote the older', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Main__.rb'),
     "[Na__AgentOutliner::Na__Payloads.na_time_value(pair[1]['at']), pair[1]['id'].to_s]", "Na__AgentOutliner::Na__Payloads.na_time_value(pair[1]['at'])"),
    # 0.1.15: icons, the selection backstop, the switches
    ('icons: the names keep their prefix', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__DialogManager__.rb'),
     ".sub(NA_ICON_PREFIX, '')", ".to_s"),
    ('backstop: it sends even when nothing changed', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__DialogManager__.rb'),
     "return if self.na_selection_signature(model) == @na_selection_sent", "nil"),
    ('backstop: the signature walks the whole selection', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__DialogManager__.rb'),
     "break if ids.length >= 16", "nil"),
    ('backstop: a second start adds a second watch', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__DialogManager__.rb'),
     "            self.Na__Dialog__StopSelectionWatch\n            @na_selection_watch = UI.start_timer", "            @na_selection_watch = UI.start_timer"),
    ('switches: the switch\'s message is ignored', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__ActionRouter__.rb'),
     "message.empty? ? 'Settings saved.' : message[0, 200]", "'Settings saved.'"),
    # 0.1.16: Tree by Tag (the Ruby folders, then the page store on node)
    ('tags: the folders come innermost first', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "folders.unshift(folder)", "folders.push(folder)"),
    ('tag tree: a part on the same tag inside a tagged group is listed twice', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "if (above && spec.groupOf(above) === group) return false;", "if (false) return false;"),
    ('tag tree: an untagged part of a tagged group lands in Untagged', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "if (!group) return path.length === 1;", "if (!group) return true;"),
    ('tag tree: the blocks share one set of keys', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "                    kp: kp, base: depth + 1,", "                    kp: '', base: depth + 1,"),
    # 0.1.17: Show or Hide
    ('toggle: an open Outliner is brought forward, never closed', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__DialogManager__.rb'),
     "            if self.Na__Dialog__Visible?\n                self.Na__Dialog__Close", "            if false\n                self.Na__Dialog__Close"),
    ('keys: every binding in SketchUp counts as Show or Hide', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__DialogManager__.rb'),
     "entry['Path'].to_s.strip.casecmp(NA_TOGGLE_PATH).zero?", "true"),
    ('keys: the page closes on the key whatever the modifiers', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__MainShell__.js'),
     "return sameKey && !!k.ctrl === !!event.ctrlKey && !!k.alt === !!event.altKey && !!k.shift === !!event.shiftKey;", "return sameKey;"),
    ('closeDialog: the page cannot ask Ruby to close', os.path.join('01__AppCore', 'Na__AgentOutliner__AppCore__ActionRouter__.rb'),
     "            'closeDialog'     => :na_close_dialog,", ""),
    # 0.1.17: agent_outliner tag_tree
    ('tag_tree: an untagged part of a tagged group heads Untagged', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "return path.length == 1 if tag.empty?", "return true if tag.empty?"),
    ('tag_tree: a same-tag part is listed twice', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "path[0...-1].none? { |up| rows[up] && rows[up][key].to_s == tag }", "true"),
    ('tag_tree: a part on another tag hides its tag', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "node[field]    = own if !own.empty? && own != card_tag", "nil"),
    ('tag_tree: depth is ignored', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "if level >= depth", "if false"),
    ('tag tree: [ shuts every heading at once (0.1.15 stepping)', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "return item.header ? (item.depth || 0) - 100 :", "return item.header ? -1 :"),
    ('tag tree: a tag heading opens a full gap right under its own folder', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "if (parentKey && out[out.length - 1].key === parentKey) return 3;", "void parentKey;"),
    ('tag tree: an untagged part follows to Untagged, not its group\'s tag', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "            if (above && spec.groupOf(above)) group = spec.groupOf(above);", "            if (false) group = spec.groupOf(above);"),
    ('rows: a search counts an object again in each block it is listed in', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "if (filter.on && match && !state.counted[row.p]) { state.counted[row.p] = true; state.count += 1; }", "if (filter.on && match) { state.count += 1; }"),
    ('tag tree: Expand All leaves the blocks shut', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "blocks[group].roots.forEach(function (pid) { var row = S.ents[pid]; if (row) walk(row, reach[pid] || [pid], 0, kp); });", "void kp;"),
    # 0.1.18: agent_outliner category_tree
    ('category_tree: the categories go by name, not Configure\'s order', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "named.keys.sort_by { |name| [categories.fetch(name, 1_000_000), self.na_natural_key(name)] }", "named.keys.sort_by { |name| [0, self.na_natural_key(name)] }"),
    ('category_tree: No Standard Name comes first', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "result['cards'] << card.call('') if blocks.key?('')", "result['cards'].unshift(card.call('')) if blocks.key?('')"),
    ('category_tree: a same-prefix part is listed twice', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "blocks[on]['roots'] << pid if self.na_tag_root?(rows, on, path, key)", "blocks[on]['roots'] << pid if self.na_tag_root?(rows, on, path)"),
    ('category_tree: a card loses its colour', os.path.join('06__McpOperations', 'Na__AgentOutliner__McpOperations__Payloads__.rb'),
     "'colour' => entry ? entry['colour'] : nil, 'objects_named'", "'colour' => nil, 'objects_named'"),
    # 0.1.18: Group by Category (the card views' engine, grouped by the naming prefix)
    ('category: No Standard Name comes first', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "if (!item.group) return 2e6;", "if (!item.group) return -1;"),
    ('category: the categories go by name, not Configure\'s order', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "if (item.folder) return order.categories[item.name] !== undefined ? order.categories[item.name] : 1e6;", "if (item.folder) return 0;"),
    ('category: a card ignores its prefix\'s colour', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "return entry && entry.colour ? entry.colour : NA_TT_UNTAGGED;", "return NA_TT_UNTAGGED;"),
    ('category: the prefixes are not filed under their category', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "return [entry && entry.category ? entry.category : 'Other'];", "return [];"),
    ('category: its cards share Tree by Tag\'s keys', os.path.join('05__UserInterface', 'Na__AgentOutliner__UiSystem__OutlinerModel__.js'),
     "function na_card_key(spec, group)       { return 'g:' + spec.view + ':' + spec.short + ':' + group; }",
     "function na_card_key(spec, group)       { return 'g:tagtree:t:' + group; }"),
]


def na_su_ruby():
    for candidate in NA_SU_RUBY_CANDIDATES:
        if candidate and os.path.exists(candidate):
            return candidate
    sys.exit('su_ruby.py not found: set NA_SU_RUBY to the skill\'s scripts/su_ruby.py.')


# This runner's own Ruby output log and scratch folder (0.1.16). su_ruby's default log
# (%TEMP%/na_su_ruby_output.log) is shared by every su_ruby run on the PC (skill lesson L069), and the
# suite used to wipe and refill one %TEMP%/ao_suite: two runs at once (another session, a syntax check
# beside --mutate) failed each other's checks, so a fault could be counted caught or missed by chance.
NA_LOG     = os.path.join(tempfile.gettempdir(), 'na_ao_suite_%d.log' % os.getpid())
NA_SCRATCH = os.path.join(tempfile.gettempdir(), 'ao_suite_%d' % os.getpid())


def na_run(module_root):
    command = [sys.executable, na_su_ruby(), 'run', NA_SUITE, '--modules-root', module_root, '--harness', NA_TESTS, '--log', NA_LOG]
    run = subprocess.run(command, capture_output=True, text=True, env=dict(os.environ, NA_AO_SCRATCH=NA_SCRATCH))
    shutil.rmtree(NA_SCRATCH, ignore_errors=True)
    code, output = run.returncode, run.stdout + run.stderr
    node = shutil.which('node')
    if not node:
        return code, output + '\nSKIPPED the page store checks: node is not on the PATH'
    store = subprocess.run([node, NA_STORE, module_root], capture_output=True, text=True)
    return max(code, store.returncode), output + '\n' + store.stdout + store.stderr


def na_mutate():
    root = os.path.join(os.environ.get('TEMP', NA_TESTS), 'aom_%d' % os.getpid())   # <-- Its own copies, too
    caught = 0
    for index, (label, relative, old, new) in enumerate(NA_MUTATIONS):
        copy = os.path.join(root, str(index))
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(NA_MODULE, copy, ignore=shutil.ignore_patterns('91__UserConfig__LocalOnly', '__pycache__'))
        path = os.path.join(copy, relative)
        with open(path, encoding='utf-8', newline='') as handle:
            text = handle.read()
        if text.count(old) != 1:
            print('STALE   %s: the anchor is no longer in %s (update NA_MUTATIONS)' % (label, relative))
            continue
        with open(path, 'w', encoding='utf-8', newline='') as handle:
            handle.write(text.replace(old, new))
        code, output = na_run(copy)
        failed = [line.strip() for line in output.splitlines() if line.startswith('FAIL:')]
        if code != 0 and failed:
            caught += 1
            print('CAUGHT  %s (%d checks failed)' % (label, len(failed)))
        else:
            lines = [line.strip() for line in output.splitlines() if line.strip()]
            print('MISSED  %s (exit %d; last line: %s)' % (label, code, lines[-1][:160] if lines else 'no output'))   # <-- Tells a real miss from a run that never started
        shutil.rmtree(copy, ignore_errors=True)
    print('%d of %d deliberate faults caught' % (caught, len(NA_MUTATIONS)))
    return 0 if caught == len(NA_MUTATIONS) else 1


def main():
    if '--mutate' in sys.argv:
        return na_mutate()
    code, output = na_run(NA_MODULE)
    print(output.strip())
    return code


if __name__ == '__main__':
    sys.exit(main())

# =============================================================================
# END OF FILE
# =============================================================================
