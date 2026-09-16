# =============================================================================
# NA ARRAY BUILDER TOOLS - CORNER MERGER
# FILE       : Na__ArrayBuilder__CornerMerger__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Native solid unions for overlapping parametric units at bends.
# =============================================================================

require_relative 'Na__ArrayBuilder__LayoutEngine__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__CornerMerger

        # FUNCTION | Union Corner Neighbours Inside the Builder's Undo Operation
        # ------------------------------------------------------------
        def self.Na__Corners__Merge(na_units, na_plan)
            return unless na_plan[:config]['merge_corners'] && na_plan[:config]['type'] == 'block'
            na_pairs = (0...na_units.length - 1).map { |na_index| [na_index, na_index + 1] }
            if na_units.length > 2 && na_plan[:points].first.distance(na_plan[:points].last) < 0.001
                na_pairs << [na_units.length - 1, 0]
            end
            na_corners = {}
            na_pairs.each do |na_a, na_b|
                na_positions = na_plan[:positions]
                next if Na__Corners__Dot(na_positions[na_a][:direction], na_positions[na_b][:direction]) > 0.999999
                [na_a, na_b].each do |na_index|
                    na_corners[na_index] ||= Na__ArrayBuilder__LayoutEngine.Na__Layout__Corners(na_positions[na_index], na_plan[:config])
                end
                next unless Na__Corners__Overlap?(na_corners[na_a], na_corners[na_b])
                na_left, na_right = na_units[na_a], na_units[na_b]
                next if na_left == na_right
                na_merged = na_left.union(na_right)
                unless na_merged && na_merged.valid?
                    raise ArgumentError, 'SketchUp could not union these corner blocks. Adjust their overlap or turn Merge corner objects off.'
                end
                na_merged.set_attribute(Na__ArrayBuilder__DataSerializer::NA_INSTANCE_DICT, 'role', 'unit')
                na_merged.name = 'Noble Array · merged corner'
                na_units.map! { |na_unit| na_unit == na_left || na_unit == na_right ? na_merged : na_unit }
            end
        end

        def self.Na__Corners__Dot(na_a, na_b)
            na_a.x * na_b.x + na_a.y * na_b.y + na_a.z * na_b.z
        end

        # FUNCTION | Oriented-Box Separating Axes Avoid False Bounding-Box Unions
        # ------------------------------------------------------------
        def self.Na__Corners__Overlap?(na_a, na_b)
            na_axes_a = [1,3,4].map { |na_index| (na_a[na_index] - na_a[0]).normalize }
            na_axes_b = [1,3,4].map { |na_index| (na_b[na_index] - na_b[0]).normalize }
            na_axes = na_axes_a + na_axes_b + na_axes_a.flat_map { |na_axis| na_axes_b.map { |na_other| na_axis.cross(na_other) } }
            na_axes.all? do |na_axis|
                next true if na_axis.length < 0.000001
                na_axis = na_axis.normalize
                na_range_a = na_a.map { |na_point| Na__Corners__Dot(na_point, na_axis) }.minmax
                na_range_b = na_b.map { |na_point| Na__Corners__Dot(na_point, na_axis) }.minmax
                [na_range_a.last, na_range_b.last].min - [na_range_a.first, na_range_b.first].max > 0.0001
            end
        end

    end # module Na__ArrayBuilder__CornerMerger
end # module Na__ArrayBuilderTools
