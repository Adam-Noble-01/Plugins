# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Creates and rebuilds cabinet components: resolves the layout,
#              then calls each builder into the cabinet's own definition.
# CREATED    : 29-Oct-2026
#
# COMPONENT HIERARCHY
#   ACB001__BaseUnit__<name>          ComponentInstance, tag 27__ProposedBuilding__Fixtures
#     Na__Cabinet__Carcass            sides, base, rails / top, back, shelves, rail
#     Na__Cabinet__Fronts             doors and drawer fronts (Flat / Shaker / Recessed)
#     Na__Cabinet__DrawerBoxes        one group of five boards per drawer
#     Na__Cabinet__Plinth             full-width plinth board
#     Na__Cabinet__Legs               leg asset instances, stretched to the plinth
#     Na__Cabinet__Handles            handle asset instances
#
# COORDINATES
# - Everything inside the definition is built in its own frame (the unit
#   frame of Na__LayoutResolver: back-left corner at floor level, X along
#   the run, front facing -Y). The definition is a closed context, so no
#   active-context conversion applies.
# - The insertion transform comes from the caller already in world terms
#   (InputPoint positions, the run measurement) and is passed to
#   active_entities.add_instance as it is; inside an open group SketchUp reads
#   it as world (see the Coordinate Rule), so no edit_transform is applied.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative 'Na__AssemblyStudio__Cabinetry__Defaults__'
require_relative 'Na__AssemblyStudio__Cabinetry__LayoutResolver__'
require_relative 'Na__AssemblyStudio__Cabinetry__CarcassBuilder__'
require_relative 'Na__AssemblyStudio__Cabinetry__FrontBuilder__'
require_relative 'Na__AssemblyStudio__Cabinetry__DrawerBoxBuilder__'
require_relative 'Na__AssemblyStudio__Cabinetry__PlinthLegsBuilder__'
require_relative 'Na__AssemblyStudio__Cabinetry__HandleBuilder__'
require_relative 'Na__AssemblyStudio__Cabinetry__DataSerializer__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        TagManager        = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
        Defaults          = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__Defaults
        LayoutResolver    = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver
        CarcassBuilder    = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__CarcassBuilder
        FrontBuilder      = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__FrontBuilder
        DrawerBoxBuilder  = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DrawerBoxBuilder
        PlinthLegsBuilder = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__PlinthLegsBuilder
        HandleBuilder     = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__HandleBuilder
        DataSerializer    = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DataSerializer

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Create a Cabinet Component and Place One Instance
        # ------------------------------------------------------------
        # @param config     [Hash] Na__CabinetConfiguration block
        # @param cabinet_id [String] ACB id (already allocated)
        # @param transform  [Geom::Transformation] world placement of the
        #                   unit frame (back-left corner at floor level)
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_create_cabinet(config, cabinet_id, transform)
            model = Sketchup.active_model
            return nil unless model

            unit_type  = LayoutResolver.na_effective(config)[:type]
            definition = model.definitions.add(Defaults.na_name_head(cabinet_id, unit_type))
            na_build_into(definition.entities, config)

            instance = model.active_entities.add_instance(definition, transform)
            TagManager.na_apply_tag_to_entity(instance, :proposed_fixtures)
            DebugTools.na_debug_geometry("Created cabinet #{cabinet_id} (#{unit_type})")
            instance
        rescue StandardError => e
            DebugTools.na_debug_error("Cabinet create failed", e)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild an Existing Cabinet in Place
        # ------------------------------------------------------------
        # The instance keeps its position; only its definition is rebuilt.
        # @return [Boolean]
        def self.na_update_cabinet(instance, config)
            return false unless instance && instance.valid?
            definition = instance.definition
            definition.entities.clear!
            na_build_into(definition.entities, config)
            DebugTools.na_debug_geometry("Rebuilt cabinet definition #{definition.name}")
            true
        rescue StandardError => e
            DebugTools.na_debug_error("Cabinet rebuild failed", e)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cabinet Live Mode Should Rebuild
        # ------------------------------------------------------------
        # The selected cabinet first, else the one last created or loaded.
        def self.na_find_live_update_target(current_instance)
            model = Sketchup.active_model
            return nil unless model
            selected = model.selection.find do |entity|
                entity.is_a?(Sketchup::ComponentInstance) && DataSerializer.na_get_id_from_instance(entity)
            end
            return selected if selected
            (current_instance && current_instance.valid?) ? current_instance : nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Build Pipeline
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Every Part of One Cabinet Into Entities
        # ------------------------------------------------------------
        # @return [Hash] the resolved layout
        def self.na_build_into(entities, config)
            layout    = LayoutResolver.na_resolve(config)
            materials = na_resolve_materials(config)

            CarcassBuilder.na_build(layout, entities, materials)
            FrontBuilder.na_build(layout, entities, materials)
            DrawerBoxBuilder.na_build(layout, entities, materials)
            PlinthLegsBuilder.na_build_plinth(layout, entities, materials)
            PlinthLegsBuilder.na_build_legs(layout, entities, layout[:values][:leg_key], materials)
            HandleBuilder.na_build(layout, entities, layout[:values][:handle_key], materials)

            layout[:warnings].each { |warning| DebugTools.na_debug_warn("Cabinet layout: #{warning}") }
            layout
        end
        private_class_method :na_build_into
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Look Up Each Part's Material Through MaterialManager
        # ------------------------------------------------------------
        # nil means the SketchUp default material (MAT001__Default resolves
        # to nil on purpose in MaterialManager).
        def self.na_resolve_materials(config)
            door    = na_material(na_config_text(config, "DoorMaterialId",    Defaults::NA_DEFAULT_DOOR_MATERIAL_ID))
            carcass = na_material(na_config_text(config, "CarcassMaterialId", Defaults::NA_DEFAULT_CARCASS_MATERIAL_ID))
            {
                :door    => door,
                :carcass => carcass,
                :plinth  => (config["#{Defaults::NA_CONFIG_KEY_PREFIX}PlinthMatchesDoors"] == false) ? carcass : door,
                :handle  => na_material(na_config_text(config, "HandleMaterialId", Defaults::NA_DEFAULT_HANDLE_MATERIAL_ID)),
                :leg     => na_material(na_config_text(config, "LegMaterialId",    Defaults::NA_DEFAULT_LEG_MATERIAL_ID))
            }
        end
        private_class_method :na_resolve_materials
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Material by Id (Nil When Unavailable)
        # ------------------------------------------------------------
        def self.na_material(material_id)
            return nil unless defined?(Na__AssemblyStudio::Na__AppData::Na__MaterialManager)
            Na__AssemblyStudio::Na__AppData::Na__MaterialManager.na_get_material_by_id(material_id)
        rescue StandardError => e
            DebugTools.na_debug_warn("Cabinet material '#{material_id}' unavailable: #{e.message}")
            nil
        end
        private_class_method :na_material
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Text Setting, or Its Fallback When Blank
        # ------------------------------------------------------------
        def self.na_config_text(config, key, fallback)
            value = config["#{Defaults::NA_CONFIG_KEY_PREFIX}#{key}"].to_s.strip
            value.empty? ? fallback : value
        end
        private_class_method :na_config_text
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryEngine
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
