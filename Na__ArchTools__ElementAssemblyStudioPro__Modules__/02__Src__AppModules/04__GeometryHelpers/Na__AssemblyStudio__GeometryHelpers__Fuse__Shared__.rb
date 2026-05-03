# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SHARED FUSE / OUTER_SHELL HELPER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__GeometryHelpers__Fuse__Shared__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__GeometryHelpers
# MODULE     : Na__Fuse
# AUTHOR     : Noble Architecture
# PURPOSE    : Single implementation of na_sequential_outer_shell. Replaces
#              duplicated logic from Window FuseParts and Interior Door
#              fuse modules.
#
# DESCRIPTION:
# - Mutates `groups` with shift — pass a duplicate if the caller needs the
#   original Array preserved.
# - Logs manifold warnings via DebugTools before first boolean step.
#
# POLICY     : Default = window-strict — return nil immediately when an
#              outer_shell call returns nil. Pass on_nil: :continue to mimic
#              the permissive Interior Door path (keep accumulator, skip merge).
#
# NAMING CONVENTION:
# - Geometry helper namespace Na__GeometryHelpers / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__GeometryHelpers
        module Na__Fuse

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Sequential Outer Shell — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Walk an Array of groups with successive outer_shell
            # ------------------------------------------------------------
            # @param groups [Array<Sketchup::Group>] First element becomes base;
            #   remaining entries are peeled off with shift.
            # @param result_name [String] Assigned to the final accumulator
            # @param on_nil [Symbol] :return_nil (default) or :continue
            # @return [Sketchup::Group, nil]
            def self.na_sequential_outer_shell(groups, result_name, on_nil: :return_nil)
                return nil if groups.nil? || groups.length < 2

                groups.each do |g|
                    DebugTools.na_debug_warn("Group '#{g.name}' is NOT manifold - outer_shell may fail") unless g.manifold?
                end

                accumulator = groups.shift

                groups.each_with_index do |item, i|
                    unless accumulator && accumulator.valid?
                        DebugTools.na_debug_error("Accumulator became invalid at step #{i}")
                        return nil
                    end

                    unless item.valid?
                        DebugTools.na_debug_warn("Operand at step #{i} is invalid; skipping")
                        next
                    end

                    DebugTools.na_debug_geometry("  outer_shell step #{i + 1}: '#{accumulator.name}' + '#{item.name}'")

                    begin
                        new_result = accumulator.outer_shell(item)
                    rescue StandardError => e
                        DebugTools.na_debug_error("outer_shell raised at step #{i + 1}: #{e.message}", e)
                        return nil
                    end

                    if new_result
                        accumulator = new_result
                    elsif on_nil == :continue
                        DebugTools.na_debug_warn("outer_shell returned nil at step #{i + 1}; continuing (on_nil: :continue)")
                    else
                        DebugTools.na_debug_error("outer_shell returned nil at step #{i + 1}")
                        return nil
                    end
                end

                return nil unless accumulator && accumulator.valid?
                accumulator.name = result_name
                accumulator
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end
