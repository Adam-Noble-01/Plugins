# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - PLUGIN RELOADER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__PluginReloader__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__PluginReloader
# PURPOSE    : Developer hot reload - re-`load`s every Ruby file, drops cached
#              JSON, re-checks the overlay registry. The DialogManager then
#              closes and reopens the dialog so HTML, CSS and JS reload too.
#
# NATIVE ENGINE:
#   Loaded with Fiddle from a shadow copy, so a rebuilt DLL is swapped in by a
#   reload (no SketchUp restart). A Ruby C extension could not be unloaded.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__PluginReloader

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Reload__Run
            if Na__AsyncJobs.Na__Jobs__Busy?
                return { 'isSuccess' => false, 'isBlocked' => true,
                         'statusMessage' => 'Reload skipped: a task is still running. Cancel it or wait for it to finish.' }
            end

            rb_files = Dir.glob(File.join(Na__PointCloudViewer::NA_SRC_ROOT, '**', '*.rb')).sort
            issues   = []
            loaded   = 0

            previous_verbose = $VERBOSE
            $VERBOSE = nil
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
            Na__ModelRegistry.Na__Registry__InstallOnce
            native_note = self.na_reload_native
            Sketchup.active_model.active_view.invalidate if Sketchup.active_model

            issues.each { |issue| Na__DebugTools.Na__Debug__Warn("Reload issue: #{issue}") }
            {
                'isSuccess'     => issues.empty?,
                'isBlocked'     => false,
                'rubyFileCount' => loaded,
                'issues'        => issues,
                'statusMessage' => issues.empty? ?
                    "Reloaded #{loaded} Ruby files plus HTML, CSS and JS. #{native_note}" :
                    "Reloaded #{loaded} of #{rb_files.length} Ruby files; #{issues.length} failed. First: #{issues.first}"
            }
        ensure
            $VERBOSE = previous_verbose if defined?(previous_verbose) && !previous_verbose.nil?
        end

        # The native engine is a Fiddle-loaded DLL copy, so unlike a Ruby C
        # extension it CAN be swapped: only if it was loaded and a newer build
        # is on disk. Clouds re-upload on their next draw.
        def self.na_reload_native
            status = Na__NativeEngine.Na__Native__Status
            return 'Native engine: not loaded yet.' unless status['isLoaded']
            return 'Native engine: unchanged.' unless status['isStale']
            Na__NativeEngine.Na__Native__EnsureLoaded ? 'Native engine: new build swapped in.' : "Native engine swap failed: #{Na__NativeEngine.Na__Native__Status['error']}"
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
