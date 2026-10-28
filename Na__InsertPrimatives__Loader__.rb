# =============================================================================
# NA INSERT PRIMATIVES - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__Loader__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads the Na Insert Primatives plugin and registers UI
# CREATED    : 2026
#
# DESCRIPTION:
# - Loads the plugin once at SketchUp startup
# - Registers the Extensions submenu, including Reload Plugin Data
# - Tool commands / hotkeys only activate a tool. They never reload Ruby.
# - After editing modules, use Reload Plugin Data (or restart SketchUp).
#
# =============================================================================

require 'sketchup.rb'

# PATH SETUP | Define Paths
# ------------------------------------------------------------
plugin_root   = File.dirname(__FILE__)                                      # <-- Plugins folder
plugin_folder = File.join(plugin_root, 'Na__InsertPrimatives__Modules__')    # <-- Modules subfolder
app_core_dir  = File.join(plugin_folder, '01__AppCore')
main_file     = File.join(app_core_dir, 'Na__InsertPrimatives__AppCore__Main__.rb')
reloader_file = File.join(app_core_dir, 'Na__InsertPrimatives__AppCore__PluginReloader__.rb')
# ---------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Loader Helpers
# -----------------------------------------------------------------------------

    # FUNCTION | Forget Loaded Feature Path
    # ------------------------------------------------------------
    def Na__InsertPrimatives__ForgetLoadedFeature(file_path)
        target_path = File.expand_path(file_path).tr('\\', '/').downcase

        $LOADED_FEATURES.delete_if do |loaded_feature|
            File.expand_path(loaded_feature).tr('\\', '/').downcase == target_path
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Plugin Runtime Is Already in Memory
    # ------------------------------------------------------------
    def Na__InsertPrimatives__PluginReady?
        defined?(Na__InsertPrimatives) &&
            Na__InsertPrimatives.const_defined?(:DrawnPushPullTool, false) &&
            Na__InsertPrimatives.const_defined?(:DrawnChamferTool, false) &&
            Na__InsertPrimatives.respond_to?(:Na__InsertPrimatives__DeepPushPull)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Activate a Public Tool Entry, or Point at Reload Plugin Data
    # ------------------------------------------------------------
    # Shortcuts must stay cheap. If startup failed, recovery is the Reload
    # Plugin Data menu — the reloader is loaded on its own so it still exists.
    # ------------------------------------------------------------
    def Na__InsertPrimatives__RunTool(entry_name)
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(entry_name)
            UI.messagebox(
                "Na Insert Primatives is not loaded.\n\n" \
                "Use Extensions > Na__InsertPrimitives > Reload Plugin Data, " \
                "or restart SketchUp."
            )
            return
        end

        Na__InsertPrimatives.public_send(entry_name)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Run a Deep Scale Switch From Its Shortcut Command
    # ------------------------------------------------------------
    # The same guard as RunTool. The switch itself starts Deep Scale when it
    # is not already running (Na__Scale__Hotkey).
    # ------------------------------------------------------------
    def Na__InsertPrimatives__RunScaleHotkey(action)
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__Scale__Hotkey)
            UI.messagebox(
                "Na Insert Primatives is not loaded.\n\n" \
                "Use Extensions > Na__InsertPrimitives > Reload Plugin Data, " \
                "or restart SketchUp."
            )
            return
        end

        Na__InsertPrimatives.Na__Scale__Hotkey(action)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Tick a Deep Scale Switch's Menu Entry When It Is On
    # ------------------------------------------------------------
    def Na__InsertPrimatives__ScaleHotkeyState(action)
        return MF_GRAYED unless defined?(Na__InsertPrimatives) &&
                                Na__InsertPrimatives.respond_to?(:Na__Scale__HotkeyChecked?)

        Na__InsertPrimatives.Na__Scale__HotkeyChecked?(action) ? MF_CHECKED : MF_UNCHECKED
    rescue StandardError
        MF_UNCHECKED
    end
    # ---------------------------------------------------------------


    # FUNCTION | Write Loader Diagnostics Only When AppConfig Dev Mode Is On
    # ------------------------------------------------------------
    def Na__InsertPrimatives__DebugPuts(*args)
        return unless defined?(Na__InsertPrimatives) &&
                      Na__InsertPrimatives.respond_to?(:Na__Config__DevMode?) &&
                      Na__InsertPrimatives.Na__Config__DevMode?

        puts(*args)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Load Main Primitive Tool Script (Startup Only)
    # ------------------------------------------------------------
    def Na__InsertPrimatives__LoadMainScript(main_file)
        return true if Na__InsertPrimatives__PluginReady?

        unless File.exist?(main_file)
            puts "✗ Na Insert Primatives main file not found at: #{main_file}"
            return false
        end

        previous_verbose = $VERBOSE
        begin
            $VERBOSE = nil

            app_core_dir   = File.dirname(main_file)
            modules_root   = File.expand_path('..', app_core_dir)
            manifest_file  = File.join(app_core_dir, 'Na__InsertPrimatives__AppCore__LoadManifest__.rb')

            load manifest_file if File.exist?(manifest_file)

            runtime_paths = if defined?(Na__InsertPrimatives) &&
                               Na__InsertPrimatives.respond_to?(:Na__LoadManifest__RuntimeAbsolutePaths)
                Na__InsertPrimatives.Na__LoadManifest__RuntimeAbsolutePaths(modules_root)
            else
                [File.expand_path(main_file).tr('\\', '/')]
            end

            runtime_paths.each do |file_path|
                Na__InsertPrimatives__ForgetLoadedFeature(file_path)
            end

            require main_file
            Na__InsertPrimatives__DebugPuts('✓ Na Insert Primatives loaded successfully')
            true
        rescue => e
            puts "✗ Error loading Na Insert Primatives: #{e.message}"
            puts e.backtrace.join("\n")
            false
        ensure
            $VERBOSE = previous_verbose
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Idempotent Menu Registration
# -----------------------------------------------------------------------------

