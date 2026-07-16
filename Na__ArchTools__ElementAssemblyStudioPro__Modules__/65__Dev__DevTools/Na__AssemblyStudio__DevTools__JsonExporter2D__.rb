# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DEV TOOLS - 2D ASSET JSON EXPORTER (Na__ SCHEMA)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__DevTools__JsonExporter2D__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__DevTools
# MODULE     : Na__JsonExporter2D
# AUTHOR     : Noble Architecture
# PURPOSE    : Export selected 2D linework to the Na__ unified asset schema.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Selection requirements:
#     * Loose edges and faces in the XY plane.
#     * Exactly one Sketchup::Group named or tagged "00__OriginPoint".
# - Emits:
#     * meta
#     * Na__Asset__Metadata
#     * Na__Asset__Plan2D or Na__Asset__Elevation2D
# - Geometry key naming matches Na__StandardTemplate.json.
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

        NA_INCH_TO_MM               = 25.4
        NA_GROUP_ORIGIN             = "00__OriginPoint".freeze

        NA_MODE_PLAN                = "Plan2D".freeze
        NA_MODE_ELEVATION           = "Elevation2D".freeze
        NA_OUTPUT_FILENAME_PLAN     = "Na__Asset__Plan2D__Untitled__.json".freeze
        NA_OUTPUT_FILENAME_ELEV     = "Na__Asset__Elevation2D__Untitled__.json".freeze

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Single Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the Na__ 2D Asset Exporter
        # ------------------------------------------------------------
        # Returns a result hash (:status => :saved|:cancelled|:error,
        # :message => String, :path => optional String) on every code
        # path so callers (Settings tab) can show a real outcome instead
        # of assuming the export always succeeds.
        def self.na_run_export
            model      = Sketchup.active_model
            selection  = model.selection.to_a

            origin_group, error = na_validate_selection(selection)
            if error
                return na_report_and_return_error(error)
            end

            export_mode = na_resolve_export_mode
            unless export_mode
                puts "\n>> Export mode selection cancelled."
                return { :status => :cancelled, :message => "2D export cancelled." }
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

            full_document = na_build_full_document(export_mode, loose_edges, arcs, lines, polygons, bbox)
            json_str      = na_generate_full_document_json(full_document)

            na_print_to_console(json_str)
            na_save_to_disk(json_str, export_mode)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Report a Failure to Console + Screen and Return its Result
        # ------------------------------------------------------------
        # Selection/validation failures used to only `puts` to the Ruby
        # Console, which reads as a silent failure if nobody has it open.
        # UI.messagebox makes the failure visible immediately.
        def self.na_report_and_return_error(message)
            puts "\n!! Na__JsonExporter2D : #{message}"
            UI.messagebox("Na__ 2D Export failed:\n\n#{message}")
            { :status => :error, :message => message }
        end
        private_class_method :na_report_and_return_error
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Export Mode Resolver
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Ask User Whether this is Plan2D or Elevation2D
        # ---------------------------------------------------------------
        def self.na_resolve_export_mode
            prompts  = ["2D Block Type"]
            defaults = [NA_MODE_PLAN]
            lists    = ["#{NA_MODE_PLAN}|#{NA_MODE_ELEVATION}"]
            result   = UI.inputbox(prompts, defaults, lists, "Na 2D Export Mode")
            return nil unless result

            mode = result[0].to_s.strip
            return NA_MODE_ELEVATION if mode == NA_MODE_ELEVATION
            NA_MODE_PLAN
        end
        private_class_method :na_resolve_export_mode
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Coordinate & Unit Conversion Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert a SketchUp Point3d to Local XY Millimetres
        # ---------------------------------------------------------------
        def self.na_pt_mm(pt, origin)
            {
                "X"  => ((pt.x - origin.x) * NA_INCH_TO_MM).round(3),
                "Y"  => ((pt.y - origin.y) * NA_INCH_TO_MM).round(3)
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
        def self.na_validate_selection(selection)
            return [nil, "Nothing selected. Select loose edges + the 00__OriginPoint group."] if selection.empty?

            origin_group = selection.find do |e|
                e.is_a?(Sketchup::Group) &&
                    (e.name == NA_GROUP_ORIGIN ||
                     (e.respond_to?(:layer) && e.layer && e.layer.name == NA_GROUP_ORIGIN))
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

        # SUB FUNCTION | Extract Arc and Circle Curves from Edge List
        # ---------------------------------------------------------------
        def self.na_extract_arcs(edges, origin_pt)
            seen_curves = {}
            arcs        = []

            edges.each do |edge|
                curve = edge.curve
                next unless curve.is_a?(Sketchup::ArcCurve)
                next if seen_curves[curve.object_id]
                seen_curves[curve.object_id] = true

                center_mm = na_pt_mm(curve.center, origin_pt)
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
                end_pt_mm   = na_pt_mm(curve.edges.last.end.position, origin_pt)

                arcs << {
                    "PathType"        => is_circle ? "Circle" : "Arc",
                    "VertexName"      => "",
                    "Center_mm"       => center_mm,
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

        # SUB FUNCTION | Extract Straight Line Segments from Edge List
        # ---------------------------------------------------------------
        def self.na_extract_lines(edges, origin_pt, arc_curve_ids)
            lines = []
            edges.each do |edge|
                curve = edge.curve
                next if curve.is_a?(Sketchup::ArcCurve) && arc_curve_ids[curve.object_id]

                lines << {
                    "PathType"    => "Line",
                    "VertexName"  => "",
                    "Start_mm"    => na_pt_mm(edge.start.position, origin_pt),
                    "End_mm"      => na_pt_mm(edge.end.position, origin_pt)
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
                vertices_mm = face.outer_loop.vertices.map { |v| na_pt_mm(v.position, origin_pt) }
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

        # SUB FUNCTION | Calculate Bounding Box Across Extracted Paths
        # ---------------------------------------------------------------
        def self.na_calc_bbox(arcs, lines, polygons)
            xs = []
            ys = []

            lines.each do |line|
                xs << line["Start_mm"]["X"] << line["End_mm"]["X"]
                ys << line["Start_mm"]["Y"] << line["End_mm"]["Y"]
            end

            arcs.each do |arc|
                radius = arc["Radius_mm"]
                cx     = arc["Center_mm"]["X"]
                cy     = arc["Center_mm"]["Y"]
                xs << (cx - radius) << (cx + radius)
                ys << (cy - radius) << (cy + radius)
            end

            polygons.each do |poly|
                poly["Vertices_mm"].each do |vertex|
                    xs << vertex["X"]
                    ys << vertex["Y"]
                end
            end

            return {} if xs.empty?

            min_x = xs.min.round(3)
            max_x = xs.max.round(3)
            min_y = ys.min.round(3)
            max_y = ys.max.round(3)

            {
                "Na__Geometry__MinX_mm"   => min_x,
                "Na__Geometry__MaxX_mm"   => max_x,
                "Na__Geometry__MinY_mm"   => min_y,
                "Na__Geometry__MaxY_mm"   => max_y,
                "Na__Geometry__Width_mm"  => (max_x - min_x).round(3),
                "Na__Geometry__Height_mm" => (max_y - min_y).round(3)
            }
        end
        private_class_method :na_calc_bbox
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Document Assembly
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Root meta Block
        # ---------------------------------------------------------------
        def self.na_build_meta_block
            {
                "fileName"         => "",
                "description"      => "2D asset file exported by Na__DevTools::Na__JsonExporter2D.",
                "version"          => "1.0.0",
                "lastUpdated"      => Time.now.strftime("%Y-%m-%d"),
                "namingConvention" => "All custom keys prefixed Na__. Three-stage form Na__Section__SubSection__FieldName.",
                "fieldPrefixes"    => {
                    "Na__Asset__"          => "Top-level asset metadata and content blocks",
                    "Na__Geometry__"       => "Geometry-related sub-fields (BoundingBox, Counts, OriginNote, CoordSystem)",
                    "Na__PanelPlacement__" => "Door-panel mounting transforms (RH/LH handing, vertical datum)"
                }
            }
        end
        private_class_method :na_build_meta_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Empty Na__Asset__Metadata Placeholder
        # ---------------------------------------------------------------
        def self.na_build_asset_metadata_block(export_mode)
            is_plan      = (export_mode == NA_MODE_PLAN)
            is_elevation = (export_mode == NA_MODE_ELEVATION)
            {
                "Na__Asset__Name"                      => "",
                "Na__Asset__Code"                      => "",
                "Na__Asset__Type"                      => "",
                "Na__Asset__Description"               => "",
                "Na__Asset__Notes"                     => "",
                "Na__Asset__Has2dPlan"                 => is_plan,
                "Na__Asset__Has2dElevation"            => is_elevation,
                "Na__Asset__Has2dProfile"              => false,
                "Na__Asset__Has3d"                     => false,
                "Na__Asset__Supplier"                  => "",
                "Na__Asset__SupplierProductCode"       => "",
                "Na__Asset__SupplierPrice_GBP"         => "",
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
                "Na__Asset__AvailableFinishes"         => []
            }
        end
        private_class_method :na_build_asset_metadata_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Na__Geometry__Counts Block
        # ---------------------------------------------------------------
        def self.na_build_geometry_counts_block(edges, arcs, lines, polygons)
            circle_count = arcs.count { |entry| entry["IsCircle"] == true }
            {
                "Na__Geometry__EdgeCount"    => edges.size,
                "Na__Geometry__ArcCount"     => arcs.size,
                "Na__Geometry__LineCount"    => lines.size,
                "Na__Geometry__PolygonCount" => polygons.size,
                "Na__Geometry__CircleCount"  => circle_count
            }
        end
        private_class_method :na_build_geometry_counts_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Plan/Elevation Block
        # ---------------------------------------------------------------
        def self.na_build_2d_block(export_mode, edges, arcs, lines, polygons, bbox)
            origin_note = if export_mode == NA_MODE_ELEVATION
                              "Local 0,0 = centre of 00__OriginPoint group (handle spindle). Front view of asset."
                          else
                              "Local 0,0 = centre of 00__OriginPoint group (handle spindle). Right-hand orientation."
                          end

            coord_system = if export_mode == NA_MODE_ELEVATION
                               "XY plane | X=right, Y=up | Units=mm | Z discarded"
                           else
                               "XY plane | X=right, Y=forward (away from door face) | Units=mm | Z discarded"
                           end

            {
                "Na__Geometry__OriginNote"  => origin_note,
                "Na__Geometry__CoordSystem" => coord_system,
                "Na__Geometry__BoundingBox" => bbox,
                "Na__Geometry__Counts"      => na_build_geometry_counts_block(edges, arcs, lines, polygons),
                "Na__Geometry__Paths"       => polygons + arcs + lines
            }
        end
        private_class_method :na_build_2d_block
        # ---------------------------------------------------------------

        # FUNCTION | Assemble Full Root Document Hash
        # ---------------------------------------------------------------
        def self.na_build_full_document(export_mode, edges, arcs, lines, polygons, bbox)
            root = {
                "meta"                => na_build_meta_block,
                "Na__Asset__Metadata" => na_build_asset_metadata_block(export_mode)
            }

            block_key = (export_mode == NA_MODE_ELEVATION) ? "Na__Asset__Elevation2D" : "Na__Asset__Plan2D"
            root[block_key] = na_build_2d_block(export_mode, edges, arcs, lines, polygons, bbox)
            root
        end
        private_class_method :na_build_full_document
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Custom JSON Pretty-Printer (Column-Aligned Na__ Style)
# -----------------------------------------------------------------------------

        def self.na_indent_line(line_depth)
            return ''   if line_depth < 1
            return '  ' if line_depth == 1
            ' ' * (4 * (line_depth - 1))
        end
        private_class_method :na_indent_line

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

        def self.na_key_colon_padded(key, key_column_width)
            key_json = key.to_json
            pad      = [0, key_column_width - key_json.length].max
            "#{key_json}#{' ' * pad} : "
        end
        private_class_method :na_key_colon_padded

        def self.na_format_key_value_pair(key, value, key_line_depth, key_column_width)
            indent = na_indent_line(key_line_depth)
            keycol = na_key_colon_padded(key, key_column_width)

            case value
            when Hash
                return "#{indent}#{keycol}{}" if value.empty?
                body  = na_format_object_body(value, key_line_depth + 1)
                close = na_indent_line(key_line_depth)
                "#{indent}#{keycol}{\n#{body}\n#{close}}"
            when Array
                return "#{indent}#{keycol}[]" if value.empty?
                inner = na_format_array_body(value, key_line_depth)
                "#{indent}#{keycol}[\n#{inner}\n#{indent}]"
            else
                "#{indent}#{keycol}#{na_json_scalar_fragment(value)}"
            end
        end
        private_class_method :na_format_key_value_pair

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

        def self.na_format_array_body(arr, parent_key_line_depth)
            elem_open_depth = parent_key_line_depth + 1
            chunks          = arr.map { |el| na_format_array_element(el, elem_open_depth) }
            chunks.join(",\n")
        end
        private_class_method :na_format_array_body

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

        def self.na_generate_full_document_json(root_hash)
            width = root_hash.keys.map { |k| k.to_json.length }.max
            parts = []
            root_hash.each do |k, v|
                parts << na_format_key_value_pair(k, v, 1, width)
            end
            "{\n#{parts.join(",\n")}\n}\n"
        end
        private_class_method :na_generate_full_document_json

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Output Helpers
# -----------------------------------------------------------------------------

        def self.na_print_to_console(json_str)
            puts "\n" + ("=" * 70)
            puts "NA DEV TOOLS | 2D NA__ ASSET JSON OUTPUT"
            puts "=" * 70
            puts json_str
            puts "=" * 70
        end
        private_class_method :na_print_to_console

        # Returns a result hash - see na_run_export for the shape.
        def self.na_save_to_disk(json_str, export_mode)
            default_name = (export_mode == NA_MODE_ELEVATION) ? NA_OUTPUT_FILENAME_ELEV : NA_OUTPUT_FILENAME_PLAN
            start_dir    = Na__DevTools.na_resolve_export_directory
            output_path  = UI.savepanel("Save Na 2D Asset JSON", start_dir, default_name)

            if output_path.nil?
                puts "\n>> Save cancelled. Copy the JSON from the console above."
                return { :status => :cancelled, :message => "2D export cancelled - no file was saved." }
            end

            output_path += ".json" unless output_path.downcase.end_with?(".json")

            begin
                File.open(output_path, "w") { |f| f.write(json_str) }
                Na__DevTools.na_remember_export_directory(output_path)
                puts "\n>> Saved to : #{output_path}"
                puts "\n>> Export complete."
                { :status => :saved, :message => "2D asset saved to #{output_path}", :path => output_path }
            rescue => file_err
                puts "\n!! File write failed : #{file_err.message}"
                puts "   (Copy the JSON from the console above instead)"
                UI.messagebox("Na__ 2D Export could not write the file:\n\n#{file_err.message}\n\nCopy the JSON from the Ruby Console instead.")
                { :status => :error, :message => "Could not write file: #{file_err.message}" }
            end
        end
        private_class_method :na_save_to_disk

# endregion -------------------------------------------------------------------

    end # module Na__JsonExporter2D
end # module Na__DevTools
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
