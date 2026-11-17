# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM (ENTRY POINT)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__AssemblyRunSystem (+ Na__Init partial)
# AUTHOR     : Noble Architecture
# PURPOSE    : Entry point of the Assembly Run Studio tab: runs of the
#              elements the other tabs make, set out along a path. A
#              conservatory's framework, a row of door sets between columns,
#              an L-shaped kitchen, a wall of wardrobes. Loads the sub-modules
#              on first use and registers the tab's selection handler, its
#              selection listener and its dialog callbacks.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# MODULES (one responsibility each, loaded in dependency order)
# - Defaults           ARN ids, dictionary keys, modes, column and corner kinds
# - PathMath           the path's plan geometry (pure)
# - LayoutResolver     configuration -> every span, column, post and corner (pure)
# - RunEdits           make unique, recode, change type, new path (pure)
# - DataSerializer     ARN ids, the run's saved data, span membership
# - ColumnLibrary      the library columns and their height variants
# - ColumnBuilder      posts, infill blocks, library columns, corner blocks
# - CornerUnitBuilder  the L-shaped corner cabinet
# - PanelTypes         one element per panel type, through its own pipeline
# - GeometryEngine     fills a run's definition from its layout
# - RunPipelines       create / rebuild / edit: the dialog's and the agents'
# - PathEditor         Edit Path in SketchUp (the red line)
# - DialogRouter       the tab's callbacks, selection load, member banner
# - Tools: 06__Tools__MeasurementTools RunPathMeasureTool
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Late-Bound Sub-Module Loading
# -----------------------------------------------------------------------------

    # FUNCTION | Load Every Sub-Module Once (First Dialog Open, Selection or Agent Call)
    # ------------------------------------------------------------
    def self.na_require_modules
        return if @na_modules_loaded

        require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__RunCills__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__LayoutResolver__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__RunEdits__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__DataSerializer__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnLibrary__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnBuilder__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__CornerUnitBuilder__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__FrameworkBuilder__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__PanelTypes__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__GeometryEngine__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__RunPipelines__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__MemberSync__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__PathEditor__'
        require_relative 'Na__AssemblyStudio__AssemblyRun__DialogRouter__'

        @na_modules_loaded = true
        DebugTools.na_debug_info("Assembly Run modules loaded")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Reset the Load Gate After a Developer Reload
    # ------------------------------------------------------------
    # Kernel#load replaces method bodies but keeps module state.
    def self.na_reset_for_developer_reload
        @na_modules_loaded = false
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Dialog and Selection
# -----------------------------------------------------------------------------

    # FUNCTION | Register the Tab's Callbacks on the Shared Dialog
    # ------------------------------------------------------------
    def self.na_init_callbacks(dialog)
        return false unless dialog
        na_require_modules
        Na__DialogRouter.na_init(dialog)
        true
    rescue StandardError, LoadError => e
        DebugTools.na_debug_error("Assembly Run callbacks failed to register", e)
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Run Was Selected
    # ------------------------------------------------------------
    def self.na_load_into_dialog(instance, run_id)
        na_require_modules
        Na__DialogRouter.na_load_into_dialog(instance, run_id)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Selection Was Cleared
    # ------------------------------------------------------------
    def self.na_clear_from_dialog
        return unless @na_modules_loaded
        Na__DialogRouter.na_clear_from_dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Any Selection Change (the "Editing Panel Type A" Banner)
    # ------------------------------------------------------------
    def self.na_selection_changed(selection)
        na_require_modules
        Na__DialogRouter.na_selection_changed(selection)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Any Build Pipeline Committed (Is the Selected Panel Off Its Run's Sizes)
    # ------------------------------------------------------------
    # Nothing to do until the run system has been used this session: a
    # panel can only be selected as one once its banner has been shown.
    def self.na_element_committed
        return unless @na_modules_loaded
        Na__MemberSync.na_schedule_for_selection
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | EASP Per-System Init Partial (Called by AppCore::Main)
# -----------------------------------------------------------------------------

    module Na__Init

        def self.na_init
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__SelectionCoordinator__'
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__OperationScope__'

            coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator
            coordinator.na_register_handler(na_handler_descriptor)
            coordinator.na_register_listener(:assembly_run) do |selection|
                Na__AssemblyStudio::Na__AssemblyRunSystem.na_selection_changed(selection)
            end
            Na__AssemblyStudio::Na__AppCore::Na__DialogManager.na_register_system_init_hook do |dialog|
                Na__AssemblyStudio::Na__AssemblyRunSystem.na_init_callbacks(dialog)
            end
            Na__AssemblyStudio::Na__AppCore::Na__OperationScope.na_on_commit(:assembly_run) do
                Na__AssemblyStudio::Na__AssemblyRunSystem.na_element_committed
            end
        end

        def self.na_handler_descriptor
            {
                :tab_id      => 'runs',
                :resolve_id  => proc { |instance|
                    begin
                        Na__AssemblyStudio::Na__AssemblyRunSystem.na_require_modules
                        Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer.na_get_id_from_instance(instance)
                    rescue StandardError
                        nil
                    end
                },
                :on_selected => proc { |instance, id|
                    Na__AssemblyStudio::Na__AssemblyRunSystem.na_load_into_dialog(instance, id)
                },
                :on_cleared  => proc {
                    Na__AssemblyStudio::Na__AssemblyRunSystem.na_clear_from_dialog
                }
            }
        end

    end

# endregion -------------------------------------------------------------------

end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