# The registry lives in a global on purpose: it has to survive this file being
# re-loaded by the reloader, which a constant on the plugin module would not.
#
# WHY NOT THE USUAL file_loaded? GUARD:
# - Wrapping the menu block in `unless file_loaded?(__FILE__)` means it only ever
#   runs at SketchUp startup, so a tool added afterwards never reaches the menu
#   and never becomes shortcut-assignable until the next restart. Keying every
#   entry instead lets a reload add exactly what is new and nothing that already
#   exists — SketchUp cannot remove a menu item once added, so blind re-running
#   would stack duplicates.
#
# ORDERING CAVEAT:
# - An entry registered by a reload appends to the end of the submenu, because
#   the API has no insert-at-position. It lands in its designed place on the next
#   restart. Available immediately beats perfectly ordered.
$na_insert_primatives_menu ||= { :submenu => nil, :entries => {} }

    # FUNCTION | Fetch or Create the Plugin Submenu
    # ------------------------------------------------------------
    def Na__InsertPrimatives__PluginSubmenu
        existing = $na_insert_primatives_menu[:submenu]
        return existing if existing

        submenu = UI.menu('Extensions').add_submenu('Na__InsertPrimitives')
        $na_insert_primatives_menu[:submenu] = submenu
        submenu
    end
    # ---------------------------------------------------------------


    # FUNCTION | Add a Menu Entry Once and Only Once
    # ------------------------------------------------------------
    def Na__InsertPrimatives__AddMenuEntry(key)
        return false if $na_insert_primatives_menu[:entries][key]

        yield Na__InsertPrimatives__PluginSubmenu()
        $na_insert_primatives_menu[:entries][key] = true
        true
    rescue => menu_error
        puts "✗ Na Insert Primatives menu entry '#{key}' failed: #{menu_error.message}"
        false
    end
    # ---------------------------------------------------------------


    # FUNCTION | Fetch or Create a Submenu Inside the Plugin Submenu
    # ------------------------------------------------------------
    # Kept in the same global registry as the entries, for the same reason:
    # a reload must find the submenu it made, not add a second one.
    # ------------------------------------------------------------
    def Na__InsertPrimatives__NestedSubmenu(key, title)
        $na_insert_primatives_menu[:submenus] ||= {}
        existing = $na_insert_primatives_menu[:submenus][key]
        return existing if existing

        submenu = Na__InsertPrimatives__PluginSubmenu().add_submenu(title)
        $na_insert_primatives_menu[:submenus][key] = submenu
        submenu
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# SCRIPT LOADING | Load the Reloader First, On Its Own
# ------------------------------------------------------------
# The reloader depends on nothing else in the plugin and is loaded separately
# from the main script on purpose: if a module ever fails to parse, the Reload
# Plugin Data menu item is exactly what is needed to recover, so it must survive
# a broken load rather than going down with it.
# ------------------------------------------------------------
# Skipped during a reload: the reloader is the code currently running, and
# redefining it from inside itself is a reentrancy knot with nothing to gain.
unless $na_insert_primatives_reloading
    begin
        load reloader_file
    rescue => reloader_error
        puts "✗ Na Insert Primatives reloader failed to load: #{reloader_error.message}"
    end
