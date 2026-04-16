# =============================================================================
# NA EDGE UTIL - PAINT DEEP NESTED EDGES - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Main orchestrator for the standalone Paint Deep Nested Edges tool
# CREATED    : 2026
#
# DESCRIPTION:
# - Paints selected nested SketchUp edges using a predefined architectural palette.
# - Recursively traverses groups and component instances to collect deep nested edges.
# - Loads MTE edge colour data from the centralised Na__DataLib via URL/cache/fallback.
# - Loads plugin UI configuration (dialog size, title, etc.) from local EdgeConfigData JSON.
# - Loads the HtmlDialog layout from external HTML and CSS files.
# - Delegates SketchUp menu and shortcut registration to the Hotkey Binder module.
#
# -----------------------------------------------------------------------------
#
# DATA SOURCE - SINGLE SOURCE OF TRUTH
# All colour and tag data is loaded from the centralised Na__DataLib:
#
#   Edge Materials (MTE colours):
#     Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json
#     -> MTE{NNN}__ edge colour palette (greyscale + accent colours)
#     -> Loaded via Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials)
#
#   Tags (Layout linework thickness mapping):
#     Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json
#     -> 03__LayoutDrawingLineworkTags__ section maps MTE colours to Layout tags
#     -> Loaded via Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
#
# Data is fetched from GitHub (primary), cached locally for 30 minutes,
# with local plugin folder fallback if the web is unreachable.
# Plugin UI config (dialog size, title, menus) remains in local EdgeConfigData.json.
#
#
# =============================================================================

require 'sketchup.rb'
require 'json'

