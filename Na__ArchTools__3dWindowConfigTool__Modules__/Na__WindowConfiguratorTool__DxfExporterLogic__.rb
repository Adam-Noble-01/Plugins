# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - DXF EXPORTER LOGIC
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__DxfExporterLogic__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__DxfExporter
# AUTHOR     : Noble Architecture
# PURPOSE    : Generate DXF 2D CAD drawings from window configuration
# CREATED    : 2026
# VERSION    : 1.0.0
#
# DESCRIPTION:
# - Converts window configuration to properly formatted DXF R12 format
# - Creates separate layers for different window elements:
#   * NA_FRAME - Outer frame members
#   * NA_CASEMENT - Casement frame members
#   * NA_MULLION - Vertical mullion dividers
#   * NA_GLASS - Glass pane outlines
#   * NA_GLAZE_BAR - Horizontal and vertical glaze bars
#   * NA_CILL - Window cill
#   * NA_DIMENSION - Dimension annotations
# - All geometry in millimeters (1:1 scale)
# - Uses LINE entities for maximum CAD compatibility
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - DXF group codes follow AutoCAD DXF R12 specification
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'

module Na__WindowConfiguratorTool
    module Na__DxfExporter

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Layer Names
        # ------------------------------------------------------------
        NA_LAYER_FRAME     = "NA_FRAME".freeze
        NA_LAYER_CASEMENT  = "NA_CASEMENT".freeze
        NA_LAYER_MULLION   = "NA_MULLION".freeze
        NA_LAYER_TRANSOM   = "NA_TRANSOM".freeze
        NA_LAYER_GLASS     = "NA_GLASS".freeze
        NA_LAYER_GLAZE_BAR = "NA_GLAZE_BAR".freeze
        NA_LAYER_CILL      = "NA_CILL".freeze
        NA_LAYER_DIMENSION = "NA_DIMENSION".freeze
        
        # CONSTANTS | Layer Colors (AutoCAD Color Index)
        # ------------------------------------------------------------
        # 1=Red, 2=Yellow, 3=Green, 4=Cyan, 5=Blue, 6=Magenta, 7=White
        NA_COLOR_FRAME     = 30   # Orange/Tan
        NA_COLOR_CASEMENT  = 40   # Light Orange
        NA_COLOR_MULLION   = 32   # Tan
        NA_COLOR_TRANSOM   = 32   # Tan
        NA_COLOR_GLASS     = 4    # Cyan
        NA_COLOR_GLAZE_BAR = 50   # Yellow-Orange
        NA_COLOR_CILL      = 8    # Gray
        NA_COLOR_DIMENSION = 7    # White

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Frame Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Build Glaze Bar Storage Key
        # ------------------------------------------------------------
        def self.na_get_glazebar_key(opening_index, cell_index, panel_index, sash_index, orientation, bar_index)
            "#{opening_index}:#{cell_index}:#{panel_index}:#{sash_index}:#{orientation}:#{bar_index}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Removed Glaze Bar
        # ------------------------------------------------------------
        def self.na_glazebar_removed?(removed_glazebars, opening_index, cell_index, panel_index, sash_index, orientation, bar_index)
            return false unless removed_glazebars.is_a?(Array)

            removed_glazebars.include?(na_get_glazebar_key(opening_index, cell_index, panel_index, sash_index, orientation, bar_index))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Effective Frame Thicknesses
        # ------------------------------------------------------------
        def self.na_get_effective_frame_thicknesses(config)
            uniform_frame_thickness = config.key?("frame_thickness_mm") ? config["frame_thickness_mm"].to_f : 50.0
            use_advanced_frame_controls = config["advanced_frame_controls"] == true

            resolve_frame_side_thickness = lambda do |side_key|
                mm_value = if use_advanced_frame_controls && config.key?(side_key)
                    config[side_key]
                else
                    uniform_frame_thickness
                end

                [mm_value.to_f, 0.0].max
            end

            {
                top: resolve_frame_side_thickness.call("frame_top_thickness_mm"),
                bottom: resolve_frame_side_thickness.call("frame_bottom_thickness_mm"),
                left: resolve_frame_side_thickness.call("frame_left_thickness_mm"),
                right: resolve_frame_side_thickness.call("frame_right_thickness_mm")
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Export Function
# -----------------------------------------------------------------------------

        # FUNCTION | Generate Complete DXF from Configuration
        # ------------------------------------------------------------
        # Main entry point for DXF generation.
        # 
        # @param config [Hash] Window configuration hash
        # @return [String] Complete DXF file content
        def self.na_generate_dxf(config)
            DebugTools.na_debug_method("na_generate_dxf")
            
            begin
                dxf = ""
                
                # Add DXF sections
                dxf += na_generate_header(config)
                dxf += na_generate_tables
                dxf += na_generate_entities(config)
                dxf += na_generate_eof
                
                DebugTools.na_debug_success("DXF generated successfully")
                dxf
                
            rescue => e
                DebugTools.na_debug_error("Error generating DXF", e)
                nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Header Section
# -----------------------------------------------------------------------------

        # FUNCTION | Generate DXF Header Section
        # ------------------------------------------------------------
        def self.na_generate_header(config)
            width = config["width_mm"] || 900
            height = config["height_mm"] || 1200
            frame_thicknesses = na_get_effective_frame_thicknesses(config)
            
            # Include cill in extents if present
            min_y = 0
            if config["has_cill"] != false && frame_thicknesses[:bottom] > 0
                cill_height = config["cill_height_mm"] || 50
                min_y = -cill_height
            end
            
            header = <<~DXF
                0
                SECTION
                2
                HEADER
                9
                $ACADVER
                1
                AC1009
                9
                $INSBASE
                10
                0.0
                20
                0.0
                30
                0.0
                9
                $EXTMIN
                10
                0.0
                20
                #{min_y}.0
                30
                0.0
                9
                $EXTMAX
                10
                #{width}.0
                20
                #{height}.0
                30
                0.0
                9
                $LUNITS
                70
                2
                9
                $LUPREC
                70
                4
                0
                ENDSEC
            DXF
            header
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Tables Section (Layers)
# -----------------------------------------------------------------------------

        # FUNCTION | Generate DXF Tables Section with Layers
        # ------------------------------------------------------------
        def self.na_generate_tables
            tables = <<~DXF
                0
                SECTION
                2
                TABLES
                0
                TABLE
                2
                LAYER
                70
                8
            DXF
            
            # Add each layer
            tables += na_generate_layer_entry(NA_LAYER_FRAME, NA_COLOR_FRAME)
            tables += na_generate_layer_entry(NA_LAYER_CASEMENT, NA_COLOR_CASEMENT)
            tables += na_generate_layer_entry(NA_LAYER_MULLION, NA_COLOR_MULLION)
            tables += na_generate_layer_entry(NA_LAYER_TRANSOM, NA_COLOR_TRANSOM)
            tables += na_generate_layer_entry(NA_LAYER_GLASS, NA_COLOR_GLASS)
            tables += na_generate_layer_entry(NA_LAYER_GLAZE_BAR, NA_COLOR_GLAZE_BAR)
            tables += na_generate_layer_entry(NA_LAYER_CILL, NA_COLOR_CILL)
            tables += na_generate_layer_entry(NA_LAYER_DIMENSION, NA_COLOR_DIMENSION)
            
            tables += <<~DXF
                0
                ENDTAB
                0
                ENDSEC
            DXF
            tables
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Generate Single Layer Entry
        # ------------------------------------------------------------
        def self.na_generate_layer_entry(name, color)
            <<~DXF
                0
                LAYER
                2
                #{name}
                70
                0
                62
                #{color}
                6
                CONTINUOUS
            DXF
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Entities Section
# -----------------------------------------------------------------------------

        # FUNCTION | Generate DXF Entities Section
        # ------------------------------------------------------------
        def self.na_generate_entities(config)
            DebugTools.na_debug_method("na_generate_entities")
            
            entities = "0\nSECTION\n2\nENTITIES\n"
            
            # Extract configuration values
            width = config["width_mm"] || 900
            height = config["height_mm"] || 1200
            frame_thicknesses = na_get_effective_frame_thicknesses(config)
            top_frame_thickness = frame_thicknesses[:top]
            bottom_frame_thickness = frame_thicknesses[:bottom]
            left_frame_thickness = frame_thicknesses[:left]
            right_frame_thickness = frame_thicknesses[:right]
            casement_width = config["casement_width_mm"] || 65
            show_casements = config["show_casements"] != false
            sliding_sash_window = config["sliding_sash_window"] == true
            sliding_sash_overlap = (config["sliding_sash_overlap_mm"] || 20).to_f.clamp(0.0, 60.0)
            casements_per_opening = if config.key?("twin_casements") && !config.key?("casements_per_opening")
                config["twin_casements"] == true ? 2 : 1
            else
                (config["casements_per_opening"] || 1).to_i.clamp(1, 6)
            end
            num_mullions = config["mullions"] || 0
            mullion_width = config["mullion_width_mm"] || 40
            transom_count = (config["transoms"] || 0).to_i.clamp(0, 3)
            transom_width = config["transom_width_mm"] || 40
            transom_bottoms = na_get_transom_bottoms(config, transom_count)
            h_bars = config["horizontal_glaze_bars"] || 0
            v_bars = config["vertical_glaze_bars"] || 0
            bar_width = config["glaze_bar_width_mm"] || 25
            has_cill = config["has_cill"] != false
            cill_height = config["cill_height_mm"] || 50
            removed_casements = config["removed_casements"] || []
            removed_transom_segments = config["removed_transom_segments"] || []
            removed_glazebars = config["removed_glazebars"] || []
            
            # Individual casement sizes
            use_individual_sizes = config["casement_sizes_individual"] == true
            cas_top_rail = use_individual_sizes ? (config["casement_top_rail_mm"] || casement_width) : casement_width
            cas_bottom_rail = use_individual_sizes ? (config["casement_bottom_rail_mm"] || casement_width) : casement_width
            cas_left_stile = use_individual_sizes ? (config["casement_left_stile_mm"] || casement_width) : casement_width
            cas_right_stile = use_individual_sizes ? (config["casement_right_stile_mm"] || casement_width) : casement_width
            
            # Calculate openings
            num_openings = num_mullions + 1
            inner_width = width - left_frame_thickness - right_frame_thickness
            inner_height = height - top_frame_thickness - bottom_frame_thickness
            total_mullion_width = num_mullions * mullion_width
            available_width = inner_width - total_mullion_width
            opening_width = available_width.to_f / num_openings
            
            # Draw outer frame (4 rectangles) - skip in frameless mode (frame_thickness == 0)
            if left_frame_thickness > 0
                entities += na_dxf_rect(0, 0, left_frame_thickness, height, NA_LAYER_FRAME)
            end
            if right_frame_thickness > 0
                entities += na_dxf_rect(width - right_frame_thickness, 0, right_frame_thickness, height, NA_LAYER_FRAME)
            end
            if bottom_frame_thickness > 0
                entities += na_dxf_rect(left_frame_thickness, 0, inner_width, bottom_frame_thickness, NA_LAYER_FRAME)
            end
            if top_frame_thickness > 0
                entities += na_dxf_rect(left_frame_thickness, height - top_frame_thickness, inner_width, top_frame_thickness, NA_LAYER_FRAME)
            end
            
            # Draw mullions
            (1..num_mullions).each do |m|
                mullion_x = left_frame_thickness + (m * opening_width) + ((m - 1) * mullion_width)
                entities += na_dxf_rect(mullion_x, bottom_frame_thickness, mullion_width, inner_height, NA_LAYER_MULLION)
            end
            
            # Draw each opening with casement (if enabled), glass, and glaze bars
            (0...num_openings).each do |i|
                opening_x = left_frame_thickness + (i * (opening_width + mullion_width))
                opening_y = bottom_frame_thickness
                opening_layout = na_get_opening_layout(
                    i,
                    opening_x,
                    opening_y,
                    opening_width,
                    inner_height,
                    transom_bottoms,
                    transom_width,
                    removed_transom_segments
                )

                opening_layout[:transom_segments].each do |segment|
                    entities += na_dxf_rect(segment[:x], segment[:y], segment[:width], segment[:height], NA_LAYER_TRANSOM)
                end

                opening_layout[:cells].each_with_index do |cell, cell_index|
                    panel_width = cell[:width] / casements_per_opening.to_f

                    (0...casements_per_opening).each do |p|
                        panel_x = cell[:x] + (p * panel_width)
                        panel_has_casement = show_casements && !na_panel_casement_removed?(                          # <-- Per-panel removal lookup
                            removed_casements,
                            i,
                            cell_index,
                            p
                        )

                        if panel_has_casement
                            if sliding_sash_window
                                entities += na_generate_sliding_sash_panel_dxf(
                                    panel_x, cell[:y], panel_width, cell[:height],
                                    cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                                    h_bars, v_bars, bar_width, sliding_sash_overlap,
                                    opening_index: i, cell_index: cell_index, panel_index: p,
                                    removed_glazebars: removed_glazebars
                                )
                            else
                                entities += na_generate_casement_dxf(
                                    panel_x, cell[:y], panel_width, cell[:height],
                                    cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                                    h_bars, v_bars, bar_width,
                                    opening_index: i, cell_index: cell_index, panel_index: p, sash_index: 0,
                                    removed_glazebars: removed_glazebars
                                )
                            end
                        else
                            entities += na_generate_direct_glazed_dxf(
                                panel_x, cell[:y], panel_width, cell[:height],
                                h_bars, v_bars, bar_width,
                                opening_index: i, cell_index: cell_index, panel_index: p, sash_index: 0,
                                removed_glazebars: removed_glazebars
                            )
                        end
                    end
                end
            end
            
            # Draw cill (skip in frameless mode)
            if has_cill && bottom_frame_thickness > 0
                entities += na_dxf_rect(0, -cill_height, width, cill_height, NA_LAYER_CILL)
            end
            
            entities += "0\nENDSEC\n"
            entities
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Casement Generation
# -----------------------------------------------------------------------------

        # FUNCTION | Generate DXF for a Single Casement
        # ------------------------------------------------------------
        def self.na_generate_casement_dxf(x, y, width, height, top_rail, bottom_rail, left_stile, right_stile, h_bars, v_bars, bar_width, opening_index:, cell_index:, panel_index:, sash_index:, removed_glazebars:)
            dxf = ""
            
            # Casement frame (4 pieces) - JOINERY CONVENTION: Stiles full height, rails inset
            # Left stile (full height)
            dxf += na_dxf_rect(x, y, left_stile, height, NA_LAYER_CASEMENT)
            # Right stile (full height)
            dxf += na_dxf_rect(x + width - right_stile, y, right_stile, height, NA_LAYER_CASEMENT)
            # Bottom rail (inset between stiles)
            dxf += na_dxf_rect(x + left_stile, y, width - left_stile - right_stile, bottom_rail, NA_LAYER_CASEMENT)
            # Top rail (inset between stiles)
            dxf += na_dxf_rect(x + left_stile, y + height - top_rail, width - left_stile - right_stile, top_rail, NA_LAYER_CASEMENT)
            
            # Glass area inside casement
            glass_x = x + left_stile
            glass_y = y + bottom_rail
            glass_width = width - left_stile - right_stile
            glass_height = height - top_rail - bottom_rail
            
            # Glass pane outline
            dxf += na_dxf_rect(glass_x, glass_y, glass_width, glass_height, NA_LAYER_GLASS)
            dxf += na_generate_glaze_bar_dxf(
                glass_x, glass_y, glass_width, glass_height, h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: sash_index,
                removed_glazebars: removed_glazebars
            )
            
            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate DXF for Direct-Glazed Cell
        # ------------------------------------------------------------
        def self.na_generate_direct_glazed_dxf(x, y, width, height, h_bars, v_bars, bar_width, opening_index:, cell_index:, panel_index:, sash_index:, removed_glazebars:)
            dxf = ""
            dxf += na_dxf_rect(x, y, width, height, NA_LAYER_GLASS)
            dxf += na_generate_glaze_bar_dxf(
                x, y, width, height, h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: sash_index,
                removed_glazebars: removed_glazebars
            )
            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate Glaze Bars Within a Glass Area
        # ------------------------------------------------------------
        def self.na_generate_glaze_bar_dxf(glass_x, glass_y, glass_width, glass_height, h_bars, v_bars, bar_width, opening_index:, cell_index:, panel_index:, sash_index:, removed_glazebars:)
            dxf = ""

            if h_bars > 0
                section_height = glass_height.to_f / (h_bars + 1)
                (1..h_bars).each do |b|
                    next if na_glazebar_removed?(removed_glazebars, opening_index, cell_index, panel_index, sash_index, "horizontal", b)

                    bar_y = glass_y + (section_height * b) - (bar_width / 2.0)
                    dxf += na_dxf_rect(glass_x, bar_y, glass_width, bar_width, NA_LAYER_GLAZE_BAR)
                end
            end

            if v_bars > 0
                section_width = glass_width.to_f / (v_bars + 1)
                (1..v_bars).each do |b|
                    next if na_glazebar_removed?(removed_glazebars, opening_index, cell_index, panel_index, sash_index, "vertical", b)

                    bar_x = glass_x + (section_width * b) - (bar_width / 2.0)
                    dxf += na_dxf_rect(bar_x, glass_y, bar_width, glass_height, NA_LAYER_GLAZE_BAR)
                end
            end

            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate DXF for Sliding Sash Panel
        # ------------------------------------------------------------
        # Draws two stacked casements in one panel.
        # Bottom sash is extended by overlap amount to represent weathering tuck-under.
        def self.na_generate_sliding_sash_panel_dxf(x, y, width, height, top_rail, bottom_rail, left_stile, right_stile, h_bars, v_bars, bar_width, overlap_mm, opening_index:, cell_index:, panel_index:, removed_glazebars:)
            dxf = ""

            sash_height = height.to_f / 2.0
            sash_overlap = [[overlap_mm.to_f, sash_height - 1.0].min, 0.0].max

            # Bottom sash (drawn first): extended upward by overlap amount.
            dxf += na_generate_casement_dxf(
                x, y, width, sash_height + sash_overlap,
                top_rail, bottom_rail, left_stile, right_stile,
                h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: 1,
                removed_glazebars: removed_glazebars
            )

            # Top sash (drawn second): standard half-height sash.
            dxf += na_generate_casement_dxf(
                x, y + sash_height, width, sash_height,
                top_rail, bottom_rail, left_stile, right_stile,
                h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: 0,
                removed_glazebars: removed_glazebars
            )

            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Active Transom Heights
        # ------------------------------------------------------------
        def self.na_get_transom_bottoms(config, transom_count)
            [
                (config["transom_1_y_mm"] || 0).to_f,
                (config["transom_2_y_mm"] || 0).to_f,
                (config["transom_3_y_mm"] || 0).to_f
            ].first(transom_count)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Removed Transom Segment
        # ------------------------------------------------------------
        def self.na_transom_segment_removed?(removed_segments, opening_index, transom_index)
            removed_segments.include?("#{opening_index}:#{transom_index}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Removed Casement Panel (Legacy-Aware)
        # ------------------------------------------------------------
        # Bare-integer entries match every panel of that opening; new-format
        # entries match an exact "openingIndex:cellIndex:panelIndex" key.
        def self.na_panel_casement_removed?(removed_casements, opening_index, cell_index, panel_index)
            return false unless removed_casements.is_a?(Array)
            return true if removed_casements.include?("#{opening_index}:#{cell_index}:#{panel_index}")              # <-- New per-panel key
            return true if removed_casements.include?(opening_index)                                                # <-- Legacy bare-integer match
            removed_casements.any? do |entry|
                next false if entry.nil?
                next false if entry.is_a?(String) && entry.include?(':')
                Integer(entry.to_s) == opening_index rescue false                                                   # <-- Legacy stringified integer match
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Opening Cell Layout
        # ------------------------------------------------------------
        def self.na_get_opening_layout(opening_index, opening_x, opening_y, opening_width, inner_height, transom_bottoms, transom_width, removed_segments)
            cells = []
            transom_segments = []
            cell_bottom = 0

            transom_bottoms.each_with_index do |transom_bottom, transom_index|
                next if na_transom_segment_removed?(removed_segments, opening_index, transom_index)

                cell_height = transom_bottom - cell_bottom
                if cell_height > 0
                    cells << {
                        x: opening_x,
                        y: opening_y + cell_bottom,
                        width: opening_width,
                        height: cell_height
                    }
                end

                transom_segments << {
                    x: opening_x,
                    y: opening_y + transom_bottom,
                    width: opening_width,
                    height: transom_width
                }

                cell_bottom = transom_bottom + transom_width
            end

            top_cell_height = inner_height - cell_bottom
            if top_cell_height > 0
                cells << {
                    x: opening_x,
                    y: opening_y + cell_bottom,
                    width: opening_width,
                    height: top_cell_height
                }
            end

            {
                cells: cells,
                transom_segments: transom_segments
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Geometry Primitives
# -----------------------------------------------------------------------------

        # FUNCTION | Generate DXF Rectangle (as 4 LINE entities)
        # ------------------------------------------------------------
        # Creates a rectangle using 4 LINE entities for maximum compatibility.
        # 
        # @param x [Float] X position (left edge)
        # @param y [Float] Y position (bottom edge)
        # @param w [Float] Width
        # @param h [Float] Height
        # @param layer [String] Layer name
        # @return [String] DXF LINE entities
        def self.na_dxf_rect(x, y, w, h, layer)
            return "" if w <= 0 || h <= 0
            
            x1 = x
            y1 = y
            x2 = x + w
            y2 = y + h
            
            # Four lines: bottom, right, top, left
            dxf = ""
            dxf += na_dxf_line(x1, y1, x2, y1, layer)  # Bottom
            dxf += na_dxf_line(x2, y1, x2, y2, layer)  # Right
            dxf += na_dxf_line(x2, y2, x1, y2, layer)  # Top
            dxf += na_dxf_line(x1, y2, x1, y1, layer)  # Left
            dxf
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Generate Single DXF LINE Entity
        # ------------------------------------------------------------
        # @param x1 [Float] Start X
        # @param y1 [Float] Start Y
        # @param x2 [Float] End X
        # @param y2 [Float] End Y
        # @param layer [String] Layer name
        # @return [String] DXF LINE entity
        def self.na_dxf_line(x1, y1, x2, y2, layer)
            <<~DXF
                0
                LINE
                8
                #{layer}
                10
                #{format_coord(x1)}
                20
                #{format_coord(y1)}
                30
                0.0
                11
                #{format_coord(x2)}
                21
                #{format_coord(y2)}
                31
                0.0
            DXF
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Format Coordinate Value
        # ------------------------------------------------------------
        def self.format_coord(value)
            sprintf("%.4f", value.to_f)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF EOF Section
# -----------------------------------------------------------------------------

        # FUNCTION | Generate DXF EOF Marker
        # ------------------------------------------------------------
        def self.na_generate_eof
            "0\nEOF\n"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DxfExporter
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
