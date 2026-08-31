# =============================================================================
# NA PROFILE TOOLS - PROFILE SWAP ENGINE
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfileSwapEngine__Main__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__SwapEngine
# PURPOSE    : Hot-swaps the profile of an ALREADY PLACED Profile Trace
#              assembly. The helper linework, the stored start point and the
#              trace id all stay exactly as they are — only the ProfileKey (and
#              optionally the placement settings that ride with it) change, and
#              the existing regeneration engine rebuilds the swept solid.
#
# WHY THIS IS THIN
#   Everything hard was already solved by Dynamic Regeneration: the Helpers
#   sub-group is the authoritative path, and Na__RegenEngine already rebuilds
#   the SweptSolid from it using whatever ProfileKey the parent dictionary
#   carries. A swap is therefore "rewrite one dictionary value, then regenerate"
#   — no new geometry code, and every existing guarantee (legacy path frame,
#   multi-run chains, fingerprint stamping, observer re-attach) comes along.
#
# PUBLIC API
#   Na__SwapEngine__ResolveSelectedTraces(model)  -> [Sketchup::Group, ...]
#       Every distinct Profile Trace assembly touched by the current selection.
#       Any descendant (SweptSolid, Helpers, a face inside them) resolves up to
#       its parent, so the user does not have to select precisely.
#
#   Na__SwapEngine__BuildBindPayload(model)       -> Hash
#       Dialog-facing descriptor of that selection: trace ids, the primary
#       trace's current profile, and its stored placement settings.
#
#   Na__SwapEngine__ApplySwap(request)            -> Hash
#       request = { 'traceIds' => [...], 'profileKey' => '...',
#                   'rotationStep' => Int, 'toggleStates' => {...},
#                   'originOffset' => {'y'=>mm,'z'=>mm} | nil }
#       A blank / absent profileKey means "keep the profile, just re-apply the
#       placement settings" — which is what the dialog's Regenerate Trace button
#       sends after the insert point has been moved.
#
# WHAT IS DELIBERATELY NOT SWAPPABLE
#   ReverseDirection. Reverse is baked into the parent group's own
#   transformation at build time (a Z mirror about the plane through
#   bounds.max.z), so re-applying it later would mirror about a DIFFERENT plane
#   — the assembly would jump position. The stored flag is therefore carried
#   through untouched and the dialog disables the Reverse control while a trace
#   is bound.
#
#   SchemaVersion. A pre-1.2.0 assembly was swept with the legacy right-handed
#   path frame; Na__RegenEngine keys its frame choice off the stored version.
#   Bumping it here would silently mirror geometry that already stands in a
#   model, so the version stays exactly as stamped.
#
# DEPENDENCIES
#   Na__DataSerializer            - reads / patches the parent dictionary
#   Na__ProfileLibrary            - resolves and validates the incoming key
#   Na__ProfilePlacementEngine    - unified-schema check
#   Na__RegenEngine               - the rebuild itself
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__SwapEngine

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_TRACE_NAME_PREFIX     = 'Na__ProfileTrace__'.freeze
        NA_DYNREGEN_SUFFIX_FALLBACK = ' [DynRegen]'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Selection Resolution
    # -------------------------------------------------------------------------

        # Deduped by persistent id: selecting a parent AND its SweptSolid child
        # must not queue the same assembly for two rebuilds.
        def self.Na__SwapEngine__ResolveSelectedTraces(model)
            return [] unless model

            seen     = {}
            resolved = []

            model.selection.to_a.each do |entity|
                parent = Na__DataSerializer.Na__DataSerializer__ResolveTraceParentForEntity(entity)
                next unless parent
                identity = (parent.persistent_id rescue parent.object_id)
                next if seen[identity]
                seen[identity] = true
                resolved << parent
            end

            resolved
        rescue => error
            Na__DebugTools.Na__Debug__Warn("SwapEngine: selection resolve failed: #{error.message}")
            []
        end

        def self.Na__SwapEngine__ResolveTraceById(trace_id)
            return nil if trace_id.to_s.strip.empty?
            Na__DataSerializer.Na__DataSerializer__FindParentByIdInModel(trace_id.to_s)
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Bind Payload (dialog descriptor)
    # -------------------------------------------------------------------------

        def self.Na__SwapEngine__BuildBindPayload(model)
            traces = self.Na__SwapEngine__ResolveSelectedTraces(model)
            return self.Na__SwapEngine__UnboundPayload(
                'Select a Profile Trace assembly (or any part of one) first, then Swap Profile.'
            ) if traces.empty?

            trace_ids = traces.map { |group| Na__DataSerializer.Na__DataSerializer__ReadTraceId(group) }
                              .reject { |id| id.to_s.empty? }
            return self.Na__SwapEngine__UnboundPayload(
                'The selected assembly carries no Profile Trace id — it cannot be swapped.'
            ) if trace_ids.empty?

            payload = self.Na__SwapEngine__BuildBindPayloadForIds(trace_ids)
            self.Na__SwapEngine__NoteClonedIds(payload, trace_ids)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("SwapEngine: bind payload failed: #{error.message}")
            self.Na__SwapEngine__UnboundPayload("Swap target could not be read: #{error.message}")
        end

        # A freshly copied assembly keeps its original ProfileTraceId until the
        # RegenSweep re-stamps it, and traces are addressed by id — so a
        # selection of un-repaired copies would silently collapse to one and
        # swap only that. Say so rather than partly applying in silence.
        def self.Na__SwapEngine__NoteClonedIds(payload, trace_ids)
            duplicate_count = trace_ids.length - trace_ids.uniq.length
            return payload if duplicate_count.zero?

            payload.merge(
                'statusMessage' => "#{payload['statusMessage']} " \
                    "#{duplicate_count} selected copy(ies) share a trace id and were left out — " \
                    'click outside the assemblies once to let the change sweep re-stamp them, then swap again.'
            )
        rescue
            payload
        end

        # Rebuilt from ids (not group references) after a swap, so the dialog
        # always reflects what is actually stamped on the assemblies now.
        def self.Na__SwapEngine__BuildBindPayloadForIds(trace_ids)
            ids     = Array(trace_ids).map(&:to_s).reject(&:empty?).uniq
            primary = self.Na__SwapEngine__ResolveTraceById(ids.first)
            return self.Na__SwapEngine__UnboundPayload('The bound Profile Trace is no longer in the model.') unless primary

            payload      = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(primary) || {}
            profile_key  = payload['ProfileKey'].to_s
            display_name = self.Na__SwapEngine__ProfileDisplayName(profile_key)

            {
                'isBound'            => true,
                'traceIds'           => ids,
                'traceCount'         => ids.length,
                'primaryTraceId'     => ids.first,
                'primaryProfileKey'  => profile_key,
                'primaryProfileName' => display_name,
                'primaryGroupName'   => primary.name.to_s,
                'placement'          => {
                    'rotationStep'     => payload['RotationStep'].to_i,
                    'toggleStates'     => payload['ToggleStates'].is_a?(Hash) ? payload['ToggleStates'] : {},
                    'originOffset'     => payload['OriginOffset'],
                    'reverseDirection' => payload['ReverseDirection'] == true
                },
                'statusMessage'      => self.Na__SwapEngine__BindStatusMessage(ids, display_name, profile_key)
            }
        end

        def self.Na__SwapEngine__UnboundPayload(status_message)
            {
                'isBound'            => false,
                'traceIds'           => [],
                'traceCount'         => 0,
                'primaryTraceId'     => '',
                'primaryProfileKey'  => '',
                'primaryProfileName' => '',
                'primaryGroupName'   => '',
                'placement'          => {
                    'rotationStep'     => 0,
                    'toggleStates'     => {},
                    'originOffset'     => nil,
                    'reverseDirection' => false
                },
                'statusMessage'      => status_message.to_s
            }
        end

        def self.Na__SwapEngine__BindStatusMessage(ids, display_name, profile_key)
            label = display_name.to_s.empty? ? profile_key.to_s : display_name.to_s
            if ids.length == 1
                "#{ids.first} bound (currently #{label}). Pick a replacement profile in the Gallery."
            else
                "#{ids.length} traces bound (primary #{ids.first}, currently #{label}). Pick a replacement profile in the Gallery."
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Swap Execution
    # -------------------------------------------------------------------------

        def self.Na__SwapEngine__ApplySwap(request)
            request   = {} unless request.is_a?(Hash)
            trace_ids = Array(request['traceIds']).map(&:to_s).reject(&:empty?).uniq
            return self.Na__SwapEngine__FailureResult('No Profile Trace is bound — nothing to swap.') if trace_ids.empty?

            model = Sketchup.active_model
            return self.Na__SwapEngine__FailureResult('No active model.') unless model

            # Blank key = "keep the current profile, re-apply the placement only".
            requested_key = request['profileKey'].to_s.strip
            is_key_change = !requested_key.empty?

            # Validated up front, not inside the loop: every library lookup
            # re-reads the whole profile folder from disk, and a bad key must
            # fail before any assembly has been touched.
            if is_key_change
                validation = self.Na__SwapEngine__ValidateProfileKey(requested_key)
                return self.Na__SwapEngine__FailureResult(validation[:reason]) unless validation[:isValid]
            end

            overrides = self.Na__SwapEngine__NormaliseOverrides(request, is_key_change)

            swapped  = []
            failures = []

            trace_ids.each do |trace_id|
                outcome = self.Na__SwapEngine__SwapOneTrace(model, trace_id, requested_key, overrides)
                if outcome[:isSwapped]
                    swapped << trace_id
                else
                    failures << { 'traceId' => trace_id, 'reason' => outcome[:reason] }
                end
            end

            self.Na__SwapEngine__BuildSwapResult(trace_ids, swapped, failures, requested_key, is_key_change)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("SwapEngine: swap failed: #{error.message}")
            self.Na__SwapEngine__FailureResult("Swap failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Single Trace Swap
    # -------------------------------------------------------------------------

        # The dictionary patch and the rebuild are separate operations (the
        # rebuild opens its own, transparent, so both land as one undo step).
        # That leaves a window where the stored key could outrun the geometry if
        # the rebuild fails, so a failed rebuild rolls the dictionary back.
        def self.Na__SwapEngine__SwapOneTrace(model, trace_id, requested_key, overrides)
            parent_group = self.Na__SwapEngine__ResolveTraceById(trace_id)
            return { isSwapped: false, reason: 'trace not found in the model' } unless parent_group

            previous_payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(parent_group)
            return { isSwapped: false, reason: 'trace carries no Profile Path Tracer dictionary' } unless previous_payload

            readiness = self.Na__SwapEngine__CheckHelpersReady(parent_group)
            return { isSwapped: false, reason: readiness[:reason] } unless readiness[:isReady]

            previous_key  = previous_payload['ProfileKey'].to_s
            previous_name = parent_group.name.to_s
            next_key      = requested_key.empty? ? previous_key : requested_key

            updates = overrides.dup
            updates['ProfileKey'] = next_key

            # A datum picked on the old profile means nothing on the new one, so
            # a key change resets it unless the caller sent one explicitly.
            if next_key != previous_key && !updates.key?('OriginOffset')
                updates['OriginOffset'] = nil
            end

            model.start_operation('Na__ProfilePathTracer__SwapProfile', true)
            Na__DataSerializer.Na__DataSerializer__UpdateParentPlacement(parent_group, updates)
            self.Na__SwapEngine__RenameForProfile(parent_group, next_key, previous_key)
            model.commit_operation

            return { isSwapped: true, reason: nil } if Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(parent_group)

            self.Na__SwapEngine__RestorePreviousPlacement(model, parent_group, previous_payload, previous_name)
            { isSwapped: false, reason: 'rebuild failed — the previous profile has been restored' }
        rescue => error
            model.abort_operation rescue nil
            { isSwapped: false, reason: error.message }
        end

        def self.Na__SwapEngine__RestorePreviousPlacement(model, parent_group, previous_payload, previous_name)
            return unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)

            model.start_operation('Na__ProfilePathTracer__SwapProfileRevert', true, false, true)
            Na__DataSerializer.Na__DataSerializer__UpdateParentPlacement(
                parent_group,
                'ProfileKey'   => previous_payload['ProfileKey'].to_s,
                'RotationStep' => previous_payload['RotationStep'].to_i,
                'ToggleStates' => previous_payload['ToggleStates'],
                'OriginOffset' => previous_payload['OriginOffset']
            )
            parent_group.name = previous_name unless previous_name.empty?
            model.commit_operation
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("SwapEngine: rollback skipped: #{error.message}")
        end

        # Cheap pre-flight so the obvious failure (an assembly whose linework has
        # been emptied) is reported without writing to the dictionary at all.
        def self.Na__SwapEngine__CheckHelpersReady(parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return { isReady: false, reason: 'no Helpers sub-group to rebuild from' } unless helpers_group

            edge_count = helpers_group.entities.grep(Sketchup::Edge).count(&:valid?)
            return { isReady: false, reason: 'Helpers linework is empty' } if edge_count.zero?

            { isReady: true, reason: nil }
        rescue => error
            { isReady: false, reason: error.message }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Naming
    # -------------------------------------------------------------------------

        # Only renames a group still carrying the generated name for its OLD
        # profile — a group the user has renamed by hand keeps their name.
        def self.Na__SwapEngine__RenameForProfile(parent_group, next_key, previous_key)
            return false if next_key.to_s.empty? || next_key == previous_key

            suffix       = self.Na__SwapEngine__DynRegenSuffix
            current_name = parent_group.name.to_s
            has_suffix   = current_name.end_with?(suffix)
            base_name    = has_suffix ? current_name.delete_suffix(suffix) : current_name

            return false unless base_name == "#{NA_TRACE_NAME_PREFIX}#{previous_key}"

            parent_group.name = "#{NA_TRACE_NAME_PREFIX}#{next_key}#{has_suffix ? suffix : ''}"
            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("SwapEngine: rename skipped: #{error.message}")
            false
        end

        def self.Na__SwapEngine__DynRegenSuffix
            return Na__ContextMenuHandlers::NA_DYNREGEN_SUFFIX if defined?(Na__ContextMenuHandlers::NA_DYNREGEN_SUFFIX)
            NA_DYNREGEN_SUFFIX_FALLBACK
        rescue
            NA_DYNREGEN_SUFFIX_FALLBACK
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Request Normalisation + Validation
    # -------------------------------------------------------------------------

        def self.Na__SwapEngine__ValidateProfileKey(profile_key)
            profile_record = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return { isValid: false, reason: "Profile '#{profile_key}' is not in the library." } unless profile_record

            unless Na__ProfilePlacementEngine.Na__Engine__UnifiedProfileRecord?(profile_record)
                return { isValid: false, reason: "Profile '#{profile_key}' is not in unified schema format." }
            end

            { isValid: true, reason: nil }
        rescue => error
            { isValid: false, reason: "Profile '#{profile_key}' could not be read: #{error.message}" }
        end

        # Only keys the caller actually sent are patched — an absent key leaves
        # whatever the assembly was stamped with alone. 'originOffset' is the one
        # exception: the dialog sends it as an explicit null to clear the datum,
        # so presence of the key (not its value) decides.
        def self.Na__SwapEngine__NormaliseOverrides(request, _is_key_change)
            overrides = {}

            overrides['RotationStep'] = request['rotationStep'].to_i % 4 if request.key?('rotationStep')
            overrides['ToggleStates'] = request['toggleStates']          if request['toggleStates'].is_a?(Hash)
            overrides['OriginOffset'] = self.Na__SwapEngine__NormaliseOriginOffset(request['originOffset']) if request.key?('originOffset')

            overrides
        end

        def self.Na__SwapEngine__NormaliseOriginOffset(incoming)
            return nil unless incoming.is_a?(Hash)
            y_mm = (incoming['y'] || incoming[:y]).to_f
            z_mm = (incoming['z'] || incoming[:z]).to_f
            return nil if y_mm.zero? && z_mm.zero?
            { 'y' => y_mm, 'z' => z_mm }
        rescue
            nil
        end

        def self.Na__SwapEngine__ProfileDisplayName(profile_key)
            return '' if profile_key.to_s.empty?
            profile_record = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return profile_key.to_s unless profile_record
            profile_record['displayName'].to_s.empty? ? profile_key.to_s : profile_record['displayName'].to_s
        rescue
            profile_key.to_s
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Result Builders
    # -------------------------------------------------------------------------

        def self.Na__SwapEngine__BuildSwapResult(trace_ids, swapped, failures, requested_key, is_key_change)
            display_name = is_key_change ? self.Na__SwapEngine__ProfileDisplayName(requested_key) : ''
            verb         = is_key_change ? 'swapped to' : 'regenerated with'
            subject      = is_key_change ? display_name : 'its current profile'

            status = if swapped.empty?
                "Swap failed on all #{trace_ids.length} trace(s): #{failures.map { |f| f['reason'] }.uniq.join('; ')}"
            elsif failures.empty?
                "#{swapped.length} trace(s) #{verb} #{subject}."
            else
                "#{swapped.length} of #{trace_ids.length} trace(s) #{verb} #{subject}. " \
                "Skipped: #{failures.map { |f| "#{f['traceId']} (#{f['reason']})" }.join(', ')}"
            end

            self.Na__SwapEngine__ReportStatus(status)

            {
                'isSwapped'    => !swapped.empty?,
                'swappedCount' => swapped.length,
                'failedCount'  => failures.length,
                'failures'     => failures,
                'bind'         => self.Na__SwapEngine__BuildBindPayloadForIds(trace_ids),
                'statusMessage'=> status
            }
        end

        def self.Na__SwapEngine__ReportStatus(message)
            Sketchup.status_text = "Profile Path Tracer: #{message}"
            Na__DebugTools.Na__Debug__Info("SwapEngine: #{message}")
        rescue
            nil
        end

        def self.Na__SwapEngine__FailureResult(reason)
            self.Na__SwapEngine__ReportStatus(reason)
            {
                'isSwapped'    => false,
                'swappedCount' => 0,
                'failedCount'  => 0,
                'failures'     => [],
                'bind'         => self.Na__SwapEngine__UnboundPayload(reason),
                'statusMessage'=> reason.to_s
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
