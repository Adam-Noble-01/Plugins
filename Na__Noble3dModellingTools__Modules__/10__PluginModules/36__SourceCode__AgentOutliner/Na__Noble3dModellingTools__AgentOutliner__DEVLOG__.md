# Na Noble3d - Agent Outliner - Development Log
# =============================================================================
# Module : 36__SourceCode__AgentOutliner
# Plugin : Na Noble3d Modelling Tools
# Tab    : Entity Utils > Component Inspection (Agent Outliner); Extensions > Na__Noble3dModellingTools > Agent Outliner;
#          the 3D Modelling Tools toolbar (from 0.1.2). Tabs: Outliner | Chat (from 0.1.6) | Configure | Settings
# Icons  : UiIcons__DialogIcons__AgentOutliner (from 0.1.15), sent to the page by Ruby

## Overview

An Outliner built for working with Claude agents through the Na SketchUp MCP. Three tabs, Outliner | Configure | Settings:

- **Outliner.** The model's groups, components, images and section planes in a table drawn only where it is on screen, with sortable,
  resizable, movable columns; a search language; quick filters; a tree, Tree by Tag (each tag a card in its tag colour holding
  its objects as trees, 0.1.16), a flat list and eight grouped views; Quick Name for standard names
  (CAD__FrontElevation ...) in a panel that pops out on the table's left (0.1.15); flags and two way comment threads (Adam to agent,
  agent to Adam); New and Updated marks coloured by who made the change (agent violet, Adam amber) and fading with age, with a switch
  to turn the colours off; Follow Selection, which finds what is selected in SketchUp in the table; Copy for Agent. Icons on every
  tab and button from 0.1.15.
- **Configure.** The naming prefixes (label, category, mode, colour, what it means for an agent), the flag types, and the Copy for
  Agent closing note. Saved to the shared standards file.
- **Settings.** Reload Plugin Data (this tool, or all of Noble 3D Tools), change tracking, colour grading, selection, the agent bridge's
  status, where the data lives, and the Technical Log.

Agents reach the same data through the MCP tools `agent_outliner` and `agent_outliner_edit` (MCP 1.0.22; `flags`, `threads` and
`strip` from 1.0.23), whose seam is `06__McpOperations`. From 0.1.9 (MCP 1.0.28) every MCP result carries a short notice while
anything here waits for an agent, so Send reaches an agent on its next SketchUp call.

# =============================================================================
# VERSION HISTORY
# =============================================================================

## Version 0.1.18 - 12-Nov-2026 - Group by Category: Coloured Cards for the Naming Prefixes; for Agents (agent_outliner category_tree)

### Asked For

With screenshots of the Configure tab (the CATEGORY column ringed) and of the Outliner on Kann 0.0.1 (MASSING__Neighbour and
MASSING__Existing objects among unnamed Groups): "Create a group by category that appears the same as the group by tag so
coloured regions".

Then, asked whether agents should read it too through the MCP: "Yes, add it".

### What Changed

- **Group by Category**, a new view beside Tree by Tag in the view picker. Each Configure category (CAD Elevations,
  References, Drawing Planes, Guides, Massing ...) is a grey bar, as a tag folder is; inside it each naming prefix is a card
  in the prefix's own colour (the swatch in Configure), holding the objects named with it as trees, with gaps between the
  cards. Categories and prefixes keep the order Adam gives them in Configure (the Quick Name panel's order), not the
  alphabet. **No Standard Name** comes last, in grey.
- The rules are Tree by Tag's, with the prefix in place of the tag:
  - an object heads its prefix's card unless something above it carries the same prefix (MASSING__Neighbour__Chimney
    inside MASSING__Neighbour__...Blanking is listed inside it, once);
  - No Standard Name lists only top-level unnamed objects; an unnamed part of a named object (the Groups inside
    MASSING__Existing__OuterShell) is listed inside that object, in its prefix's card;
  - a named object inside an unnamed group is listed in that group (under No Standard Name) and heads its own prefix's
    card too.
- A prefix is the one Ruby already reads off each name (the longest match; Elevation Faces are segments, never prefixes, so
  that category never shows). A prefix no longer in Configure files under Other, in grey. A category or prefix with nothing
  named with it is left out.
- Everything Tree by Tag does works here: search and filters, Follow (to the object's own card), Reveal, Expand All, the
  `[` and `]` level keys, the arrow keys, Colours. A card's tooltip says what the prefix means (Configure's meaning).
- **One engine for both card views.** Tree by Tag's store code became the card views' engine, driven by a spec per view
  (`NA_CARD_SPECS`: which group an object is in, the folders, the order, the colour, the name). Tree by Tag's keys are
  unchanged, so what Adam has opened or closed stays as it was.
- **`agent_outliner category_tree`** (with Na SketchUp MCP 1.0.32): Group by Category for agents, built in Ruby with the
  view's rules (`Na__Payloads.Na__Payload__CategoryTree`): categories holding prefix cards in Configure's order, No Standard
  Name last; `prefix` reads one card (any case, a trailing `__` allowed), `depth` 0 to 8, `limit`; each card's category,
  colour and meaning; each object's `prefix` only when it carries another. Tree by Tag's Ruby (`tag_tree`) now shares the walk
  and the card rules with it (`na_tree_rows`, `na_card_blocks`; `na_tag_root?` and `na_tag_tree_node` take the row key).

### Checked

- Page store suite 42 / 42 (13 new): Configure's order (not the alphabet), empty categories and prefixes left out, an old
  prefix under Other, No Standard Name last; its top-level objects only; same-prefix parts inside, another prefix's part
  listed twice; colours; counts and indents; keys apart from Tree by Tag's; following and revealing; Expand All; search;
  reordering Configure reorders the view; Tree by Tag unchanged. The 29 earlier checks moved to the shared names.
- 60 of 60 deliberate faults (5 new in the page: No Standard Name first, categories by name, colours ignored, prefixes
  outside their category, cards sharing Tree by Tag's keys; 4 new in `category_tree`: categories by name, No Standard Name
  first, a same-prefix part listed twice, a card without its colour; six anchors brought up to the shared code).
- Offline Ruby suite 327 / 327 (9 new, `category_tree`: a read action the MCP is told about; who heads each card, any case;
  category, colour and meaning from Configure; an unnamed part inside its named group, another prefix named; a same-prefix
  part once; that part's own card with a trailing `__`; No Standard Name's top-level objects only; the whole view's order,
  no faces, No Standard Name last; a prefix with nothing named refused). `node --check` on the page files.
- MCP: BridgeCore 179 / 179, PythonServer 65 OK (the action, `prefix`, the description under 2048), ValidateApiUsage passed.
- Browser harness (the real page, a Kann-like model): the cards, colours and order; Follow to an unnamed part inside
  MASSING__Existing__OuterShell and to a named object inside an unnamed Group; the tooltips; Tree by Tag as before.

### What Offline Cannot Prove

- The view on a real model in SketchUp; `category_tree` through the MCP against a real model.

### Files

