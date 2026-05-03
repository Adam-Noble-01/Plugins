# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Orchestrates door creation and update workflows.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - High-level orchestration mirroring Na__AssemblyStudio::Na__WindowSystem::Na__GeometryEngine.
# - Public surface:
#     * na_create_door(config, door_id, insertion_origin_in)
#     * na_update_door(instance, config)
#     * na_find_live_update_target(current_instance)
# - Build pipeline:
#     1. Generate / accept ADR door ID.
#     2. Create ComponentDefinition "<DoorID>__InteriorDoor__".
#     3. Build static parts at definition root: lining (+ optional fuse),
#        front/back architraves, and the single 2D swing arc (shared by
#        the closed and open ADR copies, never duplicated/rotated).
#     4. Compose the closed-state ADR / MOD / ROT assembly inside the
#        definition (panel + handles only).
#     5. Optionally duplicate + rotate to produce the open-state ADR copy.
#     6. Add a single ComponentInstance at the model root; place it at
#        insertion_origin_in (Point A from the measure tool) when supplied,
#        otherwise IDENTITY (caller is expected to engage placement tool).
#     7. Caller runs the DataSerializer save afterwards.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__ArchitraveBuilder__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__FuseLiningParts__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__DoorAssemblyComposer__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__DataSerializer__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools          = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers     = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        GeometryBuilders    = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryBuilders
        ArchitraveBuilder   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__ArchitraveBuilder
        HandleBuilder3D     = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D
        FuseLiningParts     = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__FuseLiningParts
        DoorAssemblyComposer= Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DoorAssemblyComposer
        DataSerializer      = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DataSerializer
        TagManager          = Na__AssemblyStudio::Na__AppUtils::Na__TagManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Create
# -----------------------------------------------------------------------------

        # FUNCTION | Create the Interior Door Geometry
        # ------------------------------------------------------------
        # @param config [Hash] Na__DoorConfiguration block
        # @param door_id [String, nil] Optional pre-generated ADR ID
        # @param insertion_origin_in [Geom::Point3d, nil] Insertion point in inches (Point A)
        # @return [Sketchup::ComponentInstance, nil] The created instance, or nil on failure
        def self.na_create_door(config, door_id = nil, insertion_origin_in = nil)
            DebugTools.na_debug_method("GeometryEngine.na_create_door")
            model    = Sketchup.active_model
            return nil unless model

            door_id ||= DataSerializer.na_generate_next_door_id

            begin
                materials             = na_resolve_materials(config)
                definition_name       = "#{door_id}__InteriorDoor__"
                door_def              = model.definitions.add(definition_name)
                door_entities         = door_def.entities

                lining_result         = GeometryBuilders.na_build_lining(config, door_entities, materials[:lining])

                if config["Na__DoorConfig__FuseLining"] != false
                    FuseLiningParts.na_fuse_lining_parts(lining_result[:container])
                end

                ArchitraveBuilder.na_build_architraves(config, door_entities, materials[:architrave])

                GeometryBuilders.na_build_swing(config, door_entities)

                closed_assembly       = DoorAssemblyComposer.na_compose_closed_assembly(
                    config, door_entities, materials[:panel], materials[:handle]
                )

                if config["Na__DoorConfig__CreateOpenStateCopy"] != false
                    DoorAssemblyComposer.na_compose_open_state_copy(config, closed_assembly, door_entities)
                end

                tag_proposed_doors     = TagManager.na_get_or_create_tag(:proposed_doors)
                instance_transform     = na_resolve_insertion_transform(insertion_origin_in)
                instance               = model.active_entities.add_instance(door_def, instance_transform)
                instance.name          = definition_name
                instance.layer         = tag_proposed_doors if tag_proposed_doors

                DebugTools.na_debug_geometry("Created door definition: #{definition_name}")
                instance
            rescue => e
                DebugTools.na_debug_error("Error creating door geometry", e)
                nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Update
