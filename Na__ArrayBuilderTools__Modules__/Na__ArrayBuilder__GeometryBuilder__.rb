# =============================================================================
# NA ARRAY BUILDER TOOLS - GEOMETRY BUILDER
# =============================================================================
# FILE       : Na__ArrayBuilder__GeometryBuilder__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Transactional creation and regeneration of persistent arrays.
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'
require_relative 'Na__ArrayBuilder__LayoutEngine__'
require_relative 'Na__ArrayBuilder__DataSerializer__'
require_relative 'Na__ArrayBuilder__CornerMerger__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__GeometryBuilder

        # FUNCTION | Create an Array in the Current Editing Context
        # ------------------------------------------------------------
        # Legacy tool entry point retained for the draw and selection tools.
        def self.na_create_array(na_waypoints, na_config, _na_positions = nil)
            na_model = Sketchup.active_model
            na_source = na_config['type'] == 'object' ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo : nil
            # Both InputPoint and vertices in active_entities are already WORLD.
            # Active-context instance insertion accepts world transforms as well.
            # See 85__Docs/Na__ArrayBuilder__CoordinateSpaces__.md.
            na_points = na_waypoints
            # Definition-local paths allow moved/rotated/scaled copies to regenerate.
            na_origin = na_points.first
            na_local = na_points.map { |na_point| Geom::Point3d.new((na_point - na_origin).to_a) }
            na_plan = Na__ArrayBuilder__LayoutEngine.Na__Layout__Resolve(na_config, na_local, na_source)
            raise ArgumentError, 'The path has no array positions.' if na_plan[:positions].empty?
            na_model.start_operation('Create Noble Array', true)
            begin
                na_definition = na_model.definitions.add('Na__ArrayBuilder__Assembly')
                na_entity = na_model.active_entities.add_instance(na_definition, Geom::Transformation.translation(na_origin))
                na_entity.name = 'Noble Array'
                Na__Geometry__Populate(na_model, na_definition, na_plan)
                Na__ArrayBuilder__DataSerializer.Na__Data__Save(na_model, na_entity, na_plan[:config], na_local, na_source, na_plan[:positions].length)
                na_model.commit_operation
            rescue StandardError
                na_model.abort_operation
                raise
            end
            na_model.selection.clear
            na_model.selection.add(na_entity)
            na_entity
        end

        # FUNCTION | Rebuild One Instance or All Instances of its Definition
        # ------------------------------------------------------------
        def self.Na__Geometry__Update(na_model, na_entity, na_config, na_scope, na_source = nil, na_path = nil)
            raise ArgumentError, 'The array is locked.' if na_entity.locked?
            na_data = Na__ArrayBuilder__DataSerializer.Na__Data__Load(na_entity)
            na_source ||= Na__ArrayBuilder__DataSerializer.Na__Data__RestoreSource(na_entity, na_data, true) if na_config['type'] == 'object'
            na_source = nil unless na_config['type'] == 'object'
            na_points = na_path || Na__ArrayBuilder__DataSerializer.Na__Data__Points(na_data)
            na_plan = Na__ArrayBuilder__LayoutEngine.Na__Layout__Resolve(na_config, na_points, na_source)
            if na_scope == 'linked' && na_entity.definition.instances.any?(&:locked?)
                raise ArgumentError, 'A linked array is locked. Unlock it or choose Only this array.'
            end
            Na__Geometry__CheckSource(na_source, na_entity.definition) if na_source
            na_model.start_operation('Update Noble Array', true)
            begin
                if na_scope != 'linked' && na_entity.definition.instances.length > 1
                    na_entity.make_unique
                    na_data = na_data.merge('array_id' => SecureRandom.uuid)
                end
                Na__Geometry__Populate(na_model, na_entity.definition, na_plan)
                Na__ArrayBuilder__DataSerializer.Na__Data__Save(na_model, na_entity, na_plan[:config], na_points, na_source, na_plan[:positions].length, na_data)
                na_model.commit_operation
            rescue StandardError
                na_model.abort_operation
                raise
            end
            na_model.active_view.invalidate
            na_plan
        end

        # FUNCTION | Reject Recursive Component Sources Before Clearing Geometry
        # ------------------------------------------------------------
        def self.Na__Geometry__CheckSource(na_source, na_target)
            na_pending = [na_source[:definition]]
            na_seen = {}
            until na_pending.empty?
                na_definition = na_pending.pop
                raise ArgumentError, 'An array cannot contain itself. Pick a separate source object.' if na_definition == na_target
                next if na_seen[na_definition]
                na_seen[na_definition] = true
                na_definition.entities.each do |na_child|
                    na_pending << na_child.definition if na_child.is_a?(Sketchup::ComponentInstance) || na_child.is_a?(Sketchup::Group)
                end
            end
        end

        # FUNCTION | Replace Only Generated Units, Preserving User Additions
        # ------------------------------------------------------------
        def self.Na__Geometry__Populate(na_model, na_definition, na_plan)
            na_dictionary = Na__ArrayBuilder__DataSerializer::NA_INSTANCE_DICT
            na_old = na_definition.entities.select { |na_entity| na_entity.get_attribute(na_dictionary, 'role') == 'unit' }
            na_unit = na_plan[:source] ? na_plan[:source][:definition] : Na__Geometry__BlockDefinition(na_model, na_plan[:config])
            na_units = na_plan[:positions].map do |na_position|
                na_transform = Na__ArrayBuilder__LayoutEngine.Na__Layout__Transform(na_position, na_plan[:config], na_plan[:source])
                na_instance = na_definition.entities.add_instance(na_unit, na_transform)
                na_instance.set_attribute(na_dictionary, 'role', 'unit')
                na_instance
            end
            Na__ArrayBuilder__CornerMerger.Na__Corners__Merge(na_units, na_plan)
            na_definition.entities.erase_entities(na_old) unless na_old.empty?
            na_definition.invalidate_bounds
        end

        # FUNCTION | Reuse Dimension-Matched Blocks for Fast Live Regeneration
        # ------------------------------------------------------------
        def self.Na__Geometry__BlockDefinition(na_model, na_config)
            na_dimensions = %w[unit_width_mm unit_depth_mm unit_height_mm].map { |na_key| na_config[na_key] }
            na_key = JSON.generate(na_dimensions)
            na_existing = na_model.definitions.find { |na_definition|
                na_definition.get_attribute(Na__ArrayBuilder__DataSerializer::NA_DEFINITION_DICT, 'block_dimensions') == na_key
            }
            return na_existing if na_existing
            na_definition = na_model.definitions.add('Na__ArrayBuilder__Block')
            na_w, na_d, na_h = na_dimensions.map(&:mm)
            na_face = na_definition.entities.add_face([0,-na_d/2,0], [na_w,-na_d/2,0], [na_w,na_d/2,0], [0,na_d/2,0])
            raise ArgumentError, 'The block dimensions are too small to build.' unless na_face
            na_face.reverse! if na_face.normal.z < 0
            na_face.pushpull(na_h)
            na_definition.set_attribute(Na__ArrayBuilder__DataSerializer::NA_DEFINITION_DICT, 'block_dimensions', na_key)
            na_definition
        end

    end # module Na__ArrayBuilder__GeometryBuilder
end # module Na__ArrayBuilderTools
