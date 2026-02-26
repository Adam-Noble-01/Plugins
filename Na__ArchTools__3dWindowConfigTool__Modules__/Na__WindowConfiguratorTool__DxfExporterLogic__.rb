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
        NA_COLOR_GLASS     = 4    # Cyan
        NA_COLOR_GLAZE_BAR = 50   # Yellow-Orange
        NA_COLOR_CILL      = 8    # Gray
        NA_COLOR_DIMENSION = 7    # White

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
            
            # Include cill in extents if present
            min_y = 0
            if config["has_cill"] != false
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
                7
            DXF
            
            # Add each layer
            tables += na_generate_layer_entry(NA_LAYER_FRAME, NA_COLOR_FRAME)
            tables += na_generate_layer_entry(NA_LAYER_CASEMENT, NA_COLOR_CASEMENT)
            tables += na_generate_layer_entry(NA_LAYER_MULLION, NA_COLOR_MULLION)
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
            frame_thickness = config["frame_thickness_mm"] || 50
            casement_width = config["casement_width_mm"] || 65
            show_casements = config["show_casements"] != false
            casements_per_opening = if config.key?("twin_casements") && !config.key?("casements_per_opening")
                config["twin_casements"] == true ? 2 : 1
            else
                (config["casements_per_opening"] || 1).to_i.clamp(1, 6)
            end
            num_mullions = config["mullions"] || 0
            mullion_width = config["mullion_width_mm"] || 40
            h_bars = config["horizontal_glaze_bars"] || 0
            v_bars = config["vertical_glaze_bars"] || 0
            bar_width = config["glaze_bar_width_mm"] || 25
            has_cill = config["has_cill"] != false
            cill_depth = config["cill_depth_mm"] || 50
            cill_height = config["cill_height_mm"] || 50
            
            # Individual casement sizes
            use_individual_sizes = config["casement_sizes_individual"] == true
            cas_top_rail = use_individual_sizes ? (config["casement_top_rail_mm"] || casement_width) : casement_width
            cas_bottom_rail = use_individual_sizes ? (config["casement_bottom_rail_mm"] || casement_width) : casement_width
            cas_left_stile = use_individual_sizes ? (config["casement_left_stile_mm"] || casement_width) : casement_width
            cas_right_stile = use_individual_sizes ? (config["casement_right_stile_mm"] || casement_width) : casement_width
            
            # Calculate openings
            num_openings = num_mullions + 1
            inner_width = width - (2 * frame_thickness)
            inner_height = height - (2 * frame_thickness)
            total_mullion_width = num_mullions * mullion_width
            available_width = inner_width - total_mullion_width
            opening_width = available_width.to_f / num_openings
            
            # Draw outer frame (4 rectangles) - skip in frameless mode (frame_thickness == 0)
            if frame_thickness > 0
                # JOINERY CONVENTION: Stiles full height, rails inset
                # Left stile (full height)
                entities += na_dxf_rect(0, 0, frame_thickness, height, NA_LAYER_FRAME)
                # Right stile (full height)
                entities += na_dxf_rect(width - frame_thickness, 0, frame_thickness, height, NA_LAYER_FRAME)
                # Bottom rail (inset between stiles)
                entities += na_dxf_rect(frame_thickness, 0, inner_width, frame_thickness, NA_LAYER_FRAME)
                # Top rail (inset between stiles)
                entities += na_dxf_rect(frame_thickness, height - frame_thickness, inner_width, frame_thickness, NA_LAYER_FRAME)
            end
            
            # Draw mullions
            (1..num_mullions).each do |m|
                mullion_x = frame_thickness + (m * opening_width) + ((m - 1) * mullion_width)
                entities += na_dxf_rect(mullion_x, frame_thickness, mullion_width, inner_height, NA_LAYER_MULLION)
            end
            
            # Draw each opening with casement (if enabled), glass, and glaze bars
            (0...num_openings).each do |i|
                opening_x = frame_thickness + (i * (opening_width + mullion_width))
                opening_y = frame_thickness
                panel_width = opening_width / casements_per_opening.to_f
                
                if show_casements
                    (0...casements_per_opening).each do |p|
                        panel_x = opening_x + (p * panel_width)
                        entities += na_generate_casement_dxf(
                            panel_x, opening_y, panel_width, inner_height,
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            h_bars, v_bars, bar_width
                        )
                    end
                else
                    (0...casements_per_opening).each do |p|
                        panel_x = opening_x + (p * panel_width)
                        entities += na_dxf_rect(panel_x, opening_y, panel_width, inner_height, NA_LAYER_GLASS)
                    end
                end
            end
            
            # Draw cill (skip in frameless mode)
            if has_cill && frame_thickness > 0
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
        def self.na_generate_casement_dxf(x, y, width, height, top_rail, bottom_rail, left_stile, right_stile, h_bars, v_bars, bar_width)
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
            
            # Horizontal glaze bars
            if h_bars > 0
                section_height = glass_height.to_f / (h_bars + 1)
                (1..h_bars).each do |b|
                    bar_y = glass_y + (section_height * b) - (bar_width / 2.0)
                    dxf += na_dxf_rect(glass_x, bar_y, glass_width, bar_width, NA_LAYER_GLAZE_BAR)
                end
            end
            
            # Vertical glaze bars
            if v_bars > 0
                section_width = glass_width.to_f / (v_bars + 1)
                (1..v_bars).each do |b|
                    bar_x = glass_x + (section_width * b) - (bar_width / 2.0)
                    dxf += na_dxf_rect(bar_x, glass_y, bar_width, glass_height, NA_LAYER_GLAZE_BAR)
                end
            end
            
            dxf
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
