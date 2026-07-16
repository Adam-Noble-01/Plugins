# frozen_string_literal: true

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__ExtDouble__AssemblyComposer__'
require_relative 'Na__AssemblyStudio__ExtDouble__DataSerializer__'
require_relative 'Na__AssemblyStudio__ExtDouble__FuseParts__Panel__'
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__EdgeColourPainter__'
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__LeadedGlassBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__GeometryEngine

    AssemblyComposer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__AssemblyComposer
    DataSerializer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer
    FuseParts = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__FuseParts__Panel
    TagManager = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    EdgeColourPainter = Na__AssemblyStudio::Na__WindowSystem::Na__EdgeColourPainter
    LeadedGlassBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__LeadedGlassBuilder

    def self.na_build_exterior_double_door(config, door_id = nil, insertion_frame = nil)
        return nil unless config.is_a?(Hash)
        model = Sketchup.active_model
        return nil unless model

        model.start_operation('Create Exterior Double Door', true)
        begin
            door_id ||= DataSerializer.na_allocate_adr_id(model)
            definition = model.definitions.add("#{door_id}#{NA_DEFINITION_SUFFIX}")
            # @delegate: Na__AssemblyStudio__ExtDouble__AssemblyComposer__.rb
            AssemblyComposer.na_compose(config, definition.entities, door_id)
            na_apply_fuse_parts(config, definition.entities)
            na_apply_edge_colours(config, definition.entities)
            transform = na_resolve_insertion_transform(insertion_frame)
            instance = model.active_entities.add_instance(definition, transform)
            raise 'Unable to create Exterior Double Door instance' unless instance

            identity_saved = DataSerializer.na_set_door_id_on_instance(instance, door_id)
            data_saved = DataSerializer.na_save(instance, config)
            raise 'Unable to assign Exterior Double Door identity' unless identity_saved
            raise 'Unable to save Exterior Double Door data' unless data_saved
            TagManager.na_apply_tag_to_entity(instance, :proposed_doors)
            model.commit_operation
            instance
        rescue StandardError => error
            model.abort_operation
            DebugTools.na_debug_error('Exterior Double Door creation failed', error)
            nil
        end
    end

    def self.na_update_exterior_double_door(instance, config, transparent: false)
        return false unless config.is_a?(Hash)
        return false unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
        return false unless DataSerializer.na_get_door_id_from_instance(instance)

        model = Sketchup.active_model
        return false unless model
        operation_name = transparent ? 'Live Update Exterior Double Door' : 'Update Exterior Double Door'
        model.start_operation(operation_name, true, false, transparent)
        begin
            door_id = DataSerializer.na_get_door_id_from_instance(instance)
            definition = instance.definition
            definition.entities.clear!
            # @delegate: Na__AssemblyStudio__ExtDouble__AssemblyComposer__.rb
            AssemblyComposer.na_compose(config, definition.entities, door_id)
            na_apply_fuse_parts(config, definition.entities)
            na_apply_edge_colours(config, definition.entities)
            DataSerializer.na_set_door_id_on_instance(instance, door_id)
            raise 'Unable to save Exterior Double Door data' unless DataSerializer.na_save(instance, config)
            model.commit_operation
            true
        rescue StandardError => error
            model.abort_operation
            DebugTools.na_debug_error('Exterior Double Door update failed', error)
            false
        end
    end

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

    def self.na_apply_fuse_parts(config, entities)
        return unless config['fuse_parts'] == true
        # @delegate: Na__AssemblyStudio__ExtDouble__FuseParts__Panel__.rb
        FuseParts.na_fuse_exterior_double_door(entities)
    rescue StandardError => error
        DebugTools.na_debug_error('Exterior Double Door fuse-parts failed (non-fatal)', error)
    end
    private_class_method :na_apply_fuse_parts

    def self.na_apply_edge_colours(config, entities)
        LeadedGlassBuilder.na_migrate_legacy_leaded_colour!(config)
        EdgeColourPainter.na_apply_assembly_edge_colours(entities, config)
    rescue StandardError => error
        DebugTools.na_debug_error('Exterior Double Door edge-colour paint failed (non-fatal)', error)
    end
    private_class_method :na_apply_edge_colours

end
end
end
