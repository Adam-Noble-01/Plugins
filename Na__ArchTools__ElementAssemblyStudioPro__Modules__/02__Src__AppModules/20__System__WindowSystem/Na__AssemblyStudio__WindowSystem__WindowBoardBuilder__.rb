# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - WINDOW BOARD BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__WindowBoardBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__WindowBoardBuilder
# PURPOSE    : Load window board nosing assets and build the internal window
#              board as one solid, sized to the window it sits under.
#
# DESCRIPTION:
# - Nosing assets live in 04__Data__AssetLibrary/Windows__WindowBoards__/ as
#   Na__Window__WindowBoard__Type-NN__<Name>__t<T>mm__.json. Each carries a
#   Na__Asset__Profile2D outer loop (Y back across the reveal, Z up, mm) whose
#   origin is the underside of the board on the wall face line.
# - Everything behind the origin is the reveal section. It is rebuilt at the
#   Reveal Depth, from the back of the frame to the wall face.
# - Everything in front of it is the nose. Its shape never changes; it slides
#   out or in with the Nosing Overhang, measured from the wall face to the tip.
# - Returned nosing (the default): the nose runs round both ends and back to
#   the wall, projecting one board thickness past each side of the reveal, with
#   a mitre at each front corner. The board is the reveal section and that U of
#   nosing as one solid: every face is laid out here and added directly, the
#   same shape a Follow Me sweep joined to the reveal gives, without relying on
#   Follow Me or Solid Tools inside the window definition.
# - Without returns the whole section is one extrusion and the ends are cut
#   square in line with the reveal.
# - The board sits under the frame: its top face is flush with the underside
#   of the frame (Z = 0 before the cill lift moves the whole window up).
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__ConfigLoader__'
require_relative 'Na__AssemblyStudio__WindowSystem__SashHornBuilder__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__WindowBoardBuilder

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        ConfigLoader    = Na__AssemblyStudio::Na__AppData::Na__ConfigLoader
        SashHornBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__SashHornBuilder                    # <-- Shares its soften and paint passes

        NA_ASSET_FILE_PREFIX  = 'Na__Window__WindowBoard__Type'.freeze
        NA_TYPE_COUNT         = 3
        NA_GROUP_NAME         = 'Na_WindowBoard'.freeze
        NA_MM_TO_INCH         = 1.0 / 25.4
        NA_DATUM_TOLERANCE_MM = 0.001
        NA_NOSE_CLEARANCE_MM  = 1.0                                                                    # <-- Flat kept in front of the wall face: a nose ON the wall line is degenerate
        NA_MIN_REVEAL_MM      = 1.0
        NA_SOFTEN_ANGLE_RAD   = 22.0 * Math::PI / 180.0
        NA_POINT_TOLERANCE_IN = 0.001

        # FUNCTION | Load All Window Board Assets for JS Preview Cache
        # ------------------------------------------------------------
        def self.na_load_all_assets
            (1..NA_TYPE_COUNT).each_with_object({}) do |type, assets|
                asset = na_load_asset(type)
                assets[type.to_s] = asset if asset
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Window Board Asset JSON
        # ------------------------------------------------------------
        def self.na_load_asset(type)
            path = na_asset_file_path(type)
            return nil unless path && File.exist?(path)

            JSON.parse(File.read(path, encoding: 'UTF-8'))
        rescue JSON::ParserError, SystemCallError, IOError => e
            DebugTools.na_debug_error("Failed to load window board asset #{type}", e)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Window Board Under a Window Frame
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Window definition entities
        # @param params   [Hash] GeometryEngine parsed params (inches)
        # @param material [Sketchup::Material, nil] Board finish (nil = Default)
        # @return [Sketchup::Group, nil] The board solid
        def self.na_build_window_board(entities, params, material)
            return nil unless params[:window_board_enabled]

            section = na_resolve_section(params[:window_board_nosing_type])
            unless section
                DebugTools.na_debug_warn("Window board skipped: nosing type #{params[:window_board_nosing_type]} has no usable profile")
                return nil
            end

            geometry = na_board_geometry(params, section)
            board = if geometry[:returns]
                na_build_returned_board(entities, geometry, material)
            else
                na_build_straight_board(entities, geometry, material)
            end

            DebugTools.na_debug_geometry(
                "Window board: nosing type #{params[:window_board_nosing_type]}, " \
                "reveal #{(geometry[:wall_face_y] - geometry[:frame_back_y]).to_mm.round}mm, " \
                "overhang #{geometry[:overhang].to_mm.round(1)}mm, returns #{geometry[:returns]}, " \
                "solid #{board ? board.manifold? : 'not built'}"
            )
            board
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve a Nosing Type Into Its Parametric Section
        # ------------------------------------------------------------
        # Splits the asset's profile at the wall face line. Returns, in mm:
        #   thickness    - underside to top face
        #   nose         - [[inset, height], ...] from the underside round to
        #                  the top face, inset measured back from the tip
        #   min_overhang - the nose depth plus NA_NOSE_CLEARANCE_MM. At the
        #                  bare nose depth the nose would start on the wall
        #                  face line and the returns fold to nothing there.
        def self.na_resolve_section(type)
            loop_mm = na_extract_outer_loop(na_load_asset(type))
            return nil unless loop_mm

            chain_mm = na_extract_nose_chain(loop_mm)
            return nil unless chain_mm

            heights  = loop_mm.map { |point| point[1] }
            bottom_z = heights.min
            tip_y    = chain_mm.map { |point| point[0] }.min
            nose     = chain_mm.map { |y_mm, z_mm| [y_mm - tip_y, z_mm - bottom_z] }

            {
                thickness:    heights.max - bottom_z,
                nose:         nose,
                min_overhang: nose.map(&:first).max + NA_NOSE_CLEARANCE_MM
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Ordered Profile Outer Loop (mm)
        # ------------------------------------------------------------
        def self.na_extract_outer_loop(asset)
            profile  = asset && asset['Na__Asset__Profile2D']
            vertices = profile && profile['Na__Geometry__Vertices']
            faces    = profile && profile['Na__Geometry__Faces']
            return nil unless vertices.is_a?(Array) && faces.is_a?(Array) && faces.first.is_a?(Hash)

            table = vertices.each_with_object({}) do |vertex, memo|
                next unless vertex.is_a?(Hash) && vertex['VertexId']
                memo[vertex['VertexId']] = [vertex['PosY_mm'].to_f, vertex['PosZ_mm'].to_f]
            end
            loop_ids = faces.first['OuterLoop_VertexIds'] || faces.first['OuterLoopVertices']          # <-- Assembly Studio key, then the Profile Path Tracer's own
            return nil unless loop_ids.is_a?(Array)

            loop_mm = loop_ids.map { |vertex_id| table[vertex_id] }.compact
            loop_mm.length >= 3 ? loop_mm : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract the Nose: the Loop Run in Front of the Wall Face
        # ------------------------------------------------------------
        # Returns the profile vertices with Y < 0, in loop order, running from
        # the underside round to the top face.
        def self.na_extract_nose_chain(loop_mm)
            in_front = loop_mm.map { |point| point[0] < -NA_DATUM_TOLERANCE_MM }
            start    = (0...loop_mm.length).find { |index| in_front[index] && !in_front[index - 1] }  # <-- index - 1 wraps to the last vertex
            return nil unless start

            chain = []
            index = start
            while in_front[index] && chain.length < loop_mm.length
                chain << loop_mm[index]
                index = (index + 1) % loop_mm.length
            end
            return nil if chain.length < 2

            chain.reverse! if chain.first[1] > chain.last[1]
            chain
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Board Geometry in Window Space (Inches)
        # ------------------------------------------------------------
        # X runs along the window, Y from the outside wall face into the room,
        # Z up. The reveal spans X 0..width and starts at the back of the frame.
        def self.na_board_geometry(params, section)
            mm           = NA_MM_TO_INCH
            thickness    = section[:thickness] * mm
            frame_back_y = params[:frame_wall_inset] + params[:frame_depth]
            reveal_depth = [params[:window_board_reveal_depth].to_f, NA_MIN_REVEAL_MM * mm].max
            overhang     = [params[:window_board_nosing_overhang].to_f, section[:min_overhang] * mm].max

            {
                width:             params[:width],
                frame_back_y:      frame_back_y,
                wall_face_y:       frame_back_y + reveal_depth,
                overhang:          overhang,
                thickness:         thickness,
                bottom_z:          -thickness,                                                         # <-- Top face flush with the frame underside
                returns:           params[:window_board_returns_enabled] != false,
                return_projection: thickness,                                                          # <-- Always one board thickness past each side
                nose:              section[:nose].map { |inset, height| [inset * mm, height * mm] }
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build a Board With Square Ends (No Returns)
        # ------------------------------------------------------------
        # The full section, reveal and nose together, extruded across the
        # reveal width.
        def self.na_build_straight_board(entities, geometry, material)
            group = entities.add_group
            group.name = NA_GROUP_NAME

            points = na_straight_section_points(geometry).map { |y_in, z_in| Geom::Point3d.new(0, y_in, z_in) }
            face   = group.entities.add_face(points)
            unless face && face.valid?
                entities.erase_entities(group)
                return nil
            end

            face.reverse! if face.normal.x < 0
            face.pushpull(geometry[:width], false)
            na_finish_board(group, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build a Board With the Nosing Returned Past the Reveal
        # ------------------------------------------------------------
        def self.na_build_returned_board(entities, geometry, material)
            group = entities.add_group
            group.name = NA_GROUP_NAME

            missing = na_returned_board_faces(geometry).count do |record|
                !na_add_oriented_face(group.entities, record)
            end
            DebugTools.na_debug_warn("Window board: #{missing} face(s) could not be added") if missing > 0

            na_finish_board(group, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lay Out Every Face of the Returned Board
        # ------------------------------------------------------------
        # Pure geometry, no SketchUp entities: [{ points:, outward: }, ...] in
        # window space (inches). Each nose vertex runs on a rail round the U:
        # out along the left return from the wall face, across the front, and
        # back along the right return. Rails sit one inset in from the tip line,
        # so neighbouring rails bound the nose strips and meet at the mitres.
        def self.na_returned_board_faces(geometry)
            width    = geometry[:width]
            back_y   = geometry[:frame_back_y]
            wall_y   = geometry[:wall_face_y]
            bottom_z = geometry[:bottom_z]
            top_z    = bottom_z + geometry[:thickness]
            nose     = geometry[:nose]
            rails    = nose.map { |inset, height| na_nose_rail(geometry, inset, bottom_z + height) }

            records = []
            nose.each_cons(2).with_index do |(lower, upper), index|
                normal_s, normal_z = na_profile_outward_normal(lower, upper)
                left_0, front_left_0, front_right_0, right_0 = rails[index]
                left_1, front_left_1, front_right_1, right_1 = rails[index + 1]
                records << na_face_record([left_0, front_left_0, front_left_1, left_1], [normal_s, 0.0, normal_z])                      # <-- Left return
                records << na_face_record([front_left_0, front_right_0, front_right_1, front_left_1], [0.0, -normal_s, normal_z])     # <-- Front
                records << na_face_record([front_right_0, right_0, right_1, front_right_1], [-normal_s, 0.0, normal_z])               # <-- Right return
            end

            records << na_face_record(na_plan_outline(geometry, nose.first[0], bottom_z), [0.0, 0.0, -1.0])                           # <-- Underside
            records << na_face_record(na_plan_outline(geometry, nose.last[0], top_z), [0.0, 0.0, 1.0])                                # <-- Top face
            records << na_face_record([[0.0, back_y, bottom_z], [width, back_y, bottom_z], [width, back_y, top_z], [0.0, back_y, top_z]], [0.0, -1.0, 0.0])    # <-- Against the frame
            records << na_face_record([[0.0, back_y, bottom_z], [0.0, wall_y, bottom_z], [0.0, wall_y, top_z], [0.0, back_y, top_z]], [-1.0, 0.0, 0.0])        # <-- Left reveal side
            records << na_face_record([[width, back_y, bottom_z], [width, wall_y, bottom_z], [width, wall_y, top_z], [width, back_y, top_z]], [1.0, 0.0, 0.0])  # <-- Right reveal side
            records << na_face_record([[0.0, wall_y, bottom_z]] + rails.map(&:first) + [[0.0, wall_y, top_z]], [0.0, -1.0, 0.0])                                # <-- Left return against the wall
            records << na_face_record([[width, wall_y, bottom_z]] + rails.map(&:last) + [[width, wall_y, top_z]], [0.0, -1.0, 0.0])                             # <-- Right return against the wall
            records.compact
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Nose Vertex's Rail Round the U
        # ------------------------------------------------------------
        # [left return at the wall, left mitre, right mitre, right return at
        # the wall] for a vertex set `inset` back from the tip.
        def self.na_nose_rail(geometry, inset, z_in)
            left_x  = -geometry[:return_projection] + inset
            right_x = geometry[:width] + geometry[:return_projection] - inset
            front_y = geometry[:wall_face_y] + geometry[:overhang] - inset
            wall_y  = geometry[:wall_face_y]

            [[left_x, wall_y, z_in], [left_x, front_y, z_in], [right_x, front_y, z_in], [right_x, wall_y, z_in]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plan Outline at One Height (Top Face or Underside)
        # ------------------------------------------------------------
        # The T of reveal section plus nosing, with the nosing edge set back by
        # the nose inset at that height.
        def self.na_plan_outline(geometry, inset, z_in)
            width   = geometry[:width]
            back_y  = geometry[:frame_back_y]
            wall_y  = geometry[:wall_face_y]
            left_x  = -geometry[:return_projection] + inset
            right_x = width + geometry[:return_projection] - inset
            front_y = wall_y + geometry[:overhang] - inset

            [[0.0, back_y], [width, back_y], [width, wall_y], [right_x, wall_y],
             [right_x, front_y], [left_x, front_y], [left_x, wall_y], [0.0, wall_y]].map { |x_in, y_in| [x_in, y_in, z_in] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Outward Normal of One Nose Edge in Profile Space
        # ------------------------------------------------------------
        # The nose runs underside to top with the board behind it, so the
        # outward side is the edge direction turned a quarter left: [inset, up].
        def self.na_profile_outward_normal(lower, upper)
            delta_inset  = upper[0] - lower[0]
            delta_height = upper[1] - lower[1]
            length       = Math.sqrt((delta_inset * delta_inset) + (delta_height * delta_height))
            return [0.0, 0.0] if length <= 0.0

            [-delta_height / length, delta_inset / length]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Face Record With Repeated Points Removed
        # ------------------------------------------------------------
        # A rail of zero length (overhang at its minimum) folds a quad to a
        # triangle; anything thinner than a triangle is dropped.
        def self.na_face_record(points, outward)
            kept = na_drop_repeated_points(points)
            kept.length >= 3 ? { points: kept, outward: outward } : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add One Face, Turned to Face Outward
        # ------------------------------------------------------------
        def self.na_add_oriented_face(entities, record)
            face = entities.add_face(record[:points].map { |x_in, y_in, z_in| Geom::Point3d.new(x_in, y_in, z_in) })
            return nil unless face && face.valid?

            face.reverse! if face.normal.dot(Geom::Vector3d.new(*record[:outward])) < 0
            face
        rescue ArgumentError => e
            DebugTools.na_debug_error('Window board: add_face refused a face', e)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Soften the Curved Nose and Apply the Board Finish
        # ------------------------------------------------------------
        def self.na_finish_board(group, material)
            return nil unless group && group.valid?

            SashHornBuilder.na_apply_material(group, material)
            SashHornBuilder.na_soften_smooth_edges_below_angle(group, NA_SOFTEN_ANGLE_RAD)
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Straight Board Section in the Plane X = 0 ([y, z], Inches)
        # ------------------------------------------------------------
        def self.na_straight_section_points(geometry)
            tip_y    = geometry[:wall_face_y] + geometry[:overhang]
            bottom_z = geometry[:bottom_z]
            nose     = geometry[:nose].map { |inset, height| [tip_y - inset, bottom_z + height] }

            na_drop_repeated_points(
                [[geometry[:frame_back_y], bottom_z]] + nose + [[geometry[:frame_back_y], bottom_z + geometry[:thickness]]]
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop Consecutive Repeated Points (2D or 3D)
        # ------------------------------------------------------------
        def self.na_drop_repeated_points(points)
            kept = points.each_with_object([]) do |point, memo|
                memo << point unless memo.last && na_points_match?(memo.last, point)
            end
            kept.pop if kept.length > 1 && na_points_match?(kept.first, kept.last)
            kept
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compare Two Points Within Tolerance
        # ------------------------------------------------------------
        def self.na_points_match?(point_a, point_b)
            point_a.zip(point_b).all? { |value_a, value_b| (value_a - value_b).abs <= NA_POINT_TOLERANCE_IN }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Asset File Path for a Nosing Type
        # ------------------------------------------------------------
        def self.na_asset_file_path(type)
            pattern = File.join(na_asset_folder, "#{NA_ASSET_FILE_PREFIX}-#{format('%02d', na_normalize_type(type))}__*.json")
            Dir.glob(pattern).sort.first
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Asset Folder
        # ------------------------------------------------------------
        def self.na_asset_folder
            root_folder  = ConfigLoader.na_get_or('04__Data__AssetLibrary', 'assetLibrary', 'rootFolder')
            board_folder = ConfigLoader.na_get_or('Windows__WindowBoards__', 'assetLibrary', 'window', 'windowBoards')
            modules_root = File.expand_path('../..', __dir__)
            File.join(modules_root, root_folder, board_folder)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Normalize Nosing Type
        # ------------------------------------------------------------
        def self.na_normalize_type(type)
            match = type.to_s.match(/(\d+)/)
            value = match ? match[1].to_i : 1
            value.clamp(1, NA_TYPE_COUNT)
        end
        # ---------------------------------------------------------------

    end
end
end

# =============================================================================
# END OF FILE
# =============================================================================
