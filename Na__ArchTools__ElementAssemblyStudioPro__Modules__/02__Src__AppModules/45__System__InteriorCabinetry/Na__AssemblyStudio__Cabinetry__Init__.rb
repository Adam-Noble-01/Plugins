# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM (ENTRY POINT)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__InteriorCabinetrySystem (+ Na__Init partial)
# AUTHOR     : Noble Architecture
# PURPOSE    : Entry point of the Interior Cabinetry tab: parametric UK kitchen
#              and fitted bedroom units (base, drawer, wall, tall, wardrobe)
#              in three door styles. Loads the sub-modules on first use and
#              registers the tab's selection handler and dialog callbacks.
# CREATED    : 29-Oct-2026
#
# MODULES (one responsibility each, loaded in dependency order)
# - Defaults           ACB ids, dictionary keys, UK default configuration
# - LayoutResolver     configuration -> every part's position and size (mm)
# - GeometryHelpers    boxes, oriented faces, prisms
# - AssetLibrary       leg and handle assets (unified asset contract)
# - AssetMeshBuilder   asset mesh -> ComponentDefinition (legs stretched)
# - CarcassBuilder     sides, base, rails / top, back, shelves, hanging rail
# - FrontBuilder       doors and drawer fronts: Flat, Shaker, Recessed
# - DrawerBoxBuilder   drawer boxes
# - PlinthLegsBuilder  plinth board and legs
# - HandleBuilder      handles
# - DataSerializer     ACB ids, saved configuration, component name
# - GeometryEngine     create / rebuild a cabinet component
# - DialogRouter       callbacks, Create at Cursor, Measure Run, Live Mode
# - Tools: 06__Tools__MeasurementTools RunMeasureTool,
#          07__Tools__PlacementTools CabinetPlacementTool
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__Cabinetry__Defaults__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Late-Bound Sub-Module Loading
# -----------------------------------------------------------------------------

    # FUNCTION | Load Every Sub-Module Once (First Dialog Open or Selection)
    # ------------------------------------------------------------
    def self.na_require_modules
        return if @na_modules_loaded

        require_relative 'Na__AssemblyStudio__Cabinetry__LayoutResolver__'
        require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'
        require_relative 'Na__AssemblyStudio__Cabinetry__AssetLibrary__'
        require_relative 'Na__AssemblyStudio__Cabinetry__AssetMeshBuilder__'
        require_relative 'Na__AssemblyStudio__Cabinetry__CarcassBuilder__'
        require_relative 'Na__AssemblyStudio__Cabinetry__FrontBuilder__'
        require_relative 'Na__AssemblyStudio__Cabinetry__DrawerBoxBuilder__'
        require_relative 'Na__AssemblyStudio__Cabinetry__PlinthLegsBuilder__'
        require_relative 'Na__AssemblyStudio__Cabinetry__HandleBuilder__'
        require_relative 'Na__AssemblyStudio__Cabinetry__DataSerializer__'
        require_relative 'Na__AssemblyStudio__Cabinetry__GeometryEngine__'
        require_relative 'Na__AssemblyStudio__Cabinetry__DialogRouter__'

        @na_modules_loaded = true
        DebugTools.na_debug_info("Interior Cabinetry modules loaded")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Reset the Load Gate and Caches After a Developer Reload
    # ------------------------------------------------------------
    # Kernel#load replaces method bodies but keeps module state, so the
    # gate and the parsed-asset / built-definition caches are dropped here.
    def self.na_reset_for_developer_reload
        @na_modules_loaded = false
        Na__AssetLibrary.na_clear_cache     if defined?(Na__AssetLibrary)
        Na__AssetMeshBuilder.na_clear_cache if defined?(Na__AssetMeshBuilder)
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
        Na__DialogRouter.na_init(dialog, Na__Defaults.na_default_config)
        true
    rescue StandardError => e
        DebugTools.na_debug_error("Interior Cabinetry callbacks failed to register", e)
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Cabinet Was Selected
    # ------------------------------------------------------------
    def self.na_load_into_dialog(instance, cabinet_id)
        na_require_modules
        Na__DialogRouter.na_load_into_dialog(instance, cabinet_id)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Selection Was Cleared
    # ------------------------------------------------------------
    def self.na_clear_from_dialog
        return unless @na_modules_loaded
        Na__DialogRouter.na_clear_from_dialog
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

            Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator.na_register_handler(na_handler_descriptor)
            Na__AssemblyStudio::Na__AppCore::Na__DialogManager.na_register_system_init_hook do |dialog|
                Na__AssemblyStudio::Na__InteriorCabinetrySystem.na_init_callbacks(dialog)
            end
        end

        def self.na_handler_descriptor
            {
                :tab_id      => 'cabinets',
                :resolve_id  => proc { |instance|
                    begin
                        Na__AssemblyStudio::Na__InteriorCabinetrySystem.na_require_modules
                        Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DataSerializer.na_get_id_from_instance(instance)
                    rescue StandardError
                        nil
                    end
                },
                :on_selected => proc { |instance, id|
                    Na__AssemblyStudio::Na__InteriorCabinetrySystem.na_load_into_dialog(instance, id)
                },
                :on_cleared  => proc {
                    Na__AssemblyStudio::Na__InteriorCabinetrySystem.na_clear_from_dialog
                }
            }
        end

    end

# endregion -------------------------------------------------------------------

end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
