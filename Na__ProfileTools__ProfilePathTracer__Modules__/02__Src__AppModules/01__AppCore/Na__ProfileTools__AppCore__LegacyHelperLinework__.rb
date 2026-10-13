# =============================================================================
# NA PROFILE TOOLS - APP CORE - LEGACY HELPER LINEWORK
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__LegacyHelperLinework__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__LegacyHelperLinework
# PURPOSE    : Takes the Helpers linework out of a model built before v1.6.16.
#
# BACKGROUND
#   Until v1.6.15 every trace kept its path as edges in a Helpers sub-group on
#   the 02__ProfilePathTracer_Helpers tag, shown in every scene. From v1.6.16 a
#   trace stores its path as data (PathRuns) and draws it only while it is
#   edited (Edit Path). An old trace moves over by itself the first time it is
#   rebuilt or edited; Settings > Remove Helper Linework moves every trace in
#   the model at once and then removes the tag, if nothing else uses it.
#
# WHAT IT DOES, PER LEGACY TRACE
#   linework as built     -> the path is read from it into PathRuns and the
#                            Helpers group erased. The solid is not touched.
#   linework edited since -> rebuilt along it first (the solid did not follow
#   (fingerprint differs)    it yet), which also stores it and erases it
#   no edges to read      -> left as it is, and counted
#   the user is inside it -> left as it is, and counted
#
#   One undo step: the rebuilds and the tag removal join the operation that
#   moved the rest (transparent).
#
# PUBLIC API
#   Na__LegacyHelpers__Stats(model)     -> Hash (Settings readout)
#   Na__LegacyHelpers__RetireAll(model) -> Hash (with statusMessage)
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__LegacyHelperLinework

    # -------------------------------------------------------------------------
    # REGION | Public - Stats
    # -------------------------------------------------------------------------

        def self.Na__LegacyHelpers__Stats(model)
            empty = { 'total' => 0, 'legacy' => 0, 'editing' => 0, 'helperTag' => false }
            return empty unless model

            parents = self.Na__LegacyHelpers__Traces(model)
            {
                'total'     => parents.length,
                'legacy'    => parents.count { |group| Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(group) },
                'editing'   => parents.count { |group| Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(group) },
                'helperTag' => !self.Na__LegacyHelpers__HelperTag(model).nil?
            }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("LegacyHelperLinework: stats failed: #{error.message}")
            empty
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Remove Helper Linework
    # -------------------------------------------------------------------------

        def self.Na__LegacyHelpers__RetireAll(model)
            return { 'isDone' => false, 'statusMessage' => 'No active model.' } unless model

            legacy = self.Na__LegacyHelpers__Traces(model).select do |group|
                Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(group)
            end
            active_path = Array(model.active_path)
            open_traces = legacy.select { |group| active_path.include?(group) }
            legacy     -= open_traces

            edited, plain = legacy.partition { |group| self.Na__LegacyHelpers__LineworkEdited?(group) }

            moved      = 0
            unreadable = 0
            unless plain.empty?
                model.start_operation('Na__ProfilePathTracer__RemoveHelperLinework', true)
                plain.each do |group|
                    path = Na__RegenEngine.Na__RegenEngine__StoredPathRuns(group)
                    if path[:isValid] && path[:source] == :legacy
                        # A copy sharing this definition would lose its Helpers too.
                        Na__RegenEngine.Na__RegenEngine__EnsureUniqueAssembly(group)
                        Na__DataSerializer.Na__DataSerializer__WritePathRuns(group, path[:runs])
                        Na__DataSerializer.Na__DataSerializer__RetireLegacyHelpers(group)
                        moved += 1
                    else
                        unreadable += 1
                    end
                end
                model.commit_operation
            end

            rebuilt = 0
            failed  = 0
            edited.each do |group|
                if Na__RegenEngine.Na__RegenEngine__RegenerateTrace(group)
                    rebuilt += 1
                else
                    failed += 1
                end
            end

            tag_state = self.Na__LegacyHelpers__RemoveTagIfUnused(model, (moved + rebuilt) > 0)

            status = self.Na__LegacyHelpers__Status(moved, rebuilt, failed, unreadable, open_traces.length, tag_state)
            Sketchup.status_text = "Profile Path Tracer: #{status}"
            {
                'isDone'        => true,
                'moved'         => moved,
                'rebuilt'       => rebuilt,
                'failed'        => failed,
                'unreadable'    => unreadable,
                'skippedOpen'   => open_traces.length,
                'tagState'      => tag_state.to_s,
                'statusMessage' => status
            }
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Error('Remove helper linework failed.', error)
            { 'isDone' => false, 'statusMessage' => "Remove helper linework failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - The Tag
    # -------------------------------------------------------------------------

        # The tag goes only when nothing in the model is on it any more, so a
        # model that reused it for something else keeps it. Removing a tag also
        # takes it out of every scene.
        def self.Na__LegacyHelpers__RemoveTagIfUnused(model, transparent)
            tag = self.Na__LegacyHelpers__HelperTag(model)
            return :absent unless tag
            return :active if model.respond_to?(:active_layer) && model.active_layer == tag
            return :in_use if self.Na__LegacyHelpers__TagInUse?(model, tag)

            model.start_operation('Na__ProfilePathTracer__RemoveHelperTag', true, false, transparent)
            removed = model.layers.remove(tag)
            model.commit_operation
            removed ? :removed : :failed
        rescue => error
            model.commit_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("LegacyHelperLinework: tag removal skipped: #{error.message}")
            :failed
        end

        def self.Na__LegacyHelpers__HelperTag(model)
            model.layers[Na__GeometryBuilders::NA_HELPERS_TAG_NAME]
        rescue
            nil
        end

        # Every entity is visited once: the model root and each definition's
        # own entities (a definition is shared by all its instances).
        def self.Na__LegacyHelpers__TagInUse?(model, tag)
            on_tag = ->(entity) { entity.respond_to?(:layer) && entity.layer == tag }
            return true if model.entities.any?(&on_tag)
            model.definitions.any? { |definition| definition.entities.any?(&on_tag) }
        rescue
            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Support
    # -------------------------------------------------------------------------

        def self.Na__LegacyHelpers__Traces(model)
            seen = {}
            Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model).select do |group|
                pid = (group.persistent_id rescue group.object_id)
                next false if seen[pid]
                seen[pid] = true
            end
        end

        # The solid was built from the linework the stored fingerprint
        # describes; different linework was edited without a rebuild.
        def self.Na__LegacyHelpers__LineworkEdited?(group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(group)
            return false unless helpers_group
            stored_fingerprint = Na__DataSerializer.Na__DataSerializer__ReadHelpersFingerprint(group)
            return false if stored_fingerprint.to_s.empty?
            current_fingerprint = Na__RegenSweep.Na__RegenSweep__ComputeFingerprint(helpers_group)
            !current_fingerprint.nil? && current_fingerprint != stored_fingerprint
        rescue
            false
        end

        def self.Na__LegacyHelpers__Status(moved, rebuilt, failed, unreadable, skipped_open, tag_state)
            parts = []
            if moved.zero? && rebuilt.zero? && failed.zero? && unreadable.zero? && skipped_open.zero?
                parts << 'No trace in this model carries helper linework.'
            else
                parts << "Helper linework removed from #{moved + rebuilt} trace(s); their paths are now stored on the traces." if (moved + rebuilt) > 0
                parts << "#{rebuilt} of them were rebuilt first, because their linework had been edited." if rebuilt > 0
                parts << "#{failed} trace(s) with edited linework would not rebuild and keep it (the status bar said why)." if failed > 0
                parts << "#{unreadable} trace(s) had no linework to read and were left as they are." if unreadable > 0
                parts << "#{skipped_open} trace(s) open for editing were left — close them and run this again." if skipped_open > 0
            end
            tag_name = Na__GeometryBuilders::NA_HELPERS_TAG_NAME
            case tag_state
            when :removed then parts << "The #{tag_name} tag was removed."
            when :in_use  then parts << "The #{tag_name} tag is kept: something in the model is still on it."
            when :active  then parts << "The #{tag_name} tag is kept: it is the current tag."
            when :failed  then parts << "The #{tag_name} tag could not be removed."
            end
            parts.join(' ')
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
