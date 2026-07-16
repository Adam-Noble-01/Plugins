# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - PANEL LAYOUT RESOLVER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__PanelLayoutResolver__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__PanelLayoutResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : System-agnostic fielded-panel layout resolver. Given a
#              normalized panel_config hash (prefix-free) and a leaf hash,
#              returns members / regions / field cells / dividers / glaze bars.
#
# DESCRIPTION:
# - Extracted from the Exterior Double Door System so single, sliding and
#   multifold doors can share one fielded-panel contract.
# - The caller (each system's adapter) is responsible for translating its own
#   prefixed config keys (double_door_*, single_door_*, sliding_door_*,
#   bifold_door_*) into the canonical panel_config keys consumed here.
#
# INPUT panel_config (all keys optional, sensible fallbacks applied):
#   'composition'                 FullyGlazed | GlazedOverFielded | FullyFielded
#   'output_mode'                 Linework | ThreeDimensional
#   'profile'                     RaisedBevelled | RecessedShaker
#   'preset'                      OnePanel | TwoVertical | TwoHorizontal |
#                                 FourPanel | SixPanel | Custom
#   'columns' / 'rows'            Custom grid counts
#   'fielded_height_mm'           Lower fielded region height (GlazedOverFielded)
#   'mid_rail_width_mm'           Separating mid rail width
#   'stile_width_mm'              Perimeter stile width
#   'top_rail_width_mm'           Perimeter top rail width
#   'bottom_rail_width_mm'        Perimeter bottom rail width
#   'panel_inset_mm'              Fielded panel inset
#   'panel_depth_mm'              Fielded panel depth
#   'panel_bevel_width_mm'        Raised bevel width
#   'horizontal_glaze_bars'       Glaze bar counts / widths / insets / margins
#   'vertical_glaze_bars'
#   'glaze_bar_width_mm'
#   'glazebar_inset_mm'
#   'glazebar_margin_enabled'
#   'glazebar_margin_offset_mm'
#   'glazebar_horizontal_offset_mm'
#   'removed_glazebars'           Array of removed glaze-bar keys
#
# INPUT leaf (mm space): :origin_x_mm, :origin_z_mm, :width_mm, :height_mm,
#                        :thickness_mm, :index
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
module Na__PanelLayoutResolver

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_COMPOSITIONS = %w[FullyGlazed GlazedOverFielded FullyFielded].freeze
    NA_OUTPUT_MODES = %w[Linework ThreeDimensional].freeze
    NA_PROFILES     = %w[RaisedBevelled RecessedShaker].freeze
    NA_PRESET_GRIDS = {
        'OnePanel'      => [1, 1],
        'TwoVertical'   => [2, 1],
        'TwoHorizontal' => [1, 2],
        'FourPanel'     => [2, 2],
        'SixPanel'      => [2, 3]
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve the Full Panel Layout for a Single Leaf
    # ------------------------------------------------------------
    # @param panel_config [Hash] Canonical (prefix-free) panel config
    # @param leaf         [Hash] Leaf descriptor in millimetre space
    # @return [Hash] Frozen layout with members, regions, cells, glaze bars
    def self.na_resolve(panel_config, leaf)
        effective = panel_config
        composition = na_enum(effective['composition'], NA_COMPOSITIONS, 'GlazedOverFielded')
        members = na_resolve_members(effective, leaf)
        regions = na_resolve_regions(effective, leaf, members, composition)
        fields = na_resolve_field_cells(effective, regions[:field], members)
        field_dividers = na_resolve_field_dividers(regions[:field], fields)

        {
            :composition => composition,
            :output_mode => na_enum(effective['output_mode'], NA_OUTPUT_MODES, 'ThreeDimensional'),
            :profile => na_enum(effective['profile'], NA_PROFILES, 'RaisedBevelled'),
            :members => members.freeze,
            :glazed_region => regions[:glazed]&.freeze,
            :field_region => regions[:field]&.freeze,
            :field_cells => fields.map(&:freeze).freeze,
            :field_dividers => field_dividers.map(&:freeze).freeze,
            :glaze_bars => na_resolve_glaze_bars(effective, leaf),
            :panel_inset_mm => GeometryHelpers.na_clamp(effective['panel_inset_mm'], 5, 100),
            :panel_depth_mm => GeometryHelpers.na_clamp(effective['panel_depth_mm'], 1, leaf[:thickness_mm] / 2.0 - 0.5),
            :panel_bevel_width_mm => GeometryHelpers.na_clamp(effective['panel_bevel_width_mm'], 2, 100)
        }.freeze
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Members + Regions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Perimeter Member Widths
    # ------------------------------------------------------------
    def self.na_resolve_members(effective, leaf)
        stile = GeometryHelpers.na_clamp(effective['stile_width_mm'], 20, leaf[:width_mm] / 3.0)
        top_rail = GeometryHelpers.na_clamp(effective['top_rail_width_mm'], 20, leaf[:height_mm] / 3.0)
        bottom_rail = GeometryHelpers.na_clamp(effective['bottom_rail_width_mm'], 20, leaf[:height_mm] / 3.0)
        mid = GeometryHelpers.na_clamp(effective['mid_rail_width_mm'], 20, leaf[:height_mm] / 3.0)
        {
            :stile_width_mm => stile,
            :top_rail_width_mm => top_rail,
            :bottom_rail_width_mm => bottom_rail,
            :mid_rail_width_mm => mid
        }
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve Fielded and Glazed Regions From Composition
    # ------------------------------------------------------------
    def self.na_resolve_regions(effective, leaf, members, composition)
        inner_x = leaf[:origin_x_mm] + members[:stile_width_mm]
        inner_z = leaf[:origin_z_mm] + members[:bottom_rail_width_mm]
        inner_w = leaf[:width_mm] - 2.0 * members[:stile_width_mm]
        inner_h = leaf[:height_mm] - members[:top_rail_width_mm] - members[:bottom_rail_width_mm]
        return { :field => nil, :glazed => nil } if inner_w <= 0 || inner_h <= 0

        full = { :x_mm => inner_x, :z_mm => inner_z, :width_mm => inner_w, :height_mm => inner_h }
        return { :field => nil, :glazed => full } if composition == 'FullyGlazed'
        return { :field => full, :glazed => nil } if composition == 'FullyFielded'

        field_height = GeometryHelpers.na_clamp(
            effective['fielded_height_mm'], 100, inner_h - members[:mid_rail_width_mm] - 100
        )
        field = full.merge(:height_mm => field_height)
        glazed_z = inner_z + field_height + members[:mid_rail_width_mm]
        glazed = {
            :x_mm => inner_x,
            :z_mm => glazed_z,
            :width_mm => inner_w,
            :height_mm => [inner_z + inner_h - glazed_z, 0.0].max
        }
        { :field => field, :glazed => glazed }
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Field Cells + Dividers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Field Cell Grid From Preset or Custom Counts
    # ------------------------------------------------------------
    def self.na_resolve_field_cells(effective, region, members)
        return [] unless region && region[:width_mm] > 0 && region[:height_mm] > 0

        preset = effective['preset'].to_s
        columns, rows = if preset == 'Custom'
                            [effective['columns'].to_i, effective['rows'].to_i]
                        else
                            NA_PRESET_GRIDS.fetch(preset, [1, 1])
                        end
        columns = GeometryHelpers.na_clamp(columns, 1, 6).to_i
        rows = GeometryHelpers.na_clamp(rows, 1, 6).to_i
        separator = [members[:mid_rail_width_mm] * 0.55, 30.0].max
        cell_width = (region[:width_mm] - separator * (columns - 1)) / columns
        cell_height = (region[:height_mm] - separator * (rows - 1)) / rows
        return [] if cell_width < 40 || cell_height < 40

        cells = []
        rows.times do |row|
            columns.times do |column|
                cells << {
                    :column => column + 1,
                    :row => row + 1,
                    :x_mm => region[:x_mm] + column * (cell_width + separator),
                    :z_mm => region[:z_mm] + row * (cell_height + separator),
                    :width_mm => cell_width,
                    :height_mm => cell_height
                }
            end
        end
        cells
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve Vertical and Horizontal Field Dividers
    # ------------------------------------------------------------
    def self.na_resolve_field_dividers(region, cells)
        return [] unless region && cells.length > 1

        dividers = []
        columns = cells.group_by { |cell| cell[:x_mm] }.values
            .map(&:first)
            .sort_by { |cell| cell[:x_mm] }
        rows = cells.group_by { |cell| cell[:z_mm] }.values
            .map(&:first)
            .sort_by { |cell| cell[:z_mm] }

        columns.each_cons(2).with_index do |(current, following), index|
            gap_x = current[:x_mm] + current[:width_mm]
            gap_width = following[:x_mm] - gap_x
            next unless gap_width > 0
            dividers << {
                :orientation => :vertical,
                :index => index + 1,
                :x_mm => gap_x,
                :z_mm => region[:z_mm],
                :width_mm => gap_width,
                :height_mm => region[:height_mm]
            }
        end

        rows.each_cons(2).with_index do |(current, following), index|
            gap_z = current[:z_mm] + current[:height_mm]
            gap_height = following[:z_mm] - gap_z
            next unless gap_height > 0
            dividers << {
                :orientation => :horizontal,
                :index => index + 1,
                :x_mm => region[:x_mm],
                :z_mm => gap_z,
                :width_mm => region[:width_mm],
                :height_mm => gap_height
            }
        end
        dividers
    end
    private_class_method :na_resolve_field_dividers
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Glaze Bars + Enum Coercion
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Glaze-Bar Counts, Widths and Offsets
    # ------------------------------------------------------------
    def self.na_resolve_glaze_bars(effective, leaf)
        maximum_inset = [leaf[:thickness_mm] / 2.0 - 1.0, 0.0].max
        removed_keys = effective['removed_glazebars']
        {
            :horizontal_count => GeometryHelpers.na_clamp(effective['horizontal_glaze_bars'], 0, 12).to_i,
            :vertical_count => GeometryHelpers.na_clamp(effective['vertical_glaze_bars'], 0, 12).to_i,
            :width_mm => GeometryHelpers.na_clamp(effective['glaze_bar_width_mm'], 5, 100),
            :inset_mm => GeometryHelpers.na_clamp(effective['glazebar_inset_mm'], 0, maximum_inset),
            :margin_enabled => effective['glazebar_margin_enabled'] == true,
            :margin_offset_mm => [effective['glazebar_margin_offset_mm'].to_f, 0.0].max,
            :horizontal_offset_mm => effective['glazebar_horizontal_offset_mm'].to_f,
            :removed_keys => Array(removed_keys).map(&:to_s).freeze
        }.freeze
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Coerce an Enum Value Against an Allowed List
    # ------------------------------------------------------------
    def self.na_enum(value, allowed, fallback)
        candidate = value.to_s
        allowed.include?(candidate) ? candidate : fallback
    end
    private_class_method :na_enum
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__PanelLayoutResolver
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
