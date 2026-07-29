# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - PANEL LAYOUT RESOLVER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__PanelLayoutResolver__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__PanelLayoutResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : Adapter that maps single_door_* construction keys into the
#              prefix-free panel_config the shared ExtDoorCommon panel
#              resolver consumes. Single doors have one leaf, so there is
#              no per-leaf override logic.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryHelpers__'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__PanelLayoutResolver

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    SharedResolver = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLayoutResolver

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve Fielded-Panel Layout for the Single Leaf
    # ------------------------------------------------------------
    def self.na_resolve(config, leaf)
        SharedResolver.na_resolve(na_panel_config(config), leaf)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Config Mapping
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Map single_door_* Keys to Shared Panel Config
    # ------------------------------------------------------------
    def self.na_panel_config(config)
        get = lambda { |suffix, fallback| v = config["single_door_#{suffix}"]; v.nil? ? fallback : v }
        {
            'composition' => get.call('leaf_composition', 'GlazedOverFielded'),
            'output_mode' => get.call('panel_output_mode', 'ThreeDimensional'),
            'profile' => get.call('panel_profile', 'RaisedBevelled'),
            'preset' => get.call('panel_preset', 'OnePanel'),
            'columns' => get.call('panel_columns', 1),
            'rows' => get.call('panel_rows', 1),
            'fielded_height_mm' => get.call('fielded_section_height_mm', 300),
            'mid_rail_width_mm' => get.call('mid_rail_width_mm', 120),
            'stile_width_mm' => get.call('panel_stile_width_mm', 95),
            'top_rail_width_mm' => get.call('panel_top_rail_width_mm', 95),
            'bottom_rail_width_mm' => get.call('panel_bottom_rail_width_mm', 150),
            'panel_inset_mm' => get.call('panel_inset_mm', 25),
            'panel_depth_mm' => get.call('panel_depth_mm', 12),
            'panel_bevel_width_mm' => get.call('panel_bevel_width_mm', 18),
            'horizontal_glaze_bars' => get.call('horizontal_glaze_bars', config['horizontal_glaze_bars'] || 0),
            'vertical_glaze_bars' => get.call('vertical_glaze_bars', config['vertical_glaze_bars'] || 0),
            'glaze_bar_width_mm' => get.call('glaze_bar_width_mm', config['glaze_bar_width_mm'] || 25),
            'glazebar_inset_mm' => get.call('glazebar_inset_mm', config['glazebar_inset_mm'] || 10),
            'glazebar_margin_enabled' => get.call('glazebar_margin_enabled', config['glazebar_margin_enabled'] == true),
            'glazebar_margin_offset_mm' => get.call('glazebar_margin_offset_mm', config['glazebar_margin_offset_mm'] || 120),
            'glazebar_horizontal_offset_mm' => get.call('glazebar_horizontal_offset_mm', config['glazebar_horizontal_offset_mm'] || 0),
            'removed_glazebars' => (config['single_door_removed_glazebars'].is_a?(Array) ? config['single_door_removed_glazebars'] : config['removed_glazebars'])
        }.merge(na_offset_keys(config, get))
    end
    private_class_method :na_panel_config
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Per-Bar Offset Keys (single_door_* -> plain fallback)
    # ------------------------------------------------------------
    # glazebar_h_offset_N_mm / glazebar_v_offset_N_mm, N = 1..8 (1-based
    # bar index). Applied after the spacing math in the composer.
    def self.na_offset_keys(config, get)
        keys = {}
        (1..8).each do |bar_index|
            %w[h v].each do |axis|
                suffix = "glazebar_#{axis}_offset_#{bar_index}_mm"
                keys[suffix] = get.call(suffix, config[suffix] || 0)
            end
        end
        keys
    end
    private_class_method :na_offset_keys
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__PanelLayoutResolver
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
