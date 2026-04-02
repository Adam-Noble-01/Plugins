# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - FUSE PARTS
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__FuseParts__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__FuseParts
# AUTHOR     : Noble Architecture
# PURPOSE    : Post-processing module that fuses individual window parts
#              into simplified solid objects using boolean operations
# CREATED    : 2026-02-16
# VERSION    : 0.9.12
#
# DESCRIPTION:
# - Standalone post-processing module called AFTER geometry creation
# - Fuses frame stiles/rails/mullions/transoms into one Frame Solid
# - Fuses casement stiles/rails into one Casement Solid per panel
# - Fuses horizontal/vertical glaze bars into one GlazeBar Solid per panel
# - Trims glass panes using fused glaze bars for clean individual panels
# - Uses sequential outer_shell for fusion and trim for glass cutting
# - Only runs on explicit Create/Update, never during Live Mode
#
# BOOLEAN OPERATIONS USED:
# - outer_shell: Fuse touching/overlapping solids into one outer envelope
# - trim: Non-destructive cut (cutter stays, target gets trimmed)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'

module Na__WindowConfiguratorTool
    module Na__FuseParts

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Main Orchestrator
# -----------------------------------------------------------------------------

        # FUNCTION | Fuse Window Parts
        # ------------------------------------------------------------
        # Main entry point. Scans entities for named groups and performs
        # sequential boolean operations to fuse them into simplified solids.
        #
        # @param entities [Sketchup::Entities] The component definition entities
        # @return [Hash] Summary of fuse operations { fused: Integer, failed: Integer, skipped: Integer }
        def self.na_fuse_window_parts(entities)
            DebugTools.na_debug_method("FuseParts.na_fuse_window_parts")

            summary = { fused: 0, failed: 0, skipped: 0 }

            begin
                # Step 1: Fuse frame (stiles + rails + mullions)
                frame_result = na_fuse_frame(entities)
                na_update_summary(summary, frame_result)

                # Step 2: Fuse casements (per opening)
                casement_result = na_fuse_casements(entities)
                na_update_summary(summary, casement_result)

                # Step 3: Fuse glaze bars (per opening)
                glazebar_result = na_fuse_glaze_bars(entities)
                na_update_summary(summary, glazebar_result)

                # Step 4: Trim glass panels using fused glaze bars
                trim_result = na_trim_glass_panels(entities)
                na_update_summary(summary, trim_result)

                # Step 5: Fuse door panel internal parts (stiles + rails + panels)
                door_panel_result = na_fuse_door_panels(entities)
                na_update_summary(summary, door_panel_result)

                # Step 6: Fuse door trim moulding pieces
                door_trim_result = na_fuse_door_trim(entities)
                na_update_summary(summary, door_trim_result)

                DebugTools.na_debug_success(
                    "Fuse complete: #{summary[:fused]} fused, " \
                    "#{summary[:failed]} failed, #{summary[:skipped]} skipped"
                )

            rescue => e
                DebugTools.na_debug_error("Error in na_fuse_window_parts", e)
            end

            summary
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Fusion
# -----------------------------------------------------------------------------

        # FUNCTION | Fuse Frame Parts
        # ------------------------------------------------------------
        # Collects all Na_Frame_*, Na_Mullion_*, and Na_Transom_* groups and fuses them
        # into a single frame solid using sequential outer_shell.
        #
        # @param entities [Sketchup::Entities] The component definition entities
        # @return [Hash] Result { fused: Integer, failed: Integer, skipped: Integer }
        def self.na_fuse_frame(entities)
            DebugTools.na_debug_geometry("Fusing frame parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            # Collect frame stiles, rails, mullions, and transoms
            frame_groups = na_collect_groups_by_prefix(entities, "Na_Frame_")
            mullion_groups = na_collect_groups_by_prefix(entities, "Na_Mullion_")
            transom_groups = na_collect_groups_by_prefix(entities, "Na_Transom_")
            all_frame_groups = frame_groups + mullion_groups + transom_groups

            if all_frame_groups.length < 2
                DebugTools.na_debug_geometry("Frame: fewer than 2 groups, skipping fusion")
                result[:skipped] += [all_frame_groups.length, 1].max
                return result
            end

            DebugTools.na_debug_geometry("Frame: found #{all_frame_groups.length} groups to fuse")

            fused = na_sequential_outer_shell(all_frame_groups, "Na_Frame_Fused")

            if fused
                result[:fused] += 1
                DebugTools.na_debug_success("Frame fused into: #{fused.name}")
            else
                result[:failed] += 1
                DebugTools.na_debug_error("Frame fusion failed")
            end

            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Casement Fusion
# -----------------------------------------------------------------------------

        # FUNCTION | Fuse Casement Parts
        # ------------------------------------------------------------
        # For each casement panel, collects its stiles and rails and
        # fuses them into a single casement solid. Uses suffix-aware
        # parsing to extract the full panel_id (e.g. "0_0_P0") so that
        # multi-casement panels are fused independently.
        #
        # @param entities [Sketchup::Entities] The component definition entities
        # @return [Hash] Result { fused: Integer, failed: Integer, skipped: Integer }
        def self.na_fuse_casements(entities)
            DebugTools.na_debug_geometry("Fusing casement parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            casement_panel_ids = na_find_unique_panel_ids(
                entities,
                /^Na_Casement_(.+)_(Left_Stile|Right_Stile|Top_Rail|Bottom_Rail|Mid_Rail)$/
            )

            if casement_panel_ids.empty?
                DebugTools.na_debug_geometry("Casements: no casement groups found, skipping")
                return result
            end

            casement_panel_ids.each do |panel_id|
                prefix = "Na_Casement_#{panel_id}_"
                groups = na_collect_groups_by_prefix(entities, prefix)

                if groups.length < 2
                    DebugTools.na_debug_geometry("Casement #{panel_id}: fewer than 2 groups, skipping")
                    result[:skipped] += 1
                    next
                end

                DebugTools.na_debug_geometry("Casement #{panel_id}: found #{groups.length} groups to fuse")

                fused = na_sequential_outer_shell(groups, "Na_Casement_#{panel_id}_Fused")

                if fused
                    result[:fused] += 1
                    DebugTools.na_debug_success("Casement #{panel_id} fused into: #{fused.name}")
                else
                    result[:failed] += 1
                    DebugTools.na_debug_error("Casement #{panel_id} fusion failed")
                end
            end

            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Glaze Bar Fusion
# -----------------------------------------------------------------------------

        # FUNCTION | Fuse Glaze Bar Parts
        # ------------------------------------------------------------
        # For each panel, collects its horizontal and vertical glaze bars
        # and fuses them into a single glaze bar solid. Uses suffix-aware
        # parsing so multi-casement panels get independent bar solids.
        #
        # @param entities [Sketchup::Entities] The component definition entities
        # @return [Hash] Result { fused: Integer, failed: Integer, skipped: Integer }
        def self.na_fuse_glaze_bars(entities)
            DebugTools.na_debug_geometry("Fusing glaze bar parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            glazebar_panel_ids = na_find_unique_panel_ids(
                entities,
                /^Na_GlazeBar_(.+)_[HV]\d+$/
            )

            if glazebar_panel_ids.empty?
                DebugTools.na_debug_geometry("Glaze bars: no glaze bar groups found, skipping")
                return result
            end

            glazebar_panel_ids.each do |panel_id|
                prefix = "Na_GlazeBar_#{panel_id}_"
                groups = na_collect_groups_by_prefix(entities, prefix)

                if groups.length < 2
                    DebugTools.na_debug_geometry("GlazeBar #{panel_id}: fewer than 2 groups, skipping")
                    result[:skipped] += 1
                    next
                end

                DebugTools.na_debug_geometry("GlazeBar #{panel_id}: found #{groups.length} groups to fuse")

                fused = na_sequential_outer_shell(groups, "Na_GlazeBar_#{panel_id}_Fused")

                if fused
                    result[:fused] += 1
                    DebugTools.na_debug_success("GlazeBar #{panel_id} fused into: #{fused.name}")
                else
                    result[:failed] += 1
                    DebugTools.na_debug_error("GlazeBar #{panel_id} fusion failed")
                end
            end

            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Glass Panel Trimming
# -----------------------------------------------------------------------------

        # FUNCTION | Trim Glass Panels
        # ------------------------------------------------------------
        # For each panel that has a fused glaze bar solid, uses trim
        # to cut the glass pane, creating clean individual glass panels.
        # Matches glass by full panel_id so multi-casement panels are
        # trimmed independently.
        #
        # trim behavior: fused_bars.trim(glass) -> bars stay, glass is
        # erased and replaced with trimmed version (overlap areas removed).
        #
        # @param entities [Sketchup::Entities] The component definition entities
        # @return [Hash] Result { fused: Integer, failed: Integer, skipped: Integer }
        def self.na_trim_glass_panels(entities)
            DebugTools.na_debug_geometry("Trimming glass panels with fused glaze bars...")

            result = { fused: 0, failed: 0, skipped: 0 }

            fused_bars = na_collect_groups_by_exact(entities, "Na_GlazeBar_", "_Fused")

            if fused_bars.empty?
                DebugTools.na_debug_geometry("Glass trim: no fused glaze bar groups found, skipping")
                return result
            end

            fused_bars.each do |bar_group|
                panel_id = na_extract_panel_id_from_fused_name(bar_group.name, "Na_GlazeBar_")
                next unless panel_id

                glass_name = "Na_Glass_#{panel_id}"
                glass_group = na_find_group_by_name(entities, glass_name)

                unless glass_group
                    DebugTools.na_debug_geometry("Glass trim #{panel_id}: no glass pane '#{glass_name}' found, skipping")
                    result[:skipped] += 1
                    next
                end

                unless bar_group.manifold?
                    DebugTools.na_debug_warn("Glass trim #{panel_id}: fused glaze bars not manifold, skipping trim")
                    result[:failed] += 1
                    next
                end

                unless glass_group.manifold?
                    DebugTools.na_debug_warn("Glass trim #{panel_id}: glass pane not manifold, skipping trim")
                    result[:failed] += 1
                    next
                end

                DebugTools.na_debug_geometry("Glass trim #{panel_id}: trimming '#{glass_name}' with '#{bar_group.name}'")

                begin
                    trimmed = bar_group.trim(glass_group)

                    if trimmed
                        trimmed.name = "Na_Glass_#{panel_id}_Trimmed"
                        result[:fused] += 1
                        DebugTools.na_debug_success("Glass #{panel_id} trimmed: #{trimmed.name}")
                    else
                        result[:failed] += 1
                        DebugTools.na_debug_error("Glass trim #{panel_id} returned nil (operation failed)")
                    end

                rescue => e
                    result[:failed] += 1
                    DebugTools.na_debug_error("Glass trim #{panel_id} error: #{e.message}")
                end
            end

            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Door Panel Fusion
# -----------------------------------------------------------------------------

        # FUNCTION | Fuse Door Panel Internal Parts
        # ------------------------------------------------------------
        # For each door panel, collects its grid stiles, rails, and recessed
        # panel groups and fuses them into a single solid per panel_id.
        def self.na_fuse_door_panels(entities)
            DebugTools.na_debug_geometry("Fusing door panel parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            door_panel_ids = na_find_unique_panel_ids(
                entities,
                /^Na_DoorPanel_(.+)_(Backing|Stile_\d+|Rail_\d+|Panel_\d+)$/
            )

            if door_panel_ids.empty?
                DebugTools.na_debug_geometry("Door panels: no door panel groups found, skipping")
                return result
            end

            door_panel_ids.each do |panel_id|
                prefix = "Na_DoorPanel_#{panel_id}_"
                groups = na_collect_groups_by_prefix(entities, prefix)

                if groups.length < 2
                    DebugTools.na_debug_geometry("DoorPanel #{panel_id}: fewer than 2 groups, skipping")
                    result[:skipped] += 1
                    next
                end

                DebugTools.na_debug_geometry("DoorPanel #{panel_id}: found #{groups.length} groups to fuse")

                fused = na_sequential_outer_shell(groups, "Na_DoorPanel_#{panel_id}_Fused")

                if fused
                    result[:fused] += 1
                    DebugTools.na_debug_success("DoorPanel #{panel_id} fused into: #{fused.name}")
                else
                    result[:failed] += 1
                    DebugTools.na_debug_error("DoorPanel #{panel_id} fusion failed")
                end
            end

            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Fuse Door Trim Moulding Parts
        # ------------------------------------------------------------
        # For each door panel, collects its trim strips (Bottom, Top, Left, Right)
        # and fuses them into a single trim solid per panel_id.
        def self.na_fuse_door_trim(entities)
            DebugTools.na_debug_geometry("Fusing door trim parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            door_trim_ids = na_find_unique_panel_ids(
                entities,
                /^Na_DoorTrim_(.+)_\d+_(Bottom|Top|Left|Right)$/
            )

            if door_trim_ids.empty?
                DebugTools.na_debug_geometry("Door trim: no door trim groups found, skipping")
                return result
            end

            door_trim_ids.each do |panel_id|
                prefix = "Na_DoorTrim_#{panel_id}_"
                groups = na_collect_groups_by_prefix(entities, prefix)

                if groups.length < 2
                    DebugTools.na_debug_geometry("DoorTrim #{panel_id}: fewer than 2 groups, skipping")
                    result[:skipped] += 1
                    next
                end

                DebugTools.na_debug_geometry("DoorTrim #{panel_id}: found #{groups.length} groups to fuse")

                fused = na_sequential_outer_shell(groups, "Na_DoorTrim_#{panel_id}_Fused")

                if fused
                    result[:fused] += 1
                    DebugTools.na_debug_success("DoorTrim #{panel_id} fused into: #{fused.name}")
                else
                    result[:failed] += 1
                    DebugTools.na_debug_error("DoorTrim #{panel_id} fusion failed")
                end
            end

            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Boolean Helper
# -----------------------------------------------------------------------------

        # FUNCTION | Sequential Outer Shell
        # ------------------------------------------------------------
        # Takes an array of groups and sequentially applies outer_shell
        # to combine them into a single fused solid.
        #
        # IMPORTANT: Works on a Ruby Array copy, never on C++ collections
        # directly. Checks validity and manifold status at each step.
        #
        # @param groups [Array<Sketchup::Group>] Groups to fuse (will be consumed)
        # @param result_name [String] Name for the final fused group
        # @return [Sketchup::Group, nil] The fused group or nil if failed
        def self.na_sequential_outer_shell(groups, result_name)
            return nil if groups.nil? || groups.length < 2

            # Log manifold status for diagnostics
            groups.each do |g|
                unless g.manifold?
                    DebugTools.na_debug_warn("Group '#{g.name}' is NOT manifold - outer_shell may fail")
                end
            end

            # Take the first group as the accumulator
            accumulator = groups.shift

            groups.each_with_index do |item, i|
                # Safety: check both are still valid (previous op may have consumed them)
                unless accumulator && accumulator.valid?
                    DebugTools.na_debug_error("Accumulator became invalid at step #{i}")
                    return nil
                end

                unless item.valid?
                    DebugTools.na_debug_warn("Group at step #{i} is no longer valid, skipping")
                    next
                end

                DebugTools.na_debug_geometry("  outer_shell step #{i + 1}: '#{accumulator.name}' + '#{item.name}'")

                begin
                    new_result = accumulator.outer_shell(item)

                    if new_result
                        accumulator = new_result
                    else
                        DebugTools.na_debug_error("  outer_shell returned nil at step #{i + 1}")
                        return nil
                    end

                rescue => e
                    DebugTools.na_debug_error("  outer_shell error at step #{i + 1}: #{e.message}")
                    return nil
                end
            end

            # Name the final result
            if accumulator && accumulator.valid?
                accumulator.name = result_name
                return accumulator
            end

            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Group Collection Helpers
# -----------------------------------------------------------------------------

        private

        # FUNCTION | Collect Groups by Name Prefix
        # ------------------------------------------------------------
        # Scans entities for groups whose name starts with the given prefix.
        # Returns a Ruby Array (safe for iteration during modification).
        #
        # @param entities [Sketchup::Entities] Entities to scan
        # @param prefix [String] Name prefix to match
        # @return [Array<Sketchup::Group>] Matching groups
        def self.na_collect_groups_by_prefix(entities, prefix)
            entities.to_a.grep(Sketchup::Group).find_all { |g| g.name.start_with?(prefix) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Collect Fused Groups by Prefix and Suffix
        # ------------------------------------------------------------
        # Finds groups whose name starts with prefix and ends with suffix.
        # Used to locate fused glaze bar groups for the trim step.
        #
        # @param entities [Sketchup::Entities] Entities to scan
        # @param prefix [String] Name prefix
        # @param suffix [String] Name suffix
        # @return [Array<Sketchup::Group>] Matching groups
        def self.na_collect_groups_by_exact(entities, prefix, suffix)
            entities.to_a.grep(Sketchup::Group).find_all do |g|
                g.name.start_with?(prefix) && g.name.end_with?(suffix)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find Group by Exact Name
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Entities to scan
        # @param name [String] Exact group name
        # @return [Sketchup::Group, nil] The matching group or nil
        def self.na_find_group_by_name(entities, name)
            entities.to_a.grep(Sketchup::Group).find { |g| g.name == name }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find Unique Panel IDs
        # ------------------------------------------------------------
        # Scans group names matching a regex pattern and extracts unique
        # panel identifiers from the first capture group. Suffix-aware
        # so that multi-segment panel_ids (e.g. "0_0_P0", "0_0_P1")
        # are correctly distinguished.
        #
        # @param entities [Sketchup::Entities] Entities to scan
        # @param pattern [Regexp] Pattern with one capture group for the panel_id
        # @return [Array<String>] Sorted unique panel_ids
        def self.na_find_unique_panel_ids(entities, pattern)
            panel_ids = []
            entities.to_a.grep(Sketchup::Group).each do |g|
                match = g.name.match(pattern)
                next unless match
                panel_ids << match[1]
            end
            panel_ids.uniq.sort
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Panel ID from Fused Group Name
        # ------------------------------------------------------------
        # Extracts the full panel_id from a fused group name by taking
        # everything between the prefix and the "_Fused" suffix.
        # E.g., "Na_GlazeBar_0_0_P0_Fused" with prefix "Na_GlazeBar_"
        # returns "0_0_P0".
        #
        # @param name [String] Group name
        # @param prefix [String] Expected prefix
        # @return [String, nil] The extracted panel_id or nil
        def self.na_extract_panel_id_from_fused_name(name, prefix)
            return nil unless name.start_with?(prefix) && name.end_with?("_Fused")
            panel_id = name.sub(prefix, '').sub(/_Fused$/, '')
            return panel_id unless panel_id.empty?
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Update Summary Hash
        # ------------------------------------------------------------
        # Merges a step result into the running summary.
        #
        # @param summary [Hash] Running summary
        # @param step_result [Hash] Result from one step
        def self.na_update_summary(summary, step_result)
            summary[:fused] += step_result[:fused]
            summary[:failed] += step_result[:failed]
            summary[:skipped] += step_result[:skipped]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FuseParts
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
