# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DEV TOOLS - 2D CAD OBJECT JSON EXPORTER (ValeSpec Hardware Schema)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__DevTools__JsonExporter2D__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__DevTools
# MODULE     : Na__JsonExporter2D
# AUTHOR     : Noble Architecture
# PURPOSE    : Forked from ValeSpec__CadObjectBuilder__JsonExporter__.rb.
#              Exports selected SketchUp 2D linework / faces (loose edges +
#              faces in the XY plane) to a structured JSON file using the
#              original ValeSpec hardware-item schema.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Selection requirements:
#     * Loose edges and faces in the XY plane.
#     * Exactly one Sketchup::Group named or tagged "00__OriginPoint" - its
#       bounding box centre defines local 0,0.
# - Output JSON contains:
#     * ValeSpec__HardwareItemData  (placeholders, keys retained)
#     * HardwareItem__VectorData    (Paths, BoundingBox, counts)
# - Arcs and circles export as arc primitives (center, radius, angles).
# - Straight edges export as Line entries with Start_mm / End_mm.
# - Faces export as Polygon entries with the outer loop vertices.
# - Saves via UI.savepanel; also prints the JSON to the Ruby Console.
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
    module Na__JsonExporter2D

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Unit Conversion and Selection Tags
        # ------------------------------------------------------------
        NA_INCH_TO_MM             = 25.4
        NA_GROUP_ORIGIN           = "00__OriginPoint".freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Single Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the ValeSpec-Style 2D CAD Object Exporter
        # ------------------------------------------------------------
        # Single public entry point. Bind to a UI button or call directly
        # from the Ruby Console:
        #     Na__DevTools::Na__JsonExporter2D.na_run_export
        def self.na_run_export
            model      = Sketchup.active_model
            selection  = model.selection.to_a

            origin_group, error = na_validate_selection(selection)
            if error
                puts "\n!! Na__JsonExporter2D : #{error}"
                return
            end

            origin_pt = origin_group.bounds.center
            puts "\n>> Origin found  : #{origin_pt.x.round(4)}\", #{origin_pt.y.round(4)}\", #{origin_pt.z.round(4)}\" (inches)"

            loose_edges = selection.select { |e| e.is_a?(Sketchup::Edge) }
            loose_faces = selection.select { |e| e.is_a?(Sketchup::Face) }
            puts ">> Loose edges   : #{loose_edges.size}"
            puts ">> Loose faces   : #{loose_faces.size}"

            arcs, arc_curve_ids = na_extract_arcs(loose_edges, origin_pt)
            lines               = na_extract_lines(loose_edges, origin_pt, arc_curve_ids)
            polygons            = na_extract_faces(loose_faces, origin_pt)
            bbox                = na_calc_bbox(arcs, lines, polygons)

            arc_edge_count      = loose_edges.count { |e| e.curve.is_a?(Sketchup::ArcCurve) }
            straight_edge_count = loose_edges.size - arc_edge_count
            puts ">> Arcs/Circles  : #{arcs.size}  (from #{arc_edge_count} arc edges)"
            puts ">> Line segments : #{lines.size} (from #{straight_edge_count} straight edges)"
            puts ">> Polygons      : #{polygons.size} (from #{loose_faces.size} faces)"

            full_document = na_build_full_document(loose_edges, arcs, lines, polygons, bbox)
            json_str      = na_generate_full_document_json(full_document)

            na_print_to_console(json_str)
            na_save_to_disk(json_str)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Coordinate & Unit Conversion Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert a SketchUp Point3d to a Local MM Coordinate Hash
        # ---------------------------------------------------------------
        # Returns { "X" => float_mm, "Y" => float_mm } relative to the origin
        # point. The Z axis is intentionally discarded - all geometry is
        # treated as 2D XY linework.
        def self.na_pt_mm(pt, origin)
            {
                "X"  =>  ((pt.x - origin.x) * NA_INCH_TO_MM).round(3),
                "Y"  =>  ((pt.y - origin.y) * NA_INCH_TO_MM).round(3)
            }
        end
        private_class_method :na_pt_mm
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Processing & Validation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Validate Selection and Locate the Origin Group
        # ---------------------------------------------------------------
        # Returns [origin_group, nil] on success or [nil, error_string] on
        # failure.
        def self.na_validate_selection(selection)
            return [nil, "Nothing selected. Select loose edges + the 00__OriginPoint group."] if selection.empty?

            origin_group = selection.find do |e|
                e.is_a?(Sketchup::Group) &&
                    (e.name == NA_GROUP_ORIGIN ||
                     (e.respond_to?(:layer) && e.layer.name == NA_GROUP_ORIGIN))
            end

            return [nil, "No group named/tagged '#{NA_GROUP_ORIGIN}' found in selection."] unless origin_group

            [origin_group, nil]
        end
        private_class_method :na_validate_selection
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Geometry Extraction & Classification
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Extract Arc and Circle Curves from the Edge List
        # ---------------------------------------------------------------
        # Arcs are processed once regardless of how many segments make them.
        # Arc angles are converted from SketchUp's arc-local space to world
        # space degrees. Returns [arcs_array, seen_curve_ids_hash].
        def self.na_extract_arcs(edges, origin_pt)
            seen_curves = {}
            arcs        = []

            edges.each do |edge|
                curve = edge.curve
                next unless curve.is_a?(Sketchup::ArcCurve)
                next if seen_curves[curve.object_id]
                seen_curves[curve.object_id] = true

                ctr_mm    = na_pt_mm(curve.center, origin_pt)
                radius_mm = (curve.radius * NA_INCH_TO_MM).round(3)
                is_circle = curve.circular?

                xaxis           = curve.xaxis
                xaxis_angle_rad = Math.atan2(xaxis.y, xaxis.x)
                start_ang_rad   = xaxis_angle_rad + curve.start_angle
                end_ang_rad     = xaxis_angle_rad + curve.end_angle

                if is_circle && (end_ang_rad - start_ang_rad) > (2 * Math::PI + 0.001)
                    end_ang_rad = start_ang_rad + (2 * Math::PI)
                end

                start_deg = (start_ang_rad * 180.0 / Math::PI).round(3)
                end_deg   = (end_ang_rad   * 180.0 / Math::PI).round(3)
                sweep_deg = (end_deg - start_deg).round(3)

                start_pt_mm = na_pt_mm(curve.edges.first.start.position, origin_pt)
                end_pt_mm   = na_pt_mm(curve.edges.last.end.position,    origin_pt)

                arcs << {
                    "PathType"        => is_circle ? "Circle" : "Arc",
                    "VertexName"      => "",
                    "Center_mm"       => ctr_mm,
                    "Radius_mm"       => radius_mm,
                    "StartAngle_deg"  => start_deg,
                    "EndAngle_deg"    => end_deg,
                    "Sweep_deg"       => sweep_deg,
                    "StartPoint_mm"   => start_pt_mm,
                    "EndPoint_mm"     => end_pt_mm,
                    "IsCircle"        => is_circle
                }
            end

            [arcs, seen_curves]
        end
        private_class_method :na_extract_arcs
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Straight Line Segments from the Edge List
        # ---------------------------------------------------------------
        # Edges that belong to an already-handled ArcCurve are skipped.
        def self.na_extract_lines(edges, origin_pt, arc_curve_ids)
            lines = []

            edges.each do |edge|
                curve = edge.curve
                next if curve.is_a?(Sketchup::ArcCurve) && arc_curve_ids[curve.object_id]

                lines << {
                    "PathType"     => "Line",
                    "VertexName"   => "",
                    "Start_mm"     => na_pt_mm(edge.start.position, origin_pt),
                    "End_mm"       => na_pt_mm(edge.end.position,   origin_pt)
                }
            end

            lines
        end
        private_class_method :na_extract_lines
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Faces as Polygons (Outer Loop Only)
        # ---------------------------------------------------------------
        def self.na_extract_faces(faces, origin_pt)
            polygons = []
            faces.each do |face|
                vertices_mm = face.outer_loop.vertices.map do |v|
                    na_pt_mm(v.position, origin_pt)
                end
                polygons << {
                    "PathType"    => "Polygon",
                    "VertexName"  => "",
                    "Vertices_mm" => vertices_mm
                }
            end
            polygons
        end
        private_class_method :na_extract_faces
        # ---------------------------------------------------------------

        # SUB FUNCTION | Calculate Tight Bounding Box Across All Extracted Paths
        # ---------------------------------------------------------------
        # Arc bounding boxes use the conservative full-circle extent
        # (centre +/- radius) rather than tracing the arc sweep itself.
        def self.na_calc_bbox(arcs, lines, polygons)
            xs = []
            ys = []

            lines.each do |l|
                xs << l["Start_mm"]["X"] << l["End_mm"]["X"]
                ys << l["Start_mm"]["Y"] << l["End_mm"]["Y"]
            end

            arcs.each do |a|
                r  = a["Radius_mm"]
                cx = a["Center_mm"]["X"]
                cy = a["Center_mm"]["Y"]
                xs << (cx - r) << (cx + r)
                ys << (cy - r) << (cy + r)
            end

            polygons.each do |p|
                p["Vertices_mm"].each do |v|
                    xs << v["X"]
                    ys << v["Y"]
                end
            end

            return {} if xs.empty?

            min_x = xs.min.round(3)
            max_x = xs.max.round(3)
            min_y = ys.min.round(3)
            max_y = ys.max.round(3)

            {
                "MinX_mm"   => min_x,
                "MaxX_mm"   => max_x,
                "MinY_mm"   => min_y,
                "MaxY_mm"   => max_y,
                "Width_mm"  => (max_x - min_x).round(3),
                "Height_mm" => (max_y - min_y).round(3)
            }
        end
        private_class_method :na_calc_bbox
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Document Assembly
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Empty ValeSpec__HardwareItemData Placeholder
        # ---------------------------------------------------------------
        # Keys are retained so the consumer can fill them in later or merge
        # the file with metadata authored elsewhere.
        def self.na_empty_hardware_item_data_hash
            {
                "HardwareItem__Name"                =>  "",
                "HardwareItem__Code"                =>  "",
                "HardwareItem__Type"                =>  "",
                "HardwareItem__Description"         =>  "",
                "HardwareItem__Notes"               =>  "",
                "HardwareItem__DataFile"            =>  "",
                "HardwareItem__IsComplementary"     =>  false,
                "HardwareItem__Supplier"            =>  "",
                "HardwareItem__SupplierProductCode" =>  "",
                "HardwareItem__SupplierPrice__GBP"  =>  "",
                "HardwareItem__PanelPlacement"      =>  {
                    "DefaultHeightFromOrigin_mm" => nil,
                    "RightHand__Transform"       => {
                        "OffsetX_mm" => nil,
                        "OffsetY_mm" => nil,
                        "ScaleX"     => nil
                    },
                    "LeftHand__Transform"        => {
                        "OffsetX_mm" => nil,
                        "OffsetY_mm" => nil,
                        "ScaleX"     => nil
                    }
                },
                "HardwareItem__AvailableFinishes"   =>  []
            }
        end
        private_class_method :na_empty_hardware_item_data_hash
        # ---------------------------------------------------------------

        # FUNCTION | Assemble the Full Document Hash (Metadata + Vector Data)
        # ---------------------------------------------------------------
        def self.na_build_full_document(loose_edges, arcs, lines, polygons, bbox)
            all_paths = polygons + arcs + lines

            vector_block = {
                "OriginNote"   => "Local 0,0 = centre of 00__OriginPoint group (e.g. handle spindle). Right-hand orientation.",
                "CoordSystem"  => "XY plane | X=right, Y=up | Units=mm | Z discarded",
                "BoundingBox"  => bbox,
                "EdgeCount"    => loose_edges.size,
                "ArcCount"     => arcs.size,
                "LineCount"    => lines.size,
                "PolygonCount" => polygons.size,
                "Paths"        => all_paths
            }

            {
                "ValeSpec__HardwareItemData" => na_empty_hardware_item_data_hash,
                "HardwareItem__VectorData"   => vector_block
            }
        end
        private_class_method :na_build_full_document
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Custom JSON Pretty-Printer (Column-Aligned, ValeSpec Style)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Indent a Line at a Given Depth
        # ---------------------------------------------------------------
        # Depth 1 => 2 spaces; depth 2 => 4 spaces; depth >= 3 => 4 * (depth - 1).
        def self.na_indent_line(line_depth)
            return ''   if line_depth < 1
            return '  ' if line_depth == 1
            ' ' * (4 * (line_depth - 1))
        end
        private_class_method :na_indent_line
        # ---------------------------------------------------------------

        # HELPER FUNCTION | JSON Scalar Fragment (null, bool, number, string)
        # ---------------------------------------------------------------
        def self.na_json_scalar_fragment(value)
            case value
            when NilClass   then 'null'
            when TrueClass  then 'true'
            when FalseClass then 'false'
            when String     then value.to_json
            when Integer    then value.to_json
            when Float
                value.nan? || value.infinite? ? 'null' : value.to_json
            else
                value.to_json
            end
        end
        private_class_method :na_json_scalar_fragment
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Padded JSON Key + Space-Colon (Column-Aligned)
        # ---------------------------------------------------------------
        def self.na_key_colon_padded(key, key_column_width)
            kjs = key.to_json
            pad = [0, key_column_width - kjs.length].max
            "#{kjs}#{' ' * pad} : "
        end
        private_class_method :na_key_colon_padded
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format One Key-Value Pair at a Given Line Depth
        # ---------------------------------------------------------------
        def self.na_format_key_value_pair(key, value, key_line_depth, key_column_width)
            ind  = na_indent_line(key_line_depth)
            kcol = na_key_colon_padded(key, key_column_width)

            case value
            when Hash
                return "#{ind}#{kcol}{}" if value.empty?
                body  = na_format_object_body(value, key_line_depth + 1)
                close = na_indent_line(key_line_depth)
                "#{ind}#{kcol}{\n#{body}\n#{close}}"
            when Array
                return "#{ind}#{kcol}[]" if value.empty?
                inner = na_format_array_body(value, key_line_depth)
                "#{ind}#{kcol}[\n#{inner}\n#{ind}]"
            else
                "#{ind}#{kcol}#{na_json_scalar_fragment(value)}"
            end
        end
        private_class_method :na_format_key_value_pair
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format Object Interior (Comma-Separated Key Lines)
        # ---------------------------------------------------------------
        def self.na_format_object_body(hash, inner_key_line_depth)
            return '' if hash.empty?
            width = hash.keys.map { |k| k.to_json.length }.max
            pairs = []
            hash.each do |k, v|
                pairs << na_format_key_value_pair(k, v, inner_key_line_depth, width)
            end
            pairs.join(",\n")
        end
        private_class_method :na_format_object_body
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format Array Body (Objects / Scalars)
        # ---------------------------------------------------------------
        def self.na_format_array_body(arr, parent_key_line_depth)
            elem_open_depth = parent_key_line_depth + 1
            chunks          = arr.map { |el| na_format_array_element(el, elem_open_depth) }
            chunks.join(",\n")
        end
        private_class_method :na_format_array_body
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format One Array Element
        # ---------------------------------------------------------------
        def self.na_format_array_element(element, elem_line_depth)
            case element
            when Hash
                return "#{na_indent_line(elem_line_depth)}{}" if element.empty?
                body = na_format_object_body(element, elem_line_depth + 1)
                open = na_indent_line(elem_line_depth)
                "#{open}{\n#{body}\n#{open}}"
            else
                "#{na_indent_line(elem_line_depth)}#{na_json_scalar_fragment(element)}"
            end
        end
        private_class_method :na_format_array_element
        # ---------------------------------------------------------------

        # FUNCTION | Serialise Full Root Hash to ValeSpec-Indented JSON String
        # ---------------------------------------------------------------
        def self.na_generate_full_document_json(root_hash)
            width = root_hash.keys.map { |k| k.to_json.length }.max
            parts = []
            root_hash.each do |k, v|
                parts << na_format_key_value_pair(k, v, 1, width)
            end
            "{\n#{parts.join(",\n")}\n}\n"
        end
        private_class_method :na_generate_full_document_json
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Output Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Print the Generated JSON to the Ruby Console
        # ---------------------------------------------------------------
        def self.na_print_to_console(json_str)
            puts "\n" + ("=" * 70)
            puts "NA DEV TOOLS | 2D CAD OBJECT BUILDER - JSON OUTPUT"
            puts "=" * 70
            puts json_str
            puts "=" * 70
        end
        private_class_method :na_print_to_console
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Save the JSON to Disk via Save Panel
        # ---------------------------------------------------------------
        def self.na_save_to_disk(json_str)
            output_path = UI.savepanel(
                "Save Na 2D CAD Object JSON",
                "",
                "Na__CadObject__2D__Untitled__.json"
            )

            if output_path.nil?
                puts "\n>> Save cancelled. Copy the JSON from the console above."
                return
            end

            output_path += ".json" unless output_path.downcase.end_with?(".json")

            begin
                File.open(output_path, "w") { |f| f.write(json_str) }
                puts "\n>> Saved to : #{output_path}"
            rescue => file_err
                puts "\n!! File write failed : #{file_err.message}"
                puts "   (Copy the JSON from the console above instead)"
            end

            puts "\n>> Export complete."
        end
        private_class_method :na_save_to_disk
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__JsonExporter2D
end # module Na__DevTools
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
