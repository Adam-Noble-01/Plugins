# frozen_string_literal: true

# =============================================================================
# EXTERIOR DOUBLE DOOR - PANEL LAYOUT RESOLVER (ADAPTER)
# -----------------------------------------------------------------------------
# Thin adapter over the shared exterior-door panel resolver. This module keeps
# the double-door-specific linked / per-leaf-override key logic and translates
# it into the prefix-free panel_config the shared resolver consumes.
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__.rb
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelLayoutResolver

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    SharedResolver = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLayoutResolver

    NA_COMPOSITIONS = SharedResolver::NA_COMPOSITIONS
    NA_OUTPUT_MODES = SharedResolver::NA_OUTPUT_MODES
    NA_PROFILES = SharedResolver::NA_PROFILES
    NA_PRESET_GRIDS = SharedResolver::NA_PRESET_GRIDS

    def self.na_resolve(config, leaf)
        panel_config = na_effective_leaf_config(config, leaf[:side])
        SharedResolver.na_resolve(panel_config, leaf)
    end

    def self.na_effective_leaf_config(config, side)
        prefix = "double_door_#{side}_"
        linked = GeometryHelpers.na_boolean(config, 'double_door_leaf_settings_linked', true)
        override = GeometryHelpers.na_boolean(config, "#{prefix}leaf_override_enabled", false)
        use_override = !linked && override

        value = lambda do |suffix, fallback|
            shared_key = "double_door_#{suffix}"
            leaf_key = "#{prefix}#{suffix}"
            raw = use_override && config.key?(leaf_key) ? config[leaf_key] : config[shared_key]
            raw.nil? ? fallback : raw
        end

        legacy_rail = if use_override && config.key?("#{prefix}panel_rail_width_mm")
                          config["#{prefix}panel_rail_width_mm"]
                      else
                          config['double_door_panel_rail_width_mm']
                      end
        legacy_rail = 150 if legacy_rail.nil?

        removed_keys = if config['double_door_removed_glazebars'].is_a?(Array)
                           config['double_door_removed_glazebars']
                       else
                           config['removed_glazebars']
                       end

        {
            'composition' => value.call('leaf_composition', 'GlazedOverFielded'),
            'output_mode' => value.call('panel_output_mode', 'ThreeDimensional'),
            'profile' => value.call('panel_profile', 'RaisedBevelled'),
            'preset' => value.call('panel_preset', 'OnePanel'),
            'columns' => value.call('panel_columns', 1),
            'rows' => value.call('panel_rows', 1),
            'fielded_height_mm' => value.call('fielded_section_height_mm', 300),
            'mid_rail_width_mm' => value.call('mid_rail_width_mm', 120),
            'stile_width_mm' => value.call('panel_stile_width_mm', 95),
            'top_rail_width_mm' => value.call('panel_top_rail_width_mm', 95),
            'bottom_rail_width_mm' => value.call('panel_bottom_rail_width_mm', legacy_rail),
            'panel_inset_mm' => value.call('panel_inset_mm', 25),
            'panel_depth_mm' => value.call('panel_depth_mm', 12),
            'panel_bevel_width_mm' => value.call('panel_bevel_width_mm', 18),
            'horizontal_glaze_bars' => value.call('horizontal_glaze_bars', config['horizontal_glaze_bars'] || 0),
            'vertical_glaze_bars' => value.call('vertical_glaze_bars', config['vertical_glaze_bars'] || 0),
            'glaze_bar_width_mm' => value.call('glaze_bar_width_mm', config['glaze_bar_width_mm'] || 25),
            'glazebar_inset_mm' => value.call('glazebar_inset_mm', config['glazebar_inset_mm'] || 10),
            'glazebar_margin_enabled' => value.call(
                'glazebar_margin_enabled',
                config['glazebar_margin_enabled'] == true
            ),
            'glazebar_margin_offset_mm' => value.call(
                'glazebar_margin_offset_mm',
                config['glazebar_margin_offset_mm'] || 120
            ),
            'glazebar_horizontal_offset_mm' => value.call(
                'glazebar_horizontal_offset_mm',
                config['glazebar_horizontal_offset_mm'] || 0
            ),
            'removed_glazebars' => removed_keys
        }
    end

end
end
end
