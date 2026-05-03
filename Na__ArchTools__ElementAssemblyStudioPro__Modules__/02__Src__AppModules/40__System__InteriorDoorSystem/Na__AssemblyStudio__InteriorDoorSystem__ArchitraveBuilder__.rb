# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - ARCHITRAVE BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__ArchitraveBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__ArchitraveBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds the front and back architrave solids using a Follow Me
#              sweep around the door lining perimeter (top + jamb-L + jamb-R).
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Reads the architrave asset JSON from Na__AssetLibrary.
# - Builds a 3-segment perimeter path that traces the architrave's
#   INNER-EDGE corners offset from the LINING'S INNER FACES (UK
#   reveal detail). Default offset is 5mm (configurable via
#   Na__DoorConfig__ArchitraveOffset_mm); this offset is the strip
#   of lining inner face that remains visible past the architrave.
# - Path runs: bottom of left jamb -> top of left jamb -> top of
#   right jamb -> bottom of right jamb. There is NO bottom
#   architrave (UK convention - the path stays open at the floor).
# - The 2D profile is loaded primarily from the asset's
#   Na__Asset__Profile2D block (vertices use PosY_mm / PosZ_mm
#   authored on the local YZ plane). If Profile2D is missing,
#   Na__Asset__Plan2D polygon data is converted into profile points.
#   The profile face is built in the XY plane so it is perpendicular
#   to the +Z first-edge tangent of the path, keeping Follow Me
#   well-defined for the vertical jamb sweeps.
# - Mirrors the algorithm used by Na__ProfileTools__ProfilePathTracer's
#   GeometryBuilders.Na__Geometry__BuildProfileAlongPath but operates on
#   a caller-supplied entities collection (so the resulting solid lives
#   inside the door's ComponentDefinition, not at the model root).
# - Falls back to a primitive 70x22 chamfered profile if the asset cannot
#   be loaded, so the door always builds even when the library is missing.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__ArchitraveBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        AssetLibrary    = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary
        TagManager      = Na__AssemblyStudio::Na__AppUtils::Na__TagManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Fallback Profile (used when asset loading fails)
        # ------------------------------------------------------------
        # Simple 70mm wide x 22mm projection chamfered architrave.
        # Coordinates: Y (outward from lining) and Z (projection out of wall).
        NA_FALLBACK_PROFILE_VERTICES_MM = [
            [ 0,  0],
            [ 6, 16],
            [ 6, 22],
            [70, 22],
            [70,  0]
        ].freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build Front and Back Architraves Inside Target Entities
        # ------------------------------------------------------------
        # Adds two Follow-Me solids to the supplied entities collection
        # (one for the front face of the wall, one for the back face).
        # Each is grouped, named, and tagged with the :architrave role.
        #
        # @param config [Hash] Door configuration block
        # @param entities [Sketchup::Entities] Target entities (component def)
        # @param material [Sketchup::Material, nil] Optional architrave material
        # @return [Hash] { :front => Group, :back => Group } (either may be nil)
        def self.na_build_architraves(config, entities, material = nil)
            asset_key   = config["Na__DoorConfig__ArchitraveProfileKey"]
            asset       = AssetLibrary.na_load_architrave_asset(asset_key)
            profile_pts = na_extract_profile_points_mm(asset)

            front_enabled = config["Na__DoorConfig__ArchitraveFrontEnabled"] != false
            back_enabled  = config["Na__DoorConfig__ArchitraveBackEnabled"]  != false

            front_group = nil
            back_group  = nil

            front_group = na_build_single_architrave(config, entities, profile_pts, :front, material) if front_enabled
            back_group  = na_build_single_architrave(config, entities, profile_pts, :back,  material) if back_enabled

            { :front => front_group, :back => back_group }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Profile Extraction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Extract 2D Profile Points from Asset (or Fallback)
        # ------------------------------------------------------------
        # Returns an Array<[y_mm, z_mm]> describing the architrave outline
        # in the local profile YZ plane. Y runs outward from the lining,
        # Z runs forward into the room.
        #
        # @param asset [Hash, nil] Parsed unified asset JSON
        # @return [Array<Array<Numeric>>] Profile vertices in mm
        def self.na_extract_profile_points_mm(asset)
            return na_fallback_profile_points if asset.nil?

            profile_block = asset["Na__Asset__Profile2D"]
            if profile_block
                profile_points = na_extract_profile_points_from_profile2d(profile_block)
                return profile_points if profile_points
                DebugTools.na_debug_warn("Architrave asset has invalid Na__Asset__Profile2D - trying Na__Asset__Plan2D")
            end

            plan_block = asset["Na__Asset__Plan2D"]
            if plan_block
                plan_points = na_extract_profile_points_from_plan2d(plan_block)
                return plan_points if plan_points
                DebugTools.na_debug_warn("Architrave asset has invalid Na__Asset__Plan2D - using fallback")
            end

            DebugTools.na_debug_warn("Architrave asset has no usable Profile2D/Plan2D profile data - using fallback")
            na_fallback_profile_points
        end
        private_class_method :na_extract_profile_points_mm
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Extract Ordered Profile Points from Profile2D
        # ------------------------------------------------------------
        def self.na_extract_profile_points_from_profile2d(profile_block)
            vertex_records = profile_block["Na__Geometry__Vertices"] || []
            face_records   = profile_block["Na__Geometry__Faces"]    || []
            return nil if vertex_records.empty?

            indexed_points = na_build_indexed_point_table(vertex_records)
            outer_loop_ids = na_resolve_outer_loop_ids(face_records, vertex_records)
            ordered        = outer_loop_ids.map { |vid| indexed_points[vid] }.compact

            return nil if ordered.length < 3
            ordered
        end
        private_class_method :na_extract_profile_points_from_profile2d
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Extract Ordered Profile Points from Plan2D
        # ------------------------------------------------------------
        def self.na_extract_profile_points_from_plan2d(plan_block)
            path_records = plan_block["Na__Geometry__Paths"]
            return nil unless path_records.is_a?(Array) && !path_records.empty?

            vertices = na_find_plan2d_polygon_vertices(path_records)
            return nil unless vertices

            raw_points = vertices.map do |vertex|
                next nil unless vertex.is_a?(Hash)
                next nil unless vertex.key?("X") && vertex.key?("Y")
                [-(vertex["X"].to_f), -(vertex["Y"].to_f)]
            end.compact

            return nil if raw_points.length < 3
            normalized = na_normalize_plan2d_profile_points(raw_points)
            return nil if normalized.length < 3
            normalized
        end
        private_class_method :na_extract_profile_points_from_plan2d
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Find the First Polygon Vertex Set in Plan2D Paths
        # ------------------------------------------------------------
        def self.na_find_plan2d_polygon_vertices(path_records)
            path_records.each do |record|
                next unless record.is_a?(Hash)
                next unless record["PathType"].to_s.downcase == "polygon"
                vertices = record["Vertices_mm"]
                return vertices if vertices.is_a?(Array) && vertices.length >= 3
            end
            nil
        end
        private_class_method :na_find_plan2d_polygon_vertices
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Normalize Plan2D Points to Local Positive Space
        # ------------------------------------------------------------
        def self.na_normalize_plan2d_profile_points(raw_points)
            min_y = raw_points.map { |point| point[0] }.min || 0.0
            min_z = raw_points.map { |point| point[1] }.min || 0.0
            normalized = raw_points.map { |y_val, z_val| [y_val - min_y, z_val - min_z] }

            if normalized.length > 3 && na_points_equal?(normalized.first, normalized.last)
                normalized.pop
            end
            normalized
        end
        private_class_method :na_normalize_plan2d_profile_points
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Float-Safe 2D Point Equality
        # ------------------------------------------------------------
        def self.na_points_equal?(point_a, point_b, epsilon = 0.001)
            return false unless point_a.is_a?(Array) && point_b.is_a?(Array)
            return false unless point_a.length >= 2 && point_b.length >= 2
            (point_a[0] - point_b[0]).abs <= epsilon && (point_a[1] - point_b[1]).abs <= epsilon
        end
        private_class_method :na_points_equal?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build a VertexId -> [y_mm, z_mm] Lookup Hash
        # ------------------------------------------------------------
        def self.na_build_indexed_point_table(vertex_records)
            table = {}
            vertex_records.each do |vrec|
                next unless vrec.is_a?(Hash)
                vid = vrec["VertexId"]
                y   = vrec["PosY_mm"]
                z   = vrec["PosZ_mm"]
                next unless vid && y && z
                table[vid] = [y.to_f, z.to_f]
            end
            table
        end
        private_class_method :na_build_indexed_point_table
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Ordered Outer Loop Vertex IDs
        # ------------------------------------------------------------
        # Prefers the first face's OuterLoop_VertexIds. Falls back to the
        # raw vertex declaration order if no face is provided.
        def self.na_resolve_outer_loop_ids(face_records, vertex_records)
            if face_records && !face_records.empty?
                outer = face_records.first["OuterLoop_VertexIds"]
                return outer if outer.is_a?(Array) && !outer.empty?
            end
            vertex_records.map { |vrec| vrec["VertexId"] }
        end
        private_class_method :na_resolve_outer_loop_ids
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Fallback Profile Points (No Asset Available)
        # ------------------------------------------------------------
        def self.na_fallback_profile_points
            DebugTools.na_debug_architrave("Using fallback architrave profile (70x22 chamfered)")
            NA_FALLBACK_PROFILE_VERTICES_MM.dup
        end
        private_class_method :na_fallback_profile_points
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Single Architrave Builder
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Build a Single Architrave Solid (Front or Back)
        # ------------------------------------------------------------
        # @param config [Hash]
        # @param entities [Sketchup::Entities]
        # @param profile_pts_mm [Array<Array<Numeric>>] Local YZ profile
        # @param side [Symbol] :front or :back
        # @param material [Sketchup::Material, nil]
        # @return [Sketchup::Group, nil]
        def self.na_build_single_architrave(config, entities, profile_pts_mm, side, material)
            opening_w_mm   = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            opening_h_mm   = config["Na__DoorConfig__OpeningHeight_mm"].to_f
            wall_depth_mm  = config["Na__DoorConfig__WallDepth_mm"].to_f
            lining_t_mm    = config["Na__DoorConfig__LiningThickness_mm"].to_f
            face_offset_mm = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            arch_offset_mm = config["Na__DoorConfig__ArchitraveOffset_mm"].to_f
            arch_offset_mm = 5.0 if arch_offset_mm <= 0

            wrapper        = entities.add_group
            wrapper.name   = (side == :front) ? "Na__Architrave__Front" : "Na__Architrave__Back"
            wrapper_ents   = wrapper.entities

            ordered_path_pts = na_compute_perimeter_path_inches(opening_w_mm, opening_h_mm, lining_t_mm, arch_offset_mm, side, face_offset_mm, wall_depth_mm)
            return nil if ordered_path_pts.length < 2

            path_edges       = na_create_path_edges(wrapper_ents, ordered_path_pts)
            return nil if path_edges.empty?

            profile_face     = na_create_profile_face(wrapper_ents, profile_pts_mm, ordered_path_pts.first, side, face_offset_mm, wall_depth_mm)

            unless profile_face && profile_face.valid?
                DebugTools.na_debug_error("Architrave (#{side}): could not build profile face")
                wrapper.erase! if wrapper.valid?
                return nil
            end

            begin
                profile_face.followme(path_edges)
                wrapper_ents.erase_entities(profile_face) if profile_face.valid?
            rescue => e
                DebugTools.na_debug_error("Architrave (#{side}): Follow Me failed", e)
                wrapper.erase! if wrapper.valid?
                return nil
            end

            na_apply_material_to_group(wrapper, material) if material
            TagManager.na_apply_tag_to_entity(wrapper, :architrave)

            DebugTools.na_debug_architrave("Built architrave (#{side}) - #{path_edges.length} path edges")
            wrapper
        end
        private_class_method :na_build_single_architrave
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Compute the Perimeter Path Points (Inches)
        # ------------------------------------------------------------
        # Three-segment polyline (4 vertices, 3 edges): bottom of left
        # jamb, top of left jamb, top of right jamb, bottom of right
        # jamb. The path leaves the bottom open (no architrave under
        # the door - UK convention).
        #
        # The path traces the architrave inner-edge corners offset
        # from the LINING'S INNER FACES (UK reveal detail). The
        # offset is applied AWAY from the passage on every side, so
        # all three architrave outer edges end up the same distance
        # beyond the structural opening (profile_width - lining_t +
        # offset) and all three inner edges leave the same 'offset'
        # mm strip of lining inner face visible as a reveal:
        #   * Left jamb path x  = lining_t - offset
        #     (move from the left lining inner face TOWARD the wall
        #      = -X = subtract the offset)
        #   * Right jamb path x = (opening_w - lining_t) + offset
        #     (TOWARD the wall = +X for the right jamb = add)
        #   * Top path z        = (opening_h - lining_t) + offset
        #     (TOWARD the wall = +Z for the head = add the offset
        #      so the architrave bottom sits 'offset' mm above the
        #      head lining bottom face, NOT below it)
        #   * Bottom path z     = 0 (path stays open at the floor)
        def self.na_compute_perimeter_path_inches(opening_w_mm, opening_h_mm, lining_t_mm, arch_offset_mm, side, face_offset_mm, wall_depth_mm)
            x_left_mm   = lining_t_mm - arch_offset_mm
            x_right_mm  = (opening_w_mm - lining_t_mm) + arch_offset_mm
            z_bottom_mm = 0
            z_top_mm    = (opening_h_mm - lining_t_mm) + arch_offset_mm

            y_face_mm   = (side == :front) ? face_offset_mm : (face_offset_mm + wall_depth_mm)

            mm = ->(v) { GeometryHelpers.na_mm_to_inch(v) }

            [
                Geom::Point3d.new(mm.call(x_left_mm),  mm.call(y_face_mm), mm.call(z_bottom_mm)),
                Geom::Point3d.new(mm.call(x_left_mm),  mm.call(y_face_mm), mm.call(z_top_mm)),
                Geom::Point3d.new(mm.call(x_right_mm), mm.call(y_face_mm), mm.call(z_top_mm)),
                Geom::Point3d.new(mm.call(x_right_mm), mm.call(y_face_mm), mm.call(z_bottom_mm))
            ]
        end
        private_class_method :na_compute_perimeter_path_inches
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Create the Path Edges in the Wrapper Entities
        # ------------------------------------------------------------
        def self.na_create_path_edges(entities, ordered_points)
            edges = []
            (0...(ordered_points.length - 1)).each do |i|
                edge = entities.add_line(ordered_points[i], ordered_points[i + 1])
                edges << edge if edge
            end
            edges
        end
        private_class_method :na_create_path_edges
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Create the Profile Face at the Path Start
        # ------------------------------------------------------------
        # Profile is authored on the local YZ plane (Y = profile width
        # running outward from the lining, Z = profile depth running
        # forward into the room). Follow Me requires the face to lie
        # perpendicular to the path tangent at the start vertex:
        # * Path tangent at the bottom-left -> top-left segment is +Z,
        #   so the face must lie in the XY plane (constant Z).
        # * Profile width (Y field) -> -X so the architrave extends
        #   outward from the lining (away from the opening) at the
        #   left jamb start point.
        # * Profile depth (Z field) -> y_sign * Y so the front
        #   architrave projects in -Y (out of the wall front face)
        #   and the back architrave projects in +Y.
        # * The face normal is forced to align with the +Z path
        #   tangent so Follow Me extrudes a closed solid in both
        #   front and back copies.
        def self.na_create_profile_face(entities, profile_pts_mm, start_point, side, face_offset_mm, wall_depth_mm)
            mm = ->(v) { GeometryHelpers.na_mm_to_inch(v) }

            y_sign     = (side == :front) ? -1.0 : 1.0
            x_at_start = start_point.x
            z_at_start = start_point.z

            transformed_points = profile_pts_mm.map do |y_mm, z_mm|
                Geom::Point3d.new(
                    x_at_start - mm.call(y_mm),                                            # <-- Profile width (Y field) extends outward from the lining (-X at left jamb)
                    start_point.y + y_sign * mm.call(z_mm),                                # <-- Profile depth (Z field) projects forward (-Y front) or backward (+Y back)
                    z_at_start                                                             # <-- Face stays in the XY plane (perpendicular to +Z path tangent)
                )
            end

            face = entities.add_face(transformed_points)
            return face unless face && face.valid?
            face.reverse! if face.normal.dot(Z_AXIS) < 0                                    # <-- Align face normal with path tangent so Follow Me sweeps in +Z
            face
        end
        private_class_method :na_create_profile_face
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Recursively Apply Material to a Group
        # ------------------------------------------------------------
        def self.na_apply_material_to_group(group, material)
            return unless group && group.valid? && material

            group.entities.each do |ent|
                if ent.is_a?(Sketchup::Face)
                    ent.material      = material
                    ent.back_material = material
                elsif ent.is_a?(Sketchup::Group)
                    na_apply_material_to_group(ent, material)
                end
            end
        end
        private_class_method :na_apply_material_to_group
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArchitraveBuilder
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
