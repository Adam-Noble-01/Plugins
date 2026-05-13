# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - GROUP SELECTION COLLECTOR
# =============================================================================
#
# FILE       : Na__MeshDecimator__GroupSelection__Collector__.rb
# NAMESPACE  : Na__MeshDecimator::Na__GroupSelection::Na__Collector
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Collects SketchUp::Group instances from the active selection or
#              active context, with optional recursive nesting. Also houses
#              the ParseBoolean helper used when reading form inputs.
#
# =============================================================================

require 'sketchup.rb'

module Na__MeshDecimator
    module Na__GroupSelection
        module Na__Collector

            # -----------------------------------------------------------------
            # REGION | Boolean Parsing
            # -----------------------------------------------------------------

            def self.na_parse_boolean(value)
                return true  if value == true
                return false if value == false

                normalised = value.to_s.strip.downcase
                normalised == 'true' || normalised == 'yes' || normalised == '1'
            end

            # -----------------------------------------------------------------
            # REGION | Group Collection
            # -----------------------------------------------------------------

            # Returns top-level groups from the selection, falling back to all
            # top-level groups in the active context when nothing is selected.
            def self.na_collect_groups_from_selection_or_context(model)
                selected = model.selection.grep(Sketchup::Group)
                return selected unless selected.empty?

                model.active_entities.grep(Sketchup::Group)
            end

            # Traverses the supplied groups depth-first and returns all
            # groups including nested descendants.
            def self.na_collect_groups_including_nested(groups)
                collected = []
                stack     = groups.dup

                until stack.empty?
                    group = stack.shift
                    next if group.deleted?

                    collected << group
                    stack.concat(group.entities.grep(Sketchup::Group))
                end

                collected
            end

            # -----------------------------------------------------------------
            # REGION | Validation
            # -----------------------------------------------------------------

            # Rejects deleted, locked, or duplicate groups from a list.
            def self.na_filter_processable_groups(groups)
                groups.uniq.reject { |g| g.deleted? || g.locked? }
            end

        end
    end
end
