# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SLIDING DOOR - PANEL LAYOUT RESOLVER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__PanelLayoutResolver__.rb
# PURPOSE    : Maps sliding_door_* keys into ExtDoorCommon panel_config.
#              One shared config applies to every leaf in the set.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__.rb
#
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__PanelLayoutResolver

    SharedResolver = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLayoutResolver

    def self.na_resolve(config, leaf)
        SharedResolver.na_resolve(na_panel_config(config), leaf)
    end

    def self.na_panel_config(config)
        get = lambda do |key, fallback|
            value = config[key]
            value.nil? ? fallback : value
        end

        # Legacy fully-glazed toggle maps to FullyGlazed when composition absent.
        composition = get.call('sliding_door_leaf_composition', nil)
        if composition.nil?
            composition = config['sliding_door_glazed'] == false ? 'FullyFielded' : 'FullyGlazed'
        end

        {
            'composition' => composition,
            'output_mode' => get.call('sliding_door_panel_output_mode', 'ThreeDimensional'),
            'profile' => get.call('sliding_door_panel_profile', 'RaisedBevelled'),
            'preset' => get.call('sliding_door_panel_preset', 'OnePanel'),
            'columns' => get.call('sliding_door_panel_columns', 1),
            'rows' => get.call('sliding_door_panel_rows', 1),
            'fielded_height_mm' => get.call('sliding_door_fielded_section_height_mm', 300),
            'mid_rail_width_mm' => get.call('sliding_door_mid_rail_width_mm', 120),
            'stile_width_mm' => get.call('sliding_door_stile_width_mm', 95),
            'top_rail_width_mm' => get.call('sliding_door_head_rail_mm', 95),
            'bottom_rail_width_mm' => get.call('sliding_door_base_rail_mm', 200),
            'panel_inset_mm' => get.call('sliding_door_panel_inset_mm', 25),
            'panel_depth_mm' => get.call('sliding_door_panel_depth_mm', 12),
            'panel_bevel_width_mm' => get.call('sliding_door_panel_bevel_width_mm', 18),
            'horizontal_glaze_bars' => get.call('horizontal_glaze_bars', config['horizontal_glaze_bars'] || 0),
            'vertical_glaze_bars' => get.call('vertical_glaze_bars', config['vertical_glaze_bars'] || 0),
            'glaze_bar_width_mm' => get.call('glaze_bar_width_mm', config['glaze_bar_width_mm'] || 25),
            'glazebar_inset_mm' => get.call('glazebar_inset_mm', config['glazebar_inset_mm'] || 10),
            'glazebar_margin_enabled' => config['glazebar_margin_enabled'] == true,
            'glazebar_margin_offset_mm' => get.call('glazebar_margin_offset_mm', config['glazebar_margin_offset_mm'] || 120),
            'glazebar_horizontal_offset_mm' => get.call('glazebar_horizontal_offset_mm', config['glazebar_horizontal_offset_mm'] || 0),
            'removed_glazebars' => (config['removed_glazebars'].is_a?(Array) ? config['removed_glazebars'] : [])
        }
    end
    private_class_method :na_panel_config

end
end
end
