# =============================================================================
# NA PAINTERLYNPR ASSETS - APP CORE - PLUGIN RELOADER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppCore__PluginReloader__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__PluginReloader
# PURPOSE    : Reload Plugin Data: re-`load`s every Ruby file under
#              02__Src__AppModules and drops every cached reading (config, user
#              config, register, catalogue). The DialogManager then closes and
#              reopens the page so HTML, CSS and JS reload too.
# CREATED    : 30-Oct-2026
#
# WHAT A RELOAD CANNOT DO (Kernel#load):
#   It never deletes a method, constant or menu item that a file no longer
#   defines; a new menu item appears only after a SketchUp restart.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__PluginReloader

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Reload__Run
            if Na__BuildUtil.Na__BuildUtil__Busy?
                return { 'isSuccess' => false, 'isBlocked' => true,
                         'statusMessage' => "Reload skipped: PainterlyNPR's build utility is still running. Try again in a moment." }
            end

            rb_files = Dir.glob(File.join(Na__PainterlyAssets::NA_SRC_ROOT, '**', '*.rb')).sort
            issues   = []
            loaded   = 0

            previous_verbose = $VERBOSE
            $VERBOSE = nil                                                                            # <-- "already initialized constant" warnings would bury real errors
            rb_files.each do |rb_file|
                begin
                    load rb_file
                    loaded += 1
                rescue ScriptError, StandardError => error
                    issues << "#{File.basename(rb_file)}: #{error.class}: #{error.message}"
                end
            end
            $VERBOSE = previous_verbose

            Na__ConfigLoader.Na__Config__ClearCache
            Na__UserConfigStore.Na__UserConfig__ClearCache
            Na__Register.Na__Register__ClearCache
            Na__Catalogue.Na__Catalogue__Scan

            issues.each { |issue| Na__DebugTools.Na__Debug__Warn("Reload issue: #{issue}") }
            {
                'isSuccess'     => issues.empty?,
                'isBlocked'     => false,
                'rubyFileCount' => loaded,
                'issues'        => issues,
                'statusMessage' => issues.empty? ?
                    "Reloaded #{loaded} Ruby files plus HTML, CSS and JS (version #{Na__PainterlyAssets.Na__PublicApi__Version})." :
                    "Reloaded #{loaded} of #{rb_files.length} Ruby files; #{issues.length} failed. First: #{issues.first}"
            }
        ensure
            $VERBOSE = previous_verbose if defined?(previous_verbose) && !previous_verbose.nil?
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
