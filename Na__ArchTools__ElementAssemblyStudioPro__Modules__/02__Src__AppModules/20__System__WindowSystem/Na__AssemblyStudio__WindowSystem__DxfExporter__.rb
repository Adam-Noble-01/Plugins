# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - DXF EXPORTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__DxfExporter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
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
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__WindowSystem__SashHornBuilder__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__DxfExporter

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        SashHornBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__SashHornBuilder

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
            # Advanced Glazebar (Margin + Gothic Arch) options. The values
            # remain in mm here because the DXF stream is mm-based already.
            advanced_glazebar = {
                margin_enabled:  config["glazebar_margin_enabled"] == true,
                margin_offset:   (config["glazebar_margin_offset_mm"] || 0).to_f,
                arch_enabled:    config["glazebar_gothic_arch_enabled"] == true,
                arch_amount:     [[(config["glazebar_gothic_arch_amount"] || 2).to_i, 1].max, 8].min,            # <-- V1.9.4 Allow single lancet arch
                arch_height:     (config["glazebar_gothic_arch_height_mm"] || 0).to_f,
                arch_height_mm:  (config["glazebar_gothic_arch_height_mm"] || 0).to_f,
                h_offset:        (config["glazebar_horizontal_offset_mm"] || 0).to_f,                # <-- DxfExporter works in mm so inches/mm collapse to the same value
                h_offset_mm:     (config["glazebar_horizontal_offset_mm"] || 0).to_f,
                h_bar_offsets:   (1..(config["horizontal_glaze_bars"] || 0).to_i).map { |i| (config["glazebar_h_offset_#{i}_mm"] || 0).to_f },   # <-- Per-bar vertical nudges (mm)
                v_bar_offsets:   (1..(config["vertical_glaze_bars"] || 0).to_i).map { |i| (config["glazebar_v_offset_#{i}_mm"] || 0).to_f }      # <-- Per-bar horizontal nudges (mm)
            }
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
            top_sash_bottom_rail = (config["top_sash_bottom_rail_mm"] || cas_bottom_rail).to_f
            bottom_sash_top_rail = if config["bottom_sash_top_rail_override"] == true
                (config["bottom_sash_top_rail_mm"] || cas_top_rail).to_f
            else
                cas_top_rail.to_f
            end
            sash_horns_enabled = config["sash_horns_enabled"] != false
            sash_horn_type = config["sash_horn_type"] || "1"
            # Signed nudge for the meeting rail away from the 50/50 split
            # (mm here - the DXF exporter works in millimetres throughout).
            meeting_rail_offset = if config["meeting_rail_position_override"] == true
                (config["meeting_rail_offset_mm"] || 0).to_f
            else
                0.0
            end

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
                                    cas_top_rail, cas_bottom_rail, top_sash_bottom_rail, bottom_sash_top_rail, cas_left_stile, cas_right_stile,
                                    h_bars, v_bars, bar_width, sliding_sash_overlap, meeting_rail_offset,
                                    opening_index: i, cell_index: cell_index, panel_index: p,
                                    removed_glazebars: removed_glazebars,
                                    sash_horns_enabled: sash_horns_enabled,
                                    sash_horn_type: sash_horn_type,
                                    advanced_glazebar: advanced_glazebar
                                )
                            else
                                entities += na_generate_casement_dxf(
                                    panel_x, cell[:y], panel_width, cell[:height],
                                    cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                                    h_bars, v_bars, bar_width,
                                    opening_index: i, cell_index: cell_index, panel_index: p, sash_index: 0,
                                    removed_glazebars: removed_glazebars,
                                    advanced_glazebar: advanced_glazebar
                                )
                            end
                        else
                            entities += na_generate_direct_glazed_dxf(
                                panel_x, cell[:y], panel_width, cell[:height],
                                h_bars, v_bars, bar_width,
                                opening_index: i, cell_index: cell_index, panel_index: p, sash_index: 0,
                                removed_glazebars: removed_glazebars,
                                advanced_glazebar: advanced_glazebar
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
        def self.na_generate_casement_dxf(x, y, width, height, top_rail, bottom_rail, left_stile, right_stile, h_bars, v_bars, bar_width, opening_index:, cell_index:, panel_index:, sash_index:, removed_glazebars:, advanced_glazebar: nil)
            dxf = ""

            # Casement frame (4 pieces) - JOINERY CONVENTION: Stiles full height, rails inset
            dxf += na_dxf_rect(x, y, left_stile, height, NA_LAYER_CASEMENT)
            dxf += na_dxf_rect(x + width - right_stile, y, right_stile, height, NA_LAYER_CASEMENT)
            dxf += na_dxf_rect(x + left_stile, y, width - left_stile - right_stile, bottom_rail, NA_LAYER_CASEMENT)
            dxf += na_dxf_rect(x + left_stile, y + height - top_rail, width - left_stile - right_stile, top_rail, NA_LAYER_CASEMENT)

            # Glass area inside casement
            glass_x = x + left_stile
            glass_y = y + bottom_rail
            glass_width = width - left_stile - right_stile
            glass_height = height - top_rail - bottom_rail

            dxf += na_dxf_rect(glass_x, glass_y, glass_width, glass_height, NA_LAYER_GLASS)
            dxf += na_generate_glaze_bar_dxf(
                glass_x, glass_y, glass_width, glass_height, h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: sash_index,
                removed_glazebars: removed_glazebars, advanced_glazebar: advanced_glazebar
            )

            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate DXF for Direct-Glazed Cell
        # ------------------------------------------------------------
        def self.na_generate_direct_glazed_dxf(x, y, width, height, h_bars, v_bars, bar_width, opening_index:, cell_index:, panel_index:, sash_index:, removed_glazebars:, advanced_glazebar: nil)
            dxf = ""
            dxf += na_dxf_rect(x, y, width, height, NA_LAYER_GLASS)
            dxf += na_generate_glaze_bar_dxf(
                x, y, width, height, h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: sash_index,
                removed_glazebars: removed_glazebars, advanced_glazebar: advanced_glazebar
            )
            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate Glaze Bars Within a Glass Area
        # ------------------------------------------------------------
        # Honours Advanced Glazebar Controls so DXF output matches the live
        # 2D preview and 3D model:
        #   - Margin Glazing: outer pair inset, inner bars distributed evenly.
        #   - Gothic Arch: regular bar grid shrinks vertically; arch tracery
        #     emits as filled rectangles tessellated along each two-centred
        #     arc (same segment count rule as the Ruby 3D builder).
        def self.na_generate_glaze_bar_dxf(glass_x, glass_y, glass_width, glass_height, h_bars, v_bars, bar_width, opening_index:, cell_index:, panel_index:, sash_index:, removed_glazebars:, advanced_glazebar: nil)
            dxf = ""

            adv = advanced_glazebar.is_a?(Hash) ? advanced_glazebar : {}
            margin_enabled = adv[:margin_enabled]  == true
            margin_offset  = (adv[:margin_offset]  || 0).to_f
            arch_enabled   = adv[:arch_enabled]    == true
            arch_amount    = [[(adv[:arch_amount]  || 1).to_i, 1].max, 8].min
            arch_height    = (adv[:arch_height]    || 0).to_f
            arch_height_mm = (adv[:arch_height_mm] || 0).to_f
            h_offset       = (adv[:h_offset]       || 0).to_f                                       # <-- Uniform vertical nudge (mm, positive = up)

            effective_glass_height = glass_height
            if arch_enabled && arch_height > 0 && arch_amount >= 1
                bay_w = glass_width.to_f / arch_amount
                total_zone = na_gothic_total_zone_height_dxf(bay_w, arch_height)
                effective_glass_height = [glass_height - total_zone, 0].max
            end

            if h_bars > 0 && effective_glass_height > 0
                h_positions = na_compute_bar_positions_dxf(glass_y, effective_glass_height, h_bars, margin_enabled, margin_offset)
                h_positions = h_positions.map { |y| y + h_offset } if h_offset != 0.0               # <-- Was packed but never applied pre-V1.3.0 (DXF/3D parity fix)
                h_positions = na_apply_bar_offsets_dxf(h_positions, adv[:h_bar_offsets])            # <-- Per-bar vertical nudges
                h_positions.each_with_index do |bar_center_y, idx|
                    b = idx + 1
                    next if na_glazebar_removed?(removed_glazebars, opening_index, cell_index, panel_index, sash_index, "horizontal", b)

                    bar_y = bar_center_y - (bar_width / 2.0)
                    dxf += na_dxf_rect(glass_x, bar_y, glass_width, bar_width, NA_LAYER_GLAZE_BAR)
                end
            end

            arch_align_vbars_dxf = arch_enabled && !margin_enabled && (v_bars + 1 == arch_amount)
            if v_bars > 0 && effective_glass_height > 0
                v_positions = if arch_align_vbars_dxf
                                  na_compute_arch_aligned_bar_positions_dxf(glass_x, glass_width, v_bars, bar_width, arch_amount)
                              else
                                  na_compute_bar_positions_dxf(glass_x, glass_width, v_bars, margin_enabled, margin_offset)
                              end
                v_positions = na_apply_bar_offsets_dxf(v_positions, adv[:v_bar_offsets])            # <-- Per-bar horizontal nudges
                v_positions.each_with_index do |bar_center_x, idx|
                    b = idx + 1
                    next if na_glazebar_removed?(removed_glazebars, opening_index, cell_index, panel_index, sash_index, "vertical", b)

                    bar_x = bar_center_x - (bar_width / 2.0)
                    dxf += na_dxf_rect(bar_x, glass_y, bar_width, effective_glass_height, NA_LAYER_GLAZE_BAR)
                end
            end

            if arch_enabled && arch_height > 0 && arch_amount >= 1
                springing_y = glass_y + effective_glass_height
                dxf += na_generate_gothic_arch_dxf(glass_x, springing_y, glass_width, arch_height, arch_amount, bar_width, arch_height_mm)
            end

            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Per-Bar Offset Application (DXF copy)
        # ------------------------------------------------------------
        # Local mirror of GeometryBuilders.na_apply_bar_offsets, kept
        # local to avoid cross-loading the geometry builders.
        def self.na_apply_bar_offsets_dxf(positions, offsets)
            return positions unless positions.is_a?(Array) && offsets.is_a?(Array) && !offsets.empty?
            positions.each_with_index.map do |position, index|
                offset = offsets[index]
                offset.is_a?(Numeric) ? position + offset : position
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Margin-Aware Bar Centerline Positions (DXF copy)
        # ------------------------------------------------------------
        # Local copy that mirrors GeometryBuilders.na_compute_bar_positions
        # (3D Ruby) and Na__GlazebarMath.na_computeBarPositions (2D JS) so
        # all three representations stay in lockstep. Kept local to avoid
        # cross-loading the geometry builders into the DXF path.
        def self.na_compute_bar_positions_dxf(start, size, count, margin_enabled, margin_offset)
            return [] if count.nil? || count <= 0

            if !margin_enabled || count < 2
                step = size.to_f / (count + 1)
                return (1..count).map { |i| start + step * i }
            end

            first_pos = start + margin_offset
            last_pos  = start + size - margin_offset
            return [first_pos, last_pos] if count == 2

            inner_step = (last_pos - first_pos) / (count - 1).to_f
            (0...count).map { |i| first_pos + inner_step * i }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arch-Aligned Bar Positions (DXF Helper)
        # ------------------------------------------------------------
        # Local mirror of GeometryBuilders.na_compute_arch_aligned_bar_positions
        # so the DXF stream stays in lockstep with the SketchUp solid and
        # the SVG preview.
        def self.na_compute_arch_aligned_bar_positions_dxf(glass_start, glass_size, count, bar_width, arch_amount)
            return [] if count.nil? || count <= 0 || arch_amount.nil? || arch_amount < 2
            half_bar = bar_width / 2.0
            ext_glass_start = glass_start - half_bar
            ext_glass_size  = glass_size  + (2 * half_bar)
            ext_bay_width   = ext_glass_size / arch_amount.to_f
            (0...count).map { |i| ext_glass_start + (i + 1) * ext_bay_width }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Emit Gothic Arch Polyline Outlines For DXF
        # ------------------------------------------------------------
        # Emits each arc-half as a closed POLYLINE traversing the outer
        # arc and back along the inner arc. The arch zone is first
        # extended by half_bar on each side and on top, then each
        # polygon is clipped (Sutherland-Hodgman) against the glass
        # rectangle so the DXF stream matches the SketchUp solid: clean
        # plumb edges where the arches meet the casement stiles and
        # top rail, no curved tangent overshoot left in the casement.
        def self.na_generate_gothic_arch_dxf(glass_left_x, springing_y, glass_width, arch_height, arch_amount, bar_width, arch_height_mm)
            dxf = ""
            half_bar = bar_width / 2.0

            ext_glass_left  = glass_left_x - half_bar
            ext_glass_width = glass_width  + (2 * half_bar)
            ext_arch_height = arch_height  + half_bar
            ext_bay_width   = ext_glass_width.to_f / arch_amount
            segments_per_arc = na_gothic_segments_for_arch_height(arch_height_mm)

            # Clip rectangle's TOP edge must sit at the true glass top
            # (inside of casement header), which is springing_y plus the
            # total zone height (apex + overshoot). Using arch_height
            # alone clipped at the apex and removed the overshoot ring.
            original_bay_width = glass_width.to_f / arch_amount
            total_zone_height  = na_gothic_total_zone_height_dxf(original_bay_width, arch_height)

            clip_rect = {
                x_min: glass_left_x,
                x_max: glass_left_x + glass_width,
                y_min: springing_y,
                y_max: springing_y + total_zone_height
            }

            (0...arch_amount).each do |bay_index|
                bay_left = ext_glass_left + (bay_index * ext_bay_width)
                params = na_compute_gothic_arc_params_dxf(ext_bay_width, ext_arch_height)
                r_out = params[:radius] + half_bar
                r_in  = [params[:radius] - half_bar, 0.01].max

                dxf += na_emit_arc_ring_polyline_dxf(
                    bay_left + params[:left_center_x], springing_y,
                    r_out, r_in, params[:left_start_ang], params[:left_end_ang],
                    segments_per_arc, clip_rect
                )
                dxf += na_emit_arc_ring_polyline_dxf(
                    bay_left + params[:right_center_x], springing_y,
                    r_out, r_in, params[:right_start_ang], params[:right_end_ang],
                    segments_per_arc, clip_rect
                )
            end

            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Emit One Closed Ring-Segment Polyline (DXF, clipped)
        # ------------------------------------------------------------
        # Walks the outer arc start->end then the inner arc end->start
        # to produce a single closed polyline footprint on the
        # NA_GLAZEBAR layer, then clips it against the glass rectangle.
        def self.na_emit_arc_ring_polyline_dxf(cx, cy, r_out, r_in, start_ang, end_ang, segments, clip_rect = nil)
            seg = [segments.to_i, 8].max
            points = []
            (0..seg).each do |i|
                t = i.to_f / seg
                ang = start_ang + (end_ang - start_ang) * t
                points << [cx + r_out * Math.cos(ang), cy + r_out * Math.sin(ang)]
            end
            (0..seg).to_a.reverse.each do |i|
                t = i.to_f / seg
                ang = start_ang + (end_ang - start_ang) * t
                points << [cx + r_in * Math.cos(ang), cy + r_in * Math.sin(ang)]
            end

            points = na_clip_polygon_to_aabb(points, clip_rect) if clip_rect
            return "" if points.nil? || points.length < 3

            na_dxf_polygon(points, NA_LAYER_GLAZE_BAR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clip a Polygon Against an Axis-Aligned Bounding Box
        # ------------------------------------------------------------
        # Standard Sutherland-Hodgman polygon clipping against the four
        # edges of the rectangle in turn. `points` is an Array of [x, y]
        # pairs ordered in either winding direction.
        # `clip_rect` is { x_min:, x_max:, y_min:, y_max: }.
        def self.na_clip_polygon_to_aabb(points, clip_rect)
            output = points
            output = na_clip_polygon_against_edge(output, :left,   clip_rect[:x_min])
            output = na_clip_polygon_against_edge(output, :right,  clip_rect[:x_max])
            output = na_clip_polygon_against_edge(output, :bottom, clip_rect[:y_min])
            output = na_clip_polygon_against_edge(output, :top,    clip_rect[:y_max])
            output
        end
        # ---------------------------------------------------------------

        # FUNCTION | Sutherland-Hodgman Step: Clip Against One Edge
        # ------------------------------------------------------------
        # `side` is :left | :right | :bottom | :top. `bound` is the
        # axis-aligned coordinate of the clip line.
        def self.na_clip_polygon_against_edge(poly, side, bound)
            return [] if poly.nil? || poly.empty?

            inside = lambda do |pt|
                case side
                when :left   then pt[0] >= bound
                when :right  then pt[0] <= bound
                when :bottom then pt[1] >= bound
                when :top    then pt[1] <= bound
                end
            end

            intersect_pt = lambda do |a, b|
                case side
                when :left, :right
                    t = (bound - a[0]).to_f / (b[0] - a[0])
                    [bound, a[1] + t * (b[1] - a[1])]
                when :bottom, :top
                    t = (bound - a[1]).to_f / (b[1] - a[1])
                    [a[0] + t * (b[0] - a[0]), bound]
                end
            end

            result = []
            prev = poly.last
            prev_in = inside.call(prev)
            poly.each do |curr|
                curr_in = inside.call(curr)
                if curr_in
                    result << intersect_pt.call(prev, curr) unless prev_in
                    result << curr
                elsif prev_in
                    result << intersect_pt.call(prev, curr)
                end
                prev    = curr
                prev_in = curr_in
            end
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Total Visible Arch Zone Height (DXF Helper)
        # ------------------------------------------------------------
        # Mirror of na_compute_gothic_total_zone_height in 3D Ruby. Used
        # to shrink the effective glass height by the FULL arch zone
        # (apex + overshoot) so DXF matches 3D + SVG.
        def self.na_gothic_total_zone_height_dxf(bay_width, apex_height)
            params = na_compute_gothic_arc_params_dxf(bay_width, apex_height)
            terminus_y = params[:radius] * Math.sin(params[:left_end_ang])
            [apex_height, terminus_y].max
        end
        # ---------------------------------------------------------------

        # FUNCTION | Gothic Arc Parameters (DXF Helper, Mirror Of JS / 3D)
        # ------------------------------------------------------------
        def self.na_compute_gothic_arc_params_dxf(bay_width, arch_height)
            w = [bay_width.to_f, 0.0001].max
            h = [arch_height.to_f, 0.0001].max
            c = (w / 4.0) + (h * h) / w
            right_center_x = w - c
            {
                radius:           c,
                left_center_x:    c,
                right_center_x:   right_center_x,
                left_start_ang:   Math::PI,
                left_end_ang:     Math.atan2(h, (w / 2.0) - c) - (15.0 * Math::PI / 180.0),
                right_start_ang:  0.0,
                right_end_ang:    Math.atan2(h, (w / 2.0) - right_center_x) + (15.0 * Math::PI / 180.0)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tessellation Count Table (DXF copy of 3D Ruby helper)
        # ------------------------------------------------------------
        def self.na_gothic_segments_for_arch_height(arch_height_mm)
            h = arch_height_mm.to_f
            return 24 if h < 450.0
            return 36 if h <= 600.0
            48
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Meeting Rail Height Within a Sash Cell
        # ------------------------------------------------------------
        # Mirrors SvgGenerator.na_resolveMeetingRailHeight so the exported
        # DXF matches the 2D preview. Positive offset drives the meeting
        # rail UP, clamped to 10%-90% of the cell height. All mm.
        def self.na_resolve_meeting_rail_height(cell_height, offset_mm)
            height_value = cell_height.to_f
            centre_split = height_value / 2.0
            offset_value = offset_mm.to_f
            return centre_split if offset_value == 0.0
            [[centre_split + offset_value, height_value * 0.10].max, height_value * 0.90].min
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate DXF for Sliding Sash Panel
        # ------------------------------------------------------------
        # Draws two stacked casements in one panel.
        # Bottom sash is extended by overlap amount to represent weathering tuck-under.
        def self.na_generate_sliding_sash_panel_dxf(x, y, width, height, top_rail, bottom_rail, top_sash_bottom_rail, bottom_sash_top_rail, left_stile, right_stile, h_bars, v_bars, bar_width, overlap_mm, meeting_rail_offset_mm, opening_index:, cell_index:, panel_index:, removed_glazebars:, sash_horns_enabled:, sash_horn_type:, advanced_glazebar: nil)
            dxf = ""

            meeting_rail_y = na_resolve_meeting_rail_height(height, meeting_rail_offset_mm)
            bottom_sash_height = meeting_rail_y                                                    # <-- Cell floor up to the meeting rail
            top_sash_height = height.to_f - meeting_rail_y                                         # <-- Meeting rail up to the cell head
            sash_overlap = [[overlap_mm.to_f, top_sash_height - 1.0].min, 0.0].max

            # Bottom sash: arch decoration is suppressed (architectural
            # tracery belongs at the head of the assembly only). Margin
            # glazing still applies.
            advanced_no_arch = nil
            if advanced_glazebar.is_a?(Hash)
                advanced_no_arch = advanced_glazebar.merge(arch_enabled: false, arch_amount: 0, arch_height: 0)
            end

            dxf += na_generate_casement_dxf(
                x, y, width, bottom_sash_height + sash_overlap,
                bottom_sash_top_rail, bottom_rail, left_stile, right_stile,
                h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: 1,
                removed_glazebars: removed_glazebars,
                advanced_glazebar: advanced_no_arch
            )

            # Top sash gets the full advanced_glazebar (margin + arches).
            dxf += na_generate_casement_dxf(
                x, y + meeting_rail_y, width, top_sash_height,
                top_rail, top_sash_bottom_rail, left_stile, right_stile,
                h_bars, v_bars, bar_width,
                opening_index: opening_index, cell_index: cell_index, panel_index: panel_index, sash_index: 0,
                removed_glazebars: removed_glazebars,
                advanced_glazebar: advanced_glazebar
            )

            if sash_horns_enabled
                dxf += na_generate_sash_horn_dxf(
                    sash_horn_type,
                    x,
                    y + meeting_rail_y,
                    width,
                    left_stile,
                    right_stile
                )
            end

            dxf
        end
        # ---------------------------------------------------------------

        # FUNCTION | Generate Sash Horn DXF Polygons
        # ------------------------------------------------------------
        def self.na_generate_sash_horn_dxf(type, panel_x, top_sash_bottom_y, panel_width, left_stile, right_stile)
            SashHornBuilder.na_build_profiles_mm(type, panel_x, top_sash_bottom_y, panel_width, left_stile, right_stile).map do |profile|
                na_dxf_polygon(profile[:points], NA_LAYER_CASEMENT)
            end.join
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

        # FUNCTION | Generate DXF Polygon
        # ------------------------------------------------------------
        def self.na_dxf_polygon(points, layer)
            return "" unless points.is_a?(Array) && points.length >= 3

            dxf = ""
            points.each_with_index do |point, index|
                next_point = points[(index + 1) % points.length]
                dxf += na_dxf_line(point[:x], point[:z], next_point[:x], next_point[:z], layer)
            end
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
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
