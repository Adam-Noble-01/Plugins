# =============================================================================
# NA ARRAY BUILDER TOOLS - PLUGIN RELOADER
# FILE       : Na__ArrayBuilder__PluginReloader__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Reload modules and dialog while retaining the current draft.
# =============================================================================

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PluginReloader

        NA_MODULE_ORDER = %w[
            Configuration AssetResolver ObjectRegistry ObjectPicker Distribution
            PathFromSelection LayoutEngine DataSerializer CornerMerger GeometryBuilder
            PreviewGeometry PreviewRenderMixin AxisLockMixin PathInference PathTool SelectionArrayTool
            PresetsLibrary DialogManager ModelObservers Main PluginReloader
        ].freeze

        # FUNCTION | Compile All Modules Before Closing the Working Interface
        # ------------------------------------------------------------
        def self.Na__Reload__Schedule(na_snapshot)
            return if @na_pending
            na_files = NA_MODULE_ORDER.map { |na_name| File.join(__dir__, "Na__ArrayBuilder__#{na_name}__.rb") }
            na_files.each { |na_file| RubyVM::InstructionSequence.compile_file(na_file) }
            @na_pending = true
            UI.start_timer(0.05, false) { Na__Reload__Run(na_files, na_snapshot) }
        rescue SyntaxError => na_error
            raise ArgumentError, "Reload stopped before closing the dialog: #{na_error.message}"
        end

        def self.Na__Reload__Run(na_files, na_snapshot)
            na_verbose = $VERBOSE
            Na__ArrayBuilder__DialogManager.Na__Dialog__StopTool()
            Na__ArrayBuilder__ModelObservers.Na__Observers__Detach()
            Na__ArrayBuilder__DialogManager.na_get_dialog.close
            $VERBOSE = nil
            na_files.each { |na_file| load na_file }
            Na__ArrayBuilder__ModelObservers.Na__Observers__InstallOnce()
            Na__ArrayBuilderTools.na_init
            Na__ArrayBuilder__DialogManager.Na__Dialog__RestoreReload(na_snapshot)
        rescue StandardError, ScriptError => na_error
            # A runtime error remains visible even if the former dialog is closed.
            UI.messagebox("Array Builder could not finish reloading:\n#{na_error.message}")
        ensure
            $VERBOSE = na_verbose
            @na_pending = false
        end

    end # module Na__ArrayBuilder__PluginReloader
end # module Na__ArrayBuilderTools
