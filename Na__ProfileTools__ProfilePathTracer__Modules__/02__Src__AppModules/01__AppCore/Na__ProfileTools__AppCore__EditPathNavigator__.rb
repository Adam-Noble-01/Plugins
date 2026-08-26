# =============================================================================
# NA PROFILE TOOLS - APP CORE - EDIT PATH NAVIGATOR
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__EditPathNavigator__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditPathNavigator
# PURPOSE    : One-click "open the path linework for editing".
#
#              The helper rail usually hugs a corner of the swept solid, which
#              makes it near-impossible to double-click into by hand. This
#              module resolves the Profile Trace assembly from the current
#              selection (the parent itself, or any child such as the
#              SweptSolid), drills the edit context straight into the Helpers
#              sub-group via Model#active_path= (SketchUp 2020+), and
#              pre-selects the path edges ready for Move / stretch / draw.
#
#              Closing the group afterwards fires onActivePathChanged, which
#              triggers the RegenSweep fingerprint pass — so the solid rebuilds
#              automatically when the user clicks back out.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__EditPathNavigator

    # -------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -------------------------------------------------------------------------

        def self.Na__EditPath__OpenForCurrentSelection
            model = Sketchup.active_model
            return self.Na__EditPath__Failure('No active model.') unless model

            if Sketchup.version.to_i < 20
                return self.Na__EditPath__Failure(
                    'Opening the path programmatically needs SketchUp 2020 or newer.'
                )
            end

            parent_group = self.Na__EditPath__ResolveTraceParent(model)
            unless parent_group
                return self.Na__EditPath__Failure(
                    'Select a Profile Trace assembly (or any part of one) first.'
                )
            end

            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            unless helpers_group
                return self.Na__EditPath__Failure(
                    "#{parent_group.name} has no Helpers sub-group to edit."
                )
            end

            edit_path = self.Na__EditPath__BuildEditPath(model, parent_group, helpers_group)
            model.selection.clear

            begin
                model.active_path = edit_path
            rescue ArgumentError => error
                return self.Na__EditPath__Failure(
                    "Could not open the path (locked or invalid context): #{error.message}"
                )
            end

            edge_count = self.Na__EditPath__SelectHelperEdges(model, parent_group)

            message = "Path of #{parent_group.name} open for editing — #{edge_count} edge(s) selected. " \
                      'Edit the linework, then click outside the group and the profile rebuilds automatically.'
            Sketchup.status_text = message
            { 'isOpened' => true, 'statusMessage' => message }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: open failed: #{error.message}")
            self.Na__EditPath__Failure("Edit path failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Resolution Helpers
    # -------------------------------------------------------------------------

        def self.Na__EditPath__ResolveTraceParent(model)
            selection = model.selection.to_a
            return nil unless selection.length == 1
            Na__DataSerializer.Na__DataSerializer__ResolveTraceParentForEntity(selection.first)
        rescue
            nil
        end

        # The selection always lives in the currently open context, so the full
        # instance path is (current active path) + parent + helpers. If the
        # user is ALREADY somewhere inside the assembly, truncate back to it
        # first so the parent never appears twice in the path.
        def self.Na__EditPath__BuildEditPath(model, parent_group, helpers_group)
            base_path    = Array(model.active_path)
            parent_index = base_path.index { |instance| instance == parent_group rescue false }

            if parent_index
                base_path[0..parent_index] + [helpers_group]
            else
                base_path + [parent_group, helpers_group]
            end
        end

        # Re-resolves the Helpers group AFTER the context switch: opening a
        # copied (shared-definition) assembly can make it unique on the spot,
        # swapping in fresh child entities.
        def self.Na__EditPath__SelectHelperEdges(model, parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return 0 unless helpers_group

            edges = helpers_group.entities.grep(Sketchup::Edge).select(&:valid?)
            model.selection.add(edges) unless edges.empty?
            edges.length
        rescue => error
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: edge selection skipped: #{error.message}")
            0
        end

        def self.Na__EditPath__Failure(reason)
            Sketchup.status_text = "Profile Path Tracer: #{reason}"
            { 'isOpened' => false, 'statusMessage' => reason }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
