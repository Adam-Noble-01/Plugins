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
# - Loads the main tool from the Na__InsertPrimatives__Modules__ subfolder
# - Creates menu item in the Plugins menu
#
# =============================================================================

require 'sketchup.rb'

# PATH SETUP | Define Paths
# ------------------------------------------------------------
plugin_root   = File.dirname(__FILE__)                                      # <-- Plugins folder
plugin_folder = File.join(plugin_root, 'Na__InsertPrimatives__Modules__')    # <-- Modules subfolder
main_file     = File.join(plugin_folder, 'Na__InsertPrimatives__Main__.rb')  # <-- Main script
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


    # FUNCTION | Load Main Primitive Tool Script
    # ------------------------------------------------------------
    def Na__InsertPrimatives__LoadMainScript(main_file)
        if File.exist?(main_file)
            begin
                module_folder = File.dirname(main_file)
                module_files = [
                    'Na__InsertPrimatives__UserInput__VcbFunctions__.rb',
                    'Na__InsertPrimatives__3dPreviewGraphics__.rb',
                    'Na__InsertPrimatives__PlaneMode__.rb',
                    'Na__InsertPrimatives__RightClickPopup__.rb',
                    'Na__InsertPrimatives__KeyboardHandlers__.rb',
                    'Na__InsertPrimatives__DrawnGridSnap__.rb',
                    'Na__InsertPrimatives__DrawnVcbArithmetic__.rb',
                    'Na__InsertPrimatives__DrawnPreviewGraphics__.rb',
                    'Na__InsertPrimatives__DrawnGeometry__.rb',
                    'Na__InsertPrimatives__DrawnToolShared__.rb',
                    'Na__InsertPrimatives__DrawnPlaneTool__.rb',
                    'Na__InsertPrimatives__DrawnVolumeTool__.rb',
                    'Na__InsertPrimatives__DrawnRoofGeometry__.rb',
                    'Na__InsertPrimatives__DrawnCylinderTool__.rb',
                    'Na__InsertPrimatives__DrawnDeepPick__.rb',
                    'Na__InsertPrimatives__DrawnSlopePush__.rb',
                    'Na__InsertPrimatives__DrawnRoofTools__.rb',
                    'Na__InsertPrimatives__DrawnPushPullTool__.rb',
                    'Na__InsertPrimatives__DrawnEdgeLoops__.rb',
                    'Na__InsertPrimatives__DrawnPushPull2dTool__.rb',
                    'Na__InsertPrimatives__DrawnChamferTool__.rb',
                    'Na__InsertPrimatives__Main__.rb'
                ]

                module_files.each do |file_name|
                    Na__InsertPrimatives__ForgetLoadedFeature(File.join(module_folder, file_name))
                end

                require main_file
                puts "✓ Na Insert Primatives loaded successfully"
                true
            rescue => e
                puts "✗ Error loading Na Insert Primatives: #{e.message}"
                puts e.backtrace.join("\n")
                false
            end
        else
            puts "✗ Na Insert Primatives main file not found at: #{main_file}"
            false
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
        load File.join(plugin_folder, 'Na__InsertPrimatives__PluginReloader__.rb')
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
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__InsertCube               # <-- Activate the placement tool
    }
    cmd.tooltip         = "Insert Primitive Cube"                           # <-- Tooltip text
    cmd.status_bar_text = "Activate primitive cube placement tool"          # <-- Status bar text
    cmd.menu_text       = "Insert Cube"                                     # <-- Menu display text (inside the submenu)
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Plane Tool (Click and Drag Rectangle)
    # ------------------------------------------------------------
    drawn_plane_cmd = UI::Command.new('NA_DrawPlanePrimitive') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DrawPlane                 # <-- Activate the drag rectangle tool
    }
    drawn_plane_cmd.tooltip         = "Draw Plane Primitive"
    drawn_plane_cmd.status_bar_text = "Click and drag a grid-snapped rectangle primitive"
    drawn_plane_cmd.menu_text       = "Drawn Plane"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Volume Tool (Click and Drag Box)
    # ------------------------------------------------------------
    drawn_volume_cmd = UI::Command.new('NA_DrawVolumePrimitive') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DrawVolume                # <-- Activate the drag box tool
    }
    drawn_volume_cmd.tooltip         = "Draw Volume Primitive"
    drawn_volume_cmd.status_bar_text = "Click and drag a grid-snapped box primitive"
    drawn_volume_cmd.menu_text       = "Drawn Volume"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Drawn Cylinder Tool (Click and Drag Cylinder)
    # ------------------------------------------------------------
    drawn_cylinder_cmd = UI::Command.new('NA_DrawCylinderPrimitive') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DrawCylinder              # <-- Activate the drag cylinder tool
    }
    drawn_cylinder_cmd.tooltip         = "Draw Cylinder Primitive"
    drawn_cylinder_cmd.status_bar_text = "Click and drag a cylinder primitive centred on the grid"
    drawn_cylinder_cmd.menu_text       = "Drawn Cylinder"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Pitched Roof Tool (Click and Drag Gable Roof)
    # ------------------------------------------------------------
    pitched_roof_cmd = UI::Command.new('NA_DrawPitchedRoofPrimitive') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DrawPitchedRoof           # <-- Activate the gable roof tool
    }
    pitched_roof_cmd.tooltip         = "Draw Pitched Roof Primitive"
    pitched_roof_cmd.status_bar_text = "Drag a plan footprint then pull up the ridge, or type a pitch"
    pitched_roof_cmd.menu_text       = "Pitched Roof"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Hipped Roof Tool (Click and Drag Hip Roof)
    # ------------------------------------------------------------
    hipped_roof_cmd = UI::Command.new('NA_DrawHippedRoofPrimitive') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DrawHippedRoof            # <-- Activate the hip roof tool
    }
    hipped_roof_cmd.tooltip         = "Draw Hipped Roof Primitive"
    hipped_roof_cmd.status_bar_text = "Drag a plan footprint then pull up the ridge, or type a pitch"
    hipped_roof_cmd.menu_text       = "Hipped Roof"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Push/Pull Tool
    # ------------------------------------------------------------
    push_pull_cmd = UI::Command.new('NA_DeepPushPull') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DeepPushPull              # <-- Activate the deep push/pull tool
    }
    push_pull_cmd.tooltip         = "Deep Push/Pull"
    push_pull_cmd.status_bar_text = "Push or pull any face at any nesting depth, on the voxel grid"
    # No slash in the menu text: SketchUp builds the shortcut path with "/" as
    # the separator, so "Deep Push / Pull" would read as two extra path levels in
    # Preferences -> Shortcuts.
    push_pull_cmd.menu_text       = "Deep Push Pull"
    # ---------------------------------------------------------------

    # COMMAND SETUP | Deep Chamfer Tool
    # ------------------------------------------------------------
    chamfer_cmd = UI::Command.new('NA_DeepChamfer') {
        Na__InsertPrimatives__LoadMainScript(main_file)
        Na__InsertPrimatives.Na__InsertPrimatives__DeepChamfer               # <-- Activate the deep chamfer tool
    }
    chamfer_cmd.tooltip         = "Deep Chamfer"
    chamfer_cmd.status_bar_text = "Chamfer any edge at any nesting depth, on the voxel grid"
    chamfer_cmd.menu_text       = "Deep Chamfer"
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
    reload_cmd.tooltip         = "Reload Na Insert Primatives"
    reload_cmd.status_bar_text = "Hot reload every Na Insert Primatives module without restarting"
    reload_cmd.menu_text       = "Reload Plugin Data"
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
    Na__InsertPrimatives__AddMenuEntry('sep_after_roof')  { |m| m.add_separator }

    Na__InsertPrimatives__AddMenuEntry('push_pull')       { |m| m.add_item(push_pull_cmd) }
    Na__InsertPrimatives__AddMenuEntry('chamfer')         { |m| m.add_item(chamfer_cmd) }
    Na__InsertPrimatives__AddMenuEntry('sep_after_mod')   { |m| m.add_separator }

    Na__InsertPrimatives__AddMenuEntry('reload')          { |m| m.add_item(reload_cmd) }
    # ---------------------------------------------------------------

rescue => loader_menu_error
    puts "✗ Na Insert Primatives menu registration failed: #{loader_menu_error.message}"
end

file_loaded(__FILE__) unless file_loaded?(__FILE__)                         # <-- Convention only; no longer gates the menu

# =============================================================================
# END OF LOADER
# =============================================================================
