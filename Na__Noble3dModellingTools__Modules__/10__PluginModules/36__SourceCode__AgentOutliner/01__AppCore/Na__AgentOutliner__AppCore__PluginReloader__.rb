# =============================================================================
# NA AGENT OUTLINER - APP CORE - PLUGIN RELOADER (HOT RELOAD)
# =============================================================================
#
# FILE       : Na__AgentOutliner__AppCore__PluginReloader__.rb
# NAMESPACE  : Na__AgentOutliner::Na__PluginReloader
# MODULE     : Na__PluginReloader (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Reload Plugin Data for this tool alone (Settings tab): write
#              the change history, re-`load` every Ruby file under
#              36__SourceCode__AgentOutliner, drop the cached config, and let
#              the DialogManager close and reopen the page so its HTML, CSS
#              and JS reload too
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - OBSERVERS STAY ATTACHED: Kernel#load reopens their classes, so the ones
#   already watching each model run the new code at once, and the tracker's
#   live maps survive (their module variables are guarded).
# - WHAT A RELOAD CANNOT DO (Kernel#load): it never deletes a method or a
#   constant a file no longer defines, and a new menu item appears only after
#   a SketchUp restart. Renamed or deleted files need a restart.
# - Each file loads in its own rescue (ScriptError too, so a syntax error in
#   one file is reported by name and the rest still load).
# - "already initialized constant" warnings are silenced for the reload only:
#   they would bury a real error in the Ruby Console.
#
# =============================================================================

module Na__AgentOutliner
    module Na__PluginReloader

# -----------------------------------------------------------------------------
# REGION | Public Surface
# -----------------------------------------------------------------------------

        # FUNCTION | Reload Every Ruby File of the Agent Outliner
        # ------------------------------------------------------------
        def self.Na__Reload__Run
            Na__AgentOutliner::Na__Tracker.Na__Tracker__SaveAll if defined?(Na__AgentOutliner::Na__Tracker)

            rb_files = Dir.glob(File.join(Na__AgentOutliner::NA_MODULE_ROOT.tr('\\', '/'), '**', '*.rb')).sort
            issues   = []
            loaded   = 0
            previous_verbose = $VERBOSE
            begin
                $VERBOSE = nil
                rb_files.each do |rb_file|
                    begin
                        load rb_file
                        loaded += 1
                    rescue ScriptError, StandardError => error
                        issues << "#{File.basename(rb_file)}: #{error.class}: #{error.message}"
                    end
                end
            ensure
                $VERBOSE = previous_verbose
            end

            Na__AgentOutliner::Na__ConfigStore.Na__Config__ClearCache
            issues.each { |issue| Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("Reload issue: #{issue}") }
            {
                'isSuccess'     => issues.empty?,
                'rubyFileCount' => loaded,
                'issues'        => issues,
                'statusMessage' => if issues.empty?
                                       "Reloaded #{loaded} Ruby files plus HTML, CSS and JS (Agent Outliner #{Na__AgentOutliner.Na__AgentOutliner__Version})."
                                   else
                                       "Reloaded #{loaded} of #{rb_files.length} Ruby files; #{issues.length} failed. First: #{issues.first}"
                                   end
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PluginReloader
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
