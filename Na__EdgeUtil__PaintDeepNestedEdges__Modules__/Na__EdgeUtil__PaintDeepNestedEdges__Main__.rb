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
# - Loads colour configuration from external JSON data.
# - Loads the HtmlDialog layout from external HTML and CSS files.
# - Delegates SketchUp menu and shortcut registration to the Hotkey Binder module.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

require_relative 'Na__EdgeUtil__PaintDeepNestedEdges__HotkeyBinder__'

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
    # ------------------------------------------------------------

    # MODULE VARIABLES | State Management
    # ------------------------------------------------------------
    @na_dialog            = nil
    @na_edge_config_data  = nil
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Loading and Public Metadata
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Load External Edge Configuration Data
    # ---------------------------------------------------------------
    def self.na_edge_config_data
        return @na_edge_config_data if @na_edge_config_data

        json_content = File.read(NA_EDGE_CONFIG_FILE)
        @na_edge_config_data = JSON.parse(json_content)
        return @na_edge_config_data
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Return Configured Colour Palette
    # ---------------------------------------------------------------
    def self.na_colours
        na_edge_config_data.fetch('colours', {})
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

    # HELPER FUNCTION | Return Default Colour Key
    # ---------------------------------------------------------------
    def self.na_default_colour_key
        na_edge_config_data.fetch('default_colour_key', 'Default')
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

    # FUNCTION | Register Menu and Shortcut Binder
    # ------------------------------------------------------------
    def self.na_register_hotkey_and_menu
        Na__HotkeyBinder.na_register_hotkey_and_menu
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
        return unless model

        selection = model.selection

        if selection.empty?
            UI.messagebox('Select something first.')
            return
        end

        edges = []
        selection.each { |entity| na_collect_edges(entity, edges) }

        if edges.empty?
            UI.messagebox('No edges found in selection.')
            return
        end

        model.start_operation("PaintDeepNestedEdges #{colour_key}", true)

        begin
            material = na_material_for_key(model, colour_key)
            edges.each { |edge| edge.material = material }
            model.commit_operation
        rescue => error
            model.abort_operation
            UI.messagebox("Failed to paint edges.\n\n#{error.message}")
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

    # HELPER FUNCTION | Render Complete Dialog Html
    # ---------------------------------------------------------------
    def self.na_render_dialog_html
        initial_info = "#{na_edge_count_selection} edges selected."

        return na_dialog_template_html
            .gsub('{{DIALOG_TITLE}}', na_dialog_title)
            .gsub('{{STYLESHEET_CONTENT}}', na_dialog_stylesheet_content)
            .gsub('{{OPTIONS_HTML}}', na_build_options_html)
            .gsub('{{INITIAL_INFO}}', initial_info)
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Configure Dialog Callbacks For User Interaction
    # ---------------------------------------------------------------
    def self.na_setup_dialog_callbacks(dialog)
        dialog.add_action_callback('apply_colour') do |_context, colour_key|
            na_paint_edges(colour_key)
            dialog.close
        end

        dialog.add_action_callback('fetch_selection') do |_context, _value|
            selection_count = na_edge_count_selection
            dialog.execute_script("document.getElementById('info').textContent='#{selection_count} edges selected.';")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create and Display Paint Edges Dialog
    # ------------------------------------------------------------
    def self.na_show_dialog
        dialog_options = {
            dialog_title:    na_dialog_title,
            preferences_key: na_dialog_preferences_key,
            scrollable:      false,
            resizable:       false,
            width:           na_dialog_width,
            height:          na_dialog_height,
            style:           UI::HtmlDialog::STYLE_DIALOG
        }

        @na_dialog = UI::HtmlDialog.new(dialog_options)
        @na_dialog.set_html(na_render_dialog_html)
        na_setup_dialog_callbacks(@na_dialog)
        @na_dialog.show
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
