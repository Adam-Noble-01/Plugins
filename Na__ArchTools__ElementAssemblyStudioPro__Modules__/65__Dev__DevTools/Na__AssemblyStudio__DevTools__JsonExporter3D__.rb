# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DEV TOOLS - UNIFIED 2D + 3D ASSET JSON EXPORTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__DevTools__JsonExporter3D__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__DevTools
# MODULE     : Na__JsonExporter3D
# AUTHOR     : Noble Architecture
# PURPOSE    : Forked and moved from legacy Interior Door dev exporter
#              (pre-refactor Na__InteriorDoorConfigurator JSON exporter).
#              Exports a unified asset JSON containing optional Plan2D,
#              Elevation2D, Profile2D and Mesh3D blocks for handles,
#              architraves, hinges and any future asset type.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Selection requirements (in the active model):
#     * Exactly one Sketchup::Group named "00__OriginPoint" - its bounding
#       box centre defines local 0,0,0.
#     * Optionally one Sketchup::Group named "01__PlanView" containing
#       loose 2D edges/faces in the XY plane.
#     * Optionally one Sketchup::Group named "02__ElevationView" containing
#       loose 2D edges/faces in the XZ plane.
#     * Optionally one Sketchup::Group named "03__Model3D" containing the
#       3D mesh of the asset, expressed in the same XYZ frame.
#     * Optionally one Sketchup::Group named "04__Profile2D" for architrave
#       profiles (rich vertices/edges/faces in the YZ plane).
# - Output JSON structure (Na__Asset__* keys, three-stage column-aligned
#   style) - any block whose source group is missing is omitted, and the
#   matching Na__Asset__Has* flag is set to false.
#
#     {
#       "meta"                : { ... },
#       "Na__Asset__Metadata" : { ... },
#       "Na__Asset__Plan2D"      : { Paths, BoundingBox, ... },
#       "Na__Asset__Elevation2D" : { Paths, BoundingBox, ... },
#       "Na__Asset__Profile2D"   : { Vertices, Edges, Faces, ... },
#       "Na__Asset__Mesh3D"      : { Vertices, Faces, BoundingBox, ... }
#     }
#
# - Saves via UI.savepanel.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
# - Inner helpers are private_class_method so only na_run_export is public.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module Na__AssemblyStudio
module Na__DevTools
    module Na__JsonExporter3D

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM             = 25.4

        NA_GROUP_ORIGIN           = "00__OriginPoint".freeze
        NA_GROUP_PLAN             = "01__PlanView".freeze
        NA_GROUP_ELEVATION        = "02__ElevationView".freeze
        NA_GROUP_MODEL3D          = "03__Model3D".freeze
        NA_GROUP_PROFILE2D        = "04__Profile2D".freeze

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Single Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the Unified Asset Exporter
        # ------------------------------------------------------------
        # Single public entry point. Bind to a UI button or call directly
        # from the Ruby Console:
        #     Na__DevTools::Na__JsonExporter3D.na_run_export
        def self.na_run_export
            model     = Sketchup.active_model
            selection = model.selection.to_a

            origin_group = na_find_named_group(selection, NA_GROUP_ORIGIN)
            unless origin_group
                puts "\n!! Na__JsonExporter3D : No group named '#{NA_GROUP_ORIGIN}' found in selection."
                return
            end
            origin_pt = origin_group.bounds.center

            plan_block       = na_extract_plan_block(selection, origin_pt)
            elevation_block  = na_extract_elevation_block(selection, origin_pt)
            profile_block    = na_extract_profile_block(selection, origin_pt)
            mesh_block       = na_extract_mesh_block(selection, origin_pt)

            metadata = na_build_metadata_placeholder(
                :has_plan      => !plan_block.nil?,
                :has_elevation => !elevation_block.nil?,
                :has_profile   => !profile_block.nil?,
                :has_3d        => !mesh_block.nil?
            )

            full_document = {
                "meta"                  => na_build_meta_block,
                "Na__Asset__Metadata"   => metadata
            }
            full_document["Na__Asset__Plan2D"]      = plan_block      if plan_block
            full_document["Na__Asset__Elevation2D"] = elevation_block if elevation_block
            full_document["Na__Asset__Profile2D"]   = profile_block   if profile_block
            full_document["Na__Asset__Mesh3D"]      = mesh_block      if mesh_block

            json_string = na_serialize_root(full_document)

            na_print_to_console(json_string)
            na_save_to_disk(json_string)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find a Group in the Selection Matching a Name or Tag
        # ------------------------------------------------------------
        def self.na_find_named_group(selection, target_name)
            selection.find do |entity|
                entity.is_a?(Sketchup::Group) &&
                    (entity.name == target_name ||
                     (entity.respond_to?(:layer) && entity.layer && entity.layer.name == target_name))
            end
        end
        private_class_method :na_find_named_group
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | 2D Plan / Elevation Extraction
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Extract the 2D Plan Block (XY Plane, Z Discarded)
        # ------------------------------------------------------------
        def self.na_extract_plan_block(selection, origin_pt)
            group = na_find_named_group(selection, NA_GROUP_PLAN)
            return nil unless group

            edges, faces = na_collect_edges_and_faces(group.entities)
            arcs, arc_ids = na_extract_arcs_xy(edges, origin_pt)
            lines         = na_extract_lines_xy(edges, origin_pt, arc_ids)
            polygons      = na_extract_faces_xy(faces, origin_pt)
            bbox          = na_calc_bbox_xy(arcs, lines, polygons)

            {
                "Na__Geometry__OriginNote"   => "Local 0,0 = centre of 00__OriginPoint group; XY plane.",
                "Na__Geometry__CoordSystem"  => "X=right, Y=up | Units=mm | Z discarded",
                "Na__Geometry__BoundingBox"  => bbox,
                "Na__Geometry__EdgeCount"    => edges.size,
                "Na__Geometry__ArcCount"     => arcs.size,
                "Na__Geometry__LineCount"    => lines.size,
                "Na__Geometry__PolygonCount" => polygons.size,
                "Na__Geometry__Paths"        => polygons + arcs + lines
            }
        end
        private_class_method :na_extract_plan_block
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract the 2D Elevation Block (XZ Plane, Y Discarded)
        # ------------------------------------------------------------
        def self.na_extract_elevation_block(selection, origin_pt)
            group = na_find_named_group(selection, NA_GROUP_ELEVATION)
            return nil unless group

            edges, faces = na_collect_edges_and_faces(group.entities)
            arcs, arc_ids = na_extract_arcs_xz(edges, origin_pt)
            lines         = na_extract_lines_xz(edges, origin_pt, arc_ids)
            polygons      = na_extract_faces_xz(faces, origin_pt)
            bbox          = na_calc_bbox_xz(arcs, lines, polygons)

            {
                "Na__Geometry__OriginNote"   => "Local 0,0 = centre of 00__OriginPoint group; XZ plane.",
                "Na__Geometry__CoordSystem"  => "X=right, Z=up | Units=mm | Y discarded",
                "Na__Geometry__BoundingBox"  => bbox,
                "Na__Geometry__EdgeCount"    => edges.size,
                "Na__Geometry__ArcCount"     => arcs.size,
                "Na__Geometry__LineCount"    => lines.size,
                "Na__Geometry__PolygonCount" => polygons.size,
                "Na__Geometry__Paths"        => polygons + arcs + lines
            }
        end
        private_class_method :na_extract_elevation_block
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract the 2D Profile Block (YZ Plane, Architrave-style)
        # ------------------------------------------------------------
        # Profile blocks are stored as rich vertex/edge/face indices to
        # match the Profile Path Tracer's authoring format.
        def self.na_extract_profile_block(selection, origin_pt)
            group = na_find_named_group(selection, NA_GROUP_PROFILE2D)
            return nil unless group

            edges, faces = na_collect_edges_and_faces(group.entities)

            vertex_table = {}
            vertices_out = []
            edges.each do |edge|
                [edge.start, edge.end].each do |vertex|
                    next if vertex_table.key?(vertex.object_id)
                    pos     = vertex.position
                    pos_y   = ((pos.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
                    pos_z   = ((pos.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
                    vid     = "V%03d" % (vertices_out.length + 1)
                    vertex_table[vertex.object_id] = vid
                    vertices_out << { "VertexId" => vid, "PosY_mm" => pos_y, "PosZ_mm" => pos_z }
                end
            end

            edges_out = []
            edges.each_with_index do |edge, idx|
                eid = "E%03d" % (idx + 1)
                edges_out << {
                    "EdgeId"        => eid,
                    "StartVertex"   => vertex_table[edge.start.object_id],
                    "EndVertex"     => vertex_table[edge.end.object_id]
                }
            end

            faces_out = []
            faces.each_with_index do |face, idx|
                fid     = "F%03d" % (idx + 1)
                loop_v  = face.outer_loop.vertices.map { |v| vertex_table[v.object_id] }.compact
                faces_out << { "FaceId" => fid, "OuterLoopVertices" => loop_v }
            end

            {
                "Na__Geometry__OriginNote"   => "Local 0,0 = inner-bottom corner; profile authored in YZ plane.",
                "Na__Geometry__CoordSystem"  => "Y=horizontal width, Z=projection | Units=mm",
                "Na__Geometry__Vertices"     => vertices_out,
                "Na__Geometry__Edges"        => edges_out,
                "Na__Geometry__Faces"        => faces_out
            }
        end
        private_class_method :na_extract_profile_block
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | 3D Mesh Extraction
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Extract the 3D Mesh Block (Indexed Vertices + Triangles)
        # ------------------------------------------------------------
        def self.na_extract_mesh_block(selection, origin_pt)
            group = na_find_named_group(selection, NA_GROUP_MODEL3D)
            return nil unless group

            faces        = na_collect_faces_recursively(group.entities)
            return nil if faces.empty?

            vertex_table = {}
            vertices_out = []
            faces_out    = []

            faces.each do |face|
                outer_indices = face.outer_loop.vertices.map do |v|
                    pos = v.position
                    key = [pos.x, pos.y, pos.z]
                    if vertex_table.key?(key)
                        vertex_table[key]
                    else
                        idx = vertices_out.length
                        vertex_table[key] = idx
                        vertices_out << {
                            "PosX_mm" => ((pos.x - origin_pt.x) * NA_INCH_TO_MM).round(3),
                            "PosY_mm" => ((pos.y - origin_pt.y) * NA_INCH_TO_MM).round(3),
                            "PosZ_mm" => ((pos.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
                        }
                        idx
                    end
                end
                faces_out << { "VertexIndices" => outer_indices }
            end

            bbox = na_calc_bbox_xyz(vertices_out)

            {
                "Na__Geometry__OriginNote"  => "Local 0,0,0 = centre of 00__OriginPoint group.",
                "Na__Geometry__CoordSystem" => "Right-handed | X=right, Y=front, Z=up | Units=mm",
                "Na__Geometry__BoundingBox" => bbox,
                "Na__Geometry__VertexCount" => vertices_out.size,
                "Na__Geometry__FaceCount"   => faces_out.size,
                "Na__Geometry__Vertices"    => vertices_out,
                "Na__Geometry__Faces"       => faces_out
            }
        end
        private_class_method :na_extract_mesh_block
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Geometry Collection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect Loose Edges and Faces in a Container
        # ------------------------------------------------------------
        def self.na_collect_edges_and_faces(entities)
            edges = []
            faces = []
            entities.each do |entity|
                edges << entity if entity.is_a?(Sketchup::Edge)
                faces << entity if entity.is_a?(Sketchup::Face)
            end
            [edges, faces]
        end
        private_class_method :na_collect_edges_and_faces
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Recursively Collect Faces from Nested Groups/Components
        # ------------------------------------------------------------
        def self.na_collect_faces_recursively(entities)
            faces = []
            entities.each do |entity|
                if entity.is_a?(Sketchup::Face)
                    faces << entity
                elsif entity.is_a?(Sketchup::Group)
                    faces.concat(na_collect_faces_recursively(entity.entities))
                elsif entity.is_a?(Sketchup::ComponentInstance)
                    faces.concat(na_collect_faces_recursively(entity.definition.entities))
                end
            end
            faces
        end
        private_class_method :na_collect_faces_recursively
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | XY Plane Extractors (Plan View)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | XY Point in MM
        # ------------------------------------------------------------
        def self.na_pt_xy_mm(pt, origin_pt)
            {
                "X_mm" => ((pt.x - origin_pt.x) * NA_INCH_TO_MM).round(3),
                "Y_mm" => ((pt.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
            }
        end
        private_class_method :na_pt_xy_mm
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Arcs from Edges (XY)
        # ------------------------------------------------------------
        def self.na_extract_arcs_xy(edges, origin_pt)
            seen = {}
            arcs = []
            edges.each do |edge|
                curve = edge.curve
                next unless curve.is_a?(Sketchup::ArcCurve)
                next if seen[curve.object_id]
                seen[curve.object_id] = true

                arcs << na_arc_to_hash(curve, origin_pt, :xy)
            end
            [arcs, seen]
        end
        private_class_method :na_extract_arcs_xy
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Lines from Edges (XY)
        # ------------------------------------------------------------
        def self.na_extract_lines_xy(edges, origin_pt, arc_ids)
            lines = []
            edges.each do |edge|
                curve = edge.curve
                next if curve.is_a?(Sketchup::ArcCurve) && arc_ids[curve.object_id]
                lines << {
                    "PathType"   => "Line",
                    "VertexName" => "",
                    "Start_mm"   => na_pt_xy_mm(edge.start.position, origin_pt),
                    "End_mm"     => na_pt_xy_mm(edge.end.position, origin_pt)
                }
            end
            lines
        end
        private_class_method :na_extract_lines_xy
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Polygons from Faces (XY)
        # ------------------------------------------------------------
        def self.na_extract_faces_xy(faces, origin_pt)
            polygons = []
            faces.each do |face|
                vertices = face.outer_loop.vertices.map { |v| na_pt_xy_mm(v.position, origin_pt) }
                polygons << {
                    "PathType"    => "Polygon",
                    "VertexName"  => "",
                    "Vertices_mm" => vertices
                }
            end
            polygons
        end
        private_class_method :na_extract_faces_xy
        # ---------------------------------------------------------------

        # SUB FUNCTION | Calculate Bounding Box (XY)
        # ------------------------------------------------------------
        def self.na_calc_bbox_xy(arcs, lines, polygons)
            xs = []
            ys = []
            lines.each do |l|
                xs << l["Start_mm"]["X_mm"] << l["End_mm"]["X_mm"]
                ys << l["Start_mm"]["Y_mm"] << l["End_mm"]["Y_mm"]
            end
            arcs.each do |a|
                cx = a["Center_mm"]["X_mm"]; cy = a["Center_mm"]["Y_mm"]; r = a["Radius_mm"]
                xs << (cx - r) << (cx + r)
                ys << (cy - r) << (cy + r)
            end
            polygons.each do |p|
                p["Vertices_mm"].each { |v| xs << v["X_mm"]; ys << v["Y_mm"] }
            end
            return {} if xs.empty?
            na_bbox_2d_hash(xs, ys, "X", "Y")
        end
        private_class_method :na_calc_bbox_xy
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | XZ Plane Extractors (Elevation View)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | XZ Point in MM
        # ------------------------------------------------------------
        def self.na_pt_xz_mm(pt, origin_pt)
            {
                "X_mm" => ((pt.x - origin_pt.x) * NA_INCH_TO_MM).round(3),
                "Z_mm" => ((pt.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
            }
        end
        private_class_method :na_pt_xz_mm
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Arcs from Edges (XZ)
        # ------------------------------------------------------------
        def self.na_extract_arcs_xz(edges, origin_pt)
            seen = {}
            arcs = []
            edges.each do |edge|
                curve = edge.curve
                next unless curve.is_a?(Sketchup::ArcCurve)
                next if seen[curve.object_id]
                seen[curve.object_id] = true
                arcs << na_arc_to_hash(curve, origin_pt, :xz)
            end
            [arcs, seen]
        end
        private_class_method :na_extract_arcs_xz
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Lines from Edges (XZ)
        # ------------------------------------------------------------
        def self.na_extract_lines_xz(edges, origin_pt, arc_ids)
            lines = []
            edges.each do |edge|
                curve = edge.curve
                next if curve.is_a?(Sketchup::ArcCurve) && arc_ids[curve.object_id]
                lines << {
                    "PathType"   => "Line",
                    "VertexName" => "",
                    "Start_mm"   => na_pt_xz_mm(edge.start.position, origin_pt),
                    "End_mm"     => na_pt_xz_mm(edge.end.position, origin_pt)
                }
            end
            lines
        end
        private_class_method :na_extract_lines_xz
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Polygons from Faces (XZ)
        # ------------------------------------------------------------
        def self.na_extract_faces_xz(faces, origin_pt)
            polygons = []
            faces.each do |face|
                vertices = face.outer_loop.vertices.map { |v| na_pt_xz_mm(v.position, origin_pt) }
                polygons << {
                    "PathType"    => "Polygon",
                    "VertexName"  => "",
                    "Vertices_mm" => vertices
                }
            end
            polygons
        end
        private_class_method :na_extract_faces_xz
        # ---------------------------------------------------------------

        # SUB FUNCTION | Calculate Bounding Box (XZ)
        # ------------------------------------------------------------
        def self.na_calc_bbox_xz(arcs, lines, polygons)
            xs = []
            zs = []
            lines.each do |l|
                xs << l["Start_mm"]["X_mm"] << l["End_mm"]["X_mm"]
                zs << l["Start_mm"]["Z_mm"] << l["End_mm"]["Z_mm"]
            end
            arcs.each do |a|
                cx = a["Center_mm"]["X_mm"]; cz = a["Center_mm"]["Z_mm"]; r = a["Radius_mm"]
                xs << (cx - r) << (cx + r)
                zs << (cz - r) << (cz + r)
            end
            polygons.each do |p|
                p["Vertices_mm"].each { |v| xs << v["X_mm"]; zs << v["Z_mm"] }
            end
            return {} if xs.empty?
            na_bbox_2d_hash(xs, zs, "X", "Z")
        end
        private_class_method :na_calc_bbox_xz
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Generic Helpers (Bounding Box / Arc Hash)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert an ArcCurve to a Plain Hash
        # ------------------------------------------------------------
        def self.na_arc_to_hash(curve, origin_pt, plane)
            ctr_inch  = curve.center
            radius_mm = (curve.radius * NA_INCH_TO_MM).round(3)
            xaxis     = curve.xaxis
            base_ang  = Math.atan2(xaxis.y, xaxis.x)
            start_rad = base_ang + curve.start_angle
            end_rad   = base_ang + curve.end_angle

            if curve.circular? && (end_rad - start_rad) > (2 * Math::PI + 0.001)
                end_rad = start_rad + (2 * Math::PI)
            end

            start_deg = (start_rad * 180.0 / Math::PI).round(3)
            end_deg   = (end_rad   * 180.0 / Math::PI).round(3)

            ctr_hash =
                if plane == :xy
                    na_pt_xy_mm(ctr_inch, origin_pt)
                else
                    na_pt_xz_mm(ctr_inch, origin_pt)
                end

            start_pt =
                if plane == :xy
                    na_pt_xy_mm(curve.edges.first.start.position, origin_pt)
                else
                    na_pt_xz_mm(curve.edges.first.start.position, origin_pt)
                end

            end_pt =
                if plane == :xy
                    na_pt_xy_mm(curve.edges.last.end.position, origin_pt)
                else
                    na_pt_xz_mm(curve.edges.last.end.position, origin_pt)
                end

            {
                "PathType"        => curve.circular? ? "Circle" : "Arc",
                "VertexName"      => "",
                "Center_mm"       => ctr_hash,
                "Radius_mm"       => radius_mm,
                "StartAngle_deg"  => start_deg,
                "EndAngle_deg"    => end_deg,
                "Sweep_deg"       => (end_deg - start_deg).round(3),
                "StartPoint_mm"   => start_pt,
                "EndPoint_mm"     => end_pt,
                "IsCircle"        => curve.circular?
            }
        end
        private_class_method :na_arc_to_hash
        # ---------------------------------------------------------------

        # HELPER FUNCTION | 2D Bounding-Box Hash (Parametric Axis Labels)
        # ------------------------------------------------------------
        def self.na_bbox_2d_hash(values_a, values_b, label_a, label_b)
            {
                "Min#{label_a}_mm" => values_a.min.round(3),
                "Max#{label_a}_mm" => values_a.max.round(3),
                "Min#{label_b}_mm" => values_b.min.round(3),
                "Max#{label_b}_mm" => values_b.max.round(3),
                "Width_mm"         => (values_a.max - values_a.min).round(3),
                "Height_mm"        => (values_b.max - values_b.min).round(3)
            }
        end
        private_class_method :na_bbox_2d_hash
        # ---------------------------------------------------------------

        # HELPER FUNCTION | 3D Bounding Box Across Vertex Hashes
        # ------------------------------------------------------------
        def self.na_calc_bbox_xyz(vertices)
            return {} if vertices.empty?
            xs = vertices.map { |v| v["PosX_mm"] }
            ys = vertices.map { |v| v["PosY_mm"] }
            zs = vertices.map { |v| v["PosZ_mm"] }
            {
                "MinX_mm"   => xs.min.round(3),
                "MaxX_mm"   => xs.max.round(3),
                "MinY_mm"   => ys.min.round(3),
                "MaxY_mm"   => ys.max.round(3),
                "MinZ_mm"   => zs.min.round(3),
                "MaxZ_mm"   => zs.max.round(3),
                "Width_mm"  => (xs.max - xs.min).round(3),
                "Depth_mm"  => (ys.max - ys.min).round(3),
                "Height_mm" => (zs.max - zs.min).round(3)
            }
        end
        private_class_method :na_calc_bbox_xyz
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Metadata Placeholder Builders
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the meta Block (File-Level Metadata)
        # ------------------------------------------------------------
        def self.na_build_meta_block
            {
                "fileName"    => "",
                "description" => "Unified asset file exported by Na__DevTools::Na__JsonExporter3D.",
                "author"      => "Noble Architecture",
                "version"     => "1.0.0",
                "createdDate" => Time.now.strftime("%Y-%m-%d")
            }
        end
        private_class_method :na_build_meta_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Na__Asset__Metadata Block (Placeholders + Flags)
        # ------------------------------------------------------------
        def self.na_build_metadata_placeholder(opts)
            has_plan      = opts[:has_plan]      ? true : false
            has_elevation = opts[:has_elevation] ? true : false
            has_profile   = opts[:has_profile]   ? true : false
            has_3d        = opts[:has_3d]        ? true : false
            {
                "Na__Asset__Name"                  => "",
                "Na__Asset__Type"                  => "",
                "Na__Asset__Description"           => "",
                "Na__Asset__Notes"                 => "",
                "Na__Asset__Has2dPlan"             => has_plan,
                "Na__Asset__Has2dElevation"        => has_elevation,
                "Na__Asset__Has2dProfile"          => has_profile,
                "Na__Asset__Has3d"                 => has_3d,
                "Na__Asset__Supplier"              => "",
                "Na__Asset__SupplierProductCode"   => "",
                "Na__Asset__SupplierPrice__GBP"    => "",
                "Na__PanelPlacement__DefaultHeight_mm" => nil,
                "Na__PanelPlacement__RightHand"        => {
                    "Na__PanelPlacement__OffsetX_mm" => nil,
                    "Na__PanelPlacement__OffsetY_mm" => nil,
                    "Na__PanelPlacement__ScaleX"     => nil
                },
                "Na__PanelPlacement__LeftHand"         => {
                    "Na__PanelPlacement__OffsetX_mm" => nil,
                    "Na__PanelPlacement__OffsetY_mm" => nil,
                    "Na__PanelPlacement__ScaleX"     => nil
                },
                "Na__Asset__AvailableFinishes"     => []
            }
        end
        private_class_method :na_build_metadata_placeholder
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Column-Aligned JSON Pretty-Printer (3-Stage Style)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Indent for a Given Depth
        # ------------------------------------------------------------
        def self.na_indent(depth)
            return ""    if depth < 1
            return "  "  if depth == 1
            " " * (4 * (depth - 1))
        end
        private_class_method :na_indent
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Format a Scalar Value
        # ------------------------------------------------------------
        def self.na_scalar(value)
            case value
            when NilClass    then "null"
            when TrueClass   then "true"
            when FalseClass  then "false"
            when Float
                value.nan? || value.infinite? ? "null" : value.to_json
            else
                value.to_json
            end
        end
        private_class_method :na_scalar
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Padded Key + " : " for Column Alignment
        # ------------------------------------------------------------
        def self.na_padded_key(key, column_width)
            kjs = key.to_json
            pad = [0, column_width - kjs.length].max
            "#{kjs}#{' ' * pad} : "
        end
        private_class_method :na_padded_key
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format One Key/Value Pair at a Given Depth
        # ------------------------------------------------------------
        def self.na_format_pair(key, value, depth, column_width)
            ind  = na_indent(depth)
            kcol = na_padded_key(key, column_width)
            case value
            when Hash
                return "#{ind}#{kcol}{}" if value.empty?
                body  = na_format_object_body(value, depth + 1)
                close = na_indent(depth)
                "#{ind}#{kcol}{\n#{body}\n#{close}}"
            when Array
                return "#{ind}#{kcol}[]" if value.empty?
                inner = na_format_array_body(value, depth)
                "#{ind}#{kcol}[\n#{inner}\n#{ind}]"
            else
                "#{ind}#{kcol}#{na_scalar(value)}"
            end
        end
        private_class_method :na_format_pair
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format Object Body
        # ------------------------------------------------------------
        def self.na_format_object_body(hash, depth)
            return "" if hash.empty?
            width = hash.keys.map { |k| k.to_json.length }.max
            hash.map { |k, v| na_format_pair(k, v, depth, width) }.join(",\n")
        end
        private_class_method :na_format_object_body
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format Array Body
        # ------------------------------------------------------------
        def self.na_format_array_body(arr, parent_depth)
            elem_depth = parent_depth + 1
            arr.map { |el| na_format_array_element(el, elem_depth) }.join(",\n")
        end
        private_class_method :na_format_array_body
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format One Array Element
        # ------------------------------------------------------------
        def self.na_format_array_element(element, depth)
            case element
            when Hash
                return "#{na_indent(depth)}{}" if element.empty?
                body = na_format_object_body(element, depth + 1)
                open = na_indent(depth)
                "#{open}{\n#{body}\n#{open}}"
            else
                "#{na_indent(depth)}#{na_scalar(element)}"
            end
        end
        private_class_method :na_format_array_element
        # ---------------------------------------------------------------

        # FUNCTION | Serialise the Root Hash to a Column-Aligned JSON String
        # ------------------------------------------------------------
        def self.na_serialize_root(root_hash)
            width = root_hash.keys.map { |k| k.to_json.length }.max
            parts = root_hash.map { |k, v| na_format_pair(k, v, 1, width) }
            "{\n#{parts.join(",\n")}\n}\n"
        end
        private_class_method :na_serialize_root
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Output Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Print the JSON to the Ruby Console
        # ------------------------------------------------------------
        def self.na_print_to_console(json_string)
            puts "\n" + ("=" * 70)
            puts "NA DEV TOOLS | UNIFIED 2D + 3D ASSET JSON OUTPUT"
            puts ("=" * 70)
            puts json_string
            puts ("=" * 70)
        end
        private_class_method :na_print_to_console
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Save the JSON String to Disk via Save Panel
        # ------------------------------------------------------------
        def self.na_save_to_disk(json_string)
            output_path = UI.savepanel(
                "Save Na Unified Asset JSON",
                "",
                "Na__Asset__Untitled__.json"
            )

            if output_path.nil?
                puts "\n>> Save cancelled. Copy the JSON from the console above."
                return
            end

            output_path += ".json" unless output_path.downcase.end_with?(".json")

            begin
                File.open(output_path, "w") { |f| f.write(json_string) }
                puts "\n>> Saved to : #{output_path}"
            rescue => e
                puts "\n!! File write failed : #{e.message}"
            end

            puts "\n>> Export complete."
        end
        private_class_method :na_save_to_disk
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__JsonExporter3D
end # module Na__DevTools
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