require_relative 'Na__EdgeUtil__PaintDeepNestedEdges__HotkeyBinder__'
require_relative 'Na__EdgeUtil__PaintDeepNestedEdges__PaletteManager__'
require_relative 'Na__EdgeUtil__PaintDeepNestedEdges__ApplyLineThicknessTags__'
require_relative 'Na__EdgeUtil__PaintDeepNestedEdges__RefreshPluginData__'
require_relative '10__EdgeUtil__EdgeRepairModules/Na__EdgeUtil__RepairUtil__EdgeCleaner__Module__'
require_relative '10__EdgeUtil__EdgeRepairModules/Na__EdgeUtil__RepairUtil__RepairCorner__Module__'
require_relative '10__EdgeUtil__EdgeRepairModules/Na__EdgeUtil__GeomUtil__AddPointsAlongPatrh__Module__'
require_relative '10__EdgeUtil__EdgeRepairModules/Na__EdgeUtil__GeomUtil__ChamferEdgeCorners__Module__'
require_relative '../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Module Constants and File Paths
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | File Paths
    # ------------------------------------------------------------
    NA_PLUGIN_ROOT          = File.dirname(__FILE__).freeze
    NA_EDGE_CONFIG_FILE     = File.join(NA_PLUGIN_ROOT, 'Na__EdgeUtil__PaintDeepNestedEdges__EdgeConfigData__.json').freeze
    NA_UI_LAYOUT_FILE       = File.join(NA_PLUGIN_ROOT, 'Na__EdgeUtil__PaintDeepNestedEdges__UiLayout__.html').freeze
    NA_STYLESHEET_FILE      = File.join(NA_PLUGIN_ROOT, 'Na__EdgeUtil__PaintDeepNestedEdges__Styles__.css').freeze
    NA_UI_HELPERS_FILE      = File.join(NA_PLUGIN_ROOT, '10__EdgeUtil__EdgeRepairModules', 'Na__EdgeUtil__UiHelpers__.js').freeze
    # ------------------------------------------------------------

    # MODULE VARIABLES | State Management
    # ------------------------------------------------------------
    @na_dialog            = nil
    @na_edge_config_data  = nil                                               # <-- Local plugin UI config (dialog size, title, etc.)
    @na_mte_data          = nil                                               # <-- Centralised MTE edge colour data from DataLib
    @na_mte_colours       = nil                                               # <-- Flattened { SketchUpName => HexValue } colour hash
    @na_mte_swatches      = nil                                               # <-- Array of { key, hex, swatch_name } for Swatches tab
    @na_mte_meta          = nil                                               # <-- MTE meta block (uiDefaults, naming convention, etc.)
    @na_selection_observer = nil
    @na_observed_selection = nil
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Local Plugin UI Configuration (dialog size, title, menus)
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Load Local Plugin UI Config
    # ---------------------------------------------------------------
    def self.na_edge_config_data
        return @na_edge_config_data if @na_edge_config_data

        json_content = File.read(NA_EDGE_CONFIG_FILE)
        @na_edge_config_data = JSON.parse(json_content)
        return @na_edge_config_data
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Extension Display Name
    # ---------------------------------------------------------------
    def self.na_extension_name
        na_edge_config_data.fetch('extension_name', 'Na Edge Util - Paint Deep Nested Edges')
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Dialog Title
    # ---------------------------------------------------------------
    def self.na_dialog_title
        na_edge_config_data.fetch('dialog_title', na_extension_name)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Dialog Preferences Key
    # ---------------------------------------------------------------
    def self.na_dialog_preferences_key
        na_edge_config_data.fetch('dialog_preferences_key', 'Na__EdgeUtil__PaintDeepNestedEdges')
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Shortcut Command Name
    # ---------------------------------------------------------------
    def self.na_command_name
        na_edge_config_data.fetch('command_name', na_extension_name)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Command Tooltip
    # ---------------------------------------------------------------
    def self.na_command_tooltip
        na_edge_config_data.fetch('command_tooltip', 'Open the Paint Deep Nested Edges dialogue')
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Command Status Bar Text
    # ---------------------------------------------------------------
    def self.na_command_status_bar_text
        na_edge_config_data.fetch('command_status_bar_text', 'Paint selected nested SketchUp edges')
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Menu Text
    # ---------------------------------------------------------------
    def self.na_menu_text
        na_edge_config_data.fetch('menu_text', na_extension_name)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Edge Tools Configuration Block
    # ---------------------------------------------------------------
    def self.na_edge_tools_config
        na_edge_config_data.fetch('edge_tools', {})
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Edge Cleaner Command Name
    # ---------------------------------------------------------------
    def self.na_edge_cleaner_command_name
        na_edge_tools_config.dig('edge_cleaner', 'command_name') || 'Na Edge Util - Edge Cleaner'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Edge Cleaner Command Tooltip
    # ---------------------------------------------------------------
    def self.na_edge_cleaner_command_tooltip
        na_edge_tools_config.dig('edge_cleaner', 'tooltip') || 'Remove redundant colinear vertices from selected edges'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Edge Cleaner Status Bar Text
    # ---------------------------------------------------------------
    def self.na_edge_cleaner_command_status_bar_text
        na_edge_tools_config.dig('edge_cleaner', 'status_bar_text') || 'Run Edge Cleaner on selected edges'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Edge Cleaner Menu Text
    # ---------------------------------------------------------------
    def self.na_edge_cleaner_menu_text
        na_edge_tools_config.dig('edge_cleaner', 'menu_text') || na_edge_cleaner_command_name
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Repair Corner Command Name
    # ---------------------------------------------------------------
    def self.na_repair_corner_command_name
        na_edge_tools_config.dig('repair_edge_corners', 'command_name') || 'Na Edge Util - Repair Edge Corners'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Repair Corner Command Tooltip
    # ---------------------------------------------------------------
    def self.na_repair_corner_command_tooltip
        na_edge_tools_config.dig('repair_edge_corners', 'tooltip') || 'Repair loose edge corners up to the configured maximum distance'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Repair Corner Status Bar Text
    # ---------------------------------------------------------------
    def self.na_repair_corner_command_status_bar_text
        na_edge_tools_config.dig('repair_edge_corners', 'status_bar_text') || 'Repair selected corner gaps'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Repair Corner Menu Text
    # ---------------------------------------------------------------
    def self.na_repair_corner_menu_text
        na_edge_tools_config.dig('repair_edge_corners', 'menu_text') || na_repair_corner_command_name
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Insert Points Command Name
    # ---------------------------------------------------------------
    def self.na_insert_points_command_name
        na_edge_tools_config.dig('insert_points_along_paths', 'command_name') || 'Na Edge Util - Insert Points Along Paths'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Insert Points Command Tooltip
    # ---------------------------------------------------------------
    def self.na_insert_points_command_tooltip
        na_edge_tools_config.dig('insert_points_along_paths', 'tooltip') || 'Insert evenly spaced points along the selected edge path'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Insert Points Status Bar Text
    # ---------------------------------------------------------------
    def self.na_insert_points_command_status_bar_text
        na_edge_tools_config.dig('insert_points_along_paths', 'status_bar_text') || 'Subdivide selected path edges into equal segments'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Insert Points Menu Text
    # ---------------------------------------------------------------
    def self.na_insert_points_menu_text
        na_edge_tools_config.dig('insert_points_along_paths', 'menu_text') || na_insert_points_command_name
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Chamfer Edge Corners Command Name
    # ---------------------------------------------------------------
    def self.na_chamfer_edge_corners_command_name
        na_edge_tools_config.dig('chamfer_edge_corners', 'command_name') || 'Na Edge Util - Chamfer Edge Corners'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Chamfer Edge Corners Command Tooltip
    # ---------------------------------------------------------------
    def self.na_chamfer_edge_corners_command_tooltip
        na_edge_tools_config.dig('chamfer_edge_corners', 'tooltip') || 'Chamfer selected corners with optional corner-building prepass'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Chamfer Edge Corners Status Bar Text
    # ---------------------------------------------------------------
    def self.na_chamfer_edge_corners_command_status_bar_text
        na_edge_tools_config.dig('chamfer_edge_corners', 'status_bar_text') || 'Run chamfer corner tool on selected edges'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Chamfer Edge Corners Menu Text
    # ---------------------------------------------------------------
    def self.na_chamfer_edge_corners_menu_text
        na_edge_tools_config.dig('chamfer_edge_corners', 'menu_text') || na_chamfer_edge_corners_command_name
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Dialog Width
    # ---------------------------------------------------------------
    def self.na_dialog_width
        na_edge_config_data.fetch('dialog_width', 460).to_i
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Dialog Height
    # ---------------------------------------------------------------
    def self.na_dialog_height
        na_edge_config_data.fetch('dialog_height', 260).to_i
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Dialog Resizable Flag
    # ---------------------------------------------------------------
    def self.na_dialog_resizable
        na_edge_config_data.fetch('dialog_resizable', true)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Register Menu and Shortcut Binder
    # ------------------------------------------------------------
    def self.na_register_hotkey_and_menu
        Na__HotkeyBinder.na_register_hotkey_and_menu
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run Edge Cleaner Tool Action
    # ------------------------------------------------------------
    def self.na_run_edge_cleaner
        Na__EdgeTools__EdgeCleaner.Na__EdgeTools__EdgeCleaner__Execute
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run Repair Corner Tool Action
    # ------------------------------------------------------------
    def self.na_run_repair_edge_corners(max_gap_mm = nil)
        Na__EdgeTools__RepairEdgeCorners.Na__EdgeTools__RepairEdgeCorners__ExecuteRepair(max_gap_mm)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run Insert Points Along Paths Tool Action
    # ------------------------------------------------------------
    def self.na_run_insert_points_along_paths
        Na__EdgeTools__InsertPointsAlongPaths.Na__EdgeTools__InsertPointsAlongPaths__Execute
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run Chamfer Edge Corners Tool Action
    # ------------------------------------------------------------
    def self.na_run_chamfer_edge_corners(chamfer_size_mm = nil, build_corners_enabled = nil, build_corner_max_gap_mm = nil)
        Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__Execute(
            chamfer_size_mm,
            build_corners_enabled,
            build_corner_max_gap_mm
        )
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Centralised MTE Edge Colour Data (from Na__DataLib)
# -----------------------------------------------------------------------------

    # FUNCTION | Load MTE Edge Colour Data from DataLib
    # ------------------------------------------------------------
    def self.na_load_mte_data
        return @na_mte_data if @na_mte_data

        @na_mte_data = Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials)

        if @na_mte_data
            @na_mte_meta    = @na_mte_data["meta"]
            result          = na_flatten_mte_series(@na_mte_data)
            @na_mte_colours  = result[:colours]
            @na_mte_swatches = result[:swatches]
            puts "    [EdgePainter] MTE data loaded: #{@na_mte_colours.size} colours"
        else
            puts "    [EdgePainter] WARNING: MTE data unavailable, colour palette will be empty"
            @na_mte_meta     = {}
            @na_mte_colours  = {}
            @na_mte_swatches = []
        end

        @na_mte_data
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Flatten MTE Series Groups into Colour Hash and Swatch Array
    # ---------------------------------------------------------------
    def self.na_flatten_mte_series(mte_data)
        flat     = {}
        swatches = []
        library  = mte_data["Na__DataLib__CoreIndex__EdgeMaterials"]
        return { colours: flat, swatches: swatches } unless library.is_a?(Hash)

        library.each do |_series_key, series|
            next unless series.is_a?(Hash)

            series.each do |_entry_key, config|
                next unless config.is_a?(Hash)

                if config["IsReserved"] && config["IsDefault"]
                    flat["Default"] = "default"
                    swatches << { key: "Default", hex: "#FFFFFF", swatch_name: "Default" }
                else
                    sketchup_name = config["SketchUpName"]
                    next unless sketchup_name && !sketchup_name.empty?
                    hex_value   = config["HexValue"]
                    swatch_name = config["SwatchName"] || sketchup_name
                    flat[sketchup_name] = hex_value
                    swatches << { key: sketchup_name, hex: hex_value, swatch_name: swatch_name }
                end
            end
        end

        { colours: flat, swatches: swatches }
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Swatch Data Array for Swatches Tab
    # ---------------------------------------------------------------
    def self.na_swatches
        na_load_mte_data unless @na_mte_swatches
        @na_mte_swatches || []
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Configured MTE Colour Palette
    # ---------------------------------------------------------------
    def self.na_colours
        na_load_mte_data unless @na_mte_colours
        @na_mte_colours || {}
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Default Colour Key
    # ---------------------------------------------------------------
    def self.na_default_colour_key
        na_load_mte_data unless @na_mte_meta
        ui_defaults = @na_mte_meta && @na_mte_meta["uiDefaults"]
        ui_defaults ? ui_defaults.fetch("DefaultColourKey", "Default") : "Default"
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Default Quick Palette Colour Key
    # ---------------------------------------------------------------
    def self.na_dynamic_palette_default_key
        na_load_mte_data unless @na_mte_meta
        ui_defaults = @na_mte_meta && @na_mte_meta["uiDefaults"]
        configured_default_key = ui_defaults ? ui_defaults.fetch("DynamicPaletteDefaultKey", "") : ""
        return configured_default_key if na_colours.key?(configured_default_key)

        detected_white_key = na_colours.find { |_colour_key, colour_spec| colour_spec.to_s.upcase == '#FFFFFF' }
        return detected_white_key[0] if detected_white_key

        return na_default_colour_key
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Quick Palette Slot Count
    # ---------------------------------------------------------------
    def self.na_dynamic_palette_slot_count
        na_load_mte_data unless @na_mte_meta
        ui_defaults = @na_mte_meta && @na_mte_meta["uiDefaults"]
        ui_defaults ? ui_defaults.fetch("DynamicPaletteSlotCount", 4).to_i : 4
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Collection and Analysis Helper Functions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Count Selected Edges for User Feedback
    # ---------------------------------------------------------------
    def self.na_edge_count_selection
        model = Sketchup.active_model
        return 0 unless model

        edges = []
        model.selection.each { |entity| na_collect_edges(entity, edges) }
        return edges.length
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Recursively Collect Edges From Entities
    # ---------------------------------------------------------------
    def self.na_collect_edges(entity, bucket)
        case entity
        when Sketchup::Edge
            bucket << entity
        when Sketchup::Group
            entity.entities.each { |child| na_collect_edges(child, bucket) }
        when Sketchup::ComponentInstance
            entity.definition.entities.each { |child| na_collect_edges(child, bucket) }
        else
            if entity.respond_to?(:entities)
                entity.entities.each { |child| na_collect_edges(child, bucket) }
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Creation and Colour Conversion Utilities
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Convert Hexadecimal Colour to RGB Values
    # ---------------------------------------------------------------
    def self.na_hex_to_rgb(hex)
        sanitized_hex = hex.to_s.strip.delete('#')
        return [0, 0, 0] unless sanitized_hex.length == 6

        return [sanitized_hex[0..1], sanitized_hex[2..3], sanitized_hex[4..5]].map { |channel| channel.to_i(16) }
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Convert HSL Colour Values to RGB
    # ---------------------------------------------------------------
    def self.na_hsl_to_rgb(hue, saturation, lightness)
        normalized_hue        = hue.to_f / 360.0
        normalized_saturation = saturation.to_f / 100.0
        normalized_lightness  = lightness.to_f / 100.0

        return Array.new(3, (normalized_lightness * 255).round) if normalized_saturation.zero?

        q = normalized_lightness < 0.5 ? normalized_lightness * (1 + normalized_saturation) : normalized_lightness + normalized_saturation - normalized_lightness * normalized_saturation
        p = 2 * normalized_lightness - q

        red   = na_hue_to_rgb(p, q, normalized_hue + 1.0 / 3)
        green = na_hue_to_rgb(p, q, normalized_hue)
        blue  = na_hue_to_rgb(p, q, normalized_hue - 1.0 / 3)

        return [(red * 255).round, (green * 255).round, (blue * 255).round]
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Convert Hue Segment to RGB Channel
    # ---------------------------------------------------------------
    def self.na_hue_to_rgb(p_value, q_value, hue_value)
        normalized_hue = hue_value
        normalized_hue += 1 if normalized_hue < 0
        normalized_hue -= 1 if normalized_hue > 1

        return p_value + (q_value - p_value) * 6 * normalized_hue if normalized_hue < 1.0 / 6
        return q_value if normalized_hue < 1.0 / 2
        return p_value + (q_value - p_value) * (2.0 / 3 - normalized_hue) * 6 if normalized_hue < 2.0 / 3

        return p_value
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Convert RGB Values to Hexadecimal Colour
    # ---------------------------------------------------------------
    def self.na_rgb_to_hex(red, green, blue)
        format('#%02X%02X%02X', red.to_i, green.to_i, blue.to_i)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Colour Hexadecimal For Colour Key
    # ---------------------------------------------------------------
    def self.na_colour_hex_for_key(colour_key)
        return '#FFFFFF' if colour_key == na_default_colour_key

        colour_specification = na_colours[colour_key]
        return '#FFFFFF' if colour_specification.nil? || colour_specification == 'default'
        return colour_specification if colour_specification.is_a?(String)

        rgb_values = na_hsl_to_rgb(
            colour_specification['h'],
            colour_specification['s'],
            colour_specification['l']
        )

        return na_rgb_to_hex(*rgb_values)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create or Retrieve Material For Colour Key
    # ------------------------------------------------------------
    def self.na_material_for_key(model, colour_key)
        return nil if colour_key == na_default_colour_key

        existing_material = model.materials[colour_key]
        return existing_material if existing_material

        colour_specification = na_colours[colour_key]
        return nil if colour_specification.nil? || colour_specification == 'default'

        rgb_values = if colour_specification.is_a?(String)
            na_hex_to_rgb(colour_specification)
        else
            na_hsl_to_rgb(
                colour_specification['h'],
                colour_specification['s'],
                colour_specification['l']
            )
        end

        created_material = model.materials.add(colour_key)
        created_material.color = Sketchup::Color.new(*rgb_values)
        created_material.name  = colour_key
        return created_material
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Edge Painting Logic
# -----------------------------------------------------------------------------

    # FUNCTION | Apply Colour to Selected Nested Edges
    # ------------------------------------------------------------
    def self.na_paint_edges(colour_key)
        model = Sketchup.active_model
        return false unless model

        selection = model.selection

        if selection.empty?
            UI.messagebox('Select something first.')
            return false
        end

        edges = []
        selection.each { |entity| na_collect_edges(entity, edges) }

        if edges.empty?
            UI.messagebox('No edges found in selection.')
            return false
        end

        model.start_operation("PaintDeepNestedEdges #{colour_key}", true)

        begin
            material = na_material_for_key(model, colour_key)
            edges.each { |edge| edge.material = material }
            model.commit_operation
            return true
        rescue => error
            model.abort_operation
            UI.messagebox("Failed to paint edges.\n\n#{error.message}")
            return false
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HtmlDialog Rendering and Management
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Select Options Html From Colour Data
    # ---------------------------------------------------------------
    def self.na_build_options_html
        na_colours.keys.map { |colour_key| "<option value=\"#{colour_key}\">#{colour_key}</option>" }.join
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Swatches Tab Html Grid From MTE Data
    # ---------------------------------------------------------------
    def self.na_build_swatches_html
        na_swatches.map do |swatch|
            hex        = swatch[:hex] || "#FFFFFF"
            key_json   = swatch[:key].to_json
            label      = na_escape_html(swatch[:swatch_name])
            border_col = (swatch[:key] == "Default") ? "#b5b5b5" : hex

            <<~HTML_CELL.strip
            <div class="naSwatchCell" onclick='sketchup.apply_swatch_colour(#{key_json})' title="#{na_escape_html(swatch[:key])}">
                <div class="naSwatchCell__Colour" style="background-color: #{hex}; border-color: #{border_col};"></div>
                <span class="naSwatchCell__Name">#{label}</span>
            </div>
            HTML_CELL
        end.join("\n            ")
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Advanced Tab Mapping Table Html
    # ---------------------------------------------------------------
    def self.na_build_mapping_table_html
        entries = Na__ApplyLineThicknessTags.Na__LineTags__TagEntries
        return "<tr><td colspan='3'>No mapping data available</td></tr>" if entries.empty?

        entries.map do |entry|
            hex = na_colour_hex_for_key(entry[:colour_id])
            <<~HTML_ROW.strip
            <tr>
                <td><span class="naAdvanced__ColourSwatch" style="background-color: #{hex};"></span></td>
                <td>#{na_escape_html(entry[:colour_id])}</td>
                <td>#{na_escape_html(entry[:tag_name])}</td>
            </tr>
            HTML_ROW
        end.join("\n                ")
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Escape Text For Safe Html Output
    # ---------------------------------------------------------------
    def self.na_escape_html(text)
        text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
            .gsub("'", '&#39;')
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Load Dialog Html Template
    # ---------------------------------------------------------------
    def self.na_dialog_template_html
        File.read(NA_UI_LAYOUT_FILE)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Load Dialog Stylesheet Content
    # ---------------------------------------------------------------
    def self.na_dialog_stylesheet_content
        File.read(NA_STYLESHEET_FILE)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Load Dialog JavaScript Helper Content
    # ---------------------------------------------------------------
    def self.na_dialog_ui_helpers_script
        File.read(NA_UI_HELPERS_FILE)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Format Float for Html Number Input
    # ---------------------------------------------------------------
    def self.na_number_for_html_input(number_value)
        format('%.3f', number_value.to_f).sub(/\.?0+$/, '')
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Render Complete Dialog Html
    # ---------------------------------------------------------------
    def self.na_render_dialog_html
        initial_info                  = "#{na_edge_count_selection} edges selected."
        max_gap_mm_string             = na_number_for_html_input(
            Na__EdgeTools__RepairEdgeCorners.Na__EdgeTools__RepairEdgeCorners__StoredMaxGapMm
        )
        chamfer_size_mm_string        = na_number_for_html_input(
            Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__StoredChamferSizeMm
        )
        build_corners_enabled         = Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__StoredBuildCornersEnabled
        build_corners_checked_attr    = build_corners_enabled ? 'checked' : ''
        build_corner_config_class     = build_corners_enabled ? '' : 'naEdgeToolCard__ConfigBox--hidden'
        build_corner_max_gap_mm_string = na_number_for_html_input(
            Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__StoredBuildCornerMaxGapMm
        )

        return na_dialog_template_html
            .gsub('{{DIALOG_TITLE}}', na_dialog_title)
            .gsub('{{STYLESHEET_CONTENT}}', na_dialog_stylesheet_content)
            .gsub('{{UI_HELPERS_SCRIPT}}', na_dialog_ui_helpers_script)
            .gsub('{{DYNAMIC_PALETTE_HTML}}', Na__PaletteManager.na_build_palette_html)
            .gsub('{{OPTIONS_HTML}}', na_build_options_html)
            .gsub('{{SWATCHES_HTML}}', na_build_swatches_html)
            .gsub('{{MAPPING_TABLE_HTML}}', na_build_mapping_table_html)
            .gsub('{{REPAIR_CORNER_MAX_GAP_MM}}', max_gap_mm_string)
            .gsub('{{CHAMFER_SIZE_MM}}', chamfer_size_mm_string)
            .gsub('{{CHAMFER_BUILD_CORNERS_CHECKED}}', build_corners_checked_attr)
            .gsub('{{CHAMFER_BUILD_CORNER_CONFIG_CLASS}}', build_corner_config_class)
            .gsub('{{CHAMFER_BUILD_CORNER_MAX_GAP_MM}}', build_corner_max_gap_mm_string)
            .gsub('{{INITIAL_INFO}}', initial_info)
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Refresh Dialog Info and Dynamic Palette Content
    # ---------------------------------------------------------------
    def self.na_refresh_dialog_state(dialog, selected_colour_key = nil)
        selection_info_text = "#{na_edge_count_selection} edges selected."
        palette_html = Na__PaletteManager.na_build_palette_html

        dialog.execute_script("document.getElementById('info').textContent=#{selection_info_text.to_json};")
        dialog.execute_script("document.getElementById('quickPaletteRow').innerHTML=#{palette_html.to_json};")

        if selected_colour_key
            dialog.execute_script("document.getElementById('colour').value=#{selected_colour_key.to_json};")
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Write Status Text and Class to UI Element
    # ---------------------------------------------------------------
    def self.na_update_status_element(dialog, element_id, base_class, status_text, status_modifier = nil)
        full_class = [base_class, status_modifier].compact.join(' ')
        dialog.execute_script("var el=document.getElementById(#{element_id.to_json}); if(el){el.textContent=#{status_text.to_json}; el.className=#{full_class.to_json};}")
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Handle Selection Changes While Dialog Is Open
    # ---------------------------------------------------------------
    def self.na_handle_selection_changed
        return unless @na_dialog
        return unless @na_dialog.visible?

        selection_info_text = "#{na_edge_count_selection} edges selected."
        @na_dialog.execute_script("var el=document.getElementById('info'); if(el){el.textContent=#{selection_info_text.to_json};}")
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Attach Selection Observer to Active Model Selection
    # ---------------------------------------------------------------
    def self.na_attach_selection_observer
        model = Sketchup.active_model
        return unless model

        selection = model.selection
        return if @na_observed_selection == selection && @na_selection_observer

        na_detach_selection_observer

        @na_selection_observer ||= Na__DialogSelectionObserver.new
        selection.add_observer(@na_selection_observer)
        @na_observed_selection = selection
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Detach Selection Observer from Previous Selection
    # ---------------------------------------------------------------
    def self.na_detach_selection_observer
        return unless @na_observed_selection && @na_selection_observer

        @na_observed_selection.remove_observer(@na_selection_observer)
        @na_observed_selection = nil
    rescue StandardError
        @na_observed_selection = nil
    end
    # ---------------------------------------------------------------

    # OBSERVER CLASS | Listen to SketchUp Selection Events
    # ---------------------------------------------------------------
    class Na__DialogSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_selection)
            Na__EdgeUtil__PaintDeepNestedEdges.na_handle_selection_changed
        end

        def onSelectionAdded(_selection, _entity)
            Na__EdgeUtil__PaintDeepNestedEdges.na_handle_selection_changed
        end

        def onSelectionRemoved(_selection, _entity)
            Na__EdgeUtil__PaintDeepNestedEdges.na_handle_selection_changed
        end

        def onSelectionCleared(_selection)
            Na__EdgeUtil__PaintDeepNestedEdges.na_handle_selection_changed
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Configure Dialog Callbacks For User Interaction
    # ---------------------------------------------------------------
    def self.na_setup_dialog_callbacks(dialog)
        dialog.add_action_callback('apply_colour') do |_context, colour_key|
            if na_paint_edges(colour_key)
                Na__PaletteManager.na_remember_colour(colour_key)
                na_refresh_dialog_state(dialog, colour_key)
            end
        end

        dialog.add_action_callback('apply_palette_colour') do |_context, colour_key|
            if na_paint_edges(colour_key)
                Na__PaletteManager.na_remember_colour(colour_key)
                na_refresh_dialog_state(dialog, colour_key)
            end
        end

        dialog.add_action_callback('apply_swatch_colour') do |_context, colour_key|
            if na_paint_edges(colour_key)
                Na__PaletteManager.na_remember_colour(colour_key)
                na_refresh_dialog_state(dialog, colour_key)
            end
        end

        dialog.add_action_callback('apply_line_tags') do |_context, _value|
            result         = Na__ApplyLineThicknessTags.Na__LineTags__ApplyToModel
            status_text    = "#{result[:applied]} tagged, #{result[:untagged]} moved to Untagged, #{result[:skipped]} errors (#{result[:total_edges]} total scanned)"
            status_modifier = result[:errors].empty? ? "naAdvanced__Status--success" : "naAdvanced__Status--error"
            na_update_status_element(dialog, 'advancedStatus', 'naAdvanced__Status', status_text, status_modifier)
        end

        dialog.add_action_callback('run_edge_cleaner') do |_context, _value|
            result         = Na__EdgeTools__EdgeCleaner.Na__EdgeTools__EdgeCleaner__Execute
            status_modifier = result[:success] ? 'naEdgeTools__Status--success' : 'naEdgeTools__Status--error'
            na_update_status_element(dialog, 'edgeToolsStatus', 'naEdgeTools__Status', result[:message], status_modifier)
            na_refresh_dialog_state(dialog)
        end

        dialog.add_action_callback('set_repair_corner_max_gap_mm') do |_context, max_gap_mm|
            stored_value = Na__EdgeTools__RepairEdgeCorners.Na__EdgeTools__RepairEdgeCorners__SetStoredMaxGapMm(max_gap_mm)
            update_script = "var input=document.getElementById('naRepairCornerMaxGapMm'); if(input){input.value=#{na_number_for_html_input(stored_value).to_json};}"
            dialog.execute_script(update_script)
        end

        dialog.add_action_callback('run_repair_corners') do |_context, max_gap_mm|
            result = Na__EdgeTools__RepairEdgeCorners.Na__EdgeTools__RepairEdgeCorners__ExecuteRepair(max_gap_mm)
            status_modifier = result[:success] ? 'naEdgeTools__Status--success' : 'naEdgeTools__Status--error'
            na_update_status_element(dialog, 'edgeToolsStatus', 'naEdgeTools__Status', result[:message], status_modifier)
            na_refresh_dialog_state(dialog)
        end

        dialog.add_action_callback('run_insert_points_along_path') do |_context, _value|
            result          = Na__EdgeTools__InsertPointsAlongPaths.Na__EdgeTools__InsertPointsAlongPaths__Execute
            status_modifier = result[:success] ? 'naEdgeTools__Status--success' : 'naEdgeTools__Status--error'
            na_update_status_element(dialog, 'edgeToolsStatus', 'naEdgeTools__Status', result[:message], status_modifier)
            na_refresh_dialog_state(dialog)
        end

        dialog.add_action_callback('set_chamfer_size_mm') do |_context, chamfer_size_mm|
            stored_value = Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__SetStoredChamferSizeMm(chamfer_size_mm)
            update_script = "var input=document.getElementById('naChamferSizeMm'); if(input){input.value=#{na_number_for_html_input(stored_value).to_json};}"
            dialog.execute_script(update_script)
        end

        dialog.add_action_callback('set_chamfer_build_corners_enabled') do |_context, build_corners_enabled|
            stored_value = Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__SetStoredBuildCornersEnabled(build_corners_enabled)
            update_script = <<~SCRIPT.strip
            (function() {
                var toggle = document.getElementById('naChamferBuildCornersEnabled');
                var panel  = document.getElementById('naChamferBuildCornerConfig');
                if(toggle){ toggle.checked = #{stored_value ? 'true' : 'false'}; }
                if(panel){ panel.style.display = #{(stored_value ? 'block' : 'none').to_json}; }
            })();
            SCRIPT
            dialog.execute_script(update_script)
        end

        dialog.add_action_callback('set_chamfer_build_corner_max_gap_mm') do |_context, build_corner_max_gap_mm|
            stored_value = Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__SetStoredBuildCornerMaxGapMm(build_corner_max_gap_mm)
            update_script = "var input=document.getElementById('naChamferBuildCornerMaxGapMm'); if(input){input.value=#{na_number_for_html_input(stored_value).to_json};}"
            dialog.execute_script(update_script)
        end

        dialog.add_action_callback('run_chamfer_edge_corners') do |_context, chamfer_size_mm, build_corners_enabled, build_corner_max_gap_mm|
            result = Na__EdgeTools__ChamferEdgeCorners.Na__EdgeTools__ChamferEdgeCorners__Execute(
                chamfer_size_mm,
                build_corners_enabled,
                build_corner_max_gap_mm
            )
            status_modifier = result[:success] ? 'naEdgeTools__Status--success' : 'naEdgeTools__Status--error'
            na_update_status_element(dialog, 'edgeToolsStatus', 'naEdgeTools__Status', result[:message], status_modifier)
            na_refresh_dialog_state(dialog)
        end

        dialog.add_action_callback('reload_plugin_data') do |_context, _value|
            na_update_status_element(dialog, 'settingsStatus', 'naSettings__Status', 'Reloading...')

            web_result  = Na__RefreshPluginData.Na__Refresh__FetchWebData     # <-- Force re-fetch web data files
            rb_result   = Na__RefreshPluginData.Na__Refresh__ReloadRubyFiles  # <-- Hot-reload all plugin Ruby files

            web_sources = web_result.map { |key, source| "#{key}: #{source}" }.join(', ')
            rb_summary  = "#{rb_result[:reload_count]} files reloaded, #{rb_result[:error_count]} errors"
            status_text  = "Web data: #{web_sources} | Ruby: #{rb_summary}"
            has_error    = web_result.values.any? { |s| s == :failed } || rb_result[:error_count] > 0
            status_modifier = has_error ? "naSettings__Status--error" : "naSettings__Status--success"
            na_update_status_element(dialog, 'settingsStatus', 'naSettings__Status', status_text, status_modifier)

            na_load_mte_data                                                   # <-- Re-populate in-memory MTE state
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create and Display Paint Edges Dialog
    # ------------------------------------------------------------
    def self.na_show_dialog
        if @na_dialog && @na_dialog.visible?
            @na_dialog.bring_to_front
            return
        end

        dialog_options = {
            dialog_title:    na_dialog_title,
            preferences_key: na_dialog_preferences_key,
            scrollable:      false,
            resizable:       na_dialog_resizable,
            width:           na_dialog_width,
            height:          na_dialog_height,
            style:           UI::HtmlDialog::STYLE_DIALOG
        }

        @na_dialog = UI::HtmlDialog.new(dialog_options)
        @na_dialog.set_html(na_render_dialog_html)
        na_setup_dialog_callbacks(@na_dialog)
        na_attach_selection_observer
        @na_dialog.set_on_closed do
            na_detach_selection_observer
            @na_dialog = nil
        end
        @na_dialog.show
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