# -----------------------------------------------------------------------------

        # FUNCTION | Update an Existing Door's Geometry
        # ------------------------------------------------------------
        # Clears the door's component definition entities and rebuilds
        # them from the supplied configuration. The instance position
        # in the model is preserved.
        #
        # @param instance [Sketchup::ComponentInstance] Existing door instance
        # @param config [Hash] Updated Na__DoorConfiguration block
        # @return [Boolean] True on success
        def self.na_update_door(instance, config)
            DebugTools.na_debug_method("GeometryEngine.na_update_door")
            return false unless instance && instance.valid?

            definition = instance.definition
            return false unless definition

            begin
                definition.entities.clear!

                materials             = na_resolve_materials(config)
                lining_result         = GeometryBuilders.na_build_lining(config, definition.entities, materials[:lining])

                if config["Na__DoorConfig__FuseLining"] != false
                    FuseLiningParts.na_fuse_lining_parts(lining_result[:container])
                end

                ArchitraveBuilder.na_build_architraves(config, definition.entities, materials[:architrave])

                GeometryBuilders.na_build_swing(config, definition.entities)

                closed_assembly       = DoorAssemblyComposer.na_compose_closed_assembly(
                    config, definition.entities, materials[:panel], materials[:handle]
                )

                if config["Na__DoorConfig__CreateOpenStateCopy"] != false
                    DoorAssemblyComposer.na_compose_open_state_copy(config, closed_assembly, definition.entities)
                end

                DebugTools.na_debug_geometry("Updated door definition: #{definition.name}")
                true
            rescue => e
                DebugTools.na_debug_error("Error updating door geometry", e)
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find a Suitable Live-Update Target Component Instance
        # ------------------------------------------------------------
        # Mirrors the window-side helper. Prefers the currently selected
        # door instance if one exists, then the @last instance the user
        # interacted with (passed in by the caller). Returns nil if
        # nothing suitable can be found.
        #
        # @param current_instance [Sketchup::ComponentInstance, nil]
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_find_live_update_target(current_instance)
            model = Sketchup.active_model
            return nil unless model

            selected = model.selection.find do |entity|
                entity.is_a?(Sketchup::ComponentInstance) && DataSerializer.na_get_door_id_from_instance(entity)
            end
            return selected if selected

            return current_instance if current_instance && current_instance.valid?

            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Material Resolution
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Materials for Each Door Part
        # ------------------------------------------------------------
        # Looks up Sketchup::Material instances via the existing
        # Na__AssemblyStudio::Na__AppData::Na__MaterialManager (which already
        # talks to the shared Na__DataLib materials library). Returns
        # nil for any material that fails to resolve - the builders
        # treat nil as "use SketchUp default".
        def self.na_resolve_materials(config)
            material_module = na_material_manager
            {
                :lining     => na_lookup_material(material_module, config["Na__DoorConfig__LiningMaterialId"]),
                :panel      => na_lookup_material(material_module, config["Na__DoorConfig__PanelMaterialId"]),
                :architrave => na_lookup_material(material_module, config["Na__DoorConfig__ArchitraveMaterialId"]),
                :handle     => na_lookup_material(material_module, config["Na__DoorConfig__HandleMaterialId"])
            }
        end
        private_class_method :na_resolve_materials
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Look Up Na__AssemblyStudio::Na__AppData::Na__MaterialManager
        # ------------------------------------------------------------
        # Returns nil if the parent module hasn't been loaded (the door
        # tool then runs without per-part materials). This keeps the
        # door tool decoupled from the window tool's load order.
        def self.na_material_manager
            return nil unless defined?(Na__AssemblyStudio::Na__AppData::Na__MaterialManager)
            Na__AssemblyStudio::Na__AppData::Na__MaterialManager
        end
        private_class_method :na_material_manager
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Look Up a Single Material by ID
        # ------------------------------------------------------------
        def self.na_lookup_material(material_module, material_id)
            return nil unless material_module && material_id
            material_module.na_get_material_by_id(material_id)
        rescue => e
            DebugTools.na_debug_warn("Material lookup failed for '#{material_id}': #{e.message}")
            nil
        end
        private_class_method :na_lookup_material
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Insertion Transform
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Insertion Transformation for a New Door
        # ------------------------------------------------------------
        # Priority order:
        #   1. insertion_origin_in (Point A from the measure tool, in inches)
        #   2. Identity (caller is expected to engage a placement tool)
        def self.na_resolve_insertion_transform(insertion_origin_in)
            return Geom::Transformation.new unless insertion_origin_in
            return Geom::Transformation.new unless insertion_origin_in.is_a?(Geom::Point3d)

            Geom::Transformation.new(insertion_origin_in)
        end
        private_class_method :na_resolve_insertion_transform
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryEngine
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