- `05__UserInterface/`: OutlinerModel (the card views region, the engine and the two specs), OutlinerView (the view in the
  picker, the headings' tooltips, Follow), Inspector (Reveal)
- `06__McpOperations/`: Main (`category_tree`), Payloads (`Na__Payload__CategoryTree`, the shared walk and card rules)
- `tests/`: Store (13 checks, the shared names), Core (9 checks), RunChecks (9 faults, 6 anchors)

### Checklist For Adam

- [ ] Reload Plugin Data in Noble 3D Tools (or restart SketchUp) and reopen the Outliner.
- [ ] Pick Group by Category in the view picker: a grey bar per category, a coloured card per prefix, No Standard Name last.
- [ ] Reorder a prefix in Configure and save: the cards follow.
- [ ] Click a named object in SketchUp: Follow scrolls to it in its prefix's card.
- [ ] Reload Plugin Data in the MCP too; in a new agent session `agent_outliner {action: "category_tree"}` lists your
      categories and prefix cards.

Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027

## Version 0.1.17 - 12-Nov-2026 - A Show or Hide Key You Bind; Tree by Tag for Agents (agent_outliner tag_tree)

### Asked For

1. "Add a bindable hotkey to open / close my outliner window, see how my other plugins handle hotkey management"
2. With a screenshot of Tree by Tag running live on Corrett 1.0.1: "Update the MCP tools and the 3D Modeling expert skill to
   ensure agents can also reference and see this and this struture as i belove this is a powerful way to categorise and
   group things"

### How His Plugins Handle Hotkeys (what this follows)

- Noble 3D Tools: a command in the registry (`UiCommandRegistry__.json`, `commands` and `hotkey_bindings`, `expose_to_hotkeys`)
  becomes a `UI::Command` in Extensions > Na__Noble3dModellingTools (`04__PluginHotkeyManager`), routed by `handler_key` in the
  CommandRouter. Adam binds the key himself in Window > Preferences > Shortcuts: 190 bindings in his SharedPreferences.json,
  most of them on these menu paths. No plugin sets a key itself (there is no API for it).
- Every dialog of his opens with "bring it to the front if it is showing"; none closed from the same command. The toggle
  follows the Point Cloud Viewer's naming ("Show or Hide Point Clouds").

### What Changed

- **Show or Hide Agent Outliner**, a new Noble 3D Tools command (`toggle_agent_outliner`; `quick_launch: false`, so it stays
  off the quick-launch row). Open, or close when open (`Na__AgentOutliner__ToggleDialog`, `DialogManager.Na__Dialog__Toggle`).
  The old Agent Outliner command, the Entity Utils card and the toolbar button still only open it.
- **The same key closes it from inside.** A focused HtmlDialog takes the keyboard, so SketchUp never sees its shortcut while
  the Outliner is in front. Ruby reads the binding for `Extensions/Na__Noble3dModellingTools/Show or Hide Agent Outliner`
  from SketchUp's SharedPreferences.json (read only, re-read only when the file changes; `Na__Dialog__ToggleKeys`), turns
  SketchUp's key names into the browser's `KeyboardEvent.code` (letters, digits, NumPad, F-keys, arrows, punctuation) and
  sends them in the state (`toggle_keys`). The page listens (capture phase) and asks Ruby to close (`closeDialog`, done on a
  later tick). A key with no Ctrl or Alt is left to a text field being typed in. A key it cannot name (Escape) is left out.
- **`agent_outliner tag_tree`** (with MCP 1.0.31): Tree by Tag for agents, built in Ruby with the view's rules
  (`Na__Payloads.Na__Payload__TagTree`): tag folders, tags, each tag's objects as trees; `tag` reads one card, `depth` 0 to 8,
  `limit`; each object's `id`, `name`, `type`, `tag` (only when on another tag), `hidden`, `within`, `children`, `inside`.

### Checked

- Offline Ruby suite 318 / 318 (18 new): Show or Hide opens then closes; only the Show or Hide bindings are read (any case),
  with modifiers, codes and characters; Escape is left out; a broken or missing file gives none; the state carries them;
  `closeDialog` closes on a later tick; `tag_tree` (10): a read action the MCP is told about, who heads each card, `within`, untagged parts inside their group,
  another tag named, a card read by tag in any case, Untagged's top objects only, depth 0 counts, limit, the whole view's
  folders and order, an empty tag refused.
- Page store suite 29 / 29 (4 new: the key matcher, Shift turning 9 into "(", a UK backslash by its character).
- 51 of 51 deliberate faults (8 new: the toggle never closes, every binding counts, modifiers ignored, no closeDialog
  route; an untagged part heading Untagged, a same-tag part listed twice, another tag hidden, depth ignored).
- `su_ruby.py syntax` 251/251 for Noble 3D Tools; `su_lint` clean; `node --check`; the registry parses with the command and
  its hotkey entry; MCP: BridgeCore 179/179, PythonServer 65 OK, ValidateApiUsage passed.

### What Offline Cannot Prove

- The new menu item needs a SketchUp RESTART: Noble 3D Tools registers its menu once (Reload Plugin Data re-syncs the
  toolbar, not the menu).
- When SketchUp writes a new binding to SharedPreferences.json (on OK in Preferences, or only on exit). Until it does,
  the key works from the model but not from inside the Outliner.
- `tag_tree` against a real model through the MCP.

### Files

- Noble 3D Tools: `UiCommandRegistry__.json` (the command and its hotkey entry), `PublicAPI__CommandRouter__.rb`
- `01__AppCore/`: Main (0.1.17, ToggleDialog), DialogManager (Toggle, ToggleKeys, the state), ActionRouter (closeDialog)
- `05__UserInterface/Na__AgentOutliner__UiSystem__MainShell__.js` (the key)
- `06__McpOperations/`: Main (`tag_tree`), Payloads (`Na__Payload__TagTree` and helpers)
- `tests/`: Core (18 checks), Store (4), RunChecks (8 faults, one anchor brought up to date)

### Checklist For Adam

- [ ] Restart SketchUp (the new menu item only appears after a restart).
- [ ] Window > Preferences > Shortcuts: filter "Show or Hide Agent", pick Extensions/Na__Noble3dModellingTools/Show or Hide
      Agent Outliner, give it a key (free in your list: Ctrl+Shift+6 to 0, Ctrl+Shift+J, K, N, Q, X, Y; Ctrl+Alt+5, 6, J, N, Y).
- [ ] Press it in the model: the Outliner opens. Press it again: it closes.
- [ ] Open it, click inside it, press the key: it closes (if not, restart SketchUp once so the binding is written).
- [ ] In a new agent session: `agent_outliner {action: "tag_tree"}` lists your folders and tag cards.

Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027

## Version 0.1.16 - 12-Nov-2026 - Tree by Tag: Each Tag a Coloured Card Holding Its Objects as Trees

### Asked For

"Add A grouping mode that groups by tag, and each group in the outliner is a level then its children indent, to make it easy to
see. Color the group blocks as per the layer colors and speratre the blocks to create an intituive multigroup tree stucture"

### What Changed

- **A new view, Tree by Tag** (the view picker, second after Tree; the old flat Group by Tag stays):
  - the levels are SketchUp's tag folders (nested folders nest), then the tags, then under each tag its objects as a tree:
    a group opens to show its contents one level in, whatever tags those carry;
  - an object heads its tag's card only when nothing above it carries the same tag, so a tagged group's parts on that
    tag are listed inside it, once (`Store.na_tag_root`);
  - Untagged comes first, as in SketchUp's Tags panel, and lists only the top-level untagged objects. An untagged part of
    a tagged group hides and shows with that group's tag in SketchUp, so it is listed inside the group, in that tag's
    card, and not again under Untagged (most inner groups are untagged, which would otherwise flood it);
  - an object on another tag inside a card is listed in its parent there AND at the top of its own tag's card, at its
    real place in the model. Each card opens and closes its own rows (row keys carry the card);
  - folders and tags are ordered by name (01__ before 10__); tags with no objects are left out; a heading counts the
    objects on its tag (a folder: its tags), and its tooltip says how many head the card;
  - the search and quick filters keep only the cards (and folders) that hold a match, each match counted once.
- **The cards** (Adam: "Color the group blocks as per the layer colors and separate the blocks"):
  - each tag is a card in its tag colour: a heading bar (tag colour 20%, with the swatch), a 4 px band down the card's
    left edge and a light wash (6%) behind its rows, an edge line round its right side and end;
  - a gap above each card (10 px at the top level, 6 px between cards in a folder, 3 px under the card's own folder);
  - tag folders are grey bars with a folder icon and a thin line down the cards they hold;
  - inside a card a guide line runs down from each open object's arrow to its contents;
  - a hidden tag (or folder) is struck through with an eye-off mark; Untagged is a neutral grey card;
  - the status tint, the red selection and the hover shade fill the card only, so the cards keep their shape; the status
    and selection marks stay in the margin at the left edge. The Colours switch takes the status tint off and leaves the
    tag colours.
- **How the gaps work:** rows are still 26 px, but a heading's row includes its gap, so rows are placed from a table of
  tops (`na_layout_rows`, `na_index_at`), not index x 26. The pieces of a card sit behind the row's text (z-index -1 in a
  row that is its own stacking context) and run over each row's bottom line, so the bands are unbroken.
- **Everything else works in the new view:**
  - Follow Selection opens an object's own card (its tag's, or for an untagged part, its tagged group's), its folders and
    every row on the way, and scrolls to that row (`Store.na_tt_home`, `na_reveal_tag_tree`); faces picked inside an open
    group follow the group; the Inspector's reveal does the same;
  - the arrow keys: Left from a card's top row goes to its heading, from a heading in a folder to the folder; Right opens
    a heading;
  - Expand All opens every folder, card and row; Collapse All shuts the rows and leaves the cards open;
  - ] and [ now step headings outermost first (folders, then the tags in them, then each card's rows by their level in the
    card), so [ then ] gives back what was open. Before, [ shut every heading at once and ] opened only the top ones.
- **Ruby:** the tag list sent to the page (`Na__Payload__Tags`) now carries each tag's folders, outermost first, and
  whether each is shown (`f`, `fs`; only for a tag in a folder). Folder names need not be unique, so the page keys a folder
  by its path. The agents' tag listing uses the same walk (`na_tag_folders`).
- **The test runner runs alone safely.** Two runs at once used to fail each other's checks: the Ruby suite wiped and
  refilled one `%TEMP%o_suite`, and su_ruby wrote every run's output to one shared log. A syntax check run beside
  `--mutate` made one fault read MISSED and broke a plain run. RunChecks now gives each run its own scratch folder
  (`NA_AO_SCRATCH`, deleted afterwards), its own log (`--log`) and its own fault copies (`aom_<pid>`), and a MISSED line
  says the exit code and the last line, so a run that never started cannot pass as a miss.

### Checked

- Offline Ruby suite 300 / 300 (4 new): a tag in nested folders carries them outermost first with each shown or hidden; a
  hidden folder hides its tags; a top-level tag carries no folder keys; the agents' listing still names the folder path.
- **New: the page's data store on node** (`tests/Na__AgentOutliner__Tests__Store__.js.test`, 25 checks, run by RunChecks
  after the Ruby suite), on a model with a tagged group inside an untagged one, same-tag and other-tag parts, nested tag
  folders and a hidden tag: the order of the levels; who heads each card; counts, colours, hidden; indents, bands, gaps,
  card ends and parents; no two rows share a key; each card opens its own rows; a shut heading; the search; following an
  untagged part, a same-tag part and an all-untagged one; reveal; Expand All; ] and [ by heading depth; and the plain
  tree unchanged.
- 43 of 43 deliberate faults caught (9 new: folders innermost first; a same-tag part listed twice; an untagged part
  of a tagged group in Untagged; the cards sharing one set of keys; an untagged part followed to Untagged; a match counted
  in every card; Expand All leaving the cards shut; the gap under a folder; [ shutting every heading at once). One earlier
  fault survived because its line did nothing (Untagged's name '' sorts first anyway); the line was removed.
- `node --check` on every page script.
- In a browser, the real dialog page (served over http) with a Corrett-like model: tags in folders 01__Existing,
  02__Proposed and 02__Proposed / Joinery, top-level tags, a hidden tag, status changes by agent and by Adam:
  - the cards drew in their tag colours with their gaps, folders as grey bars with their lines (screenshots
    `AgentOutliner__0.1.16__TreeByTag__Top.jpg` and `...__Bottom.jpg` in the vector skill's
    `15_TestOutputs/2026-11-12__AgentOutlinerDialog`);
  - measured: guides centred on their parents' arrows (99.5 and 115.5 against 99 and 115), bands unbroken from row to
    row, a heading's band starting at its bar, the text above the wash, the selected row red inside the card only;
  - Follow: a window picked in SketchUp reopened the shut Joinery folder and its card, was selected and sat 7 px from the
    middle; a column picked inside the open orangery reopened the shut Orangery card; faces in the open host roof brought
    its row on screen;
  - Left and Right, Expand All, Collapse All, ] and [, the search ("Column": only the 02__Proposed folder and its Orangery
    card, 4 listed), Colours off (no status tint, the cards kept), Tree and Group by Tag unchanged, the view remembered;
  - no console errors (the company logo 404 as before).

### What Offline Cannot Prove

- Whether SketchUp sends a tag change when a tag is moved into a folder or a folder is renamed (the observers push on
  `onLayerChanged` and `onLayerFolderChanged`). If a folder change does not show, Refresh brings it.
- The cards drawn by SketchUp's own HtmlDialog, and how Adam's real tag colours read as washes.

### Files

- `05__UserInterface/Na__AgentOutliner__UiSystem__OutlinerModel__.js` (the shared tree walk, Tree by Tag, heading steps)
- `05__UserInterface/Na__AgentOutliner__UiSystem__OutlinerView__.js` (the view, row tops, cards, follow, keys)
- `05__UserInterface/Na__AgentOutliner__UiSystem__Inspector__.js` (reveal), `...Styles__Outliner__.css` (the cards)
- `06__McpOperations/Na__AgentOutliner__McpOperations__Payloads__.rb` (tag folders), `01__AppCore/...Main__.rb` (0.1.16)
- `tests/`: Core suite (4 checks, its scratch folder from `NA_AO_SCRATCH`), Doubles (`LayerFolder`), Store suite (new, 25
  checks), RunChecks (the node step, 9 faults, a scratch folder, log and copies of its own per run)

### Checklist For Adam

- [ ] Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Reopen it.
- [ ] Pick Tree by Tag in the view picker: each tag is a coloured card under its folders, Untagged first.
- [ ] Open a group in a card: its contents indent with a guide line; an untagged part of a tagged group sits inside it.
- [ ] Click an object in the viewport: its card opens and the row is marked red.
- [ ] Move a tag into a folder in SketchUp's Tags panel: the card moves under the folder (Refresh if it does not).

Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027

## Version 0.1.15 - 12-Nov-2026 - Follow the SketchUp Selection, Red Selected Rows, a Colours Switch, Quick Name in a Left Panel, Icons

### Asked For

With a screenshot of the Outliner on the Corrett white card model, a red ring round the selected row:
1. "Make the agent Outliner tool move the the item in the table thats selected inside sketchup viewport and add a toggle on by
   default to turn it on of off"
2. "for the selected item's use red instead of blue as the blue is too close to the purple"
3. "add a toggle to turn of the status coloring"
4. "move the quick naming system from the top into a new left popout menu, that format is too inneffcient and not scalable havbing
   it at the top"
5. "using the graphic designer skill add icons the UI is too textual based"

### What Changed

- **Follow Selection, a switch above the table (crosshair, on by default).** It is the old Settings tickbox
  (`selection.follow_selection`), now one click away, and it does more:
  - a selection made in the model opens the tree to the object (or, in a grouped view, its group heading:
    `Store.na_reveal_groups`), selects its row and scrolls it to the MIDDLE of the table. Before, a row already
    near an edge was left there, and a grouped view with the heading closed found nothing;
  - only a selection that changed is followed. Ruby sends the selection again after every operation, and following
    that would pull the table back each time Adam scrolled away while modelling;
  - faces and edges picked inside an open group follow the group being edited;
  - turned on, it jumps straight to what is selected now. Reveal Selection still finds it once with the switch off;
  - **a backstop in Ruby** (`DialogManager.Na__Dialog__StartSelectionWatch`). SketchUp's selection observers can go
    quiet (api-issue-tracker #603, #1116), and then a click in the model never reached the page, so nothing could
    follow it. While the page is up, a look every 0.5 s compares the selection's count, its first 16 entities and
    the open group with what the page last heard (`na_selection_signature`, set by every `Na__Dialog__PushSelection`)
    and sends the selection only when they differ. With the observers working it never sends anything. It waits
    while the observers' own push is on its way, starts once per page, and stops when the dialog shuts or a check
    fails.
- **Selected rows are red** (`--na-select` #dc2626). A selected row drops its status tint for a red one (16%) with a red
  edge, so it reads clearly among violet and amber rows; SketchUp's own selection is a red bar at the name (was blue);
  the keyboard focus outline is red too; hover is a neutral grey instead of blue.
- **Colours, a switch above the table (a drop).** `grading.status_colours` (new default, on). Off: no row tint or edge, the
  status chips go grey outlines, the closed-row dots grey, and the footer legend hides. Also a tickbox in Settings >
  Colour Grading. Both switches save just their own setting (`saveSettings` with one value) and say what they did on the
  status line (`na_save_settings` now takes an optional `message`).
- **Quick Name moved into a pop-out panel on the table's left.** A side rail holds a Name button (Q opens and closes it, as
  long as no text field has the keys). The panel lists the standard names in one column under their categories, each
  category folding away (remembered: UI pref `qnCollapsed`); a filter box (Enter names the selection with the first match,
  Esc clears it); a line saying how many rows it will name; the Front faces compass; Strip Prefix and Edit Names. Open or
  shut is remembered (the old bar's `quickNameOpen`). It rebuilds when a snapshot arrives, so the face buttons pick up a
  new Front faces cardinal at once (the old bar waited for the next state). The old bar's markup, styles and toggle are gone;
  the row menu's Quick Name submenu stays.
- **Icons** (vector-graphic-artist skill, App Icon Assets): 25 line icons for the tabs (Outliner, Chat, Configure,
  Settings), the toolbar (Help, Expand All, Collapse All, Reveal Selection, Follow Selection, Status Colours, Columns,
  Refresh), the agent bar (Flag, Tag, Comment, Copy for Agent, Copy IDs, Model Thread, Mark Seen) and the panel
  (Quick Name, Strip, Edit, Compass, Panel Close, Panel Open).
  - Files: `UiIcons__DialogIcons__AgentOutliner/Icon__AgentOutliner__<Name>__.svg`, house ink #172b3a, 1024 artboard,
    weight 80 (1.4 px at the 18 px they are shown, the pixel weight of the Image Viewer toolbar's 60 at 24 px, the
    sibling Noble 3D Tools dialog family they follow). Generator and specs in the skill's
    `01__ProductionFiles/Icon__AgentOutliner__.generator`, a copy in its
    `20__Outputs__New__OutputsAfter__20-Series/2026-11-12__Noble3dTools__AgentOutlinerDialog`.
  - How they reach the page: the page is a set_file page, so Ruby reads the folder and sends the SVG text once per page
    (`Na__Dialog__PushIcons`, new 'icons' channel, before the state). `Shell.na_paint_icons` fills every `[data-na-icon]`
    by DOMParser and importNode (never innerHTML); CSS turns the ink into currentColor, so a switch that is on, or the
    blue Copy for Agent button, draws its icon white. A missing icon leaves the button's label, aria-label and tooltip.
  - Expand, Collapse, Reveal, Columns and Refresh became icon buttons (their names in the tooltips); Follow and Colours
    keep a short label beside the icon; the agent bar buttons have an icon in front of their names.

### Checked

- Offline Ruby suite 296 / 296 (18 new):
  - the icon set read from the folder, keyed by the short name; a page that comes up gets them before the state;
  - the backstop: one watch per page (a second start replaces it); nothing sent while nothing changed; a missed
    selection sent once and not again; the signature reads the count and only 16 of 100 entities; opening a group
    counts; it waits while the observers' push is pending; it stops itself when the dialog is shut;
  - the switches: Status Colours default on; each saves only its own setting, leaves the rest, and the status line says
    what was switched; back on they leave nothing in the user file; Save Settings still says "Settings saved."
- 34 of 34 deliberate faults caught (5 new: icon names keep their prefix, the backstop sends with nothing changed, the
  signature walks the whole selection, a second start adds a second watch, the switch's message is ignored).
- `su_ruby.py syntax` 19/19, `su_lint.py` clean, `node --check` on every page script.
- In a browser, the real dialog page (a mirror served over http) fed a fake Corrett-like model (62 objects, a three-deep
  Roof > Rafters > RafterTail branch) and the real icons and standards, through a `window.sketchup` stub that answers
  like Ruby:
  - all 25 icons painted;
  - Follow: a root object far down selected in SketchUp came into view and was selected; a rafter tail three deep (open
    group path Roof > Rafters) opened both parents, was selected and shown; from the top, RafterTail_Right_30 was scrolled
    to the middle; the same selection sent again after Adam scrolled away left the table where it was; faces picked
    inside Rafters brought the Rafters row into view; in Group by Tag with 06__Drawings closed, a linework group selected
    in SketchUp opened the heading and was selected;
  - Follow off: saved `{selection: {follow_selection: false}}` with its message, the Settings tickbox followed, and a new
    selection left the table alone (the red bar still marked it); on again, it jumped to that selection, centred;
  - red: SketchUp's bar rgb(220, 38, 38) 3 px; a selected row's tint rgba(220, 38, 38, 0.16) on white with the red edge;
  - Colours off: 35 tinted rows on screen went to 0, and stayed 0 after scrolling new rows in; chips transparent and
    grey; legend hidden; saved with its message; the Settings tickbox followed. On again: rows tinted, legend back;
  - Quick Name: open at start (remembered); Q closed it and saved `quickNameOpen: false`; the Name button opened it; Q typed
    in the search box stayed text; five categories, 16 names; with a row selected, "Names the selected row" and REF__
    sent `applyPrefix` for it; "rear" filtered to the two Rear names and Enter applied the first; Esc cleared the filter;
    folding CAD Elevations hid its 4 names and saved `qnCollapsed`; Front faces South sent `setFrontFaces`, and the snapshot
    that followed relabelled the faces __Front__South__, __Back__North__, __Left__West__, __Right__East__;
  - at the default 1220 x 780 the toolbar fits on one row. No console errors (one 404: the company logo, outside the
    mirror).
- The icons: `lint_svg.py --profile app-icon --deep` clean but for the deliberate weight (80, not 34) and the Refresh arrow's
  own wedge; on a contact sheet beside the Image Viewer set and the Agent Outliner toolbar icon.

### What Offline Cannot Prove

- The backstop and Follow against SketchUp's real selection: whether its observers go quiet for Adam at all, and how a
  click in the viewport feels with the 0.5 s look.
- The icons drawn by SketchUp's own HtmlDialog (Chromium, like the browser used).

### Files

- `01__AppCore/Na__AgentOutliner__AppCore__DialogManager__.rb` (icons channel, selection backstop, signature on every push)
- `01__AppCore/Na__AgentOutliner__AppCore__ActionRouter__.rb` (saveSettings message), `...AppCore__Main__.rb` (0.1.15)
- `02__AppData/Na__AgentOutliner__AppData__AppConfig__Defaults__.json` (`grading.status_colours`)
- `05__UserInterface/`: UiLayout.html, MainShell.js (icons), OutlinerView.js (follow, switches, panel), OutlinerModel.js
  (`na_reveal_groups`), Settings.js, Styles Index/Shell/Outliner.css
- `UiIcons__DialogIcons__AgentOutliner/` (new, 25 SVGs)
- `tests/`: Core suite (18 checks), RunChecks (5 faults)

### Checklist For Adam

- [ ] Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Reopen it (the new icon folder and page need the reopen).
- [ ] Click a group in the SketchUp viewport, then one nested deep inside groups: the table scrolls to it and marks it red.
- [ ] Click Follow (crosshair) to turn it off: selecting in the model no longer moves the table. Click again: it jumps back.
- [ ] Click Colours (drop): the violet and amber rows go plain. Click again to bring them back.
- [ ] Quick Name: the Name button on the left (or Q) opens and closes the panel; select rows, click a name.

Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027

## Version 0.1.14 - 11-Nov-2026 - A Reasoning Effort on Each Message, Applied by a Dispatcher Session

### Asked For

"I need a way to set reasoning effort for the messages I send". The Claude app refuses to let a session change its own
effort ("a session must not silently re-price its own turns"); another session may set it, from that session's next
turn. Asked which way to build it, Adam chose a dispatcher session.

### What Was Added

- **The picker:** beside Send in the Chat tab: Auto effort, Low, Medium, High, Extra High, Max.
  - It stays as chosen, like Claude's own (UI pref `chatEffort`), and turns violet when it is not Auto.
  - A message sent with one carries `effort` (low, medium, high, xhigh, max), and its bubble shows a chip ("Max effort").
  - Auto stores nothing and leaves the agents' effort as it is.
- **Where the effort travels:**
  - `Na__Notes__Comment(effort:)`, checked by `Na__Notes__Effort`; an unknown value is refused and nothing is written;
  - the comment route (`ActionRouter.na_comment`);
  - the waiting notice (`notice['effort']`) on every MCP result;
  - the inbox signal, which a dispatcher checks every request against;
  - and the entry itself, which agents read in `inbox` and `thread`.
- **Send's line:** with an effort, it ends "The dispatcher sets Max effort for each agent it wakes." In amber when none is
  running: "Max effort is not applied: no dispatcher is running (ask Claude to run the Outliner dispatcher)."
  - `HistoryStore.Na__History__Dispatchers` reads `ModelHistory/Dispatch__<pid>.json`. A heartbeat counts for three
    minutes, because it pauses while the dispatcher works a request.
- **The exchange** is in the 3D skill's `scripts/outliner_watch.py`, which the Outliner only reads around:
  - an idle agent's watcher, started with `--session <its id>`, writes `Want__<session>.json` when Adam's message
    carries an effort, and holds the wake-up until the dispatcher answers (`Applied__<session>.json`, 90 s at most),
    so the woken turn already runs at his effort;
  - the dispatcher session runs `--dispatch` and wakes only for a request that matches a message he really sent. It
    calls the Claude app's `set_session_effort`, answers with `--applied` (or `--refused`), and starts again;
  - a busy agent that sees an effort in a notice can end its turn with `--resume`, so its next turn runs at it.
- **Fixed on the way:** two messages in the same second tied on their time, and the notice could quote the older one.
  The entry id (milliseconds) now breaks the tie.

### Checked

- Offline suite 278 / 278 (11 new):
  - the five levels kept, Auto and blank none, anything else refused;
  - the effort on the entry, in the notice, the signal and the inbox;
  - Send with and without a dispatcher; a busy dispatcher counted, a silent one not;
  - an unknown effort writes nothing; Auto stores none.
- 29 of 29 deliberate faults caught (4 new: the comment drops the effort, the notice leaves it out, a long-silent
  dispatcher still counts, same-second messages quote the older).
- The watcher's exchange, 13 of 13 offline checks:
  - with no dispatcher, the agent wakes at once and is told;
  - with one, the agent waits, the dispatcher wakes with the request, `--applied` answers, and the agent wakes after it;
  - a forged request (Max where Adam picked Low) is refused without waking the dispatcher;
  - `--refused` gives the reason; `--resume` takes the right model's latest message;
  - with no `--session` it says how to fix it; Auto wakes at once.
- The picker in a browser, on the real dialog page, with real input: High chosen and Enter pressed sent
  `effort: "high"` and remembered it; the chip showed on a Max message.
- Not yet run live: the Claude app's `set_session_effort` itself.

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Reopen it, Chat tab: the picker sits beside Send.
2. Open a new Claude session (set its own effort to Low in Claude) and type "Run the Outliner dispatcher" (3D skill).
3. Agents start their watchers with their session id from now on (the skill's rule). Send a message at High: the line
   says the dispatcher sets High, and the agent wakes at it.

## Version 0.1.13 - 11-Nov-2026 - Copy for Agent Copies Straight Away, With a Toast

### Asked For

"Make the copy for agent button just copy straight to clipboard and avoid this menu, trace and remove all code for this its
not needed. a simple copy feature with a toasty stating it was successfully copied is enough" (with a screenshot of the
Copy for Agent panel crossed out).

### What Changed

- **Copy for Agent copies at once.** That covers every way in: the toolbar button, Ctrl+C in the tree, the row menu, and
  the side panel's button for one object or several. A toast says so: "Copied 19 objects for the agent: paste into
  Claude." With nothing selected it copies what waits for an agent: "Copied the 1 object waiting for an agent: ...".
  With nothing to copy, an amber toast says "Select rows first".
- **The text is what the panel copied by default:** paths, tags and sizes, what standard names and flags mean, the
  latest comments, and the closing note from Configure.
- **The toast** (`Shell.na_toast`, MainShell; `.na-toast` in Shell.css) is a navy note with a green tick (amber for a
  warning), low in the middle, gone after 2.6 s. Every copy raises it, Copy IDs too. If the copy has to go through Ruby
  (`copyText`, the last resort after the browser's clipboard and the hidden-textarea copy), Ruby raises it once clip has
  the text (a new 'toast' channel) and uses the page's own wording.
- **Removed, all of it:**
  - the panel's markup (`#na-handoff`: three ticks, the editable text, Cancel, Copy IDs Only, Copy) from UiLayout;
  - its styles (`.na-handoff-card`, `.na-handoff-text`);
  - its code in AgentHandoff.js: `na_open`, the options, `na_refresh`, `na_wire` and the `H` state;
  - `na_build`'s options, so it always builds the full text;
  - the stale 'handoff' channel note in DialogManager.
  Copy IDs Only went with the panel; the toolbar's Copy IDs button stays.

### Checked

- In a browser, on the real dialog page fed a fake model, with real clicks and keys:
  - two rows selected, then Copy for Agent copied at once, with no panel. The text carried the path, tag and size, the
    standard name's meaning, the flag's meaning, the latest comment and the closing note. The toast and the status line
    both showed;
  - the side panel's button copied the same text;
  - with nothing selected it copied the one object waiting, and the toast said so;
  - with nothing selected or waiting, the amber toast appeared and nothing was copied;
  - Ctrl+C on a selected row copied it.
- Every page script passes `node --check`. The offline Ruby suite (ActionRouter's copyText change) is in the line below.
- Not yet clicked inside SketchUp's own dialog window.

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Reopen it.
2. Select some rows and press Copy for Agent (or Ctrl+C): a toast says how many were copied, with no panel. Paste into
   Claude.

## Version 0.1.12 - 11-Nov-2026 - [ and ] Open and Close the Tree a Level at a Time

### Asked For

"Make the [ and ] keys open levels or collapse levels of the tree".

### What Was Added

- **] opens one level.** Every closed row that has children, at the shallowest level that still has one, opens: from
  all closed, the first press shows the top rows' children, the next their children, and so on. A branch opened by hand
  is left as it is, and the levels above it fill in first.
- **[ closes one level.** Every open row at the deepest open level closes, so the tree folds back the way it opened.
- **Shift+] and Shift+[ do every level** (the Expand and Collapse buttons; Expand still stops at 5,000 rows).
- **The status line says what happened**, e.g. "Opened 6 rows at level 2. ] opens the next level, [ closes it.", or
  "Every level is open." when there is nothing left to open.
- **The grouped views:** the group headings are the level, so [ closes every group and ] opens them again.
- **Where the keys work:** anywhere on the Outliner tab except a text field, so typing [ in the search box or a rename
  still types it. Not on the other tabs. The Expand and Collapse buttons' tooltips name the keys.
- **Where:**
  - `Store.na_step_level(rows, open)` in `OutlinerModel` steps the rows on show, so a search steps the same way;
  - `na_on_level_key` in `OutlinerView`, on the document;
  - the two tooltips in `UiLayout`.

### Checked

- In a browser, on the real dialog page fed a three-level model (3 groups, each with 2 children, each with 2
  grandchildren), with real key presses:
  - ] took the tree from 3 to 9 to 21 rows, then "Every level is open";
  - [ went back 21, 9, 3, then "Every level is closed";
  - with Wall and Wall.1 opened by hand, ] opened Roof and Lantern first (11 rows), and [ then closed Wall.1 (9 rows);
  - Shift+] opened all 21 rows, and Shift+[ closed them;
  - grouped by tag, [ closed both groups and ] opened them again;
  - "a]b[" typed into the search box stayed text, and ] on the Chat tab did nothing.
- No console errors from the change. The only one was the company logo, which is outside the folder the preview served.
- The Ruby suite is unchanged by this (no Ruby but the version).
- Not yet pressed inside SketchUp's own dialog window.

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Reopen it.
2. Click a row, then press ] a few times: the tree opens one level per press. [ folds it back. Shift+] and Shift+[ open
   and close everything.

## Version 0.1.11 - 11-Nov-2026 - Undo and Redo Credited to Whoever Pressed Them; Watches on Erased Definitions Let Go

### Found

Live in the Assembly Studio testbed window (SketchUp 2027), while checking the 0.1.7 fix:
- **An agent's undo and redo were credited to Adam.** For about two minutes after that window's Outliner was hot-reloaded
  from 0.1.4 to 0.1.9, every `model_undo` an agent made recorded its windows as removed "by user", and every redo recorded
  everything as new "by user". Only the parts, credited from the undo's own stack read, said agent. Undo and redo raise
  their entity events outside any operation, so those events took the answer the actor detection still held: an
  operation's answer never let go, or a tick answer whose clearing timer never ran. It cleared itself at the next build
  and could not be brought back on purpose, so the fix makes it impossible rather than chasing the trigger.
- **The observer kept watching definitions that no longer exist.** 179 of 490 watched Entities (204 of 520 later) belonged
  to definitions erased after they were watched (undone builds, Element Assembly Studio rebuilds). Every call on them
  raises "reference to deleted Entities", `remove_observer` included. Closing the model would have logged about 200
  "Releasing an observer" warnings, and the list grew with every build and undo.

### What Changed

- **Undo and redo** (`ActorDetect.Na__Actor__UndoRedo`, called by `Tracker.Na__Tracker__OnUndoRedo`). The call stack is read
  at the undo's own notice. SketchUp sends that notice inside the call that undid, before the entity events (traced live:
  the notice, then the removals, all inside the MCP request). Any operation's answer still held is dropped, since none is
  open across an undo, and this answer is held for the events that follow. Adam's Ctrl+Z reads as his and an agent's
  `model_undo` as the agent's (tool Actions__Undo), whatever was held before.
- **A held tick answer expires** after `NA_TICK_MAX_S` (0.5 s). A clearing timer booked over `NA_TICK_LOST_S` (2 s) ago that
  never ran is booked again, so no answer can stand for minutes again.
- **Watches on erased definitions** (`Observers.Na__Observers__Prune`) are dropped after every full pass. The tracker calls
  it from its timer, never inside a callback. `Na__Observers__Detach` skips them without a word.
- The 0.1.9 notice still moves on every undo, redo and abort (its `Na__Notes__Touch` lines are untouched).

### Checked

- Offline 267 / 267 (13 new):
  - a new definition is watched; an erased one's entities raise as SketchUp's do (new doubles: `DefinitionList#na_erase`,
    `Entities#na_dead!`, `Model#na_fire_redo`);
  - prune drops exactly the dead watch, and a second run nothing; the tracker's full pass prunes;
  - Detach skips the dead watch with no warning and lets every live one go;
  - an agent's undo and redo are the agent's with Adam's answer held; Adam's Ctrl+Z is his with an agent's held;
  - a tick answer held past its time is read again, a lost clearing timer is booked again, and the answer is let go.
- 25 of 25 deliberate faults caught (7 new: no prune; Detach asking dead entities; no prune in the full pass; a stale
  operation answer kept; the undo's answer not held; a tick answer that never expires; a lost timer never booked again).
- Live in the Assembly Studio testbed (SketchUp 2027, 0.1.11 by this tool's Reload Plugin Data), with the fault planted on
  purpose:
  - with a stale "user" answer held, an agent's `model_undo` and redo of an Element Assembly Studio window were credited
    to the agent, all five objects each time;
  - with a stale agent answer held, an undo outside any MCP request (as Ctrl+Z) was Adam's;
  - the full pass after the undo pruned the watch list from 520 to 311, none dead;
  - Detach with a dead watch still listed logged nothing.
  No Outliner log line in any of it; the testbed was left unmodified.

### Checklist For Adam

1. Close the Agent Outliner, Noble 3D Tools > Reload Plugin Data, reopen.
2. Have an agent undo or redo something it built: those rows are violet (by agent). Your own Ctrl+Z stays amber.
3. Close a model you have worked in: Settings' Technical Log gets no "Releasing an observer" lines.

## Version 0.1.10 - 11-Nov-2026 - Send Says Who Will See It: The Agent at Work, the Agents Watching, or Nobody

### Found

At 13:58 on Telfer (0.1.9, MCP 1.0.28) Adam wrote "Can you see now? if so send screenshot" and pressed Send. The line read
"Sent: agents working in this window see it on their next SketchUp call. Last agent call 13:57:24", but nobody answered:
"Nope nothing".
- **The "last call" was not an agent.** 13:57:24 was the bridge starting after his reload (the dialog's footer showed
  "(bridge_start)").
- **No agent was working, and none was watching.** An idle Claude session is never woken by SketchUp.

### What Changed

- **The last agent call** (`ActorDetect.Na__Actor__LastMcpActivity`) skips the bridge's own lines and the pings every MCP
  server sends to find its windows (`NA_NOT_AGENT_CALLS`: bridge_start, bridge_stop, reload, setting, ping, api_probe). The
  footer and Settings read it too. `Na__Actor__SecondsAgo` reads the log's HH:MM:SS clock, across midnight too.
- **Watchers** (`HistoryStore.Na__History__Watchers`): the 3D skill's `scripts/outliner_watch.py` keeps a heartbeat,
  `ModelHistory/Watch__<pid>.json` ({pid, model, who, beat}), while it waits. A heartbeat counts when it is under 30 s old
  and its `model` text is in this model's title or path (empty for any model).
- **Send's line says who will see it** (`ActionRouter.na_sent`):
  - "Sent: the agent working here sees it on its next SketchUp call (last call 14:05:08)": an agent called in the
    last 3 minutes (`NA_WORKING_S`);
  - "...; 1 waiting agent (Claude (Telfer orangery session)) wakes now": a watcher's heartbeat is fresh;
  - otherwise, in amber: "Saved, but no agent is working here (last SketchUp call 13:12:05) or watching this model, so
    none will see it until one calls SketchUp. Ask in Claude, or have agents leave the inbox watcher running."
  - The older-MCP and no-MCP lines are unchanged. An inbox flag reads the same after "Flagged 1 object For Agent."
- MCP 1.0.29 also gives the notice, as a warning line, to sessions whose MCP client started before 1.0.28.

### Checked

- Offline 254 / 254 (7 new, 2 rewritten):
  - a working agent; nobody working or watching (amber); a fresh watcher for this model counted, another model's and a
    stale one not; the watcher named; a flag with both;
  - the last call skipping bridge_start and ping; SecondsAgo across midnight.
- 18 of 18 deliberate faults caught (2 new: a stale heartbeat counted, bridge_start taken as an agent call).
- Live, in a throwaway template window (both plugins fresh): a watcher running, Send read "Sent: the agent working here
  sees it on its next SketchUp call (last call 14:05:08); 1 waiting agent (Claude (wake test)) wakes now.", and the
  watcher woke its session. The heartbeat file was gone after.

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Na SketchUp MCP: Reload Plugin Data (1.0.29). Reopen.
2. Press Send with no agent working: the line is amber and says nobody will see it.
3. With an agent at work, or one whose watcher is running, it names who sees it, and that agent answers.

## Version 0.1.9 - 11-Nov-2026 - Send Reaches the Agents Working Here, and Agents' Pictures Have Their Own Folder

### Asked For

"Should the Send button in the plugin not do that?": his 13:15 Model Chat message on Telfer-Smith 64481 waited unread while
the agent made about 15 SketchUp calls, because an agent only heard him when it thought to read its inbox. Then: "Add the
ability for Claude to share images back to me to this may require a second cache folder for incoming images".

### What Was Added

- **The waiting notice** (`06__McpOperations`, `Na__AgentOutliner__McpNotice(model)`). This is what waits for an agent,
  in a few words: how many, who, when, where (model chat or "<name> (id N)"), the latest message's first 120 characters,
  pictures, threads, and the call that reads it. The Na SketchUp MCP 1.0.28 puts it on **every** tool result while
  anything waits, so the agent hears Adam on its next SketchUp call. Nothing when nothing waits.
- **Cached, so it costs nothing per call.** It is kept per model (`state[:notice]` in the tracker's state) and worked
  out again only when one of these changes:
  - `Na__Notes__Revision`: moved by every thread or flag write, an agent's acknowledge (`MarkRead`), undo, redo, an
    aborted step, and the standards saved;
  - the tracker's notes digests;
  - the history itself;
  - an object it counted being erased.
  Live: 8 microseconds a call from the cache, 1.7 ms to work it out again over 3,001 objects.
- **Send says what will happen** (`ActionRouter.na_sent`, used by Send and by an inbox flag). The status line is one of:
  - "Sent: agents working in this window see it on their next SketchUp call. Last agent call 13:49:44." (or "No agent
    has called here yet.");
  - with an MCP older than 1.0.28: "Saved. This window's Na SketchUp MCP (1.0.24) shows it only when an agent reads its
    inbox: Extensions > Na SketchUp MCP > Reload Plugin Data ...";
  - with no MCP running here: "Saved, but the Na SketchUp MCP is not running in this window: no agent will see it until
    it starts."
  - A For Agent, Question or Check This flag reads "Flagged 1 object For Agent. Sent: ...". Reference, Do Not Touch
    and Done are not sent.
- **A signal for idle agents** (`HistoryStore.Na__History__WriteInbox`). Each Send rewrites
  `ModelHistory/Inbox__<model key>.json` with the model, when he sent and the notice. An idle Claude session runs the 3D
  skill's `scripts/outliner_watch.py` in the background. It polls those files and ends with his message, which wakes
  the session. Nothing is written for a model never saved.
- **Agents' pictures in their own folder** (`ChatCache`): `91__UserConfig__LocalOnly/ChatFromAgents`, named
  `agt_YYYYMMDD_HHMMSS_xxxx.png`, beside his `ChatCache/img_...`.
  - The name's prefix picks the folder (`Na__Chat__Path`), for the dialog too (`state.chat.agent_url`).
  - Settings lists "Pictures agents sent (this PC)" with an Open button, and the chat list counts both folders.
  - `NA_NAME_RULE` is replaced on every load, so Reload Plugin Data takes the new names without a restart.

### Notes

- The notice belongs to the MCP's handler (`Na__Handlers__AgentOutliner__Notice`), which returns nil for an Agent
  Outliner without `McpNotice`. So an older Noble 3D Tools with a new MCP gives no notice and no error.
- A raw attribute write that bypasses `Na__Notes` (an agent's own Ruby) is still caught: the tracker's full pass
  after an agent's commit changes the notes digests.
- `NA_MUTATIONS`: the 0.1.1 "reload keeps the old action lists" fault had gone stale when 0.1.5 added `tags`. Its anchor
  is updated, and it is caught again.

### Checked

- Offline suite 249 / 249 (29 new):
  - nil when nothing waits; served from the cache (no notes read); the 120 character quote; a new message, undo and an
    erased object each make it work again; acknowledge and reply end it; a fault gives nil;
  - Send's three status lines and the inbox flag; the signal file and its path length; no signal for an unsaved model;
  - agents' pictures in ChatFromAgents, the name rule replaced on reload.
- 16 of 16 deliberate faults caught: 4 new (no revision on a write or an acknowledge, an erased object still counted,
  agents' pictures in Adam's folder), and the stale one.
- Live in a throwaway SketchUp 2027 window (a template copy; both Reload Plugin Data run first): see the Na SketchUp MCP
  1.0.28 devlog. Send's line, the notice on the next call and on an error, the watcher waking, a capture sent back into
  ChatFromAgents, and acknowledge, reply and undo each ending it.

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Na SketchUp MCP: Reload Plugin Data. Reopen it.
2. While an agent is working, write in the Model Chat and press Send. The status line says agents see it on their next
   SketchUp call, and the agent should answer within a call or two.
3. Ask the agent to show you something: its picture appears in the chat, and Settings > "Pictures agents sent" opens
   the folder.

## Version 0.1.8 - 11-Nov-2026 - Point at an Object: "Hey, This One" in the Chat

### Asked For

"Add a second button with a clicking / cursor symbol. this makes it so the next object you click in the sketchup viewport
is copied and pasted at the cursor in the chat. AIM: quickly saying "Hey this object" click to select and past basically"

### What Was Added

- **The pick button**, beside the paperclip in the Chat composer (both now drawn as line icons). Press it, click an object
  in SketchUp, and "NAME (id 12345)" goes in the message where the text cursor was, spaced from the words around it (a
  selected word is replaced). The dialog comes back to the front with the cursor after it, ready to keep typing. The
  button turns amber and the hint line says what to do while SketchUp waits; pressing it again, or Esc in SketchUp, stops.
- **Which object** (`03__ModelData/Na__AgentOutliner__ModelData__ChatPick__.rb`, a SketchUp tool pushed on the model's
  tool stack and popped after the click, back to the tool in use): the deepest group or component under the cursor that
  has a name of its own, so SUB__Orangery__RoofLantern__Top__02 rather than the unnamed bar group inside it or the
  building around it. An amber box and a label ("level 2 of 3") show what a click takes before you click. Right-click (or
  Up) steps out to the object around it, and past the outermost back to the innermost; Down steps in; Ctrl takes the part
  right under the cursor, named or not. Shift+click puts the object in and keeps picking (its box turns green). Clicking
  empty space or loose geometry picks nothing and keeps waiting. The selection is never changed.
- **"(id 12345)" in any message is a chip**, in the Chat tab and the Inspector's thread: click selects the object in
  SketchUp, double-click zooms to it; struck through when the object is gone. Agents read the same text, and the id is the
  persistent id every MCP tool takes.
- **Routes** `chatPick` and `chatPickCancel`; the answer comes back on `chatPicked` ({items, done, cancelled}); a refusal
  (no model) comes back there too, so the button never stays pressed.

### Notes

- **The keyboard stays with the dialog** after its button is pressed, so the tool reads Ctrl and Shift from the mouse
  flags; Up and Down only reach it once the viewport has the keyboard (after a Shift+click, say). Right-click is the
  mouse-only way out a level.
- **Coordinates** (the global coordinate rule): `PickHelper#path_at` starts at the active entities, whose transformations
  are world; the box multiplies the path's transformations from the first and never `edit_transform`, and `View#draw` gets
  world points. The maths runs on `Transformation#to_a` (column-major) with the homogeneous w divided out, because
  SketchUp keeps a uniform scale as 1/s in the last element.

### Checked

- Offline suite 220 / 220 (22 new): the box of a group moved, turned, three deep and scaled (scale in the last element)
  lands on the hand-worked world corners; the reverse product misses them; the same box with the outer group open; the
  default, steps, clamps and Ctrl; NAME (id N); and the tool itself on a fake view and tool stack (hover label and 12
  edges, Ctrl, right-click wrap, Up and Down, Shift+click keeps picking, a click lets go and pops back, Esc and the button
  each cancel once, empty space and loose geometry pick nothing, the two routes). Four deliberate faults (reversed
  product, no w divide, outermost by default, Ctrl ignored) are each caught.
- Browser preview against a stub bridge with real typing and real clicks on the button: the object went in at the cursor,
  focus came back, a second pick after more typing landed after it; a selected word was replaced; Shift+click put in
  three; the button again and Esc each stopped it; a refusal showed its reason; the sent message's chips selected and
  zoomed. No console errors.
- Not yet run inside SketchUp: the tool, its highlight and its pick depth are checked offline only.

### Checklist For Adam

1. Close the Agent Outliner, Noble 3D Tools > Reload Plugin Data, reopen, Chat tab.
2. Type "Central rooflight is wrong - ", press the arrow button (it turns amber), move into SketchUp: an amber box follows
   the named object under the cursor. Click the lantern top: "SUB__Orangery__RoofLantern__Top__02 (id ...)" is in the
   message and you can keep typing.
3. Try right-click to box the object around it, Ctrl for the part under the cursor, Shift+click for two objects.
4. Send it: click the id chip in the bubble, and SketchUp selects the object.

## Version 0.1.7 - 11-Nov-2026 - A Deleted Definition No Longer Fills the Technical Log

### Found

An agent reading `agent_outliner summary` in the Assembly Studio testbed window (Outliner 0.1.4 loaded) saw the log tail full of
"Observer onComponentAdded failed again (30..34): reference to deleted ComponentDefinition". A definition added and erased in one
operation (an MCP rollback trial, a temporary `make_unique` copy such as the orangery kit's column variants) reaches
`DefinitionsWatch#onComponentAdded` already deleted, and the first call on it (`definition.image?`) raises. The error was caught,
so nothing broke, but every such operation added a line to the Technical Log and buried real warnings.

### Fixed

- `04__ChangeTracking/Na__AgentOutliner__ChangeTracking__Observers__.rb`: `onComponentAdded` returns at once when the definition
  is no longer valid. There is nothing to watch in a definition that no longer exists.
- `tests/Na__AgentOutliner__Tests__Core__.rb.test`: a check that a definition arriving deleted (its `image?` raising as SketchUp's
  does) is skipped with no error logged. With the guard taken out it fails, so it holds the fix.

### Validation

- [x] Offline: 198 of 198 (was 197), and 197 / 1 failed with the guard removed.
- [x] In SketchUp 2027, checked by an agent in the Assembly Studio testbed window (11-Nov-2026, 13:48 to 13:56). That window had
      run 0.1.4 since it opened, with 1,691 onComponentAdded failures logged; the Element Assembly Studio window builds (their Fuse
      Parts step) were the source. After this tool's Reload Plugin Data (0.1.9 on disk): two casement builds through
      `entity_studio_edit`, then Undo, Redo and Undo again. One build alone handed the observer 39 new definitions, 34 of them
      already deleted (the build's temporary parts). There was not one error and no Technical Log line in all of it. The Outliner
      listed both windows and their fused parts as new by agent, and as removed via undo. Suite 249 of 249 (0.1.9); a scratch copy
      without the guard fails exactly this check (248 / 1).
- [ ] Every SketchUp window opened before this fix (12:24 on 11-Nov-2026) still runs the old observer and keeps logging these
      lines: Noble 3D Tools > Reload Plugin Data (or this tool's own, in Settings), or restart SketchUp.

## Version 0.1.6 - 11-Nov-2026 - The Chat Tab: Every Conversation With Agents, With Pictures

### Asked For

"Add a dedicated Chat Tab which charts the ongoing conversation in a typical chatbot interface and shows all active agents
chats associated with the current model. ensure pasting images is possible so vreate a temp cache folder etc and handlers"

### What Was Added

- **A Chat tab** between Outliner and Configure, with a badge counting what agents wrote that you have not read.
  - **Down the side:** search; filters All / Unread / For Me (an agent answered) / With Agents (you wrote, nobody has
    picked it up) / Resolved; **Agents on this model**, one per name they sign with (`author`), with when each last wrote,
    in how many chats, a green dot when active in the last hour, and a click to see only its chats; then the chats: the
    Model Chat always first (every agent reads it), then every object thread, newest first, with the last line, unread
    count, who it waits on, its flag and how many pictures. The bridge line at the foot says whether agents can reach the
    model and the last call.
  - **The open chat:** bubbles, yours on the right in your amber, each agent on the left in its own colour with its
    initials (CB for "Claude (bay window session)"); day lines; a New line before what you have not read; flags and
    resolves as small centred lines; "sent" or "read by an agent" under yours; Delete on hover. The header names the
    object and its path, with Select, Zoom, In Outliner, Flag and Resolve / Reopen.
  - **The composer:** Enter sends, Shift+Enter is a new line. **Pictures:** Ctrl+V pastes a screenshot, pictures can be
    dropped on the chat or chosen with the clip button, up to 8 on a message, and a picture can go alone. Each shows in a
    tray while it is added; Send waits for them.
  - **New Chat** starts one about the objects selected in the Outliner (one, or each of several); "Open in Chat" is on
    the row menu and in the Inspector's thread, and the Inspector shows pictures in its thread too.
- **The picture folder:** `91__UserConfig__LocalOnly/ChatCache` (this PC only, git-ignored), one flat folder for every
  model so a Save As never loses a picture, short names (`img_20261111_120501_a1b2.png`) to stay well under Windows' 260
  characters. Shown in Settings with an Open button. Nothing is deleted automatically.
- **How a picture travels:** the dialog shrinks anything over 2,400 px or 6 MB on a canvas (PNG stays PNG unless still too
  big), sends it base64 in 480,000-character pieces (`chatUpload`); `Na__ChatCache` joins them, checks the first bytes
  (PNG, JPEG, GIF or WebP; 15 MB at most), writes a .part file and renames it, and answers with the name. The comment
  stores names only (`images: [{file, w, h, bytes, name}]`); `Na__Chat__Attachments` checks each is in the folder first.
- **For agents** (Na SketchUp MCP 1.0.26): every picture in a thread carries its `path`, so an agent opens what you
  pasted; `comment` / `reply` take `images` (picture files on this PC, e.g. a view_capture), copied into the folder before
  anything is written; the chat list's `agents` comes from the names they sign with.

### Fixed

- **New dialog actions never worked after Reload Plugin Data.** The route table was guarded with `unless defined?`, so a
  reload kept the old table: 0.1.3's Front faces picker and 0.1.5's Tag picker would have answered "Unknown action" until
  SketchUp restarted. The table is now replaced on every load (as the MCP seam's action lists are).
- `Dir.glob` reads a Windows backslash as an escape: the cache counts files with `Dir.children` instead (found by the suite,
  whose temp folder path has backslashes).

### Checked

- Offline suite 197 / 197 (26 new: picture bytes, sizes from headers, pieces in any order, refusals that write nothing,
  paths outside the folder, a picture alone, [picture] in the row, paths in threads, the chat list and its agents, an
  agent's attached file copied, an agent's missing or non-picture file refused, the route table replaced on reload).
- MCP: BridgeCore 138 / 138, PythonServer 54 OK, ValidateApiUsage passed, `--check` 68 tools at 1.0.26.
- Browser preview against a stub bridge: the tab, badge and agents; a pasted picture added, sent with real typing and
  Enter, drawn in the bubble and in the viewer (Esc closes); a 5000 x 3000 picture dropped and shrunk to 2400 x 1440; a
  5.5 MB picture sent in 16 pieces; a refused picture marked Failed; a plain-text paste left alone; two pictures alone in
  one message; filters, the agent filter and search; New Chat for two selected objects; Open in Chat from the Inspector;
  no console errors.
- Not yet seen in SketchUp. Not checked: whether SketchUp's dialog loads pictures from the file:/// folder (it loads the
  company logo the same way, from outside the dialog's folder).

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Na SketchUp MCP: Reload Plugin Data. Reopen it.
2. Open the **Chat** tab: the Model Chat is first; your object threads follow.
3. Take a screenshot (Win+Shift+S), click in the message box and press Ctrl+V: it appears above the box. Type a line,
   press Enter. The picture shows in the bubble; click it to see it full size.
4. Settings > Chat pictures > Open: the file is there.
5. Restart Claude Code, then ask an agent to read the Model Chat and describe your screenshot, and to reply with a
   view_capture picture.

## Version 0.1.5 - 11-Nov-2026 - The Tag Picker, Tags for Agents, and the Name Rename That Never Opened

### Asked For

"Create an effective efficent system for changing the tag of a item or a selection of items and ensure tagging is easily
exposed to agents too. secondly only typing the instance name works trying to change the main name does not"

### Fixed: Double-Click in the Name Cell Opened Nothing

0.1.4 still listened for the browser's own `dblclick`. The first click of a double-click selects the row, and selecting
redraws the row under the pointer, so the second click lands on a new element and Chromium never fires `dblclick` at all
(seen with real mouse clicks in the preview: no event reached the document). Instance Name only worked when its row was
already selected, so its first click redrew nothing. The click handler now tells a double-click itself: the same row
twice within 500 ms and 8 px, no modifier keys. On the Name or Instance Name cell it renames in place, on the Tag cell it
opens the picker, anywhere else it zooms as before. The twisty, eye, lock and flag keep their single-click jobs.

### Added: The Tag Picker

- **Where it opens:** click the Tag cell of a selected row (or its caret, shown on hover); double-click any Tag cell;
  the new **Tag** button in the agent bar; **T** in the table; "Change Tag..." in the row menu; **Tag...** in the
  inspector. It acts on every selected row, or on the one row clicked.
- **Using it:** type to filter (names starting with the text first, then containing it); Up / Down and Enter, or click.
  Each tag shows its colour, a strike-through when hidden, a tick on the tag the objects share now, and how many objects
  are on it. Empty, it lists Recent (the last five used, kept in the user config) above All Tags and Untagged. A name
  that matches no tag offers **Make tag "name"**, which makes the tag and moves the objects in the same step.
- **Ruby:** `Na__EntityActions.Na__Actions__FindTag` (as SketchUp shows the name, exact first, then any case; "" or
  "Untagged" is Layer0) and `Na__Actions__SetTag` (one "Agent Outliner: Tag" undo step; none when nothing moves; a
  missing tag refused unless `create`; Layer0 is never made as a tag). Dialog route `setTag`.

### Added: Tags for Agents (Na SketchUp MCP 1.0.25)

- `agent_outliner tags`: every tag with colour, shown (folders included), folder path and its object count, plus the
  untagged count (`Na__Payloads.Na__Payload__TagList`).
- `agent_outliner_edit tag`: `ids` and `tag` ("Untagged" or "" for none); a missing tag is refused `not_found` with the
  model's tags named, unless `create: true`. One "MCP: Agent Outliner Edit" step, reported as `undo`; none when nothing
  moves. `find "tag:NAME"` already lists what is on a tag.

### Checked

- Offline suite 171 / 171 (12 new: tagging, any case, refusal, create in the same step, Untagged, Layer0, the `tags`
  payload, the `tag` edit, its refusals, no undo step when nothing moves; the action lists).
- MCP: BridgeCore 137 / 137, PythonServer 54 OK, ValidateApiUsage passed, `--check` 68 tools at 1.0.25.
- Browser preview with REAL mouse clicks: double-click on an unselected Name opened the box and Enter sent `rename`;
  the Tag cell of a selected row opened the picker focused on its search; "draw" then Enter sent `setTag` 06__Drawings;
  Ctrl+click a second row, T, a new name, Enter sent `setTag` with both ids and `create: true`; the Tag button, the
  row menu item and the inspector button open it; Instance Name double-click still edits; no console errors.
- Not yet seen in SketchUp, and the MCP actions not yet called live.

### Checklist For Adam

1. Close the Agent Outliner. Noble 3D Tools: Reload Plugin Data. Na SketchUp MCP: Reload Plugin Data. Reopen.
2. Double-click the name of a row that is NOT selected: the name box opens. Type, Enter.
3. Select a few rows, press T (or click Tag, or a selected row's tag): type part of a tag name, Enter. Ctrl+Z puts
   them back in one step.
4. Type a new name in the picker: "Make tag ..." makes it and moves the rows.
5. Restart Claude Code so agents see `agent_outliner tags` and `agent_outliner_edit tag`.

## Version 0.1.4 - 11-Nov-2026 - Rename in Place, an Instance Name Column, Drawing Plane Names

### Asked For

"Add double click to rename in the name cell fix this ugly messed up dropdown"; "Add instance name next to definition and
make it a click to edit too"; new quick names REF__DrawingPlane__FrontElevation, __RightElevation, __LeftElevation,
__RearElevation, and "Also REF__DrawingPlane__PlanView".

### What Changed

- **The Front faces picker** (0.1.3) took the shared `.naSelect` style: full width, 6px padding in a 22px box, so it sat on a
  row of its own with its text clipped. It is now `.naSelect.na-qn-orient`: 150px, 24px high, inline before Strip.
- **Double-click anywhere in the Name cell renames.** Before, only a double-click on the name text itself did, and the click
  before it redraws the row, so the second click often landed on a detached element and zoomed instead. The handler now
  asks `elementFromPoint` what is under the pointer. Double-clicks on the twisty, eye, lock or flag keep their own job.
- **Instance Name column** beside Definition (on by default; a saved column layout gets it beside Definition, not at the
  end): the copy's own name (`row.n`), "No name" in italics when it has none. Double-click it, or click it on the one row
  already selected, to edit in place; Enter saves (the same `rename` as the Name column, one undo step), Escape cancels.
  Several rows selected: the multi-rename prompt. Images and section planes have no cell. Sortable.
- **Drawing Planes** quick names (replace mode, category "Drawing Planes"): REF__DrawingPlane__FrontElevation,
  __RightElevation, __LeftElevation, __RearElevation, __PlanView. Each meaning tells an agent to draw on the plane and
  never move or edit the plane. The longest label wins, so they show as their own prefix, not as plain REF.

### Checked

- Offline suite 159 / 159 (5 new: the five names, no validation issues, exact compose, match beats REF, REF swaps them).
- `node --check` on both changed scripts; plain ASCII.
- Browser preview against a stub bridge with the real standards: picker 150 x 24 inline; double-click on the empty end of a
  Name cell opens the box (Escape closes it); double-click on Instance Name opens it, Enter sent `rename` with the new
  name; a first click on an unselected row selects only, a second click edits; no console errors. Not yet seen in SketchUp.

### Checklist For Adam

1. Close the Agent Outliner, click Reload Plugin Data, reopen it.
2. The Front faces picker sits small after the Elevation Faces buttons, text readable.
3. Double-click the blank part of a Name cell: the name box opens. Enter to save.
4. Instance Name sits after Definition. Double-click one, type, Enter: SketchUp's Entity Info shows the new instance name.
5. Quick Name shows a Drawing Planes group with the five REF__DrawingPlane__ buttons.

## Version 0.1.3 - 11-Nov-2026 - Elevation Faces: Quick Names, Orientation and Filters

### Asked For

Adam set the naming standard for everything on a building (Brown 60795): elevation words from "SketchUp's default ortho
parallel projection camera faces", Front / Back / Left / Right (and Top), with a real-world cardinal after it once he
attributes one, "always like Front__North__ so we have a relative model and a real-world cardinal". Then: "update the
agent manager SketchUp hierarchy tool ... to have these quick prefixes added too and filtering by elevation or model
direction".

### What Was Added

- **A third Quick Name mode, `face`.** Five standards entries, category "Elevation Faces": `Front` (faces -Y), `Back`,
  `Left` (faces -X), `Right`, `Top`. A face is a SEGMENT inside a name, never a prefix: it is swapped in place
  (`...__Left__01` -> `...__Front__01`, cardinal and all), put before a trailing number (`SUB__Orangery__DoorHandle__01`
  -> `...__Front__01`), put straight after `SUB__LineworkDetailing` (`SUB__LineworkDetailing__Front__Doors`), or
  appended. Face entries never match as prefixes, so Strip and the Prefix column ignore them. Configure offers the mode
  ("Elevation face (a segment)") with a preview.
- **The model's orientation.** A picker at the end of the Quick Name bar, "Front faces: North / East / South / West / not
  set", stored on the model (`Na__AgentOutliner__Orientation` / `front_faces`), one undo step ("Agent Outliner: Front
  Faces South"). Set, the face buttons read `__Front__South__`, `__Left__West__` ... and add the cardinal after the face.
  Clockwise turns from Front: Left +1, Back +2, Right +3 (Front South -> Left West, Right East). Top has none.
- **Filtering.** Search terms `face:front` (the face segment) and `dir:south` (the cardinal in the name, or the one the
  face points to under the model's orientation), in the dialog and in `agent_outliner find`. Five quick filter chips,
  Front / Back / Left / Right / Top, in their own family (several at once OR together).
- **Agents** see `front_faces` in every model block (`agent_outliner summary`), and the face entries with their meaning
  in `agent_outliner prefixes`. Setting the orientation through the MCP is not built yet (no edit action).

### Notes

- Ruby constants guarded by `unless defined?` do not refresh on Reload Plugin Data, so the new mode and query fields are
  added inline (`%w[replace prefix face]`, `NA_FIELDS + %w[face dir]`) and the face words are methods.
- Diagonal faces (`FrontLeft`) are in the skill's standard but not in the Quick Name list or the parser yet.

### Checked

- Offline suite 154 / 154 (21 new face, cardinal, orientation and apply checks).
- Live on Brown after Reload Plugin Data: `agent_outliner find face:front` gave the 3 front handles, 2 wall lanterns and
  the front door linework (not `CAD__FrontElevation`); `face:left | face:right | face:top` gave the side handle, both
  pipes, the side linework and the 3 roof lanterns. The dialog itself was not opened and looked at.

## Version 0.1.2 - 10-Nov-2026 - A Toolbar Button: a Second Way In

### Asked For

"Add A SketchUp UI Icon as a second launch point to open our outliner".

### What Was Added

- **A toolbar button.** The 3D Modelling Tools toolbar gains a second button, after the NA company icon, that opens the Agent Outliner
  (tooltip "Open Agent Outliner"). It is the first entry in Noble 3D Tools 0.9.27's new registry list `toolbar_items`, runs
  `open_agent_outliner` through `RunCommandById`, and its launches count under the source `toolbar`.
- **Its icon.** `UiIcons__ToolbarIcons__AgentOutliner/Icon__Noble3dToolbar__AgentOutliner__.svg`: an outliner tree (a parent row and two
  child rows on a trunk) with a speech bubble top-right for the threads, where Cube carries its plus. Noble Drawing Tools family: stroke
  34, round caps, dots r46, ink #172b3a, coverage 13.0%. Its spec (`Icon__Noble3dToolbar__AgentOutliner__.icon.json`) and QA proof are in
  the vector skill's `10__SvgFiles__Converted/01__ProductionFiles`; a copy of the SVG is in
  `20__Outputs__New__OutputsAfter__20-Series/2026-11-10__Noble3dTools__AgentOutlinerToolbar`.
- No Agent Outliner code changed. The version moves to 0.1.2 so Settings shows the release with the icon.

### Checklist For Adam

1. Click **Reload Plugin Data** in 3D Modelling Tools > Settings, or reload all of Noble 3D Tools from this tool's Settings tab. This
   tool's own reload leaves the toolbar alone.
2. The 3D Modelling Tools toolbar now has a second button after the NA icon; hovering says "Open Agent Outliner".
3. Click it: the Agent Outliner opens.
4. If the button is missing, restart SketchUp once and look again.

## Version 0.1.1 - 10-Nov-2026 - Every Flag and Every Thread for Agents, Strip, and a History That Saves

### Asked For

From the Brown 60795 session: build every MCP tool the Agent Outliner still needs (summary, flags, threads, names; flags, threads and
standard names written back), each write one undo step and refused in read-only mode, proved by zero-trace trials in a test model.

### What Was Added (the MCP seam)

| Action | What it does |
|---|---|
| `agent_outliner flags` | Every flagged object by flag type, in the standards' order, each type with its meaning and count (empty types too); each object with id, path, who set the flag and when, its thread status and what waits. `flag` (id or label) and `by` (user or agent) narrow it. A type since dropped from the standards still shows, and says so |
| `agent_outliner threads` | Every thread on one line, the model's included: open or resolved; `waiting_on` agent (Adam's comments or flag not yet acknowledged) or user (open, last comment an agent's); counts; the last word (240 characters). Sorted on an agent, on Adam, other open, resolved, newest first. `status` and `waiting_on` narrow it |
| `agent_outliner_edit strip` | The Strip button for agents: any standard prefix off, one "MCP: Agent Outliner Edit" undo step (`Na__Naming__Strip` takes `operation_name:`), no step when nothing changes, and a warning naming any object left with no name (one named exactly a label) |

### Fixed (found in the live trial)

1. **The history was never saved.** `ModelHistory` is about 195 characters deep on Adam's PC, and 0.1.0's file names
   (`Na__AgentOutliner__History__<48 character stem>__<crc>__.json`) took the path to 274 to 292 characters. SketchUp's Ruby cannot open a
   path of 260 or more on Windows: every save failed with `Errno::ENOENT` (proved in the test window: 276 characters refused, 238
   written). So New / Updated marks, who did what, and what Adam and agents had read were lost at every restart. Files are now
   `History__<20 character stem>__<crc>.json` (about 243 characters with `.tmp`); a 0.1.0 key still held after a reload is cut to the
   same name. The folder held no 0.1.0 files to carry over.
2. **A plain Reference, Do Not Touch or Done flag waited for an agent.** Configure's "Agent inbox: waits for an agent" was honoured for a
   flag with no thread entry but not for the entry every flag writes. Now a flag entry waits only for an inbox type, or when Adam typed his
   own note with it (that note is something to read). Comments and reopens always wait. The dialog's Waiting filter and badge follow.
3. **Reload Plugin Data kept the old action lists** (guarded constants). The seam now replaces them on every load.

### Verified

- Offline: 135 of 135 checks (36 new: flags, threads, strip, the inbox rule, history path lengths on Adam's real folder, a reload that
  replaces the lists); **12 of 12 deliberate faults caught** (6 new). 17 of 17 files compile; `su_lint.py` 0 errors, 0 warnings.
- Live in a throwaway SketchUp 2027 window (a copy of the Simple template in the session scratchpad; Adam's window untouched):
  Reload Plugin Data (17 files, 0.1.1); every new action and refusal through the bridge; the history file written at 239 characters;
  each edit undone with one `model_undo`; read-only mode refusing `strip` and `acknowledge`; then every step undone, nothing left in the
  model, the window closed and its history file deleted. Full account: Na SketchUp MCP DEVLOG, 1.0.23.

### Testing Notes

- [ ] Noble 3D Tools > Settings > Reload Plugin Data (or this tool's Settings > Reload Plugin Data), then Extensions > Na SketchUp MCP >
      Reload Plugin Data. A SketchUp restart does both.
- [ ] Work a few minutes, restart SketchUp, reopen the model: the New / Updated colours are still there.
- [ ] Flag a group Do Not Touch: it does not show as Waiting; ask an agent for `agent_outliner flags` and it is listed.

**Status: MCP SEAM VERIFIED IN A SKETCHUP 2027 TEST WINDOW - THE DIALOG ITSELF NOT YET OPENED IN SKETCHUP**

## Version 0.1.0 - 10-Nov-2026 - The Agent Outliner: an Outliner Built for Working With Claude

### Asked For

*"Read your sketchup skills in my noble 3d tools in Plugins folder 2027 build a new imporved sketchup outline tailored for helping me working with calude MCP Agents. Build in tools for me to quickly tag items with standard prefixes such as CAD__FrontElevation CAD__SideElevation__Left CAD__SideElevation__Right CAD__RearElevation. Have a tab based UI similar to my other tools Outliner | Configure | Settings. Settings has the hot reloader present in my other plugins configure allows for adding new prefixes etc and maintaining them. Outliner - Create THE ULTIMATE OUTLINER tool research online SketchUps outliners pitfalls and imrpove it add robust searching, filtering and groupoing. build in a way that i can easily copy or mark items for MCP agents to help me when working with agents, create a flag feature etc and two way commenting system, so agent -> user and user -> agent and build robust MCP handling. Add flags for New , Recent , Updated etc so i can track whats been updated recently by either me ort agent with clear color grading. add ability to organise columns by clicking them. build the plugins files in my style and code in my style"*

Then, mid-build: *"I said "Tag" Should have said "Name" so it can name groups quickly , tag is something different"*. Quick Name only ever
changes names, never tags.

### What Was Built

| Part | What it does |
|---|---|
| The table | One row per object occurrence; only the rows on screen are drawn (plus a margin), so ten thousand rows scroll as fast as fifty. Columns: Name, Shown/Locked, Status, Changed, Flag, Notes, Type, Definition, Tag, Size (mm), and optionally Copies, Material, Prefix, By, ID. Click a heading to sort (again to reverse, a third time to clear), Shift+click for a second key, drag its edge to resize, drag it to move it, right-click for the column chooser. Natural order (W2 before W10). Remembered per PC |
| Views | Tree, Flat List, and Group by Tag, Type, Definition, Flag, Change, Who Changed It, Prefix or Parent |
| Search | Words, `field:value` (name def tag type flag by is has prefix id mat note), `-term`, `"a phrase"`, `/pattern/`, `a \| b`. Matches keep their parents on screen, dimmed and opened, with a match count. The MCP's `find` reads the same language |
| Quick filters | Flagged, Notes, Unread, Waiting; New, Updated, Recent, Unseen; By Agent, By Me; Hidden, Locked, Unnamed, Selected. Chips in one family are OR'd, families AND'd |
| Quick Name | One click names the selected objects from the standards: `replace` (exactly CAD__FrontElevation) or `prefix` (REF__ + the old name). A standard prefix already there is swapped, never stacked; SketchUp's placeholder names count as none; images are refused with the reason. Strip takes it off. One undo step each |
| Flags | Six seeded types (For Agent, Question, Check This in the agent inbox; Reference, Do Not Touch, Done). Set by Adam they wait for an agent; set by an agent they show with an A, for Adam |
| Threads | A chat per object and one for the model: Adam right, agents left in the agent colour, flags and resolutions as small lines; Ctrl+Enter sends; agent entries Adam has not read are marked New and counted read after a moment on screen. Resolve and reopen. Delete with a confirm (Ctrl+Z brings it back) |
| Change tracking | New, updated (name, tag, material, transform, definition, contents) and erased, with who (agent or Adam), when, and the MCP handler. Colour bands 5 min / 30 min / 2 h / 24 h (Settings). Recent = the second band. Mark Seen resets the Unseen filter. A dot on a closed row means something inside changed. Recent Activity feed when nothing is selected |
| Copy for Agent | Text to paste into a chat: each object's id, type, path, tag, size, what its standard name and flag mean, the latest comments, and the closing note from Configure. With nothing selected, what waits for an agent |
| Selecting | A click selects in SketchUp too, opening the parent group as SketchUp's Outliner does (or the top-level object, Settings); a locked parent falls back to the top object and says so. Follow Selection opens the tree to what is selected in the model. The outliner's own selection can span any groups, for flags, comments and names |
| Keys | Arrows (Shift extends), Right/Left open and close, Enter zooms, F2 renames, Ctrl+A, Ctrl+F, Ctrl+C (Copy for Agent), Esc |
| Settings | Reload Plugin Data (this tool's Ruby, then the dialog reopens so HTML, CSS and JS reload), Reload All Noble 3D Tools, tracking switches, colour bands and colours with a live legend, selection behaviour, your name in threads, the MCP status, where each kind of data lives (with Open buttons), Dev Mode and the Technical Log |

### Research: SketchUp's Outliner and Its Replacements (10-Nov-2026)

| Pitfall found | Source | What this does instead |
|---|---|---|
| Big models: refreshes on every selection change, 130k instances made it hang; Expand All froze at 16,000 rows | forums.sketchup.com/t/169103, /t/203253; api-issue-tracker #49 | Draws only the rows on screen; one reconcile per burst of changes; Expand stops at 5,000 rows and says so |
| Filter: names only; a stray space emptied the tree | /t/203117, /t/146002 | Field search, trimmed input, matches shown in place with parents, a count |
| No columns, little sorting (2027 adds Sort By Hierarchy or Tags) | help.sketchup.com, release notes 2027.0 | Sortable, resizable, movable, choosable columns |
| Selecting scrolls you away / does not follow | /t/156153, /t/238397 | Follow Selection is a setting; Reveal Selection on demand; expansion kept per model |
| Unnamed groups all read "Group"; instance and definition names confused; "#1" suffixes | /t/105617, /t/210686 | Separate Name and Definition columns, Copies, a note when an object sits inside a component placed several times |
| Hidden by itself, by tag, by parent look alike, too faint | /t/152464, /t/328065 | Italic with a struck eye; tag struck through; faded under a hidden parent; filled padlock for locked |
| Drag and drop drops into the wrong group, or into every copy | /t/35782 | No drag and drop reparenting in 0.1.0 (the MCP has entity_reparent) |
| Selecting several groups renamed them "Group" (Windows) | /t/247349 | Nothing is written as a side effect of selecting |
| API: observers miss edge moves, redo sends no events, removal passes only the entityID, onDeleteModel unreliable, removing definition observers crashed | api-issue-tracker #832, #1057, #95, #402, #665, #717, #960 | Callbacks are hints; fingerprints are the truth; an entityID index; full passes on undo, redo and agent operations; onCloseModel (2027); the DefinitionsObserver is never removed |
| Selection observers miss changes or go quiet | #603, #1116 | Every callback, both spellings, and a re-sync after every operation |
| Persistent ids change on grouping and (2023.1) a copied definition | ModelObserver#onPidChanged, #942 | onPidChanged forces a full pass |
| Large payloads to a dialog | /t/97655 | The snapshot goes in parts over 900,000 characters |

### Design Notes

- **WHERE DATA LIVES.** Flags and comments: the object's dictionary `Na__AgentOutliner__Notes` (the model's for its own thread), so they
  travel with the .skp; one named undo step per write; threads over 15,000 characters are chunked. Change history and what has been
  read: `91__UserConfig__LocalOnly/ModelHistory/<file stem>__<crc32 of the path>__.json`, beside the model on this PC, so tracking adds no
  undo steps and never marks a model modified; Save As carries the history to the new name (incremental saves keep the day's history);
  an untitled model is tracked in memory until its first save. Naming standards: `02__AppData/...NamingStandards__.json`, shared by git.
- **WHO DID IT.** The MCP bridge runs each request synchronously, and SketchUp calls observers inside the operation that caused them, so
  while an agent's request runs the MCP plugin's files are on the Ruby call stack (`caller_locations`). The stack is read once per
  operation (onTransactionStart, again at the commit) and reused for every event inside it. The first frame named
  `Na__Handlers__<Family>__<Action>` names the tool. Nothing in the MCP plugin had to change. Markers are config
  (`engine.agent_stack_markers`).
- **THE PASSES.** Observers only record and book one timer. A full pass (the first look, undo, redo, an agent's operation, Refresh, a
  pid change) compares every object's fingerprint (name, tag, material, hidden, locked, rounded transform, definition) and every placed
  definition's cheap signature (entity count and extents). Adam's own operations get a targeted pass: the objects the events named,
  the selection (a moved group may raise no event), dirty definitions, and the open group's precise signature (every edge and face,
  under 20,000 entities) for vertex moves that change no count. An agent's changes are always caught at their commit, so anything a
  later full pass finds unexplained is Adam's. If a full pass takes over 250 ms the model's agent operations switch to targeted passes.
- **THE TREE** is a graph of definitions (each object once, children by definition), walked from `ComponentDefinition#instances` and
  each instance's parent, never touching edges or faces; images and section planes come from one entity scan on full refreshes,
  capped at 600,000 entities.
- **RELOAD SAFE.** Every module variable is guarded; observers stay attached through Reload Plugin Data because their classes are
  reopened; the Noble 3D Tools reload calls `Na__AgentOutliner__AfterHostReload`.

### Provisional Choices (config values; change them freely)

1. **Seeded prefixes** beyond the four CAD elevations Adam named: `REF` (prefix mode, from his "see REF__SideElevation" on Brum) and
   `EDIT` (prefix mode, from EDIT__MASSING, with the meaning "use it for position and extent only", from the Brum correction "my mass was
   only a guide"). Delete or edit them in Configure.
2. **The CAD prefixes default to "Name it exactly"** (the object is named CAD__FrontElevation). Switch to "Put in front" to keep a drawing
   number after it.
3. **Six flag types** and their meanings; **colours** agent `#7c3aed`, Adam `#d97706`; **bands** 5, 30, 120, 1440 minutes.
4. **Hiding and locking do not count as changes** by default (Settings switches).
5. **History is kept 30 days, 4,000 changes per model.**

### Verified Offline

- `su_ruby.py syntax`: 17 of 17 Agent Outliner Ruby files, and 247 of 247 Noble 3D Tools files, compile on SketchUp's Ruby 3.2.2.
- `su_lint.py`: 0 errors, 0 warnings (the module, CoreAppData, CoreAppLogic).
- `node --check`: 8 of 8 scripts; all scripts are plain ASCII (the Write tool's raw characters re-escaped).
- Offline suite against purpose-built doubles (`tests/Na__AgentOutliner__Tests__Core__.rb.test` with `...Doubles__.rb.test`; run
  `python tests/Na__AgentOutliner__Tests__RunChecks__.py`, and `--mutate` for the fault run): **99 of 99**. Naming
  (replace, prefix, swap, placeholders, longest match, tags untouched, one undo step, images refused); notes (flags, waiting, the
  acknowledged flag not coming back, chunking, rollback of a half-failed write, copied notes, the model thread); tracking (a box Adam
  draws is his, one made through a fake MCP handler file is the agent's with the handler named, its contents too, Adam's rename of the
  agent's box, an agent's move of Adam's box, hiding not counted, an edge inside a group as contents, a ruby_eval change as the
  agent's, erase, undo, a comment not counted, history beside the model and not in it); the MCP seam (every read and edit action and
  nine refusals); the search language; snapshot shape; sizes under scale and rotation; selection paths (open the parent, close it, a
  stale path, a locked parent); settings coercion; standards validation and the aligned write.
- **Mutation run: 6 of 6 deliberate faults caught** (actor never agent; hiding counted; prefixes stacking; the flag waiting again; size
  without scale; reply not acknowledging), each in a short-path copy of the module.
- Browser preview (built-in browser, a local server and a stub bridge pushing a sample model): no console errors; tree, colour grading,
  badges, inspector thread, grouped view, search with context, the row menu, Copy for Agent, Configure and Settings all drawn and
  driven.
- Na SketchUp MCP 1.0.22: all five of its validators pass (see its DEVLOG).

### What Offline Cannot Prove (Check Live)

- Whether SketchUp fires `onElementModified` for a group moved with the Move tool (the targeted pass also re-checks the selection, so it
  should be caught either way), and whether entity events arrive inside the operation or at its commit (either works for who did it).
- The call-stack attribution against the real MCP bridge (proved only with a fake handler file of the same folder name).
- `Model#active_path=` from a dialog click, and selecting inside a locked group, on SketchUp 2027.
- The look in SketchUp's own Chromium (149) and the Windows clipboard path (navigator.clipboard, then execCommand, then clip.exe).
- Speed on a large model (the snapshot build time is shown in the status bar when over 1.5 s).

### Files

- `Na__Noble3dModellingTools__AgentOutliner__Loader__.rb`, this DEVLOG.
- `01__AppCore/`: `Main`, `DebugTools`, `DialogManager`, `ActionRouter`, `PluginReloader`.
- `02__AppData/`: `AppConfig__Defaults__.json`, `NamingStandards__.json`, `ConfigStore`.
- `03__ModelData/`: `Walker`, `Notes`, `Naming`, `EntityActions`.
- `04__ChangeTracking/`: `ActorDetect`, `HistoryStore`, `Tracker`, `Observers`.
- `05__UserInterface/`: `UiLayout__.html`; `Styles__Index/Shell/Outliner/Inspector/Configure__.css`; `UiSystem__BridgeBase/MainShell/
  OutlinerModel/OutlinerView/Inspector/AgentHandoff/Configure/Settings__.js`.
- `06__McpOperations/`: `McpOperations__Main__.rb` (the seam), `McpOperations__Payloads__.rb`.
- `tests/`: `Na__AgentOutliner__Tests__Core__.rb.test`, `...Doubles__.rb.test` (`.rb.test`, never `.rb`: the reloader would load the
  doubles into SketchUp), `...RunChecks__.py`.
- Noble 3D Tools registration: `ModuleLoaders__Main__.rb` (require), `PublicAPI__CommandRouter__.rb` (`open_agent_outliner`),
  `UiCommandRegistry__.json` (command, Entity Utils button, shortcut), `ReloadManager__.rb` (after-reload hook).

### Testing Notes

- [ ] Noble 3D Tools > Settings > Reload Plugin Data, close and reopen the Noble 3D Tools dialog, then Entity Utils > Agent Outliner.
      (The Extensions menu item and its shortcut appear after the next SketchUp restart: menus register once.)
- [ ] The tree shows your groups and components; sort by Tag, then by Changed; Shift+click Type adds a second sort; drag a column edge and
      a heading; right-click the headings to hide Size.
- [ ] Type `tag:06__Drawings -is:hidden` in the search; try Group by Tag and Group by Change.
- [ ] Select the front elevation CAD group and click CAD__FrontElevation in Quick Name: it is renamed, its TAG unchanged, one Ctrl+Z.
- [ ] Flag a group For Agent with a comment; ask an agent to read `agent_outliner inbox` and reply: the reply appears in the thread in
      violet, marked New, and the group is no longer Waiting.
- [ ] Ask the agent to make a box: NEW, AGENT, strong violet. Move a group yourself: UPDATED, ME, amber. Wait past 5 and 30 minutes and
      watch the tint fade.
- [ ] Click a nested row: its parent group opens and it is selected, as in SketchUp's Outliner. Select something in the model: the tree
      opens to it.
- [ ] Copy for Agent on two rows and paste into a chat.
- [ ] Settings > Reload Plugin Data: the dialog closes and reopens on its own, with the status "Reloaded N Ruby files".
- [ ] Check the moved, rotated, three-deep and scaled cases: Size shows each object's own size (scale included).

**Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027**
