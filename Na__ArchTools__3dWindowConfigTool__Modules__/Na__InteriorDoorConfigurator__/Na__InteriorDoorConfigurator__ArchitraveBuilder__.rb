# =============================================================================
# NA INTERIOR DOOR CONFIGURATOR - ARCHITRAVE BUILDER
# =============================================================================
#
# FILE       : Na__InteriorDoorConfigurator__ArchitraveBuilder__.rb
# NAMESPACE  : Na__InteriorDoorConfigurator
# MODULE     : Na__ArchitraveBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds the front and back architrave solids using a Follow Me
#              sweep around the door lining perimeter (top + jamb-L + jamb-R).
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Reads the architrave asset JSON from Na__AssetLibrary.
# - Builds a 3-segment perimeter path offset 5mm (configurable) around the
#   outside of the door lining: top run + left jamb + right jamb.
# - There is NO bottom architrave (UK convention).
# - The 2D profile is loaded from the asset's Na__Asset__Profile2D block
#   (vertices use PosY_mm / PosZ_mm authored on the local YZ plane).
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
require_relative 'Na__InteriorDoorConfigurator__DebugTools__'
require_relative 'Na__InteriorDoorConfigurator__GeometryHelpers__'
require_relative 'Na__InteriorDoorConfigurator__AssetLibrary__'
require_relative 'Na__InteriorDoorConfigurator__TagManager__'

module Na__InteriorDoorConfigurator
    module Na__ArchitraveBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__InteriorDoorConfigurator::Na__DebugTools
        GeometryHelpers = Na__InteriorDoorConfigurator::Na__GeometryHelpers
        AssetLibrary    = Na__InteriorDoorConfigurator::Na__AssetLibrary
        TagManager      = Na__InteriorDoorConfigurator::Na__TagManager

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
            unless profile_block
                DebugTools.na_debug_warn("Architrave asset missing Na__Asset__Profile2D - using fallback")
                return na_fallback_profile_points
            end

            vertex_records = profile_block["Na__Geometry__Vertices"] || []
            face_records   = profile_block["Na__Geometry__Faces"]    || []

            return na_fallback_profile_points if vertex_records.empty?

            indexed_points = na_build_indexed_point_table(vertex_records)
            outer_loop_ids = na_resolve_outer_loop_ids(face_records, vertex_records)

            ordered = outer_loop_ids.map { |vid| indexed_points[vid] }.compact
            return na_fallback_profile_points if ordered.length < 3
            ordered
        end
        private_class_method :na_extract_profile_points_mm
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
            face_offset_mm = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            arch_offset_mm = config["Na__DoorConfig__ArchitraveOffset_mm"].to_f
            arch_offset_mm = 5.0 if arch_offset_mm <= 0

            wrapper        = entities.add_group
            wrapper.name   = (side == :front) ? "Na__Architrave__Front" : "Na__Architrave__Back"
            wrapper_ents   = wrapper.entities

            ordered_path_pts = na_compute_perimeter_path_inches(opening_w_mm, opening_h_mm, arch_offset_mm, side, face_offset_mm, wall_depth_mm)
            return nil if ordered_path_pts.length < 2

            path_edges       = na_create_path_edges(wrapper_ents, ordered_path_pts)
            return nil if path_edges.empty?

            sweep_axis       = (side == :front) ? Z_AXIS.reverse : Z_AXIS                     # <-- Front profile mirrors Z so it projects outward
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
        # Three-segment polyline (5 vertices): bottom of left jamb, top of
        # left jamb, top of right jamb, bottom of right jamb. The path
        # leaves the bottom open (no architrave under the door).
        def self.na_compute_perimeter_path_inches(opening_w_mm, opening_h_mm, arch_offset_mm, side, face_offset_mm, wall_depth_mm)
            x_left_mm   = -arch_offset_mm
            x_right_mm  = opening_w_mm + arch_offset_mm
            z_bottom_mm = 0
            z_top_mm    = opening_h_mm + arch_offset_mm

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
        # Profile is authored on the local YZ plane (Y outward, Z forward).
        # We orient it perpendicular to the path tangent at the start:
        # * Path tangent at the start of the bottom-left -> top-left
        #   segment is +Z, so the profile face must lie in the XY plane.
        # * For the front face, the profile projects in -Y (outwards from
        #   the wall's front face); for the back face it projects in +Y.
        def self.na_create_profile_face(entities, profile_pts_mm, start_point, side, face_offset_mm, wall_depth_mm)
            mm = ->(v) { GeometryHelpers.na_mm_to_inch(v) }

            y_sign     = (side == :front) ? -1.0 : 1.0
            x_at_start = start_point.x
            z_at_start = start_point.z

            transformed_points = profile_pts_mm.map do |y_mm, z_mm|
                Geom::Point3d.new(
                    x_at_start + mm.call(y_mm) * 0.0,                                      # <-- Profile width does not move along path tangent at start
                    start_point.y + y_sign * mm.call(z_mm),                                # <-- Profile projection (Z field) lays along the wall normal
                    z_at_start - mm.call(y_mm)                                             # <-- Profile width (Y field) lays along negative Z so face stays oriented outward
                )
            end

            face = entities.add_face(transformed_points)
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
end # module Na__InteriorDoorConfigurator

# =============================================================================
# END OF FILE
# =============================================================================
