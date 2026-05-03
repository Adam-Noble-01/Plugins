# =============================================================================
# NA INTERIOR DOOR CONFIGURATOR - FUSE LINING PARTS
# =============================================================================
#
# FILE       : Na__InteriorDoorConfigurator__FuseLiningParts__.rb
# NAMESPACE  : Na__InteriorDoorConfigurator
# MODULE     : Na__FuseLiningParts
# AUTHOR     : Noble Architecture
# PURPOSE    : Optional post-processing fusion of the three lining sections
#              into a single upside-down U-shaped solid using outer_shell.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Takes the lining container group produced by Na__GeometryBuilders.na_build_lining
#   and fuses the three child groups (Jamb_L, Head, Jamb_R) into a single
#   "Na__Lining__Fused" group using sequential outer_shell.
# - Architraves are NOT fused: they are produced as single Follow-Me solids
#   by Na__ArchitraveBuilder and have no jointing requirement.
# - Returns a result hash so the caller can log fused/failed/skipped counts.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InteriorDoorConfigurator__DebugTools__'

module Na__InteriorDoorConfigurator
    module Na__FuseLiningParts

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__InteriorDoorConfigurator::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Fuse the Three Lining Sections into a Single Solid
        # ------------------------------------------------------------
        # Walks the lining container group's children, collects all
        # groups whose name begins with "Na__Lining__Jamb_" or
        # "Na__Lining__Head", and runs sequential outer_shell on them.
        #
        # @param lining_container [Sketchup::Group] Group returned by GeometryBuilders.na_build_lining
        # @return [Hash] { :fused => Integer, :failed => Integer, :skipped => Integer }
        def self.na_fuse_lining_parts(lining_container)
            result = { :fused => 0, :failed => 0, :skipped => 0 }

            return result unless lining_container && lining_container.valid?

            sections = na_collect_lining_section_groups(lining_container.entities)
            if sections.length < 2
                DebugTools.na_debug_warn("Lining: fewer than 2 sections, skipping fusion")
                result[:skipped] += sections.length
                return result
            end

            DebugTools.na_debug_geometry("Lining: fusing #{sections.length} sections")

            fused = na_sequential_outer_shell(sections, "Na__Lining__Fused")
            if fused
                result[:fused] += 1
                DebugTools.na_debug_success("Lining fused into: #{fused.name}")
            else
                result[:failed] += 1
                DebugTools.na_debug_error("Lining fusion failed")
            end

            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect Lining Section Groups by Name Prefix
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Lining container entities
        # @return [Array<Sketchup::Group>] Groups matching the lining naming pattern
        def self.na_collect_lining_section_groups(entities)
            target_names = ["Na__Lining__Jamb_L", "Na__Lining__Head", "Na__Lining__Jamb_R"]
            groups = []

            entities.grep(Sketchup::Group).each do |group|
                groups << group if target_names.include?(group.name)
            end

            groups
        end
        private_class_method :na_collect_lining_section_groups
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Sequential Outer Shell
        # ------------------------------------------------------------
        # Mirrors the Window Configurator's na_sequential_outer_shell
        # pattern: shifts the first group as accumulator and folds the
        # remaining groups in with outer_shell, naming the final result.
        #
        # @param groups [Array<Sketchup::Group>] (mutated by shift)
        # @param result_name [String]
        # @return [Sketchup::Group, nil]
        def self.na_sequential_outer_shell(groups, result_name)
            return nil if groups.nil? || groups.length < 2

            groups.each do |g|
                unless g.manifold?
                    DebugTools.na_debug_warn("Lining group '#{g.name}' is NOT manifold - outer_shell may fail")
                end
            end

            accumulator = groups.shift

            groups.each_with_index do |item, i|
                unless accumulator && accumulator.valid?
                    DebugTools.na_debug_error("Lining accumulator became invalid at step #{i}")
                    return nil
                end

                next unless item.valid?

                begin
                    new_result   = accumulator.outer_shell(item)
                    accumulator  = new_result if new_result
                rescue => e
                    DebugTools.na_debug_error("outer_shell error at lining step #{i + 1}: #{e.message}")
                    return nil
                end
            end

            return nil unless accumulator && accumulator.valid?
            accumulator.name = result_name
            accumulator
        end
        private_class_method :na_sequential_outer_shell
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FuseLiningParts
end # module Na__InteriorDoorConfigurator

# =============================================================================
# END OF FILE
# =============================================================================
