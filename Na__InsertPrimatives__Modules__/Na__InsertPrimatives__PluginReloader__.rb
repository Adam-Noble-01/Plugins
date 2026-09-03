# =============================================================================
# NA INSERT PRIMATIVES - PLUGIN RELOADER
# =============================================================================
#
# FILE       : Na__InsertPrimatives__PluginReloader__.rb
# NAMESPACE  : Na__InsertPrimatives::Na__PluginReloader
# AUTHOR     : Noble Architecture
# PURPOSE    : Hot reload every module file without restarting SketchUp
# CREATED    : 2026
#
# DESCRIPTION:
# - Mirrors the reload managers in Noble3d Modelling Tools and Profile Path
#   Tracer: load every Ruby file in the modules folder, count what worked, and
#   report what did not.
#
# DELIBERATELY SELF-CONTAINED:
# - This file requires nothing from the rest of the plugin and is loaded by the
#   loader on its own. A syntax error in any other module therefore leaves the
#   reloader intact, which is the one moment it is actually needed.
#
# LOAD ORDER:
# - Files are ordered by NA_RELOAD_PRIORITY, then anything unlisted alphabetically
#   after it, so a newly added module still reloads even if nobody remembers to
#   add it to the list.
# - Order matters less than it looks: reopening a class or module mutates the
#   object already in memory, so an earlier file holding a reference to a later
#   one still ends up with the fresh methods.
#
# WARNINGS ARE SILENCED:
# - $VERBOSE is nil-ed around each load. These modules define a lot of constants
#   and Ruby warns on every single redefinition, which would bury the real errors.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    module Na__PluginReloader

        # -----------------------------------------------------------------------------
        # REGION | Reload Order
        # -----------------------------------------------------------------------------

        NA_RELOAD_PRIORITY = [
            'Na__InsertPrimatives__UserInput__VcbFunctions__.rb',
            'Na__InsertPrimatives__DrawnGridSnap__.rb',
            'Na__InsertPrimatives__DrawnVcbArithmetic__.rb',
            'Na__InsertPrimatives__3dPreviewGraphics__.rb',
            'Na__InsertPrimatives__DrawnPreviewGraphics__.rb',
            'Na__InsertPrimatives__PlaneMode__.rb',
            'Na__InsertPrimatives__DrawnGeometry__.rb',
            'Na__InsertPrimatives__DrawnRoofGeometry__.rb',
            'Na__InsertPrimatives__RightClickPopup__.rb',
            'Na__InsertPrimatives__KeyboardHandlers__.rb',
            'Na__InsertPrimatives__DrawnToolShared__.rb',
            'Na__InsertPrimatives__DrawnPlaneTool__.rb',
            'Na__InsertPrimatives__DrawnVolumeTool__.rb',
            'Na__InsertPrimatives__DrawnCylinderTool__.rb',
            'Na__InsertPrimatives__DrawnDeepPick__.rb',
            'Na__InsertPrimatives__DrawnRoofTools__.rb',
            'Na__InsertPrimatives__DrawnPushPullTool__.rb',
            'Na__InsertPrimatives__Main__.rb'
        ].freeze

        NA_RELOAD_SKIP_FILES = [
            'Na__InsertPrimatives__PluginReloader__.rb',                      # <-- Never reload the thing doing the reloading
            'Na__InsertPrimatives__ContextMenu__.rb'                          # <-- Deprecated no-op shim, not required by anything
        ].freeze

        # Substrings that mark the active tool as belonging to this plugin, so a
        # reload can drop a stale tool without stealing an unrelated one.
        NA_RELOAD_TOOL_MARKERS = ['Primitive', 'Drawn', 'Roof'].freeze

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | File Discovery
        # -----------------------------------------------------------------------------

        # FUNCTION | Folder Holding the Plugin Modules
        # ------------------------------------------------------------
        def self.Na__Reload__ModulesRoot
            File.dirname(__FILE__)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Path to the Root Loader Script
        # ------------------------------------------------------------
        def self.Na__Reload__RootLoaderPath
            File.expand_path(
                File.join(
                    Na__InsertPrimatives::Na__PluginReloader.Na__Reload__ModulesRoot,
                    '..',
                    'Na__InsertPrimatives__Loader__.rb'
                )
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Submenu Entries Are Registered
        # ------------------------------------------------------------
        def self.Na__Reload__MenuEntryCount
            registry = $na_insert_primatives_menu
            return 0 unless registry.is_a?(Hash) && registry[:entries].is_a?(Hash)

            registry[:entries].length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Run the Loader to Pick Up New Menu Entries
        # A tool added since startup has no menu entry, and without one it cannot
        # be given a shortcut in Preferences. The loader's registration is keyed
        # and idempotent, so running it again adds only what is genuinely new.
        # Returns how many entries appeared.
        # ------------------------------------------------------------
        def self.Na__Reload__RootLoader(failures)
            path = Na__InsertPrimatives::Na__PluginReloader.Na__Reload__RootLoaderPath
            return 0 unless File.exist?(path)

            before           = Na__InsertPrimatives::Na__PluginReloader.Na__Reload__MenuEntryCount
            previous_verbose = $VERBOSE

            begin
                $VERBOSE = nil
                $na_insert_primatives_reloading = true                        # <-- Stops the loader re-requiring the modules
                load path
            rescue ScriptError, StandardError => error
                failures << "Loader — #{error.class}: #{error.message}"
                return 0
            ensure
                $na_insert_primatives_reloading = false
                $VERBOSE = previous_verbose
            end

            Na__InsertPrimatives::Na__PluginReloader.Na__Reload__MenuEntryCount - before
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Module File in Reload Order
        # ------------------------------------------------------------
        def self.Na__Reload__OrderedFiles
            pattern = File.join(Na__InsertPrimatives::Na__PluginReloader.Na__Reload__ModulesRoot, '*.rb')

            files = Dir.glob(pattern).reject do |path|
                NA_RELOAD_SKIP_FILES.include?(File.basename(path))
            end

            files.sort_by do |path|
                name  = File.basename(path)
                index = NA_RELOAD_PRIORITY.index(name)
                index.nil? ? [1, name] : [0, index]
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Reload
        # -----------------------------------------------------------------------------

        # FUNCTION | Drop a Stale Tool Belonging to This Plugin
        # A running tool holds a reference to the class object it was built from.
        # Reloading redefines that class underneath it, so the safe move is to put
        # the tool down first — but only if it is ours.
        # ------------------------------------------------------------
        def self.Na__Reload__ReleaseActiveTool
            model = Sketchup.active_model
            return false unless model

            active_name = model.tools.active_tool_name.to_s
            return false unless NA_RELOAD_TOOL_MARKERS.any? { |marker| active_name.include?(marker) }

            model.select_tool(nil)
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reload Every Module File
        # Returns a result hash so the caller can decide how loudly to report.
        # ------------------------------------------------------------
        def self.Na__Reload__PluginFiles
            files          = Na__InsertPrimatives::Na__PluginReloader.Na__Reload__OrderedFiles
            reload_count   = 0
            failures       = []
            tool_released  = Na__InsertPrimatives::Na__PluginReloader.Na__Reload__ReleaseActiveTool

            begin
                if defined?(Na__InsertPrimatives) &&
                   Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__CloseMenu)
                    Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()
                end
            rescue StandardError
                nil
            end

            files.each do |path|
                previous_verbose = $VERBOSE
                begin
                    $VERBOSE = nil                                            # <-- Constant redefinition warnings would bury real errors
                    load path
                    reload_count += 1
                rescue ScriptError, StandardError => error
                    failures << "#{File.basename(path)} — #{error.class}: #{error.message}"
                ensure
                    $VERBOSE = previous_verbose
                end
            end

            menu_added = Na__InsertPrimatives::Na__PluginReloader.Na__Reload__RootLoader(failures)

            {
                :success       => failures.empty?,
                :reload_count  => reload_count,
                :total_count   => files.length,
                :failures      => failures,
                :tool_released => tool_released,
                :menu_added    => menu_added
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reload and Report to the Console and Status Bar
        # Menu entry point. Quiet on success, loud on failure.
        # ------------------------------------------------------------
        def self.Na__Reload__RunFromMenu
            result = Na__InsertPrimatives::Na__PluginReloader.Na__Reload__PluginFiles

            puts "\n"
            puts '----------------------------------------'
            puts 'NA INSERT PRIMATIVES RELOADED'
            puts "Files : #{result[:reload_count]} of #{result[:total_count]} loaded"
            puts 'Tool  : active primitive tool released' if result[:tool_released]

            if result[:menu_added].to_i > 0
                puts "Menu  : #{result[:menu_added]} new entry/entries added — assignable in Preferences > Shortcuts now"
                puts '        (new entries append to the end of the submenu until the next restart)'
            end

            if result[:success]
                puts 'Status: OK'
            else
                puts "Status: #{result[:failures].length} FAILED"
                result[:failures].each { |failure| puts "  - #{failure}" }
            end
            puts '----------------------------------------'

            if result[:success]
                menu_note = result[:menu_added].to_i > 0 ? ", #{result[:menu_added]} new menu entries" : ''
                Sketchup::set_status_text("Na Insert Primatives reloaded — #{result[:reload_count]} files#{menu_note}", SB_PROMPT)
            else
                Sketchup::set_status_text("Na Insert Primatives reload FAILED — see Ruby Console", SB_PROMPT)
                UI.messagebox(
                    "Na Insert Primatives reload failed:\n\n" +
                    result[:failures].join("\n\n") +
                    "\n\nSee the Ruby Console for the full report."
                )
            end

            result
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End Na__PluginReloader module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF PLUGIN RELOADER MODULE
# =============================================================================
