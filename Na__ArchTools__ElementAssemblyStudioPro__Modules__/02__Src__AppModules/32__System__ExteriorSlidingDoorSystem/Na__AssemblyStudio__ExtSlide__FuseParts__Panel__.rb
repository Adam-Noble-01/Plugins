# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR PANEL FUSE PARTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__FuseParts__Panel__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__FuseParts__Panel
# AUTHOR     : Noble Architecture
# PURPOSE    : Per-leaf timber-frame fusion for sliding doors plus per-leaf
#              glaze-bar fusion, glass trim, AND outer frame fusion at the
#              ADR level so a fully fused sliding door reads exactly like a
#              fused window casement assembly.
#
# DESCRIPTION:
# - Sliding leaves are composed inside MOD groups (one per leaf), so
#   the inner timber + glazing + glaze-bar groups are children of the
#   MOD, not direct children of the ADR definition. The fuser walks
#   the parent entities, drops into every MOD it finds, and fuses
#   inside that MOD's own entities. The MOD wrapper itself (which
#   carries the FIXED / MVE animation contract in its name) is left
#   untouched so the GLB exporter's animation scanner still sees it.
# - V1.7.1 expanded the pipeline to mirror the WindowSystem casement
#   behaviour:
#     1. Per-MOD: fuse the timber stiles + rails (Na_DoorPanel_{id}_*)
#     2. Per-MOD: fuse the glaze bars (Na_GlazeBar_{id}_[HV]\d+)
#     3. Per-MOD: trim the glass (Na_Glass_{id}) with the fused bars so
#        each lite ends up as its own glass solid (matches the casement
#        glass-per-cell behaviour the user described).
#     4. ADR-level: fuse the static outer frame parts (Na_Frame_*) into
#        a single solid so the jamb/head/bottom joint lines disappear.
# - The cill is intentionally left as its own group because users may
#   swap its material independently (matches the WindowSystem flow).
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - V1.7.1: added per-leaf glaze-bar fusion + glass trim + ADR-level
#   outer frame fusion, mirroring the WindowSystem casement pipeline.
#
# 17-May-2026 - Version 0.1.0
# - Phase-9 introduction.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Fuse__Shared__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__FuseParts__Panel

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    FuseShared = Na__AssemblyStudio::Na__GeometryHelpers::Na__Fuse

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_PANEL_PART_REGEX     = /^Na_DoorPanel_(Sliding_.+)_(Stile_(?:Left|Right)|Rail_(?:Top|Bottom))$/.freeze
    # Accepts straight bars (_H<n> / _V<n>) and Gothic arch halves
    # (_Arch<n>_L / _Arch<n>_R, each a single pushpull solid) so a sliding
    # leaf with arches but no straight bars still gets a fuse pass.
    NA_GLAZEBAR_PART_REGEX  = /^Na_GlazeBar_(Sliding_.+?)_(?:[HV]\d+|Arch\d+_[LR])$/.freeze
    NA_FRAME_PART_PREFIX    = "Na_Frame_".freeze
    NA_MOD_NAME_REGEX       = /^MOD\d{3}/.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Run the Full Sliding FuseParts Pipeline
    # ------------------------------------------------------------
    # Walks the ADR ComponentDefinition entities, locates every MOD
    # group, fuses the timber + glaze bars per leaf, trims the glass
    # with the fused bars, and finally fuses the static outer frame
    # parts at the ADR level so the joint lines disappear.
    #
    # @param entities [Sketchup::Entities] ADR definition entities
    # @return [Hash] { :fused => Int, :failed => Int, :skipped => Int }
    def self.na_fuse_sliding_panels(entities)
        result = { :fused => 0, :failed => 0, :skipped => 0 }
        return result unless entities

        DebugTools.na_debug_method("ExtSlide::FuseParts__Panel.na_fuse_sliding_panels")

        mod_groups = na_collect_mod_groups(entities)
        if mod_groups.empty?
            DebugTools.na_debug_geometry("ExtSlide fuse: no MOD groups found, skipping leaf fuse")
        else
            mod_groups.each do |mod_group|
                mod_result = na_fuse_panel_pipeline_inside_mod(mod_group)
                na_accumulate_result(result, mod_result)
            end
        end

        frame_result = na_fuse_outer_frame(entities)
        na_accumulate_result(result, frame_result)

        DebugTools.na_debug_geometry(
            "ExtSlide fuse summary: fused=#{result[:fused]}, failed=#{result[:failed]}, skipped=#{result[:skipped]}"
        )
        result
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::FuseParts__Panel.na_fuse_sliding_panels failed", e)
        result
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - MOD-Level Pipeline
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Run the Three-Step Per-Leaf Pipeline Inside One MOD
    # ------------------------------------------------------------
    # Step 1: fuse the timber stiles + rails into Na_DoorPanel_{id}_Fused
    # Step 2: fuse the glaze bars into Na_GlazeBar_{id}_Fused
    # Step 3: trim Na_Glass_{id} with the fused glaze bars so each lite
    #         becomes its own glass solid (Na_Glass_{id}_Trimmed).
    def self.na_fuse_panel_pipeline_inside_mod(mod_group)
        result = { :fused => 0, :failed => 0, :skipped => 0 }
        return result unless mod_group && mod_group.valid?

        inner_entities = mod_group.entities
        panel_ids      = na_find_unique_panel_ids(inner_entities, NA_PANEL_PART_REGEX)
        if panel_ids.empty?
            result[:skipped] += 1
            return result
        end

        panel_ids.each do |panel_id|
            na_accumulate_result(result, na_fuse_timber_for_panel(inner_entities, panel_id))
            na_accumulate_result(result, na_fuse_glaze_bars_for_panel(inner_entities, panel_id))
            na_accumulate_result(result, na_fuse_leaded_glass_for_panel(inner_entities, panel_id))
            na_accumulate_result(result, na_trim_glass_for_panel(inner_entities, panel_id))
        end

        result
    end
    private_class_method :na_fuse_panel_pipeline_inside_mod
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse the Timber Stiles + Rails for a Single Panel
    # ------------------------------------------------------------
    def self.na_fuse_timber_for_panel(entities, panel_id)
        result = { :fused => 0, :failed => 0, :skipped => 0 }

        groups = na_collect_groups_by_prefix(entities, "Na_DoorPanel_#{panel_id}_")
        if groups.length < 2
            DebugTools.na_debug_geometry("ExtSlide fuse timber: #{panel_id} has <2 parts, skipping")
            result[:skipped] += 1
            return result
        end

        DebugTools.na_debug_geometry("ExtSlide fuse timber: #{panel_id} - merging #{groups.length} parts")
        fused = FuseShared.na_sequential_outer_shell(groups, "Na_DoorPanel_#{panel_id}_Fused")
        if fused
            result[:fused] += 1
        else
            result[:failed] += 1
            DebugTools.na_debug_error("ExtSlide fuse timber: #{panel_id} fusion returned nil")
        end
        result
    end
    private_class_method :na_fuse_timber_for_panel
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse the Glaze Bars for a Single Panel
    # ------------------------------------------------------------
    def self.na_fuse_glaze_bars_for_panel(entities, panel_id)
        result = { :fused => 0, :failed => 0, :skipped => 0 }

        groups = na_collect_glazebar_groups(entities, panel_id)
        if groups.length < 2
            DebugTools.na_debug_geometry("ExtSlide fuse bars: #{panel_id} has <2 bars, skipping")
            result[:skipped] += 1
            return result
        end

        DebugTools.na_debug_geometry("ExtSlide fuse bars: #{panel_id} - merging #{groups.length} bars")
        fused = FuseShared.na_sequential_outer_shell(groups, "Na_GlazeBar_#{panel_id}_Fused")
        if fused
            result[:fused] += 1
        else
            result[:failed] += 1
            DebugTools.na_debug_error("ExtSlide fuse bars: #{panel_id} fusion returned nil")
        end
        result
    end
    private_class_method :na_fuse_glaze_bars_for_panel
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse Leaded Glass Overlay for a Single Panel (No Glass Trim)
    # ------------------------------------------------------------
    def self.na_fuse_leaded_glass_for_panel(entities, panel_id)
        result = { :fused => 0, :failed => 0, :skipped => 0 }

        groups = na_collect_groups_by_prefix(entities, "Na_LeadedGlass_#{panel_id}_").select do |group|
            next false unless group && group.valid?
            next false if group.entities.grep(Sketchup::Face).empty?
            bb = group.local_bounds
            [bb.width, bb.height, bb.depth].min > 0.001.mm
        end
        if groups.length < 2
            result[:skipped] += 1
            return result
        end

        fused = FuseShared.na_sequential_outer_shell(groups, "Na_LeadedGlass_#{panel_id}_Fused")
        if fused
            result[:fused] += 1
        else
            result[:failed] += 1
            DebugTools.na_debug_error("ExtSlide fuse leaded: #{panel_id} fusion returned nil")
        end
        result
    end
    private_class_method :na_fuse_leaded_glass_for_panel
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Trim Glass with Fused Glaze Bars for a Single Panel
    # ------------------------------------------------------------
    # Mirrors `Na__WindowSystem::Na__FuseParts.na_trim_glass_panels`:
    # `bars.trim(glass)` keeps the bars intact and replaces the glass
    # group with a trimmed version that only fills the spaces between
    # bars - effectively giving each lite its own pane.
    def self.na_trim_glass_for_panel(entities, panel_id)
        result = { :fused => 0, :failed => 0, :skipped => 0 }

        bar_group   = na_find_group_by_name(entities, "Na_GlazeBar_#{panel_id}_Fused")
        glass_group = na_find_group_by_name(entities, "Na_Glass_#{panel_id}")

        unless bar_group && glass_group
            result[:skipped] += 1
            return result
        end

        unless bar_group.manifold? && glass_group.manifold?
            DebugTools.na_debug_warn("ExtSlide trim glass: #{panel_id} non-manifold operand(s); skipping")
            result[:failed] += 1
            return result
        end

        begin
            trimmed = bar_group.trim(glass_group)
            if trimmed
                trimmed.name = "Na_Glass_#{panel_id}_Trimmed"
                result[:fused] += 1
                DebugTools.na_debug_geometry("ExtSlide trim glass: #{panel_id} -> #{trimmed.name}")
            else
                result[:failed] += 1
                DebugTools.na_debug_error("ExtSlide trim glass: #{panel_id} returned nil")
            end
        rescue StandardError => e
            result[:failed] += 1
            DebugTools.na_debug_error("ExtSlide trim glass: #{panel_id} raised", e)
        end

        result
    end
    private_class_method :na_trim_glass_for_panel
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - ADR-Level Frame Fusion (V1.7.1)
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Fuse the Static Outer Frame Parts (Jambs + Head + Bottom)
    # ------------------------------------------------------------
    # The sliding frame is created via the WindowSystem GeometryBuilders
    # so it lays down the same Na_Frame_Left_Stile / Na_Frame_Right_Stile
    # / Na_Frame_Top_Rail / Na_Frame_Bottom_Rail group names. We collect
    # them at the ADR level (NOT inside MODs) and fuse them into a
    # single Na_Frame_Fused solid so the joint lines visible in the
    # user's screenshots disappear.
    def self.na_fuse_outer_frame(parent_entities)
        result = { :fused => 0, :failed => 0, :skipped => 0 }

        groups = na_collect_groups_by_prefix(parent_entities, NA_FRAME_PART_PREFIX)
        if groups.length < 2
            DebugTools.na_debug_geometry("ExtSlide fuse frame: <2 parts found, skipping")
            result[:skipped] += [groups.length, 1].max
            return result
        end

        DebugTools.na_debug_geometry("ExtSlide fuse frame: merging #{groups.length} parts")
        fused = FuseShared.na_sequential_outer_shell(groups, "Na_Frame_Fused")
        if fused
            result[:fused] += 1
        else
            result[:failed] += 1
            DebugTools.na_debug_error("ExtSlide fuse frame: returned nil")
        end
        result
    end
    private_class_method :na_fuse_outer_frame
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Group Collection
# -----------------------------------------------------------------------------

    def self.na_collect_mod_groups(entities)
        entities.to_a.grep(Sketchup::Group).find_all do |g|
            g.valid? && g.name.is_a?(String) && g.name =~ NA_MOD_NAME_REGEX
        end
    end
    private_class_method :na_collect_mod_groups
    # ---------------------------------------------------------------

    def self.na_find_unique_panel_ids(entities, regex)
        ids = []
        entities.to_a.grep(Sketchup::Group).each do |g|
            next unless g.valid?
            match = g.name.match(regex)
            ids << match[1] if match
        end
        ids.uniq.sort
    end
    private_class_method :na_find_unique_panel_ids
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Collect All Groups Whose Name Starts With a Prefix
    # ------------------------------------------------------------
    # Excludes already-fused result groups so re-running the pipeline
    # against the same definition is idempotent.
    def self.na_collect_groups_by_prefix(entities, prefix)
        entities.to_a.grep(Sketchup::Group).find_all do |g|
            g.valid? && g.name.is_a?(String) && g.name.start_with?(prefix) && g.name !~ /_Fused$/
        end
    end
    private_class_method :na_collect_groups_by_prefix
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Collect All Glaze Bar Groups for a Single Panel
    # ------------------------------------------------------------
    def self.na_collect_glazebar_groups(entities, panel_id)
        prefix = "Na_GlazeBar_#{panel_id}_"
        entities.to_a.grep(Sketchup::Group).find_all do |g|
            g.valid? && g.name.is_a?(String) && g.name.start_with?(prefix) && g.name !~ /_Fused$/
        end
    end
    private_class_method :na_collect_glazebar_groups
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Find a Single Group by Exact Name
    # ------------------------------------------------------------
    def self.na_find_group_by_name(entities, name)
        entities.to_a.grep(Sketchup::Group).find { |g| g.valid? && g.name == name }
    end
    private_class_method :na_find_group_by_name
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Merge a Step Result Into the Running Summary
    # ------------------------------------------------------------
    def self.na_accumulate_result(summary, step)
        summary[:fused]   += step[:fused]
        summary[:failed]  += step[:failed]
        summary[:skipped] += step[:skipped]
        summary
    end
    private_class_method :na_accumulate_result
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__FuseParts__Panel
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