end
# ---------------------------------------------------------------


# SCRIPT LOADING | Load the main plugin file
# ------------------------------------------------------------
# Skipped when the reloader is the one loading this file: it has just reloaded
# every module itself, so re-requiring them here would double the work and print
# any load error twice.
# ------------------------------------------------------------
Na__InsertPrimatives__LoadMainScript(main_file) unless $na_insert_primatives_reloading
# ---------------------------------------------------------------


# MENU REGISTRATION | Commands and Submenu Entries
# ------------------------------------------------------------
# Deliberately NOT wrapped in a file_loaded? guard — see the registry region
# above. Building the command objects again on a reload is cheap, and only the
# entries missing from the submenu are actually added.
# ------------------------------------------------------------
begin

    # COMMAND SETUP | Create UI Command
    # ------------------------------------------------------------
    cmd = UI::Command.new('NA_InsertPrimitiveCube') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__InsertCube)
    }
    cmd.tooltip         = "Insert Primitive Cube"                           # <-- Tooltip text
    cmd.status_bar_text = "Activate primitive cube placement tool"          # <-- Status bar text
    cmd.menu_text       = "Insert Cube"                                     # <-- Menu display text (inside the submenu)
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Plane Tool (Click and Drag Rectangle)
    # ------------------------------------------------------------
    drawn_plane_cmd = UI::Command.new('NA_DrawPlanePrimitive') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawPlane)
    }
    drawn_plane_cmd.tooltip         = "Draw Plane Primitive"
    drawn_plane_cmd.status_bar_text = "Click and drag a grid-snapped rectangle primitive"
    drawn_plane_cmd.menu_text       = "Drawn Plane"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Volume Tool (Click and Drag Box)
    # ------------------------------------------------------------
    drawn_volume_cmd = UI::Command.new('NA_DrawVolumePrimitive') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawVolume)
    }
    drawn_volume_cmd.tooltip         = "Draw Volume Primitive"
    drawn_volume_cmd.status_bar_text = "Click and drag a grid-snapped box primitive"
    drawn_volume_cmd.menu_text       = "Drawn Volume"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Cylinder Tool (Click and Drag Cylinder)
    # ------------------------------------------------------------
    drawn_cylinder_cmd = UI::Command.new('NA_DrawCylinderPrimitive') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawCylinder)
    }
    drawn_cylinder_cmd.tooltip         = "Draw Cylinder Primitive"
    drawn_cylinder_cmd.status_bar_text = "Click and drag a cylinder primitive centred on the grid"
    drawn_cylinder_cmd.menu_text       = "Drawn Cylinder"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Staircase Tool (Block, Side, Then the Flight)
    # ------------------------------------------------------------
    stair_cmd = UI::Command.new('NA_DrawStaircasePrimitive') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawStair)
    }
    stair_cmd.tooltip         = "Draw Staircase Primitive"
    stair_cmd.status_bar_text = "Drag a block, pick the side it rises from, then drag the flight in: even steps, Part K checked"
    stair_cmd.menu_text       = "Staircase"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Pipework Tool (Along Selected Edges, or Drawn Point by Point)
    # ------------------------------------------------------------
    pipe_cmd = UI::Command.new('NA_DrawPipework') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawPipe)
    }
    pipe_cmd.tooltip         = "Pipework"
    pipe_cmd.status_bar_text = "Pipe along the selected edges, or draw a run point by point: diameter, bend radius, sides (80,110,24s)"
    pipe_cmd.menu_text       = "Pipework"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Pipework Path — Edit and Finish, So Each Can Take a Shortcut
    # ------------------------------------------------------------
    pipe_edit_cmd = UI::Command.new('NA_PipeworkEditPath') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__EditPipePath)
    }
    pipe_edit_cmd.tooltip         = "Edit Pipework Path"
    pipe_edit_cmd.status_bar_text = "Re-route the selected pipe: its path comes out as a red line to edit with any tool"
    pipe_edit_cmd.menu_text       = "Edit Pipework Path"

    pipe_finish_cmd = UI::Command.new('NA_PipeworkFinishPath') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__FinishPipePath)
    }
    pipe_finish_cmd.tooltip         = "Finish Pipework Path"
    pipe_finish_cmd.status_bar_text = "Rebuild the pipe along its red line now"
    pipe_finish_cmd.menu_text       = "Finish Pipework Path"

    # COMMAND SETUP | Pipework Bar on Selection — Ticked While It Is On
    # ------------------------------------------------------------
    pipe_bar_cmd = UI::Command.new('NA_PipeworkBarOnSelection') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__TogglePipeAutoBar)
    }
    pipe_bar_cmd.tooltip         = "Pipework Bar on Selection"
    pipe_bar_cmd.status_bar_text = "Show the Pipework bar, top left, whenever pipes are selected with the Select tool"
    pipe_bar_cmd.menu_text       = "Pipework Bar on Selection"
    pipe_bar_cmd.set_validation_proc {
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__AutoBarOn?)
            next MF_GRAYED
        end

        Na__InsertPrimatives.Na__DrawnPipe__AutoBarOn? ? MF_CHECKED : MF_UNCHECKED
    }
    # ---------------------------------------------------------------

    # COMMAND SETUP | Pitched Roof Tool (Click and Drag Gable Roof)
    # ------------------------------------------------------------
    pitched_roof_cmd = UI::Command.new('NA_DrawPitchedRoofPrimitive') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawPitchedRoof)
    }
    pitched_roof_cmd.tooltip         = "Draw Pitched Roof Primitive"
    pitched_roof_cmd.status_bar_text = "Drag a plan footprint then pull up the ridge, or type a pitch"
    pitched_roof_cmd.menu_text       = "Pitched Roof"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Hipped Roof Tool (Click and Drag Hip Roof)
    # ------------------------------------------------------------
    hipped_roof_cmd = UI::Command.new('NA_DrawHippedRoofPrimitive') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DrawHippedRoof)
    }
    hipped_roof_cmd.tooltip         = "Draw Hipped Roof Primitive"
    hipped_roof_cmd.status_bar_text = "Drag a plan footprint then pull up the ridge, or type a pitch"
    hipped_roof_cmd.menu_text       = "Hipped Roof"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Push/Pull Tool
    # ------------------------------------------------------------
    push_pull_cmd = UI::Command.new('NA_DeepPushPull') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepPushPull)
    }
    push_pull_cmd.tooltip         = "Deep Push/Pull"
    push_pull_cmd.status_bar_text = "Push or pull any face at any nesting depth, on the voxel grid"
    # No slash in the menu text: SketchUp builds the shortcut path with "/" as
    # the separator, so "Deep Push / Pull" would read as two extra path levels in
    # Preferences -> Shortcuts.
    push_pull_cmd.menu_text       = "Deep Push Pull"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Push/Pull Joint Surfaces — Ticked While It Is On
    # ------------------------------------------------------------
    # The tool's SHIFT+TAB, as a command, so it can take a key of its own in
    # Preferences -> Shortcuts.
    # ------------------------------------------------------------
    push_joint_cmd = UI::Command.new('NA_DeepPushPullJointSurfaces') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__TogglePushPullJoint)
    }
    push_joint_cmd.tooltip         = "Deep Push Pull Joint Surfaces"
    push_joint_cmd.status_bar_text = "A face on a smoothed surface pushes the whole surface as one; off, one face at a time"
    push_joint_cmd.menu_text       = "Deep Push Pull Joint Surfaces"
    push_joint_cmd.set_validation_proc {
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__PushPull__JointOn?)
            next MF_GRAYED
        end

        Na__InsertPrimatives.Na__PushPull__JointOn? ? MF_CHECKED : MF_UNCHECKED
    }
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Project Tool (Carry a Face On to a Target)
    # ------------------------------------------------------------
    project_cmd = UI::Command.new('NA_DeepProject') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepProject)
    }
    project_cmd.tooltip         = "Deep Project"
    project_cmd.status_bar_text = "Carry any face, at any nesting depth, on to the plane of another face, a point or an object"
    project_cmd.menu_text       = "Deep Project"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Chamfer Tool
    # ------------------------------------------------------------
    chamfer_cmd = UI::Command.new('NA_DeepChamfer') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepChamfer)
    }
    chamfer_cmd.tooltip         = "Deep Chamfer"
    chamfer_cmd.status_bar_text = "Chamfer any edge at any nesting depth, on the voxel grid"
    chamfer_cmd.menu_text       = "Deep Chamfer"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Fillet Tool
    # ------------------------------------------------------------
    fillet_cmd = UI::Command.new('NA_DeepFillet') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepFillet)
    }
    fillet_cmd.tooltip         = "Deep Fillet"
    fillet_cmd.status_bar_text = "Round any edge to a true radius, at any nesting depth"
    fillet_cmd.menu_text       = "Deep Fillet"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Ogee Tool
    # ------------------------------------------------------------
    ogee_cmd = UI::Command.new('NA_DeepOgee') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepOgee)
    }
    ogee_cmd.tooltip         = "Deep Ogee"
    ogee_cmd.status_bar_text = "Run a classical ogee moulding along any edge, at any nesting depth"
    ogee_cmd.menu_text       = "Deep Ogee"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Ovolo Tool (Ovolo or Cavetto, With a Step)
    # ------------------------------------------------------------
    ovolo_cmd = UI::Command.new('NA_DeepOvolo') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepOvolo)
    }
    ovolo_cmd.tooltip         = "Deep Ovolo"
    ovolo_cmd.status_bar_text = "Run an ovolo or a cavetto (a quarter circle with a step) along any edge, at any nesting depth"
    ovolo_cmd.menu_text       = "Deep Ovolo"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Scale Tool (Grips, Typed Dimensions, Stretch Planes)
    # ------------------------------------------------------------
    scale_cmd = UI::Command.new('NA_DeepScale') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepScale)
    }
    scale_cmd.tooltip         = "Deep Scale"
    scale_cmd.status_bar_text = "Scale any group or component by its grips, type its size, or stretch it between cut planes"
    scale_cmd.menu_text       = "Deep Scale"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Vertex Move Tool (Box-Pick Vertices, Move With a Gimbal)
    # ------------------------------------------------------------
    # The selection when it starts is the scope: only the vertices inside those
    # groups, components or loose faces can be picked and moved.
    # ------------------------------------------------------------
    vertex_move_cmd = UI::Command.new('NA_DeepVertexMove') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__DeepVertexMove)
    }
    vertex_move_cmd.tooltip         = "Deep Vertex Move"
    vertex_move_cmd.status_bar_text = "Box-pick vertices at any depth inside the selection and move or stretch them with a gimbal, on the grid"
    vertex_move_cmd.menu_text       = "Deep Vertex Move"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Scale Options — One Command per Switch, for Shortcuts
    # ------------------------------------------------------------
    # Every switch the handle bar and the right-click menu carry, as a command
    # of its own, so each can be given a key in Preferences > Shortcuts under
    # Extensions/Na__InsertPrimitives/Deep Scale Options. Pressed with Deep
    # Scale not running, a command starts it. Single letters are left to
    # SketchUp (5.2.6): its own shortcuts take them before a tool can. The
    # ids are each shortcut's permanent identity: never rename one.
    # ------------------------------------------------------------
    scale_option_specs = [
        ['NA_DeepScale_HandlesAll',     :handles_all,     'Handles All',          'Show every scale grip'],
        ['NA_DeepScale_HandlesFaces',   :handles_faces,   'Handles Faces',        'Show the face grips only, one axis each'],
        ['NA_DeepScale_HandlesCorners', :handles_corners, 'Handles Corners',      'Show the corner grips only, a uniform scale'],
        ['NA_DeepScale_HandlesX',       :handles_x,       'Handles X Only',       'Show only the two grips that pull X (RIGHT ARROW for a moment)'],
        ['NA_DeepScale_HandlesY',       :handles_y,       'Handles Y Only',       'Show only the two grips that pull Y (LEFT ARROW for a moment)'],
        ['NA_DeepScale_HandlesZ',       :handles_z,       'Handles Z Only',       'Show only the two grips that pull Z (UP ARROW for a moment)'],
        ['NA_DeepScale_HandlesNext',    :handles_next,    'Next Handle Set',      'Step to the next handle set: All, Faces, Corners, X, Y, Z'],
        ['NA_DeepScale_StretchPlanes',  :planes,          'Stretch Planes',       'Stretch Planes on or off (SHIFT+TAB while scaling)'],
        ['NA_DeepScale_AboutCentre',    :centre,          'About Centre',         'Scale about the centre on or off (TAB)'],
        ['NA_DeepScale_Dimensions',     :dims,            'Dimensions',           'Show Dimensions on or off'],
        ['NA_DeepScale_ClearPlanes',    :clear_planes,    'Clear Stretch Planes', 'Remove every stretch plane saved with the object being scaled']
    ]

    scale_option_cmds = scale_option_specs.map do |id, action, text, status|
        command = UI::Command.new(id) { Na__InsertPrimatives__RunScaleHotkey(action) }
        command.tooltip         = "Deep Scale: #{text}"
        command.status_bar_text = status
        command.menu_text       = text
        unless [:handles_next, :clear_planes].include?(action)
            command.set_validation_proc { Na__InsertPrimatives__ScaleHotkeyState(action) }     # <-- Ticks the handle set in force and the switches that are on
        end
        [id, command]
    end
    # ---------------------------------------------------------------

    # COMMAND SETUP | Hot Reload All Plugin Modules
    # ------------------------------------------------------------
    reload_cmd = UI::Command.new('NA_InsertPrimitivesReloadPluginData') {
        if defined?(Na__InsertPrimatives::Na__PluginReloader)
            Na__InsertPrimatives::Na__PluginReloader.Na__Reload__RunFromMenu # <-- Reload every module in place
        else
            UI.messagebox('Na Insert Primatives reloader is not loaded — restart SketchUp.')
        end
    }
    reload_cmd.tooltip         = "Hot reload Na Insert Primatives"
    reload_cmd.status_bar_text = "Reload every module from disk. Tool shortcuts never reload on their own."
    reload_cmd.menu_text       = "Reload Plugin Data"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Reset the Right-Click Menu's Remembered Position
    # ------------------------------------------------------------
    # The anchored popup opens where it was last left. Unplug the monitor it
    # was left on and it opens nowhere you can click — so the way back to the
    # cursor has to live somewhere that is not the popup itself.
    # ------------------------------------------------------------
    reset_menu_cmd = UI::Command.new('NA_InsertPrimitivesResetMenuPosition') {
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__ResetPlacement)
            UI.messagebox(
                "Na Insert Primatives is not loaded.\n\n" \
                "Use Reload Plugin Data, or restart SketchUp."
            )
            next
        end

        Na__InsertPrimatives.Na__RightClickPopup__ResetPlacement
    }
    reset_menu_cmd.tooltip         = "Reset Menu Position"
    reset_menu_cmd.status_bar_text = "Forget where the right-click primitive menu was left; it opens at the cursor next time"
    reset_menu_cmd.menu_text       = "Reset Menu Position"
    # ---------------------------------------------------------------

    # COMMAND SETUP | AltGr Never Orbits or Pans — Ticked While It Is On (Windows)
    # ------------------------------------------------------------
    # SketchUp 2027 orbits on Ctrl+Alt and pans on Shift+Ctrl+Alt as the cursor
    # moves, and Windows reports AltGr as Ctrl+Alt. Drawn Plane and Drawn
    # Volume already keep AltGr from navigating a 2D view; this keeps it from
    # navigating anywhere in SketchUp. AltGr shortcuts still fire. See
    # Camera__AltGrFilter__.
    # ------------------------------------------------------------
    altgr_cmd = UI::Command.new('NA_AltGrNeverNavigates') {
        Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__ToggleAltGrFilter)
    }
    altgr_cmd.tooltip         = "AltGr Never Orbits or Pans"
    altgr_cmd.status_bar_text = "Keep AltGr (Ctrl+Alt to Windows) from starting SketchUp 2027's touchpad orbit and pan, in every tool; AltGr shortcuts still work"
    altgr_cmd.menu_text       = "AltGr Never Orbits or Pans"
    altgr_cmd.set_validation_proc {
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__AltGrFilter__Everywhere?) &&
               defined?(Na__InsertPrimatives::NA_ALTGR_FILTER_WINDOWS) &&
               Na__InsertPrimatives::NA_ALTGR_FILTER_WINDOWS
            next MF_GRAYED
        end

        Na__InsertPrimatives.Na__AltGrFilter__Everywhere? ? MF_CHECKED : MF_UNCHECKED
    }
    # ---------------------------------------------------------------

    # COMMAND SETUP | Toggle AppConfig Dev Mode
    # ------------------------------------------------------------
    # Writes Na__DevMode__Enabled in AppConfig JSON. Checkmark follows the file.
    # The command block calls module methods, so Reload Plugin Data keeps it live
    # without replacing this menu item.
    # ------------------------------------------------------------
    dev_mode_cmd = UI::Command.new('NA_InsertPrimitivesToggleDevMode') {
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__Config__ToggleDevMode)
            UI.messagebox(
                "Na Insert Primatives is not loaded.\n\n" \
                "Use Reload Plugin Data, or restart SketchUp."
            )
            next
        end

        Na__InsertPrimatives.Na__Config__ToggleDevMode
    }
    dev_mode_cmd.tooltip         = "Enable Dev Mode"
    dev_mode_cmd.status_bar_text = "Write diagnostic console output on or off to AppConfig"
    dev_mode_cmd.menu_text       = "Enable Dev Mode"
    dev_mode_cmd.set_validation_proc {
        unless defined?(Na__InsertPrimatives) &&
               Na__InsertPrimatives.respond_to?(:Na__Config__DevMode?)
            next MF_GRAYED
        end

        Na__InsertPrimatives.Na__Config__DevMode? ? MF_CHECKED : MF_UNCHECKED
    }
    # ---------------------------------------------------------------

    # MENU INTEGRATION | Single Submenu Under Extensions
    # ------------------------------------------------------------
    # Every entry is keyed so this block is safe to run again. Each key is the
    # permanent identity of that entry — never rename one, or a reload will add a
    # duplicate alongside the original.
    #
    # NOTE ON SHORTCUTS: SketchUp keys shortcuts to the menu path, so an entry
    # only becomes assignable in Preferences -> Shortcuts once it is in the menu.
    # ------------------------------------------------------------
    Na__InsertPrimatives__AddMenuEntry('insert_cube')     { |m| m.add_item(cmd) }
    Na__InsertPrimatives__AddMenuEntry('sep_after_place') { |m| m.add_separator }

    Na__InsertPrimatives__AddMenuEntry('drawn_plane')     { |m| m.add_item(drawn_plane_cmd) }
    Na__InsertPrimatives__AddMenuEntry('drawn_volume')    { |m| m.add_item(drawn_volume_cmd) }
    Na__InsertPrimatives__AddMenuEntry('drawn_cylinder')  { |m| m.add_item(drawn_cylinder_cmd) }
    Na__InsertPrimatives__AddMenuEntry('sep_after_draw')  { |m| m.add_separator }

    Na__InsertPrimatives__AddMenuEntry('pitched_roof')    { |m| m.add_item(pitched_roof_cmd) }
    Na__InsertPrimatives__AddMenuEntry('hipped_roof')     { |m| m.add_item(hipped_roof_cmd) }
    Na__InsertPrimatives__AddMenuEntry('staircase')       { |m| m.add_item(stair_cmd) }
    Na__InsertPrimatives__AddMenuEntry('pipework')        { |m| m.add_item(pipe_cmd) }
    Na__InsertPrimatives__AddMenuEntry('pipework_edit_path')   { |m| m.add_item(pipe_edit_cmd) }
    Na__InsertPrimatives__AddMenuEntry('pipework_finish_path') { |m| m.add_item(pipe_finish_cmd) }
    Na__InsertPrimatives__AddMenuEntry('pipework_bar_on_selection') { |m| m.add_item(pipe_bar_cmd) }
    Na__InsertPrimatives__AddMenuEntry('sep_after_roof')  { |m| m.add_separator }

    Na__InsertPrimatives__AddMenuEntry('push_pull')       { |m| m.add_item(push_pull_cmd) }
    Na__InsertPrimatives__AddMenuEntry('push_pull_joint') { |m| m.add_item(push_joint_cmd) }
    Na__InsertPrimatives__AddMenuEntry('project')         { |m| m.add_item(project_cmd) }
    Na__InsertPrimatives__AddMenuEntry('scale')           { |m| m.add_item(scale_cmd) }

    scale_option_cmds.each do |id, command|
        if id == 'NA_DeepScale_StretchPlanes'
            Na__InsertPrimatives__AddMenuEntry('scale_options_sep') do |_m|
                Na__InsertPrimatives__NestedSubmenu('scale_options', 'Deep Scale Options').add_separator
            end
        end

        Na__InsertPrimatives__AddMenuEntry("scale_option_#{id}") do |_m|
            Na__InsertPrimatives__NestedSubmenu('scale_options', 'Deep Scale Options').add_item(command)
        end
    end

    Na__InsertPrimatives__AddMenuEntry('vertex_move')     { |m| m.add_item(vertex_move_cmd) }

    Na__InsertPrimatives__AddMenuEntry('chamfer')         { |m| m.add_item(chamfer_cmd) }
    Na__InsertPrimatives__AddMenuEntry('fillet')          { |m| m.add_item(fillet_cmd) }
    Na__InsertPrimatives__AddMenuEntry('ogee')            { |m| m.add_item(ogee_cmd) }
    Na__InsertPrimatives__AddMenuEntry('ovolo')           { |m| m.add_item(ovolo_cmd) }
    Na__InsertPrimatives__AddMenuEntry('sep_after_mod')   { |m| m.add_separator }

    Na__InsertPrimatives__AddMenuEntry('reload')              { |m| m.add_item(reload_cmd) }
    Na__InsertPrimatives__AddMenuEntry('reset_menu_position') { |m| m.add_item(reset_menu_cmd) }
    Na__InsertPrimatives__AddMenuEntry('altgr_never_navigates') { |m| m.add_item(altgr_cmd) }
    Na__InsertPrimatives__AddMenuEntry('sep_after_reload')    { |m| m.add_separator }
    Na__InsertPrimatives__AddMenuEntry('dev_mode')            { |m| m.add_item(dev_mode_cmd) }
    # ---------------------------------------------------------------

    # MENU INTEGRATION | Branded Launcher Beside the Submenu
    # ------------------------------------------------------------
    # SketchUp gives a submenu no icon, so the NA mark rides on a command of its
    # own in the Extensions menu, straight after the submenu: the pattern Na Point
    # Cloud Viewer uses. It starts the tool on Insert Cube; a right-click then
    # opens the Primitive Menu. Keyed in the same registry, so a reload never adds
    # a second.
    # ------------------------------------------------------------
    unless $na_insert_primatives_menu[:entries]['brand_launcher']
        brand_icon = File.join(__dir__, 'Na__InsertPrimatives__Modules__', '40__UserInterface',
                               'UiIcons__MenuIcons__PrimitiveMenu', 'Na__InsertPrimatives__Brand__CustomToolbarIcon__.svg')
        launch_cmd = UI::Command.new('Na Insert Primitives') {
            Na__InsertPrimatives__RunTool(:Na__InsertPrimatives__InsertCube)
        }
        launch_cmd.tooltip         = "Na Insert Primitives"
        launch_cmd.status_bar_text = "Start Insert Primitives (right-click for the Primitive Menu)"
        launch_cmd.menu_text       = "Na Insert Primitives"
        if File.exist?(brand_icon)
            launch_cmd.small_icon = brand_icon
            launch_cmd.large_icon = brand_icon
        end
        UI.menu('Extensions').add_item(launch_cmd)
        $na_insert_primatives_menu[:entries]['brand_launcher'] = true
    end
    # ---------------------------------------------------------------

rescue => loader_menu_error
    puts "✗ Na Insert Primatives menu registration failed: #{loader_menu_error.message}"
end

file_loaded(__FILE__) unless file_loaded?(__FILE__)                         # <-- Convention only; no longer gates the menu

# =============================================================================
# END OF LOADER
# =============================================================================
