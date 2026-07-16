# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - FUSE PARTS (PANEL)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__FuseParts__Panel__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__FuseParts__Panel
# AUTHOR     : Noble Architecture
# PURPOSE    : Post-build boolean union for exterior doors that use the
#              `<container>__ADR###__Leaf###__*` joinery naming scheme
#              (double + single door). Preserves ADR/MOD/ROT wrappers, cill,
#              fielded-panel profile geometry, linework, handles and glass.
#
# DESCRIPTION:
# - Extracted from the Exterior Double Door System, parameterized by a naming
#   hash so single doors reuse it. Sliding / multifold doors keep their own
#   FuseParts modules (different `Na_DoorPanel_*` part naming).
#
# @param naming [Hash] { :container => "Na__ExteriorDoubleDoor" }
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Fuse__Shared__'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
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

    NA_MOD_NAME_REGEX    = /^MOD\d{3}/.freeze
    NA_FRAME_PART_PREFIX = 'Na_Frame_'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Fuse Door Frame and Leaf Joinery
    # ------------------------------------------------------------
    # @param entities [Sketchup::Entities] ADR definition entities
    # @param naming   [Hash] { :container => "Na__ExteriorDoubleDoor" }
    # @return [Hash] { :fused => Int, :failed => Int, :skipped => Int }
    def self.na_fuse_door(entities, naming = {})
        result = { :fused => 0, :failed => 0, :skipped => 0 }
        return result unless entities

        ctx = na_build_context(naming)

        na_collect_mod_groups(entities).each do |mod_group|
            na_accumulate(result, na_fuse_leaf_joinery(mod_group, ctx))
            na_accumulate(result, na_fuse_glaze_bars(mod_group, ctx))
            na_accumulate(result, na_fuse_leaded_glass(mod_group, ctx))
            na_accumulate(result, na_trim_glass(mod_group, ctx))
        end
        na_accumulate(result, na_fuse_outer_frame(entities))

        DebugTools.na_debug_geometry(
            "ExtDoorCommon fuse summary (#{ctx[:container]}): fused=#{result[:fused]}, " \
            "failed=#{result[:failed]}, skipped=#{result[:skipped]}"
        )
        result
    rescue StandardError => e
        DebugTools.na_debug_error('ExtDoorCommon fuse pipeline failed', e)
        result
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Context + Leaf Pipeline
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Naming Context From Container Prefix
    # ------------------------------------------------------------
    def self.na_build_context(naming)
        container = naming.is_a?(Hash) && naming[:container] && !naming[:container].to_s.empty? ?
                        naming[:container].to_s : 'Na__ExteriorDoor'
        {
            :container => container,
            :structural_regex => /^#{Regexp.escape(container)}__ADR\d{3}__Leaf\d{3}__(?:StileLeft|StileRight|RailBottom|RailTop|RailMid|FieldStile\d+|FieldRail\d+)$/,
            :glaze_bar_prefix => "#{container}__GlazeBar",
            :leaded_glass_prefix => "#{container}__LeadedGlass",
            :glass_name => "#{container}__Glass",
            :leaf_joinery_fused => "#{container}__LeafJoinery__Fused",
            :glaze_bars_fused => "#{container}__GlazeBars__Fused",
            :leaded_glass_fused => "#{container}__LeadedGlass__Fused",
            :glass_trimmed => "#{container}__Glass__Trimmed"
        }
    end
    private_class_method :na_build_context
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse Structural Leaf Joinery Inside One MOD
    # ------------------------------------------------------------
    def self.na_fuse_leaf_joinery(mod_group, ctx)
        result = na_empty_result
        groups = mod_group.entities.to_a.grep(Sketchup::Group).select do |group|
            next false unless group.valid?
            group.name.match?(ctx[:structural_regex])
        end
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(
            groups.dup,
            ctx[:leaf_joinery_fused]
        )
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDoorCommon leaf joinery fuse failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_leaf_joinery
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse Glaze Bars Inside One MOD
    # ------------------------------------------------------------
    def self.na_fuse_glaze_bars(mod_group, ctx)
        result = na_empty_result
        groups = na_collect_groups_by_prefix(mod_group.entities, ctx[:glaze_bar_prefix])
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(
            groups.dup,
            ctx[:glaze_bars_fused]
        )
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDoorCommon glaze-bar fuse failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_glaze_bars
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse Leaded Glass Overlay Inside One MOD (No Glass Trim)
    # ------------------------------------------------------------
    def self.na_fuse_leaded_glass(mod_group, ctx)
        result = na_empty_result
        groups = na_collect_groups_by_prefix(mod_group.entities, ctx[:leaded_glass_prefix]).select do |group|
            next false unless group && group.valid?
            next false if group.entities.grep(Sketchup::Face).empty?
            bb = group.local_bounds
            [bb.width, bb.height, bb.depth].min > 0.001.mm
        end
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(
            groups.dup,
            ctx[:leaded_glass_fused]
        )
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDoorCommon leaded-glass fuse failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_leaded_glass
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Trim Glass With Fused Glaze Bars Inside One MOD
    # ------------------------------------------------------------
    def self.na_trim_glass(mod_group, ctx)
        result = na_empty_result
        bars = na_find_group(mod_group.entities, ctx[:glaze_bars_fused])
        glass = na_find_group(mod_group.entities, ctx[:glass_name])
        return na_skipped(result) unless bars && glass
        return result.merge(:failed => 1) unless bars.manifold? && glass.manifold?

        trimmed = bars.trim(glass)
        return result.merge(:failed => 1) unless trimmed

        trimmed.name = ctx[:glass_trimmed]
        na_repaint_trimmed_glass(trimmed)
        result.merge(:fused => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDoorCommon glass trim failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_trim_glass
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fuse Outer Frame Parts at ADR Level
    # ------------------------------------------------------------
    def self.na_fuse_outer_frame(entities)
        result = na_empty_result
        groups = na_collect_groups_by_prefix(entities, NA_FRAME_PART_PREFIX)
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(groups.dup, 'Na_Frame_Fused')
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error('ExtDoorCommon outer-frame fuse failed', e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_outer_frame
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Group Collection
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Collect Valid MOD Groups From Parent Entities
    # ------------------------------------------------------------
    def self.na_collect_mod_groups(entities)
        entities.to_a.grep(Sketchup::Group).select do |group|
            group.valid? && group.name.match?(NA_MOD_NAME_REGEX)
        end
    end
    private_class_method :na_collect_mod_groups
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Collect Groups Matching a Name Prefix
    # ------------------------------------------------------------
    def self.na_collect_groups_by_prefix(entities, prefix)
        entities.to_a.grep(Sketchup::Group).select do |group|
            group.valid? &&
                group.name.start_with?(prefix) &&
                !group.name.end_with?('__Fused') &&
                !group.name.end_with?('_Fused')
        end
    end
    private_class_method :na_collect_groups_by_prefix
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Find a Group by Exact Name
    # ------------------------------------------------------------
    def self.na_find_group(entities, name)
        entities.to_a.grep(Sketchup::Group).find do |group|
            group.valid? && group.name == name
        end
    end
    private_class_method :na_find_group
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Materials + Result Accumulators
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Mirror Front/Back Materials Onto Missing Faces
    # ------------------------------------------------------------
    def self.na_normalize_materials(groups)
        groups.each do |group|
            group.entities.grep(Sketchup::Face).each do |face|
                next unless face.valid?
                face.back_material = face.material if face.material && face.back_material.nil?
                face.material = face.back_material if face.back_material && face.material.nil?
            end
        end
    end
    private_class_method :na_normalize_materials
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Repaint Trimmed Glass Faces With Source Material
    # ------------------------------------------------------------
    def self.na_repaint_trimmed_glass(group)
        faces = group.entities.grep(Sketchup::Face)
        material = faces.lazy.map { |face| face.material || face.back_material }.find(&:itself)
        return unless material

        faces.each do |face|
            face.material = material
            face.back_material = material
        end
    end
    private_class_method :na_repaint_trimmed_glass
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Empty Fuse Result Hash
    # ------------------------------------------------------------
    def self.na_empty_result
        { :fused => 0, :failed => 0, :skipped => 0 }
    end
    private_class_method :na_empty_result
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Mark a Step as Skipped
    # ------------------------------------------------------------
    def self.na_skipped(result)
        result.merge(:skipped => result[:skipped] + 1)
    end
    private_class_method :na_skipped
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Accumulate Step Counts Into Summary
    # ------------------------------------------------------------
    def self.na_accumulate(summary, step)
        summary[:fused] += step[:fused]
        summary[:failed] += step[:failed]
        summary[:skipped] += step[:skipped]
    end
    private_class_method :na_accumulate
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__FuseParts__Panel
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
