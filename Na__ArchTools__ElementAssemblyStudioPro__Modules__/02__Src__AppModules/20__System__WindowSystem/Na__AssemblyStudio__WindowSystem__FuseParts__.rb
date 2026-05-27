# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - FUSE PARTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__FuseParts__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
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
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__FuseParts

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

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

                # Steps 5-6: ExteriorSingleDoorSystem owns the door panel + trim fuse logic.
                # WindowSystem delegates via the inter-system PanelInterface contract.
                if defined?(::Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::PanelInterface)
                    door_result = ::Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::PanelInterface.na_fuse_panel_steps(entities)
                    na_update_summary(summary, door_result) if door_result.is_a?(Hash)
                end

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

            # Pattern accepts:
            #   _H<n>        - horizontal straight bar
            #   _V<n>        - vertical straight bar
            #   _Arch<n>_L   - left half of a Gothic arc (single pushpull solid)
            #   _Arch<n>_R   - right half of a Gothic arc (single pushpull solid)
            # so panels with arches but zero straight bars still get a fuse
            # pass triggered (the per-panel prefix collector below then
            # picks up the arch halves unchanged).
            glazebar_panel_ids = na_find_unique_panel_ids(
                entities,
                /^Na_GlazeBar_(.+?)_(?:[HV]\d+|Arch\d+_[LR])$/
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

                # Pre-fuse pass: copy front material -> back material on
                # every face of glaze bar groups that are NOT already
                # symmetric. The arch halves built by
                # `GeometryHelpers.na_create_glaze_bar_arch_half` already
                # paint both sides at construction, so we skip them here
                # (saves an entities.grep walk per arch half).
                groups.each do |g|
                    next if g.nil? || !g.valid?
                    next if g.name =~ /_Arch\d+_[LR]$/
                    na_normalize_face_back_materials(g)
                end

                # Detect whether arch halves are part of this panel's
                # fuse set. Used to decide whether the post-fuse soften
                # pass is worth running -- straight bars have no
                # near-coplanar edges to smooth, so the iteration over
                # every edge in the fused result is pure waste for
                # arch-free panels.
                has_arch_halves = groups.any? { |g| g && g.valid? && g.name =~ /_Arch\d+_[LR]$/ }

                DebugTools.na_debug_geometry("GlazeBar #{panel_id}: found #{groups.length} groups to fuse")

                fused = na_sequential_outer_shell(groups, "Na_GlazeBar_#{panel_id}_Fused")

                if fused
                    # Post-fuse pass: soften + smooth any edge whose two
                    # adjacent face normals diverge by 22 deg or less, so
                    # the tessellated gothic arc reads as a smooth curve
                    # rather than a faceted polyline. Equivalent to using
                    # SketchUp's Soften/Smooth Edges dialog with a 22 deg
                    # angle threshold. Skipped entirely when there are
                    # no arches (straight bars have nothing to smooth).
                    na_soften_smooth_edges_within_angle(fused, 22.0) if has_arch_halves

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

        # FUNCTION | Copy Front Material To Back Face Of Every Face In Group
        # ------------------------------------------------------------
        # Faces created by Entities.add_face / pushpull keep their front
        # material but leave the back side nil. When neighbouring groups
        # are then boolean-merged, the seam between them stays visible
        # because one side has a material and the other does not. This
        # helper makes both sides agree before the boolean runs.
        def self.na_normalize_face_back_materials(group)
            return unless group && group.valid?
            group.entities.grep(Sketchup::Face).each do |face|
                next unless face.valid?
                front_mat = face.material
                back_mat  = face.back_material
                if front_mat && back_mat.nil?
                    face.back_material = front_mat
                elsif back_mat && front_mat.nil?
                    face.material = back_mat
                end
            end
        rescue StandardError => e
            DebugTools.na_debug_error("na_normalize_face_back_materials exception", e)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Soften + Smooth Edges Inside a Group Below an Angle Threshold
        # ------------------------------------------------------------
        # Mirrors SketchUp's Soften/Smooth Edges dialog: walks every edge
        # in the group, and if the two adjacent face normals differ by
        # less than `angle_deg`, marks the edge as both soft (no shading
        # break) and smooth (interpolated face normals). This is how
        # tessellated curves are made to read as continuous curves in
        # SketchUp -- the standard professional workflow.
        def self.na_soften_smooth_edges_within_angle(group, angle_deg)
            return unless group && group.valid?
            threshold_rad = angle_deg.to_f * Math::PI / 180.0
            group.entities.grep(Sketchup::Edge).each do |edge|
                next unless edge.valid?
                faces = edge.faces
                next unless faces.length == 2
                normal_a = faces[0].normal
                normal_b = faces[1].normal
                angle = normal_a.angle_between(normal_b).abs
                next unless angle <= threshold_rad
                edge.soft   = true
                edge.smooth = true
            end
        rescue StandardError => e
            DebugTools.na_debug_error("na_soften_smooth_edges_within_angle exception", e)
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

                        # The trim operation creates NEW faces wherever the
                        # bars cut through the glass; those new faces only
                        # get a front material. SketchUp paints unpainted
                        # backfaces in the default "red" debug colour, so
                        # the result looks broken from inside the room.
                        # Propagate the glass material to BOTH sides of
                        # every face in the trimmed group so all glazing
                        # reads consistently.
                        na_repaint_trimmed_glass(trimmed)

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

        # FUNCTION | Apply Glass Material To Both Sides Of Every Face
        # ------------------------------------------------------------
        # Picks the glass material off whichever face already carries one
        # (the original glass pane provided it before the trim), then
        # writes it to front + back of every face in the group. This
        # eliminates the default-red backface look on glass interiors
        # that appears after `bar_group.trim(glass_group)` creates new
        # cut faces with no back material set.
        def self.na_repaint_trimmed_glass(group)
            return unless group && group.valid?
            faces = group.entities.grep(Sketchup::Face)
            return if faces.empty?

            glass_material = nil
            faces.each do |face|
                if face.material
                    glass_material = face.material
                    break
                end
                if face.back_material
                    glass_material = face.back_material
                    break
                end
            end
            return unless glass_material

            faces.each do |face|
                next unless face.valid?
                face.material      = glass_material
                face.back_material = glass_material
            end
        rescue StandardError => e
            DebugTools.na_debug_error("na_repaint_trimmed_glass exception", e)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Door Panel Fusion
# -----------------------------------------------------------------------------

        # MOVED to ExteriorSingleDoorSystem::FuseParts__DoorPanel - retained as private
        # back-compat shim returning empty result. New callers use PanelInterface.
        def self.na_fuse_door_panels_DEPRECATED(entities)
            DebugTools.na_debug_geometry("Fusing door panel parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            door_panel_ids = na_find_unique_panel_ids(
                entities,
                /^Na_DoorPanel_(.+)_(Margin_(?:Left|Right|Top|Bottom)|Stile_\d+|Rail_\d+|Panel_\d+)$/
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

        # MOVED to ExteriorSingleDoorSystem::FuseParts__DoorPanel - retained as private
        # back-compat shim returning empty result. New callers use PanelInterface.
        def self.na_fuse_door_trim_DEPRECATED(entities)
            DebugTools.na_debug_geometry("Fusing door trim parts...")

            result = { fused: 0, failed: 0, skipped: 0 }

            door_trim_ids = na_find_unique_panel_ids(
                entities,
                /^Na_DoorTrim_(.+)_\d+_[FB]_(Bottom|Top|Left|Right)$/
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
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
