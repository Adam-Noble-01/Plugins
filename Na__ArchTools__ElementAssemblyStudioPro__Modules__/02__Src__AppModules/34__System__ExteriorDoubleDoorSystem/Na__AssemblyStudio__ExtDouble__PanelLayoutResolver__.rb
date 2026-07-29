# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - PANEL LAYOUT RESOLVER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem
# MODULE     : Na__PanelLayoutResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : Thin adapter over the shared exterior-door panel resolver.
#              Keeps double-door-specific linked / per-leaf-override key logic
#              and translates it into the prefix-free panel_config the shared
#              resolver consumes.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelLayoutResolver

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    SharedResolver  = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLayoutResolver

    NA_COMPOSITIONS  = SharedResolver::NA_COMPOSITIONS
    NA_OUTPUT_MODES  = SharedResolver::NA_OUTPUT_MODES
    NA_PROFILES      = SharedResolver::NA_PROFILES
    NA_PRESET_GRIDS  = SharedResolver::NA_PRESET_GRIDS

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve Fielded-Panel Layout for One Leaf
    # ------------------------------------------------------------
    def self.na_resolve(config, leaf)
        panel_config = na_effective_leaf_config(config, leaf[:side])
        SharedResolver.na_resolve(panel_config, leaf)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Map Linked / Override Keys to Shared Panel Config
    # ------------------------------------------------------------
    # Resolves shared `double_door_*` keys, or per-leaf
    # `double_door_{left|right}_*` overrides when settings are unlinked.
    def self.na_effective_leaf_config(config, side)
        prefix       = "double_door_#{side}_"
        linked       = GeometryHelpers.na_boolean(config, 'double_door_leaf_settings_linked', true)
        override     = GeometryHelpers.na_boolean(config, "#{prefix}leaf_override_enabled", false)
        use_override = !linked && override
        value        = na_leaf_value_resolver(config, prefix, use_override)
        legacy_rail  = na_legacy_rail_width_mm(config, prefix, use_override)

        {
            'composition'                  => value.call('leaf_composition', 'GlazedOverFielded'),
            'output_mode'                  => value.call('panel_output_mode', 'ThreeDimensional'),
            'profile'                      => value.call('panel_profile', 'RaisedBevelled'),
            'preset'                       => value.call('panel_preset', 'OnePanel'),
            'columns'                      => value.call('panel_columns', 1),
            'rows'                         => value.call('panel_rows', 1),
            'fielded_height_mm'            => value.call('fielded_section_height_mm', 300),
            'mid_rail_width_mm'            => value.call('mid_rail_width_mm', 120),
            'stile_width_mm'               => value.call('panel_stile_width_mm', 95),
            'top_rail_width_mm'            => value.call('panel_top_rail_width_mm', 95),
            'bottom_rail_width_mm'         => value.call('panel_bottom_rail_width_mm', legacy_rail),
            'panel_inset_mm'               => value.call('panel_inset_mm', 25),
            'panel_depth_mm'               => value.call('panel_depth_mm', 12),
            'panel_bevel_width_mm'         => value.call('panel_bevel_width_mm', 18),
            'horizontal_glaze_bars'        => value.call('horizontal_glaze_bars', config['horizontal_glaze_bars'] || 0),
            'vertical_glaze_bars'          => value.call('vertical_glaze_bars', config['vertical_glaze_bars'] || 0),
            'glaze_bar_width_mm'           => value.call('glaze_bar_width_mm', config['glaze_bar_width_mm'] || 25),
            'glazebar_inset_mm'            => value.call('glazebar_inset_mm', config['glazebar_inset_mm'] || 10),
            'glazebar_margin_enabled'      => value.call(
                'glazebar_margin_enabled',
                config['glazebar_margin_enabled'] == true
            ),
            'glazebar_margin_offset_mm'    => value.call(
                'glazebar_margin_offset_mm',
                config['glazebar_margin_offset_mm'] || 120
            ),
            'glazebar_horizontal_offset_mm' => value.call(
                'glazebar_horizontal_offset_mm',
                config['glazebar_horizontal_offset_mm'] || 0
            ),
            'removed_glazebars'            => na_removed_glazebar_keys(config)
        }.merge(na_offset_keys(config, value))
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Config Mapping
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Shared -> Per-Leaf Value Resolver Lambda
    # ------------------------------------------------------------
    def self.na_leaf_value_resolver(config, prefix, use_override)
        lambda do |suffix, fallback|
            shared_key = "double_door_#{suffix}"
            leaf_key   = "#{prefix}#{suffix}"
            raw = use_override && config.key?(leaf_key) ? config[leaf_key] : config[shared_key]
            raw.nil? ? fallback : raw
        end
    end
    private_class_method :na_leaf_value_resolver
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Legacy Panel Rail Width Fallback (mm)
    # ------------------------------------------------------------
    def self.na_legacy_rail_width_mm(config, prefix, use_override)
        legacy_key = "#{prefix}panel_rail_width_mm"
        legacy_rail = if use_override && config.key?(legacy_key)
                          config[legacy_key]
                      else
                          config['double_door_panel_rail_width_mm']
                      end
        legacy_rail.nil? ? 150 : legacy_rail
    end
    private_class_method :na_legacy_rail_width_mm
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Removed Glazebar Key Array (Double-Door or Shared)
    # ------------------------------------------------------------
    def self.na_removed_glazebar_keys(config)
        if config['double_door_removed_glazebars'].is_a?(Array)
            config['double_door_removed_glazebars']
        else
            config['removed_glazebars']
        end
    end
    private_class_method :na_removed_glazebar_keys
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Per-Bar Offset Keys (shared -> per-leaf -> plain)
    # ------------------------------------------------------------
    # glazebar_h_offset_N_mm / glazebar_v_offset_N_mm, N = 1..8 (1-based
    # bar index). Applied after the spacing math in the composer.
    def self.na_offset_keys(config, value)
        keys = {}
        (1..8).each do |bar_index|
            %w[h v].each do |axis|
                suffix = "glazebar_#{axis}_offset_#{bar_index}_mm"
                keys[suffix] = value.call(suffix, config[suffix] || 0)
            end
        end
        keys
    end
    private_class_method :na_offset_keys
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__PanelLayoutResolver
end # module Na__ExteriorDoubleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
