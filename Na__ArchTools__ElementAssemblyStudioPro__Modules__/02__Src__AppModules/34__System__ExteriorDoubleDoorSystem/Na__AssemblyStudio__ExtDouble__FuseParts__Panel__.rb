# frozen_string_literal: true

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Fuse__Shared__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__FuseParts__Panel

    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    FuseShared = Na__AssemblyStudio::Na__GeometryHelpers::Na__Fuse

    NA_MOD_NAME_REGEX = /^MOD\d{3}/.freeze
    NA_FRAME_PART_PREFIX = 'Na_Frame_'.freeze
    NA_STRUCTURAL_PART_REGEX =
        /^Na__ExteriorDoubleDoor__ADR\d{3}__Leaf\d{3}__(?:StileLeft|StileRight|RailBottom|RailTop|RailMid|FieldStile\d+|FieldRail\d+)$/.freeze
    NA_GLAZE_BAR_PREFIX = 'Na__ExteriorDoubleDoor__GlazeBar'.freeze
    NA_GLASS_NAME = 'Na__ExteriorDoubleDoor__Glass'.freeze

    # FUNCTION | Fuse Exterior Double Door Frame and Leaf Joinery
    # ------------------------------------------------------------
    # Preserves ADR/MOD/ROT wrappers, cill, fielded-panel profile geometry,
    # linework, handles and glass as separate semantic objects.
    def self.na_fuse_exterior_double_door(entities)
        result = { :fused => 0, :failed => 0, :skipped => 0 }
        return result unless entities

        na_collect_mod_groups(entities).each do |mod_group|
            na_accumulate(result, na_fuse_leaf_joinery(mod_group))
            na_accumulate(result, na_fuse_glaze_bars(mod_group))
            na_accumulate(result, na_trim_glass(mod_group))
        end
        na_accumulate(result, na_fuse_outer_frame(entities))

        DebugTools.na_debug_geometry(
            "ExtDouble fuse summary: fused=#{result[:fused]}, " \
            "failed=#{result[:failed]}, skipped=#{result[:skipped]}"
        )
        result
    rescue StandardError => e
        DebugTools.na_debug_error('ExtDouble fuse pipeline failed', e)
        result
    end

    def self.na_fuse_leaf_joinery(mod_group)
        result = na_empty_result
        groups = mod_group.entities.to_a.grep(Sketchup::Group).select do |group|
            next false unless group.valid?
            group.name.match?(NA_STRUCTURAL_PART_REGEX)
        end
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(
            groups.dup,
            'Na__ExteriorDoubleDoor__LeafJoinery__Fused'
        )
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDouble leaf joinery fuse failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_leaf_joinery

    def self.na_fuse_glaze_bars(mod_group)
        result = na_empty_result
        groups = na_collect_groups_by_prefix(mod_group.entities, NA_GLAZE_BAR_PREFIX)
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(
            groups.dup,
            'Na__ExteriorDoubleDoor__GlazeBars__Fused'
        )
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDouble glaze-bar fuse failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_glaze_bars

    def self.na_trim_glass(mod_group)
        result = na_empty_result
        bars = na_find_group(mod_group.entities, 'Na__ExteriorDoubleDoor__GlazeBars__Fused')
        glass = na_find_group(mod_group.entities, NA_GLASS_NAME)
        return na_skipped(result) unless bars && glass
        return result.merge(:failed => 1) unless bars.manifold? && glass.manifold?

        trimmed = bars.trim(glass)
        return result.merge(:failed => 1) unless trimmed

        trimmed.name = 'Na__ExteriorDoubleDoor__Glass__Trimmed'
        na_repaint_trimmed_glass(trimmed)
        result.merge(:fused => 1)
    rescue StandardError => e
        DebugTools.na_debug_error("ExtDouble glass trim failed for #{mod_group.name}", e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_trim_glass

    def self.na_fuse_outer_frame(entities)
        result = na_empty_result
        groups = na_collect_groups_by_prefix(entities, NA_FRAME_PART_PREFIX)
        return na_skipped(result) if groups.length < 2

        na_normalize_materials(groups)
        fused = FuseShared.na_sequential_outer_shell(groups.dup, 'Na_Frame_Fused')
        fused ? result.merge(:fused => 1) : result.merge(:failed => 1)
    rescue StandardError => e
        DebugTools.na_debug_error('ExtDouble outer-frame fuse failed', e)
        result.merge(:failed => result[:failed] + 1)
    end
    private_class_method :na_fuse_outer_frame

    def self.na_collect_mod_groups(entities)
        entities.to_a.grep(Sketchup::Group).select do |group|
            group.valid? && group.name.match?(NA_MOD_NAME_REGEX)
        end
    end
    private_class_method :na_collect_mod_groups

    def self.na_collect_groups_by_prefix(entities, prefix)
        entities.to_a.grep(Sketchup::Group).select do |group|
            group.valid? &&
                group.name.start_with?(prefix) &&
                !group.name.end_with?('__Fused') &&
                !group.name.end_with?('_Fused')
        end
    end
    private_class_method :na_collect_groups_by_prefix

    def self.na_find_group(entities, name)
        entities.to_a.grep(Sketchup::Group).find do |group|
            group.valid? && group.name == name
        end
    end
    private_class_method :na_find_group

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

    def self.na_empty_result
        { :fused => 0, :failed => 0, :skipped => 0 }
    end
    private_class_method :na_empty_result

    def self.na_skipped(result)
        result.merge(:skipped => result[:skipped] + 1)
    end
    private_class_method :na_skipped

    def self.na_accumulate(summary, step)
        summary[:fused] += step[:fused]
        summary[:failed] += step[:failed]
        summary[:skipped] += step[:skipped]
    end
    private_class_method :na_accumulate

end
end
end
