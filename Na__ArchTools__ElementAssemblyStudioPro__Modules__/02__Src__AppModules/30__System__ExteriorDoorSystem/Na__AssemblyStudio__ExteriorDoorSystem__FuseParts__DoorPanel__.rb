# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR SYSTEM FUSE PARTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExteriorDoorSystem__FuseParts__DoorPanel__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorSystem::Na__FuseParts__DoorPanel
# AUTHOR     : Noble Architecture
# PURPOSE    : Door-panel and door-trim fusion. Extracted from the original
#              window FuseParts steps 5-6 so WindowSystem stays free of
#              door-specific operations. Uses the shared Fuse__Shared helper
#              for the actual outer_shell loop.
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Fuse__Shared__'

module Na__AssemblyStudio
    module Na__ExteriorDoorSystem
        module Na__FuseParts__DoorPanel

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            FuseShared = Na__AssemblyStudio::Na__GeometryHelpers::Na__Fuse

            def self.na_fuse_door_panels(entities)
                result = { :fused => 0, :failed => 0, :skipped => 0 }
                door_panel_ids = na_find_unique_panel_ids(entities,
                    /^Na_DoorPanel_(.+)_(Margin_(?:Left|Right|Top|Bottom)|Stile_\d+|Rail_\d+|Panel_\d+)$/)
                return result if door_panel_ids.empty?

                door_panel_ids.each do |panel_id|
                    groups = na_collect_groups_by_prefix(entities, "Na_DoorPanel_#{panel_id}_")
                    if groups.length < 2
                        result[:skipped] += 1
                        next
                    end
                    fused = FuseShared.na_sequential_outer_shell(groups, "Na_DoorPanel_#{panel_id}_Fused")
                    if fused
                        result[:fused] += 1
                    else
                        result[:failed] += 1
                    end
                end
                result
            end

            def self.na_fuse_door_trim(entities)
                result = { :fused => 0, :failed => 0, :skipped => 0 }
                door_trim_ids = na_find_unique_panel_ids(entities,
                    /^Na_DoorTrim_(.+)_\d+_[FB]_(Bottom|Top|Left|Right)$/)
                return result if door_trim_ids.empty?

                door_trim_ids.each do |panel_id|
                    groups = na_collect_groups_by_prefix(entities, "Na_DoorTrim_#{panel_id}_")
                    if groups.length < 2
                        result[:skipped] += 1
                        next
                    end
                    fused = FuseShared.na_sequential_outer_shell(groups, "Na_DoorTrim_#{panel_id}_Fused")
                    if fused
                        result[:fused] += 1
                    else
                        result[:failed] += 1
                    end
                end
                result
            end

            # Internal helpers -------------------------------------------------

            def self.na_collect_groups_by_prefix(entities, prefix)
                entities.to_a.grep(Sketchup::Group).find_all { |g| g.name.start_with?(prefix) }
            end
            private_class_method :na_collect_groups_by_prefix

            def self.na_find_unique_panel_ids(entities, pattern)
                ids = []
                entities.to_a.grep(Sketchup::Group).each do |g|
                    m = g.name.match(pattern)
                    ids << m[1] if m
                end
                ids.uniq.sort
            end
            private_class_method :na_find_unique_panel_ids

        end
    end
end
