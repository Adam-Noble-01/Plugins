# frozen_string_literal: true

require 'sketchup.rb'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__MaterialManager__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Defaults__'
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtDouble__LeafLayoutResolver__'
require_relative 'Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__'
require_relative 'Na__AssemblyStudio__ExtDouble__PanelLineworkBuilder__'
require_relative 'Na__AssemblyStudio__ExtDouble__PanelGeometryBuilder__'
require_relative 'Na__AssemblyStudio__ExtDouble__HandleBuilder__'
require_relative 'Na__AssemblyStudio__ExtDouble__RotationPivotBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__AssemblyComposer

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    LeafLayoutResolver = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__LeafLayoutResolver
    PanelLayoutResolver = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__PanelLayoutResolver
    PanelLineworkBuilder = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__PanelLineworkBuilder
    PanelGeometryBuilder = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__PanelGeometryBuilder
    HandleBuilder = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__HandleBuilder
    RotationPivotBuilder = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__RotationPivotBuilder
    NamingContract = Na__AssemblyStudio::Na__GeometryHelpers::Na__DoorNamingContract
    WindowBuilders = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryBuilders
    MaterialManager = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
    TagManager = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    Box = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box

    def self.na_compose(config, parent_entities, door_id)
        # @delegate: Na__AssemblyStudio__ExtDouble__LeafLayoutResolver__.rb
        leaves = LeafLayoutResolver.na_resolve(config)
        raise ArgumentError, 'Exterior double door requires two valid leaves' unless leaves.length == 2

        dimensions = leaves.first[:dimensions]
        materials = na_resolve_materials(config)
        na_build_frame(config, dimensions, parent_entities, materials[:frame])
        na_build_cill(config, dimensions, parent_entities, materials[:frame])

        records = leaves.map do |leaf|
            na_compose_leaf(config, parent_entities, leaf, door_id, materials)
        end

        open_groups = na_build_open_copies(config, records)
        swing_groups = na_build_swing_groups(config, parent_entities, leaves)
        na_apply_cill_lift(config, dimensions, parent_entities)

        {
            :leaves => records.freeze,
            :open_groups => open_groups.freeze,
            :swing_groups => swing_groups.freeze
        }.freeze
    end

    def self.na_compose_leaf(config, parent_entities, leaf, door_id, materials)
        mod = parent_entities.add_group
        mod.name = NamingContract.na_format_mod_rot_only(
            leaf[:index], leaf[:signed_angle_deg], NA_PANEL_TAG
        )
        TagManager.na_apply_tag_to_entity(mod, :door_closed)

        # @delegate: Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__.rb
        panel_layout = PanelLayoutResolver.na_resolve(config, leaf)
        na_build_leaf_members(mod.entities, leaf, panel_layout, materials[:leaf], door_id)
        na_build_field_dividers(mod.entities, leaf, panel_layout, materials[:leaf], door_id)
        na_build_glazed_region(mod.entities, leaf, panel_layout, materials)

        if panel_layout[:output_mode] == 'Linework'
            # @delegate: Na__AssemblyStudio__ExtDouble__PanelLineworkBuilder__.rb
            PanelLineworkBuilder.na_build(mod.entities, leaf, panel_layout, materials[:leaf])
        else
            # @delegate: Na__AssemblyStudio__ExtDouble__PanelGeometryBuilder__.rb
            PanelGeometryBuilder.na_build(mod.entities, leaf, panel_layout, materials[:leaf])
        end

        # @delegate: Na__AssemblyStudio__ExtDouble__HandleBuilder__.rb
        HandleBuilder.na_build_active_leaf_handle(config, mod.entities, leaf, materials[:handle])

        # MOD and matching ROT are deliberately emitted consecutively.
        # @delegate: Na__AssemblyStudio__ExtDouble__RotationPivotBuilder__.rb
        rot = RotationPivotBuilder.na_build(parent_entities, leaf)
        { :leaf => leaf, :panel_layout => panel_layout, :mod => mod, :rot => rot }.freeze
    end
    private_class_method :na_compose_leaf

    def self.na_build_leaf_members(entities, leaf, layout, material, door_id)
        members = layout[:members]
        stile = members[:stile_width_mm]
        top_rail = members[:top_rail_width_mm]
        bottom_rail = members[:bottom_rail_width_mm]
        prefix = "Na__ExteriorDoubleDoor__#{door_id}__Leaf#{format('%03d', leaf[:index])}"
        na_box(entities, "#{prefix}__StileLeft", leaf[:origin_x_mm], leaf[:origin_y_mm], leaf[:origin_z_mm],
               stile, leaf[:thickness_mm], leaf[:height_mm], material)
        na_box(entities, "#{prefix}__StileRight", leaf[:origin_x_mm] + leaf[:width_mm] - stile,
               leaf[:origin_y_mm], leaf[:origin_z_mm], stile, leaf[:thickness_mm], leaf[:height_mm], material)
        inner_width = leaf[:width_mm] - 2.0 * stile
        na_box(entities, "#{prefix}__RailBottom", leaf[:origin_x_mm] + stile, leaf[:origin_y_mm], leaf[:origin_z_mm],
               inner_width, leaf[:thickness_mm], bottom_rail, material)
        na_box(entities, "#{prefix}__RailTop", leaf[:origin_x_mm] + stile, leaf[:origin_y_mm],
               leaf[:origin_z_mm] + leaf[:height_mm] - top_rail,
               inner_width, leaf[:thickness_mm], top_rail, material)

        return unless layout[:composition] == 'GlazedOverFielded' && layout[:field_region]
        mid_z = layout[:field_region][:z_mm] + layout[:field_region][:height_mm]
        na_box(entities, "#{prefix}__RailMid", leaf[:origin_x_mm] + stile, leaf[:origin_y_mm], mid_z,
               inner_width, leaf[:thickness_mm], members[:mid_rail_width_mm], material)
    end
    private_class_method :na_build_leaf_members

    def self.na_build_field_dividers(entities, leaf, layout, material, door_id)
        layout[:field_dividers].each do |divider|
            role = divider[:orientation] == :vertical ? 'FieldStile' : 'FieldRail'
            name = format(
                'Na__ExteriorDoubleDoor__%s__Leaf%03d__%s%02d',
                door_id,
                leaf[:index],
                role,
                divider[:index]
            )
            na_box(
                entities,
                name,
                divider[:x_mm],
                leaf[:origin_y_mm],
                divider[:z_mm],
                divider[:width_mm],
                leaf[:thickness_mm],
                divider[:height_mm],
                material
            )
        end
    end
    private_class_method :na_build_field_dividers

    def self.na_build_glazed_region(entities, leaf, layout, materials)
        region = layout[:glazed_region]
        return unless region && region[:height_mm] > 0

        glass_depth = [leaf[:thickness_mm] * 0.35, 2.0].max
        glass_y = leaf[:origin_y_mm] + (leaf[:thickness_mm] - glass_depth) / 2.0
        na_box(entities, 'Na__ExteriorDoubleDoor__Glass',
               region[:x_mm], glass_y, region[:z_mm],
               region[:width_mm], glass_depth, region[:height_mm], materials[:glass])
        na_build_glaze_bars(entities, leaf, layout, materials[:leaf])
    end
    private_class_method :na_build_glazed_region

    def self.na_build_glaze_bars(entities, leaf, layout, material)
        region = layout[:glazed_region]
        bars = layout[:glaze_bars]
        y = leaf[:origin_y_mm] + bars[:inset_mm]
        depth = [leaf[:thickness_mm] - 2.0 * bars[:inset_mm], 2.0].max
        vertical_positions = WindowBuilders.na_compute_bar_positions(
            region[:x_mm],
            region[:width_mm],
            bars[:vertical_count],
            bars[:margin_enabled],
            bars[:margin_offset_mm]
        )
        horizontal_positions = WindowBuilders.na_compute_bar_positions(
            region[:z_mm],
            region[:height_mm],
            bars[:horizontal_count],
            bars[:margin_enabled],
            bars[:margin_offset_mm]
        ).map { |position| position + bars[:horizontal_offset_mm] }

        vertical_positions.each_with_index do |x, index|
            next if bars[:removed_keys].include?(na_glazebar_key(leaf, 'vertical', index + 1))
            na_box(entities, "Na__ExteriorDoubleDoor__GlazeBarV#{index + 1}",
                   x - bars[:width_mm] / 2.0, y, region[:z_mm],
                   bars[:width_mm], depth, region[:height_mm], material)
        end
        horizontal_positions.each_with_index do |z, index|
            next if bars[:removed_keys].include?(na_glazebar_key(leaf, 'horizontal', index + 1))
            na_box(entities, "Na__ExteriorDoubleDoor__GlazeBarH#{index + 1}",
                   region[:x_mm], y, z - bars[:width_mm] / 2.0,
                   region[:width_mm], depth, bars[:width_mm], material)
        end
    end
    private_class_method :na_build_glaze_bars

    def self.na_glazebar_key(leaf, orientation, bar_index)
        "0:0:#{leaf[:index] - 1}:0:#{orientation}:#{bar_index}"
    end
    private_class_method :na_glazebar_key

    def self.na_build_open_copies(config, records)
        return [] unless GeometryHelpers.na_boolean(config, 'double_door_create_open_state_copy', true)
        records.map do |record|
            copy = record[:mod].copy
            copy.name = record[:mod].name
            copy.transform!(GeometryHelpers.na_rotation_transform(record[:leaf]))
            TagManager.na_apply_tag_to_entity(copy, :door_open)
            copy
        end
    end
    private_class_method :na_build_open_copies

    def self.na_build_swing_groups(config, entities, leaves)
        return [] unless GeometryHelpers.na_boolean(config, 'double_door_show_swing_arcs', true)
        leaves.map do |leaf|
            group = entities.add_group
            group.name = format('Na__ExteriorDoubleDoor__Swing__%03d', leaf[:index])
            points = GeometryHelpers.na_arc_points_mm(
                leaf[:hinge_x_mm], leaf[:pivot_y_mm], leaf[:width_mm],
                leaf[:closed_latch_angle_deg], leaf[:signed_angle_deg], 32
            ).map { |point| na_point(point[:x], point[:y], leaf[:origin_z_mm] + 10) }
            points.each_cons(2) { |first, second| group.entities.add_line(first, second) }
            group.entities.add_line(
                na_point(leaf[:hinge_x_mm], leaf[:pivot_y_mm], leaf[:origin_z_mm] + 10),
                points.last
            ) unless points.empty?
            TagManager.na_apply_tag_to_entity(group, :door_swing)
            group
        end
    end
    private_class_method :na_build_swing_groups

    def self.na_build_frame(config, dimensions, entities, material)
        edges = {
            :top => GeometryHelpers.na_mm_to_inch(dimensions[:frame_top_mm]),
            :bottom => GeometryHelpers.na_mm_to_inch(dimensions[:frame_bottom_mm]),
            :left => GeometryHelpers.na_mm_to_inch(dimensions[:frame_left_mm]),
            :right => GeometryHelpers.na_mm_to_inch(dimensions[:frame_right_mm])
        }
        WindowBuilders.na_create_frame_geometry(
            entities,
            GeometryHelpers.na_mm_to_inch(dimensions[:width_mm]),
            GeometryHelpers.na_mm_to_inch(dimensions[:height_mm]),
            edges,
            GeometryHelpers.na_mm_to_inch(dimensions[:frame_depth_mm]),
            material,
            GeometryHelpers.na_mm_to_inch(dimensions[:frame_wall_inset_mm])
        )
    end
    private_class_method :na_build_frame

    def self.na_build_cill(config, dimensions, entities, frame_material)
        return unless GeometryHelpers.na_boolean(config, 'has_cill', true)
        return unless dimensions[:frame_bottom_mm] > 0
        height = GeometryHelpers.na_number(config, 'cill_height_mm', 50)
        depth = GeometryHelpers.na_number(config, 'cill_depth_mm', 50)
        return if height <= 0 || depth <= 0
        material = if GeometryHelpers.na_boolean(config, 'paint_cill', false)
                       frame_material
                   else
                       MaterialManager.na_get_material_by_id(
                           Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_CILL_MATERIAL_ID
                       )
                   end
        WindowBuilders.na_create_cill_geometry(
            entities,
            GeometryHelpers.na_mm_to_inch(dimensions[:width_mm]),
            GeometryHelpers.na_mm_to_inch(depth),
            GeometryHelpers.na_mm_to_inch(height),
            GeometryHelpers.na_mm_to_inch(dimensions[:frame_depth_mm]),
            material,
            GeometryHelpers.na_mm_to_inch(dimensions[:frame_wall_inset_mm])
        )
    end
    private_class_method :na_build_cill

    def self.na_apply_cill_lift(config, dimensions, entities)
        return unless GeometryHelpers.na_boolean(config, 'has_cill', true)
        return unless dimensions[:frame_bottom_mm] > 0
        lift = GeometryHelpers.na_number(config, 'cill_height_mm', 50)
        return if lift <= 0
        targets = entities.to_a
        return if targets.empty?
        transform = Geom::Transformation.translation([0, 0, GeometryHelpers.na_mm_to_inch(lift)])
        entities.transform_entities(transform, targets)
    end
    private_class_method :na_apply_cill_lift

    def self.na_resolve_materials(config)
        frame_id = config['frame_material_id'] || Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_FRAME_MATERIAL_ID
        glass_id = config['glass_material_id'] || Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_GLASS_MATERIAL_ID
        {
            :frame => MaterialManager.na_get_material_by_id(frame_id),
            :leaf => MaterialManager.na_get_material_by_id(config['double_door_leaf_material_id'] || frame_id),
            :glass => MaterialManager.na_get_material_by_id(glass_id),
            :handle => MaterialManager.na_get_material_by_id(config['double_door_handle_material_id'])
        }
    end
    private_class_method :na_resolve_materials

    def self.na_box(entities, name, x, y, z, width, depth, height, material)
        return nil if width <= 0 || depth <= 0 || height <= 0
        Box.na_create_grouped_box(
            entities, name,
            GeometryHelpers.na_mm_to_inch(x), GeometryHelpers.na_mm_to_inch(y),
            GeometryHelpers.na_mm_to_inch(z), GeometryHelpers.na_mm_to_inch(width),
            GeometryHelpers.na_mm_to_inch(depth), GeometryHelpers.na_mm_to_inch(height),
            material
        )
    end
    private_class_method :na_box

    def self.na_point(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm)
        )
    end
    private_class_method :na_point

end
end
end
