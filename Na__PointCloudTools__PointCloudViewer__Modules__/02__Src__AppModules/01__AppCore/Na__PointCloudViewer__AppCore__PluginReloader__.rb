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

            self.na_end_our_tool
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

        # A clip box, Move or Rotate tool made by the code being replaced holds
        # what that code held (before v0.10.0, the session rather than the
        # cloud's slot): it is finished before the files load again.
        def self.na_end_our_tool
            model = Sketchup.active_model
            tool = model && model.respond_to?(:tools) ? model.tools.active_tool : nil
            return unless tool
            return unless tool.class.name.to_s.start_with?('Na__PointCloudViewer::')
            model.select_tool(nil)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The point cloud tool could not be finished before the reload: #{error.message}")
        end

        # The native engine is a Fiddle-loaded DLL copy, so unlike a Ruby C
        # extension it CAN be swapped: when a newer build is on disk, or when the
        # reloaded code expects another ABI than the engine running. Clouds
        # re-upload on their next draw. A build the code cannot use is refused
        # and the engine running is kept when it can still serve (Bridge).
        def self.na_reload_native
            status = Na__NativeEngine.Na__Native__Status
            return 'Native engine: not loaded yet.' unless status['isLoaded']
            before = Na__NativeEngine.Na__Native__Generation
            loaded = Na__NativeEngine.Na__Native__EnsureLoaded
            return "Native engine swap failed: #{Na__NativeEngine.Na__Native__Status['error']}" unless loaded
            return 'Native engine: new build swapped in. Reload the point clouds (View tab, Reload All).' if Na__NativeEngine.Na__Native__Generation != before
            status['isStale'] ? "Native engine: kept. #{Na__NativeEngine.Na__Native__Status['error']}" : 'Native engine: unchanged.'
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
