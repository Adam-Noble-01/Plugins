# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Top-level create/update SketchUp operation wrapper for the
#              standalone exterior single door. Mirrors the double-door engine.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__AssemblyComposer__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__DataSerializer__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__FuseParts__Panel__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    AssemblyComposer = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__AssemblyComposer
    DataSerializer   = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer
    FuseParts        = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__FuseParts__Panel
    TagManager       = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Create / Update
# -----------------------------------------------------------------------------

    # FUNCTION | Create a New Exterior Single Door Instance
    # ------------------------------------------------------------
    # @param config          [Hash] Door configuration
    # @param door_id         [String, nil] Optional pre-allocated ADR id
    # @param insertion_frame [Geom::Point3d, Hash, nil] Placement transform source
    # @return [Sketchup::ComponentInstance, nil]
    def self.na_build_exterior_single_door(config, door_id = nil, insertion_frame = nil)
        return nil unless config.is_a?(Hash)
        model = Sketchup.active_model
        return nil unless model

        model.start_operation('Create Exterior Single Door', true)
        begin
            door_id ||= DataSerializer.na_allocate_adr_id(model)
            definition = model.definitions.add("#{door_id}#{NA_DEFINITION_SUFFIX}")
            AssemblyComposer.na_compose(config, definition.entities, door_id)
            na_apply_fuse_parts(config, definition.entities)
            transform = na_resolve_insertion_transform(insertion_frame)
            instance = model.active_entities.add_instance(definition, transform)
            raise 'Unable to create Exterior Single Door instance' unless instance

            DataSerializer.na_set_door_id_on_instance(instance, door_id)
            DataSerializer.na_save(instance, config)
            TagManager.na_apply_tag_to_entity(instance, :proposed_doors)
            model.commit_operation
            instance
        rescue StandardError => error
            model.abort_operation
            DebugTools.na_debug_error('Exterior Single Door creation failed', error)
            nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update an Existing Exterior Single Door Instance
    # ------------------------------------------------------------
    # @param instance    [Sketchup::ComponentInstance]
    # @param config      [Hash] Door configuration
    # @param transparent [Boolean] Live-update (nested) operation when true
    # @return [Boolean]
    def self.na_update_exterior_single_door(instance, config, transparent: false)
        return false unless config.is_a?(Hash)
        return false unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
        return false unless DataSerializer.na_get_door_id_from_instance(instance)

        model = Sketchup.active_model
        return false unless model
        operation_name = transparent ? 'Live Update Exterior Single Door' : 'Update Exterior Single Door'
        model.start_operation(operation_name, true, false, transparent)
        begin
            door_id = DataSerializer.na_get_door_id_from_instance(instance)
            definition = instance.definition
            definition.entities.clear!
            AssemblyComposer.na_compose(config, definition.entities, door_id)
            na_apply_fuse_parts(config, definition.entities)
            DataSerializer.na_set_door_id_on_instance(instance, door_id)
            DataSerializer.na_save(instance, config)
            model.commit_operation
            true
        rescue StandardError => error
            model.abort_operation
            DebugTools.na_debug_error('Exterior Single Door update failed', error)
            false
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Insertion + Fuse
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Insertion Transform From Frame / Point / Hash
    # ------------------------------------------------------------
    def self.na_resolve_insertion_transform(insertion_frame)
        if defined?(Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame)
            return Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame
                   .na_resolve_insertion_transform(insertion_frame)
        end
        return Geom::Transformation.translation(insertion_frame) if insertion_frame.is_a?(Geom::Point3d)
        return Geom::Transformation.new unless insertion_frame.is_a?(Hash)

        origin = insertion_frame[:origin] || insertion_frame['origin'] || ORIGIN
        xaxis = insertion_frame[:xaxis] || insertion_frame['xaxis'] || X_AXIS
        yaxis = insertion_frame[:yaxis] || insertion_frame['yaxis'] || Y_AXIS
        zaxis = insertion_frame[:zaxis] || insertion_frame['zaxis'] || Z_AXIS
        Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
    end
    private_class_method :na_resolve_insertion_transform
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Optionally Run FuseParts When Config Flag Is Set
    # ------------------------------------------------------------
    def self.na_apply_fuse_parts(config, entities)
        return unless config['fuse_parts'] == true
        FuseParts.na_fuse_exterior_single_door(entities)
    rescue StandardError => error
        DebugTools.na_debug_error('Exterior Single Door fuse-parts failed (non-fatal)', error)
    end
    private_class_method :na_apply_fuse_parts
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryEngine
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
