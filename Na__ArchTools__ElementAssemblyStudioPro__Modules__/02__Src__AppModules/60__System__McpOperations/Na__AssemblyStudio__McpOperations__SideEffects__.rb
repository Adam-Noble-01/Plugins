# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - WHAT A CHANGE ALSO SETS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__SideEffects__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 11-Nov-2026 (V2.6.0)
# PURPOSE    : Some controls set others when they change in the dialog. An
#              agent's change must land exactly as Adam's click would, so the
#              same follow-on values are set here - never over a value the
#              agent gave itself.
#
# TWIN OF (WindowSystem UiSystem MainUiLogic.js, na_onControlChange)
#   transoms 0 -> 1                       transom_1_y_mm: the top light a
#                                         third of the clear height
#                                         (na_applyTransomDefaultsForCountChange)
#   bottom_sash_top_rail_override on      bottom_sash_top_rail_mm from the top rail
#   casement_top_rail_mm (override off)   bottom_sash_top_rail_mm follows it
#   glazebar_gothic_arch_enabled on       glazebar_gothic_arch_amount / _height_mm
#                                         (na_applyGothicArchDefaultsOnEnable)
#   vertical_glaze_bars                   glazebar_gothic_arch_amount = bars + 1
#                                         (na_syncArchAmountFromVerticalBars)
#   bifold_door_leaf_composition          bifold_door_glazed
#                                         (na_syncBifoldGlazedFromComposition)
#   double_door_<side>_leaf_override_enabled on
#                                         the side's own leaf settings copied
#                                         from the shared ones (the dialog asks
#                                         its LeafConfigResolver; the raw shared
#                                         values are copied here, offsets not)
#   The product strip's switch is in Catalogue; the double door's active leaf
#   clamp is not mirrored: out-of-range leaves are refused, never clamped.
#
# =============================================================================

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Side Effects - Constants
# -----------------------------------------------------------------------------

    # ExtDouble LeafConfigResolver na_seed_leaf_override: the suffixes a
    # leaf override takes from the pair.
    NA_LEAF_OVERRIDE_SUFFIXES = %w[
        leaf_composition panel_output_mode panel_profile panel_preset panel_columns panel_rows
        fielded_section_height_mm mid_rail_width_mm panel_stile_width_mm panel_top_rail_width_mm
        panel_bottom_rail_width_mm panel_inset_mm panel_depth_mm panel_bevel_width_mm
        horizontal_glaze_bars vertical_glaze_bars glaze_bar_width_mm glazebar_inset_mm
    ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Side Effects - Apply
# -----------------------------------------------------------------------------

    # FUNCTION | Set What the Dialog Would Set After These Changes
    # ------------------------------------------------------------
    # @param before [Hash] the values before the agent's changes
    # @param values [Hash] the values after them (changed in place)
    # @param given  [Array<String>] the keys the agent set itself
    # @return [Array<String>] one note per value set
    def self.na_dialog_side_effects!(system, before, values, given)
        return [] unless system == 'window_family'

        notes = []
        turned = ->(key, to) { given.include?(key) && values[key] == to && before[key] != to }
        changed = ->(key) { given.include?(key) && before[key] != values[key] }
        follow = lambda do |key, value, why|
            next if given.include?(key) || values[key] == value

            values[key] = value
            notes << "#{key} set to #{value.inspect}: #{why}, as the dialog does."
        end

        before_transoms = na_js_or(before['transoms'], 0).to_f.round.clamp(0, 3)
        after_transoms  = na_js_or(values['transoms'], 0).to_f.round.clamp(0, 3)
        if changed.call('transoms') && before_transoms.zero? && after_transoms == 1
            inner = na_inner_height_mm(values)
            top = ((inner / 3.0) / 10.0).round * 10
            follow.call('transom_1_y_mm', na_round_like_js(inner - top - na_transom_width_mm(values)), 'one transom puts the top light at a third of the clear height')
        end

        if turned.call('bottom_sash_top_rail_override', true)
            follow.call('bottom_sash_top_rail_mm', na_js_or(values['casement_top_rail_mm'], na_js_or(values['casement_width_mm'], 60)).to_f.then { |v| na_round_like_js(v) },
                        'the bottom sash top rail starts from the top rail')
        end
        if changed.call('casement_top_rail_mm') && values['bottom_sash_top_rail_override'] != true
            follow.call('bottom_sash_top_rail_mm', values['casement_top_rail_mm'], 'the bottom sash top rail follows the top rail')
        end

        if turned.call('glazebar_gothic_arch_enabled', true)
            v_bars = na_js_or(values['vertical_glaze_bars'], 0).to_f.round.clamp(0, 99)
            amount = [na_gothic_amount_default(na_glazing_panel_width_mm(values)), (v_bars + 1).clamp(1, 8)].max.clamp(1, 8)
            follow.call('glazebar_gothic_arch_amount', amount, 'gothic arches start one per light')
            raw = na_glazing_panel_height_mm(values) / 4.0
            follow.call('glazebar_gothic_arch_height_mm', ((raw / 10.0).round * 10).clamp(200, 800), 'gothic arches start a quarter of the glass high')
        end
        if changed.call('vertical_glaze_bars')
            follow.call('glazebar_gothic_arch_amount', (na_js_or(values['vertical_glaze_bars'], 0).to_f.round + 1).clamp(1, 8),
                        'the arches pair with the vertical bars')
        end

        if changed.call('bifold_door_leaf_composition') && values['bifold_door_leaf_composition']
            follow.call('bifold_door_glazed', %w[FullyGlazed GlazedOverGlazed].include?(values['bifold_door_leaf_composition']),
                        'the composition says whether the leaves are glazed')
        end

        %w[left right].each do |side|
            next unless turned.call("double_door_#{side}_leaf_override_enabled", true)

            NA_LEAF_OVERRIDE_SUFFIXES.each do |suffix|
                shared = values["double_door_#{suffix}"]
                next if shared.nil?

                follow.call("double_door_#{side}_#{suffix}", shared, "the #{side} leaf starts from the pair's own setting")
            end
            notes << "The #{side} leaf's glazing bar offsets were not copied from the pair: set double_door_#{side}_glazebar_*_offset_*_mm if it needs them."
        end
        notes
    end
    private_class_method :na_dialog_side_effects!
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Side Effects - The Dialog's Sizes
# -----------------------------------------------------------------------------

    # MainUiLogic na_getInnerFrameHeightMm (default height 1200)
    def self.na_inner_height_mm(c)
        frame = na_frame_sides(c)
        [0.0, na_js_or(c['height_mm'], 1200).to_f - frame[:top] - frame[:bottom]].max
    end
    private_class_method :na_inner_height_mm

    # MainUiLogic na_getTransomWidthMm
    def self.na_transom_width_mm(c)
        [1.0, na_js_or(c['transom_width_mm'], 40).to_f].max
    end
    private_class_method :na_transom_width_mm

    # MainUiLogic na_getGlazingPanelWidthMm
    def self.na_glazing_panel_width_mm(c)
        frame       = na_frame_sides(c)
        inner       = [0.0, na_js_or(c['width_mm'], 900).to_f - frame[:left] - frame[:right]].max
        mullions    = [0, na_js_or(c['mullions'], 0).to_f.round].max
        mullion_w   = [0.0, na_js_or(c['mullion_width_mm'], 30).to_f].max
        per_opening = [1, na_js_or(c['casements_per_opening'], 1).to_f.round].max
        band        = [0.0, inner - mullions * mullion_w].max
        per_casement = band / [1, mullions + 1].max / per_opening
        casement_w  = [0.0, na_js_or(c['casement_width_mm'], 65).to_f].max
        individual  = c['casement_sizes_individual'] == true
        left  = individual ? na_js_or(c['casement_left_stile_mm'], casement_w).to_f : casement_w
        right = individual ? na_js_or(c['casement_right_stile_mm'], casement_w).to_f : casement_w
        [0.0, per_casement - left - right].max
    end
    private_class_method :na_glazing_panel_width_mm

    # MainUiLogic na_getGlazingPanelHeightMm
    def self.na_glazing_panel_height_mm(c)
        inner      = na_inner_height_mm(c)
        transoms   = na_js_or(c['transoms'], 0).to_f.round.clamp(0, 3)
        cell       = [0.0, (inner - transoms * na_transom_width_mm(c)) / (transoms + 1)].max
        casement_w = [0.0, na_js_or(c['casement_width_mm'], 65).to_f].max
        individual = c['casement_sizes_individual'] == true
        top    = individual ? na_js_or(c['casement_top_rail_mm'], casement_w).to_f : casement_w
        bottom = individual ? na_js_or(c['casement_bottom_rail_mm'], casement_w).to_f : casement_w
        [0.0, cell - top - bottom].max
    end
    private_class_method :na_glazing_panel_height_mm

    # MainUiLogic na_computeGothicArchAmountDefault
    def self.na_gothic_amount_default(panel_width_mm)
        width = [0.0, panel_width_mm.to_f].max
        return 1 if width <= 300
        return 2 if width <= 450

        (2 + ((width - 450) / 250).floor).clamp(1, 8)
    end
    private_class_method :na_gothic_amount_default

    # A whole number stays whole (as the dialog's JSON would carry it).
    def self.na_round_like_js(value)
        value.to_f == value.to_f.round ? value.to_f.round : value.to_f
    end
    private_class_method :na_round_like_js

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
