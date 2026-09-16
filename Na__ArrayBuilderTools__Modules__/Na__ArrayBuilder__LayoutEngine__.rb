# =============================================================================
# NA ARRAY BUILDER TOOLS - LAYOUT ENGINE
# =============================================================================
# FILE       : Na__ArrayBuilder__LayoutEngine__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : One layout and transform contract for preview and built geometry.
# =============================================================================

require_relative 'Na__ArrayBuilder__Configuration__'
require_relative 'Na__ArrayBuilder__Distribution__'
require_relative 'Na__ArrayBuilder__PathFromSelection__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__LayoutEngine

        # FUNCTION | Prepare a Validated Layout Before Any Model Mutation
        # ------------------------------------------------------------
        def self.Na__Layout__Resolve(na_config, na_points, na_source = nil)
            raise ArgumentError, 'The path exceeds 10,000 points. Simplify it before creating an array.' if na_points.length > 10_000
            na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_config)
            if na_config['type'] == 'object'
                unless na_source && na_source[:definition].valid? && na_source[:width] >= 0.1.mm
                    raise ArgumentError, 'Pick a source object with a width of at least 0.1 mm.'
                end
                %w[width depth height].each do |na_axis|
                    na_config["unit_#{na_axis}_mm"] = [na_source[na_axis.to_sym] * 25.4, 0.1].max
                end
            end
            na_path = na_points.each_with_object([]) do |na_point, na_clean|
                na_clean << na_point if na_clean.empty? || na_clean.last.distance(na_point) > 0.001
            end
            raise ArgumentError, 'Add at least two different path points.' if na_path.length < 2
            if na_config['reverse_path']
                na_path = Na__ArrayBuilder__PathFromSelection.Na__PathFromSelection__ReversePoints(
                    na_path, na_path.first.distance(na_path.last) < 0.001
                )
            end
            na_args = [na_path, na_config['distribution'], na_config['unit_width_mm'].mm,
                       na_config['spacing_mm'].mm, na_config['inset_mm'].mm]
            na_positions = Na__ArrayBuilder__Distribution.Na__Distribution__CalculatePositions(*na_args)
            na_gap = Na__ArrayBuilder__Distribution.Na__Distribution__CalculateActualSpacingMm(*na_args)
            {
                config: na_config, points: na_path, positions: na_positions, source: na_source,
                length_mm: na_path.each_cons(2).sum { |na_a, na_b| na_a.distance(na_b) * 25.4 },
                gap_mm: na_gap || na_config['spacing_mm']
            }
        end

        # FUNCTION | Right-Handed Frame, With Optional Upright Orientation
        # ------------------------------------------------------------
        def self.Na__Layout__Frame(na_position, na_config)
            na_forward = na_position[:direction].clone
            na_forward = Geom::Vector3d.new(na_forward.x, na_forward.y, 0) if na_config['keep_upright']
            na_forward = X_AXIS.clone if na_forward.length < 0.001
            na_forward.normalize!
            na_lateral = Z_AXIS.cross(na_forward)
            na_lateral = Y_AXIS.clone if na_lateral.length < 0.001
            na_lateral.normalize!
            na_up = na_forward.cross(na_lateral).normalize
            na_origin = na_position[:point].offset(na_lateral, na_config['offset_lateral_mm'].mm)
            na_origin = na_origin.offset(na_up, na_config['offset_vertical_mm'].mm)
            Geom::Transformation.axes(na_origin, na_forward, na_lateral, na_up)
        end

        # FUNCTION | Map Object Definition Coordinates Onto the Leading Face
        # ------------------------------------------------------------
        def self.Na__Layout__Transform(na_position, na_config, na_source = nil)
            na_frame = Na__Layout__Frame(na_position, na_config)
            return na_frame unless na_source
            na_scale = na_source[:scale]
            na_y = na_config['anchor_mode'] == 'centre' ? -na_source[:scaled_center].y : 0
            na_z = na_config['anchor_mode'] == 'centre' ? -na_source[:scaled_center].z : 0
            na_offset = Geom::Transformation.translation([-na_source[:scaled_min_x], na_y, na_z])
            na_frame * na_offset * Geom::Transformation.scaling(*na_scale)
        end

        # FUNCTION | Bounding Corners Using the Exact Geometry Transform
        # ------------------------------------------------------------
        def self.Na__Layout__Corners(na_position, na_config, na_source = nil)
            if na_source
                na_corners = [0, 1, 3, 2, 4, 5, 7, 6].map { |na_index| na_source[:definition].bounds.corner(na_index) }
            else
                na_w = na_config['unit_width_mm'].mm
                na_d = na_config['unit_depth_mm'].mm / 2.0
                na_h = na_config['unit_height_mm'].mm
                na_corners = [[0,-na_d,0], [na_w,-na_d,0], [na_w,na_d,0], [0,na_d,0],
                              [0,-na_d,na_h], [na_w,-na_d,na_h], [na_w,na_d,na_h], [0,na_d,na_h]].map { |na_point| Geom::Point3d.new(na_point) }
            end
            na_transform = Na__Layout__Transform(na_position, na_config, na_source)
            na_corners.map { |na_point| na_point.transform(na_transform) }
        end

    end # module Na__ArrayBuilder__LayoutEngine
end # module Na__ArrayBuilderTools
