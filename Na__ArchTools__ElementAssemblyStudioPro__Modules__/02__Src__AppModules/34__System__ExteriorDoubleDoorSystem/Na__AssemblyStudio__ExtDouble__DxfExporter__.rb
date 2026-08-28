# frozen_string_literal: true

require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtDouble__LeafLayoutResolver__'
require_relative 'Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__DxfExporter

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    LeafLayoutResolver = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__LeafLayoutResolver
    PanelLayoutResolver = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__PanelLayoutResolver

    NA_LAYER_FALLBACKS = {
        :frame => 'NA_FRAME',
        :cill => 'NA_CILL',
        :leaf => 'NA_DOOR_LEAF',
        :rail_stile => 'NA_DOOR_LEAF',
        :glass => 'NA_GLASS',
        :glaze_bar => 'NA_GLAZEBAR',
        :panel => 'NA_DOOR_PANEL',
        :hardware => 'NA_DOOR_HARDWARE',
        :swing => 'NA_DOOR_SWING',
        :dimensions => 'NA_DIMENSIONS'
    }.freeze

    # HELPER FUNCTION | Fixed-Panel Mode Predicate
    # ------------------------------------------------------------
    # Fixed panels export as dead joinery - no handle, no open-state plan
    # outline and no swing arc.
    def self.na_fixed_panels?(config)
        GeometryHelpers.na_boolean(config, 'double_door_fixed_panels', false)
    end
    private_class_method :na_fixed_panels?

    def self.na_build_entities(config)
        # @delegate: Na__AssemblyStudio__ExtDouble__LeafLayoutResolver__.rb
        leaves = LeafLayoutResolver.na_resolve(config)
        return [] unless leaves.length == 2

        elevation = []
        dimensions = leaves.first[:dimensions]
        na_add_frame(elevation, config, dimensions)
        leaves.each do |leaf|
            # @delegate: Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__.rb
            panel = PanelLayoutResolver.na_resolve(config, leaf)
            na_add_leaf_elevation(elevation, config, leaf, panel)
        end
        na_add_dimensions(elevation, config, leaves, dimensions) unless config['show_dimensions'] == false
        na_shift_elevation_for_cill(elevation, config, dimensions)

        output = elevation
        na_add_plan_output(output, config, leaves, dimensions)
        output.freeze
    end

    def self.na_export(config, writer = nil)
        entities = na_build_entities(config)
        return na_emit_to_writer(entities, writer) if writer
        na_ascii_dxf(entities)
    end

    def self.na_export_dxf(config, writer = nil)
        na_export(config, writer)
    end

    def self.na_add_frame(output, config, dimensions)
        layer = na_layer(config, :frame)
        width = dimensions[:width_mm]
        height = dimensions[:height_mm]
        na_rect(output, layer, 0, 0, dimensions[:frame_left_mm], height)
        na_rect(output, layer, width - dimensions[:frame_right_mm], 0, dimensions[:frame_right_mm], height)
        na_rect(output, layer, dimensions[:frame_left_mm], 0, dimensions[:inner_w_mm], dimensions[:frame_bottom_mm])
        na_rect(output, layer, dimensions[:frame_left_mm], height - dimensions[:frame_top_mm],
                dimensions[:inner_w_mm], dimensions[:frame_top_mm])

        return unless GeometryHelpers.na_boolean(config, 'has_cill', true)
        cill_height = GeometryHelpers.na_number(config, 'cill_height_mm', 50)
        na_rect(output, na_layer(config, :cill), 0, -cill_height, width, cill_height)
    end
    private_class_method :na_add_frame

    def self.na_add_leaf_elevation(output, config, leaf, panel)
        leaf_layer = na_layer(config, :leaf)
        na_rect(output, leaf_layer, leaf[:origin_x_mm], leaf[:origin_z_mm], leaf[:width_mm], leaf[:height_mm])
        members = panel[:members]
        member_layer = na_layer(config, :rail_stile)
        na_rect(output, member_layer, leaf[:origin_x_mm], leaf[:origin_z_mm],
                members[:stile_width_mm], leaf[:height_mm])
        na_rect(output, member_layer, leaf[:origin_x_mm] + leaf[:width_mm] - members[:stile_width_mm],
                leaf[:origin_z_mm], members[:stile_width_mm], leaf[:height_mm])
        inner_width = leaf[:width_mm] - 2.0 * members[:stile_width_mm]
        na_rect(output, member_layer, leaf[:origin_x_mm] + members[:stile_width_mm], leaf[:origin_z_mm],
                inner_width, members[:bottom_rail_width_mm])
        na_rect(output, member_layer, leaf[:origin_x_mm] + members[:stile_width_mm],
                leaf[:origin_z_mm] + leaf[:height_mm] - members[:top_rail_width_mm],
                inner_width, members[:top_rail_width_mm])

        if panel[:composition] == 'GlazedOverFielded' && panel[:field_region]
            mid_z = panel[:field_region][:z_mm] + panel[:field_region][:height_mm]
            na_rect(output, member_layer, leaf[:origin_x_mm] + members[:stile_width_mm],
                    mid_z, inner_width, members[:mid_rail_width_mm])
        end
        na_add_glazing(output, config, panel, leaf)
        panel[:field_cells].each do |cell|
            na_rect(output, na_layer(config, :panel), cell[:x_mm], cell[:z_mm],
                    cell[:width_mm], cell[:height_mm])
        end
        panel[:field_dividers].each do |divider|
            na_rect(
                output,
                member_layer,
                divider[:x_mm],
                divider[:z_mm],
                divider[:width_mm],
                divider[:height_mm]
            )
        end
        na_add_handle(output, config, leaf) if leaf[:is_active] && !na_fixed_panels?(config)
    end
    private_class_method :na_add_leaf_elevation

    def self.na_add_glazing(output, config, panel, leaf)
        region = panel[:glazed_region]
        return unless region
        na_rect(output, na_layer(config, :glass), region[:x_mm], region[:z_mm],
                region[:width_mm], region[:height_mm])
        bars = panel[:glaze_bars]
        vertical_positions = na_bar_positions(
            region[:x_mm], region[:width_mm], bars[:vertical_count],
            bars[:margin_enabled], bars[:margin_offset_mm]
        )
        horizontal_positions = na_bar_positions(
            region[:z_mm], region[:height_mm], bars[:horizontal_count],
            bars[:margin_enabled], bars[:margin_offset_mm]
        )
        vertical_positions.each_with_index do |x, index|
            next if bars[:removed_keys].include?(na_glazebar_key(leaf, 'vertical', index + 1))
            na_line(output, na_layer(config, :glaze_bar), x, region[:z_mm], x, region[:z_mm] + region[:height_mm])
        end
        horizontal_positions.each_with_index do |position, index|
            next if bars[:removed_keys].include?(na_glazebar_key(leaf, 'horizontal', index + 1))
            z = position + bars[:horizontal_offset_mm]
            na_line(output, na_layer(config, :glaze_bar), region[:x_mm], z,
                    region[:x_mm] + region[:width_mm], z)
        end
    end
    private_class_method :na_add_glazing

    def self.na_glazebar_key(leaf, orientation, bar_index)
        "0:0:#{leaf[:index] - 1}:0:#{orientation}:#{bar_index}"
    end
    private_class_method :na_glazebar_key

    def self.na_bar_positions(start, size, count, margin_enabled, margin_offset)
        return [] if count.to_i <= 0
        return (1..count).map { |index| start + size.to_f * index / (count + 1) } unless margin_enabled && count >= 2

        first = start + margin_offset
        last = start + size - margin_offset
        return [first, last] if count == 2

        step = (last - first) / (count - 1).to_f
        (0...count).map { |index| first + step * index }
    end
    private_class_method :na_bar_positions

    def self.na_add_handle(output, config, leaf)
        backset = GeometryHelpers.na_number(config, 'double_door_handle_backset_mm', 40)
        height = GeometryHelpers.na_number(config, 'double_door_handle_height_mm', 900)
        x = leaf[:side] == :left ? leaf[:origin_x_mm] + leaf[:width_mm] - backset : leaf[:origin_x_mm] + backset
        layer = na_layer(config, :hardware)
        output << { :type => :circle, :layer => layer, :x => x, :y => leaf[:origin_z_mm] + height, :radius => 12.0 }
        na_line(output, layer, x - 30, leaf[:origin_z_mm] + height, x + 30, leaf[:origin_z_mm] + height)
    end
    private_class_method :na_add_handle

    def self.na_add_plan_output(output, config, leaves, dimensions)
        plan_offset = -(leaves.map { |leaf| leaf[:width_mm] }.max + dimensions[:frame_depth_mm] + 300)
        leaves.each do |leaf|
            na_rect(
                output,
                na_layer(config, :leaf),
                leaf[:origin_x_mm],
                leaf[:origin_y_mm] + plan_offset,
                leaf[:width_mm],
                leaf[:thickness_mm]
            )
            next if na_fixed_panels?(config)
            if GeometryHelpers.na_boolean(config, 'double_door_create_open_state_copy', true)
                na_add_open_leaf_plan(output, config, leaf, plan_offset)
            end
            if GeometryHelpers.na_boolean(config, 'double_door_show_swing_arcs', true)
                output << {
                    :type => :arc,
                    :layer => na_layer(config, :swing),
                    :x => leaf[:hinge_x_mm],
                    :y => leaf[:pivot_y_mm] + plan_offset,
                    :radius => leaf[:width_mm],
                    :start_angle => leaf[:closed_latch_angle_deg],
                    :sweep_angle => leaf[:signed_angle_deg]
                }
            end
        end
    end
    private_class_method :na_add_plan_output

    def self.na_add_open_leaf_plan(output, config, leaf, plan_offset)
        pivot_x = leaf[:hinge_x_mm]
        pivot_y = leaf[:pivot_y_mm]
        corners = [
            [leaf[:origin_x_mm], leaf[:origin_y_mm]],
            [leaf[:origin_x_mm] + leaf[:width_mm], leaf[:origin_y_mm]],
            [leaf[:origin_x_mm] + leaf[:width_mm], leaf[:origin_y_mm] + leaf[:thickness_mm]],
            [leaf[:origin_x_mm], leaf[:origin_y_mm] + leaf[:thickness_mm]]
        ].map do |point|
            GeometryHelpers.na_rotate_xy(point[0], point[1], pivot_x, pivot_y, leaf[:signed_angle_deg])
        end
        corners.each_with_index do |point, index|
            following = corners[(index + 1) % corners.length]
            na_line(output, na_layer(config, :swing),
                    point[:x], point[:y] + plan_offset, following[:x], following[:y] + plan_offset)
        end
    end
    private_class_method :na_add_open_leaf_plan

    def self.na_add_dimensions(output, config, leaves, dimensions)
        layer = na_layer(config, :dimensions)
        output << {
            :type => :text, :layer => layer, :x => dimensions[:width_mm] / 2.0,
            :y => dimensions[:height_mm] + 100, :height => 35,
            :text => "Exterior Double Door #{dimensions[:width_mm].round} x #{dimensions[:height_mm].round} mm"
        }
        leaves.each do |leaf|
            output << {
                :type => :text, :layer => layer,
                :x => leaf[:origin_x_mm] + leaf[:width_mm] / 2.0,
                :y => leaf[:origin_z_mm] - 80, :height => 25,
                :text => "#{leaf[:side_name]} #{leaf[:width_mm].round} mm"
            }
        end
    end
    private_class_method :na_add_dimensions

    def self.na_shift_elevation_for_cill(entities, config, dimensions)
        return unless GeometryHelpers.na_boolean(config, 'has_cill', true)
        return unless dimensions[:frame_bottom_mm] > 0
        lift = GeometryHelpers.na_number(config, 'cill_height_mm', 50)
        return if lift <= 0

        entities.each do |entity|
            case entity[:type]
            when :line
                entity[:y1] += lift
                entity[:y2] += lift
            when :circle, :text
                entity[:y] += lift
            end
        end
    end
    private_class_method :na_shift_elevation_for_cill

    def self.na_rect(output, layer, x, y, width, height)
        return if width <= 0 || height <= 0
        na_line(output, layer, x, y, x + width, y)
        na_line(output, layer, x + width, y, x + width, y + height)
        na_line(output, layer, x + width, y + height, x, y + height)
        na_line(output, layer, x, y + height, x, y)
    end
    private_class_method :na_rect

    def self.na_line(output, layer, x1, y1, x2, y2)
        output << { :type => :line, :layer => layer, :x1 => x1, :y1 => y1, :x2 => x2, :y2 => y2 }
    end
    private_class_method :na_line

    def self.na_layer(config, role)
        configured = config['dxf_layers']
        value = configured[role.to_s] if configured.is_a?(Hash)
        value.to_s.empty? ? NA_LAYER_FALLBACKS.fetch(role) : value.to_s
    end
    private_class_method :na_layer

    def self.na_emit_to_writer(entities, writer)
        entities.each do |entity|
            case entity[:type]
            when :line
                writer.add_line(entity[:x1], entity[:y1], entity[:x2], entity[:y2], entity[:layer])
            when :arc
                writer.add_arc(entity[:x], entity[:y], entity[:radius],
                               entity[:start_angle], entity[:sweep_angle], entity[:layer])
            when :circle
                writer.add_circle(entity[:x], entity[:y], entity[:radius], entity[:layer])
            when :text
                writer.add_text(entity[:x], entity[:y], entity[:height], entity[:text], entity[:layer])
            end
        end
        writer
    end
    private_class_method :na_emit_to_writer

    def self.na_ascii_dxf(entities)
        records = ["0\nSECTION\n2\nENTITIES"]
        entities.each { |entity| records << na_ascii_entity(entity) }
        records << "0\nENDSEC\n0\nEOF"
        records.compact.join("\n")
    end
    private_class_method :na_ascii_dxf

    def self.na_ascii_entity(entity)
        case entity[:type]
        when :line
            "0\nLINE\n8\n#{entity[:layer]}\n10\n#{entity[:x1]}\n20\n#{entity[:y1]}\n11\n#{entity[:x2]}\n21\n#{entity[:y2]}"
        when :circle
            "0\nCIRCLE\n8\n#{entity[:layer]}\n10\n#{entity[:x]}\n20\n#{entity[:y]}\n40\n#{entity[:radius]}"
        when :arc
            start_angle = entity[:start_angle].to_f
            end_angle = start_angle + entity[:sweep_angle].to_f
            start_angle, end_angle = end_angle, start_angle if entity[:sweep_angle].to_f.negative?
            "0\nARC\n8\n#{entity[:layer]}\n10\n#{entity[:x]}\n20\n#{entity[:y]}\n40\n#{entity[:radius]}\n50\n#{start_angle % 360}\n51\n#{end_angle % 360}"
        when :text
            "0\nTEXT\n8\n#{entity[:layer]}\n10\n#{entity[:x]}\n20\n#{entity[:y]}\n40\n#{entity[:height]}\n1\n#{entity[:text]}"
        end
    end
    private_class_method :na_ascii_entity

end
end
end
