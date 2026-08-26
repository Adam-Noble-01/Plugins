# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - REBUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Rebuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__Rebuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Recreate selected scenes from a decoded payload inside the model
#              that is currently open.
# CREATED    : 2026
#
# THIS IS THE MODEL A SIDE OF THE TOOL.
#
# HOW A SCENE IS BUILT, AND WHY IN THIS ORDER:
#
#   Pages#add(name, flags) does not merely record intent. At the moment of
#   creation it snapshots the CURRENT model and view state for every bit set in
#   flags, and switches those use_* slots ON. Slots whose bit is absent are
#   created OFF. That is exactly the behaviour this tool wants: passing only
#   PAGE_USE_CAMERA produces a scene that overrides the camera and nothing else
#   - no style, no shadows, no fog, no tag visibility.
#
#   The freshly added page therefore holds the CURRENT viewport camera, which is
#   then overwritten in place with the captured values. There is no
#   Page#camera= setter, so the live object returned by Page#camera is mutated
#   directly - the route the SketchUp 2026 documentation itself demonstrates.
#
# UNDO:
# Since SketchUp 2026.0, modifying a page's Camera, Axes, RenderingOptions or
# ShadowInfo is an undoable action. Every scene in a batch is therefore built
# inside ONE start_operation / commit_operation pair, so the whole import is a
# single undo step rather than several hundred.
#
# NAMING:
# Every rebuilt scene is suffixed, __IMPORTED by default, so imported scenes are
# obvious at a glance and can never collide with an existing scene of the same
# name. If the suffixed name is still taken, a two-digit counter is appended.
# SketchUp 2026 also auto-uniques names inside Pages#add, so the name that comes
# back is always re-read from the page rather than assumed.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__Rebuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'NA Import Scenes'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Rebuild API
# -----------------------------------------------------------------------------

        # FUNCTION | Rebuild the Chosen Scenes From a Decoded Payload
        # ------------------------------------------------------------
        # scene_names  - names as they appear in the SOURCE payload
        # domain_keys  - which aspects to reconstruct
        # name_suffix  - appended to every rebuilt scene name
        #
        # Returns { success, message, created, skipped, warnings, created_names }
        def self.Na__SceneDataTransfer__RebuildScenes(model, payload, scene_names, domain_keys, name_suffix = nil)
            return na_result(false, 'No active SketchUp model.')            unless model
            return na_result(false, 'No scene data has been read yet.')     unless payload.is_a?(Hash)

            schema  = Na__SceneDataTransfer__Schema
            domains = na_resolve_domains(domain_keys)
            return na_result(false, 'Tick at least one thing to import.') if domains.empty?

            requested = Array(scene_names).map(&:to_s)
            return na_result(false, 'Tick at least one scene to import.') if requested.empty?

            scene_records = na_select_scene_records(payload, requested)
            return na_result(false, 'None of the ticked scenes were found in the source data.') if scene_records.empty?

            suffix     = na_resolve_suffix(name_suffix)
            flag_mask  = schema.Na__SceneDataTransfer__FlagMaskForDomains(domains)
            return na_result(false, 'Could not resolve the SketchUp scene flags for those options.') if flag_mask.zero?

            na_run_rebuild(model, payload, scene_records, domains, suffix, flag_mask)
        rescue => error
            na_result(false, "Import failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild Execution
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Every Scene Inside a Single Undo Operation
        # ------------------------------------------------------------
        # Three phases, and the order is load-bearing:
        #
        #   A. PREPARE   - create model-wide things the scenes depend on. Tags
        #                  must exist before Page#set_visibility can name them,
        #                  and section planes must exist before a scene can
        #                  activate one. Geo and north angle are written here
        #                  too, because they are model-wide and writing them per
        #                  scene would rewrite the model once for every scene.
        #   B. SCENES    - create each page and apply its per-scene domains.
        #   C. RESTORE   - put back model state the section pass had to change.
        #
        # All three run inside ONE operation. Since SketchUp 2026.0, editing a
        # page's Camera, Axes, RenderingOptions or ShadowInfo is undoable, so a
        # naive import would push hundreds of entries onto the undo stack.
        def self.na_run_rebuild(model, payload, scene_records, domains, suffix, flag_mask)
            created_names = []
            warnings      = []
            skipped       = 0

            model.start_operation(NA_OPERATION_NAME, true)
            begin
                context = na_prepare_model(model, payload, domains, warnings)       # <-- Phase A

                scene_records.each do |scene_record|                                # <-- Phase B
                    outcome = na_build_single_scene(model, scene_record, domains, suffix, flag_mask, context)

                    if outcome['created']
                        created_names << outcome['name']
                    else
                        skipped += 1
                    end

                    warnings.concat(outcome['warnings'])
                end

                na_restore_model(model, context)                                    # <-- Phase C

                model.commit_operation
            rescue => error
                model.abort_operation
                return na_result(false, "Import failed and was rolled back: #{error.class}: #{error.message}")
            end

            na_result(
                created_names.any?,
                na_summary_message(created_names, skipped, warnings),
                'created'       => created_names.length,
                'skipped'       => skipped,
                'created_names' => created_names,
                'warnings'      => warnings.uniq
            )
        end
        private_class_method :na_run_rebuild
        # ------------------------------------------------------------

        # HELPER FUNCTION | Phase A - Create the Model-Wide Things Scenes Depend On
        # ------------------------------------------------------------
        # Returns a context hash carried through the per-scene pass. The section
        # plane lookup in it is what lets a scene activate the right plane
        # without re-searching the model for every scene.
        def self.na_prepare_model(model, payload, domains, warnings)
            model_level = payload['model_level'] || {}
            context     = {
                'section_lookup'         => {},
                'style_lookup'           => {},
                'restore_section_plane'  => nil,
                'section_state_touched'  => false
            }

            # Styles first. Creating one selects it and replays rendering options
            # onto the model, so it has to finish (and put the user's own style
            # selection back) before any page snapshots the model's state.
            if domains.include?('style') && model_level['styles']
                outcome = Na__SceneDataTransfer__StyleFactory.Na__SceneDataTransfer__EnsureModelStyles(model, model_level['styles'])
                context['style_lookup'] = outcome['lookup'] || {}
                warnings.concat(outcome['warnings'])
            end

            if domains.include?('tags') && model_level['tags']
                outcome = Na__SceneDataTransfer__TagDomain.Na__SceneDataTransfer__EnsureModelTags(model, model_level['tags'])
                warnings.concat(outcome['warnings'])
            end

            if domains.include?('sections') && model_level['sections']
                # Remember the model's own active plane before anything touches
                # it, so the user's working state survives the import.
                context['restore_section_plane'] = Na__SceneDataTransfer__SectionDomain
                                                   .Na__SceneDataTransfer__ReadActiveSectionPlane(model)
                context['section_state_touched'] = true

                outcome = Na__SceneDataTransfer__SectionDomain.Na__SceneDataTransfer__EnsureModelSections(model, model_level['sections'])
                context['section_lookup'] = outcome['lookup'] || {}
                warnings.concat(outcome['warnings'])
            end

            if domains.include?('shadows') && model_level['shadows']
                outcome = Na__SceneDataTransfer__ShadowDomain.Na__SceneDataTransfer__ApplyGeoToModel(model, model_level['shadows'])
                warnings.concat(outcome['warnings'])
            end

            context
        rescue => error
            warnings << "Model preparation warning: #{error.class}: #{error.message}"
            { 'section_lookup' => {}, 'style_lookup' => {}, 'restore_section_plane' => nil, 'section_state_touched' => false }
        end
        private_class_method :na_prepare_model
        # ------------------------------------------------------------

        # HELPER FUNCTION | Phase C - Put Back Model State the Import Had to Change
        # ------------------------------------------------------------
        # Baking a scene's active section plane requires setting it on the model
        # first, because there is no Page#active_section_plane=. This undoes that
        # side effect so the user's own view is not left cut open.
        def self.na_restore_model(model, context)
            return unless context['section_state_touched']

            Na__SceneDataTransfer__SectionDomain.Na__SceneDataTransfer__RestoreActiveSectionPlane(
                model, context['restore_section_plane']
            )
        rescue => error
            puts "[Na__SceneDataTransfer] Model restore warning: #{error.class}: #{error.message}"
        end
        private_class_method :na_restore_model
        # ------------------------------------------------------------

        # HELPER FUNCTION | Create One Page and Apply Every Requested Domain
        # ------------------------------------------------------------
        def self.na_build_single_scene(model, scene_record, domains, suffix, flag_mask, context)
            source_name = scene_record['name'].to_s
            target_name = na_resolve_scene_name(model, "#{source_name}#{suffix}")
            warnings    = []

            page = model.pages.add(target_name, flag_mask)                          # <-- Snapshots the live view for these bits only
            return na_scene_outcome(false, target_name, ["Could not create a scene for '#{source_name}'."]) unless page

            actual_name = page.name.to_s                                            # <-- SketchUp 2026 may have adjusted it
            warnings << "'#{source_name}' was imported as '#{actual_name}'." if actual_name != target_name

            page.description = scene_record['description'].to_s unless scene_record['description'].to_s.empty?

            domains.each do |domain_key|
                warnings.concat(na_apply_domain(page, scene_record, domain_key, source_name, context))
            end

            na_scene_outcome(true, actual_name, warnings)
        rescue => error
            na_scene_outcome(false, scene_record['name'].to_s, ["#{scene_record['name']}: #{error.message}"])
        end
        private_class_method :na_build_single_scene
        # ------------------------------------------------------------

        # HELPER FUNCTION | Dispatch One Domain to Its Serialiser
        # ------------------------------------------------------------
        # Every new domain gets one branch here plus its own serialiser file.
        def self.na_apply_domain(page, scene_record, domain_key, source_name, context)
            domain_data = (scene_record['domains'] || {})[domain_key]
            return ["#{source_name}: the source scene carries no #{domain_key} data."] if domain_data.nil?

            outcome = na_dispatch_domain(page, domain_key, domain_data, context)
            return ["#{source_name}: '#{domain_key}' is not implemented in this build."] if outcome.nil?

            na_prefix_warnings(source_name, outcome['warnings'])
        rescue => error
            ["#{source_name}: #{domain_key} failed - #{error.message}"]
        end
        private_class_method :na_apply_domain
        # ------------------------------------------------------------

        # HELPER FUNCTION | Route One Domain to Its Serialiser
        # ------------------------------------------------------------
        # Every new domain gets one branch here plus its own serialiser file.
        def self.na_dispatch_domain(page, domain_key, domain_data, context)
            case domain_key
            when 'camera'
                Na__SceneDataTransfer__CameraDomain.Na__SceneDataTransfer__ApplyCameraToPage(page, domain_data)

            when 'axes'
                Na__SceneDataTransfer__AxesDomain.Na__SceneDataTransfer__ApplyAxesToPage(page, domain_data)

            when 'style'
                Na__SceneDataTransfer__RenderingDomain.Na__SceneDataTransfer__ApplyStyleToPage(
                    page, domain_data, context['style_lookup']
                )

            when 'fog'
                Na__SceneDataTransfer__RenderingDomain.Na__SceneDataTransfer__ApplyFogToPage(page, domain_data)

            when 'shadows'
                Na__SceneDataTransfer__ShadowDomain.Na__SceneDataTransfer__ApplyShadowsToPage(page, domain_data)

            when 'sections'
                Na__SceneDataTransfer__SectionDomain.Na__SceneDataTransfer__ApplySectionsToPage(
                    page, domain_data, context['section_lookup']
                )

            when 'tags'
                Na__SceneDataTransfer__TagDomain.Na__SceneDataTransfer__ApplyTagsToPage(page, domain_data)

            when 'hidden_geometry'
                Na__SceneDataTransfer__HiddenGeometryDomain.Na__SceneDataTransfer__ApplyHiddenGeometryToPage(page, domain_data)

            else
                nil
            end
        end
        private_class_method :na_dispatch_domain
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Naming Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Produce a Scene Name That Is Free in This Model
        # ------------------------------------------------------------
        def self.na_resolve_scene_name(model, base_name)
            candidate = base_name.to_s.strip
            candidate = 'Imported Scene' if candidate.empty?

            return model.pages.unique_name(candidate) if model.pages.respond_to?(:unique_name)

            na_manual_unique_name(model, candidate)
        rescue
            na_manual_unique_name(model, base_name.to_s)
        end
        private_class_method :na_resolve_scene_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Append a Counter Until the Name Is Free
        # ------------------------------------------------------------
        # Used on releases before SketchUp 2026, where Pages#add did not make a
        # duplicate name unique and a collision silently broke pages['name'].
        def self.na_manual_unique_name(model, base_name)
            existing = model.pages.map { |page| page.name.to_s }
            return base_name unless existing.include?(base_name)

            (2..Na__SceneDataTransfer__Schema::NA_MAX_NAME_ATTEMPTS).each do |counter|
                candidate = format('%s__%02d', base_name, counter)
                return candidate unless existing.include?(candidate)
            end

            format('%s__%d', base_name, Time.now.to_i)                              # <-- Last resort, guaranteed unique
        end
        private_class_method :na_manual_unique_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Fall Back to the Default Suffix When None Is Supplied
        # ------------------------------------------------------------
        def self.na_resolve_suffix(name_suffix)
            candidate = name_suffix.to_s
            candidate.strip.empty? ? Na__SceneDataTransfer__Schema::NA_DEFAULT_IMPORT_SUFFIX : candidate
        end
        private_class_method :na_resolve_suffix
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection and Result Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Pick the Payload Records for the Ticked Scene Names
        # ------------------------------------------------------------
        # Source order is preserved so imported scene tabs land in the same
        # sequence they had in the source model.
        def self.na_select_scene_records(payload, requested_names)
            wanted = requested_names.each_with_object({}) { |name, lookup| lookup[name] = true }

            Array(payload['scenes']).select { |scene_record| wanted.key?(scene_record['name'].to_s) }
        end
        private_class_method :na_select_scene_records
        # ------------------------------------------------------------

        # HELPER FUNCTION | Filter Requested Domains Down to Implemented Ones
        # ------------------------------------------------------------
        def self.na_resolve_domains(domain_keys)
            schema      = Na__SceneDataTransfer__Schema
            implemented = schema.Na__SceneDataTransfer__ImplementedDomainKeys

            Array(domain_keys).map(&:to_s).select { |domain_key| implemented.include?(domain_key) }
        end
        private_class_method :na_resolve_domains
        # ------------------------------------------------------------

        # HELPER FUNCTION | Tag Each Warning With Its Source Scene Name
        # ------------------------------------------------------------
        def self.na_prefix_warnings(source_name, warnings)
            Array(warnings).map { |warning_text| "#{source_name}: #{warning_text}" }
        end
        private_class_method :na_prefix_warnings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Human Summary Line
        # ------------------------------------------------------------
        def self.na_summary_message(created_names, skipped, warnings)
            return 'No scenes were imported.' if created_names.empty?

            parts = ["Imported #{created_names.length} #{created_names.length == 1 ? 'scene' : 'scenes'}."]
            parts << "#{skipped} skipped."                if skipped > 0
            parts << "#{warnings.uniq.length} warnings."  if warnings.uniq.any?
            parts.join(' ')
        end
        private_class_method :na_summary_message
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Per-Scene Outcome Hash
        # ------------------------------------------------------------
        def self.na_scene_outcome(created_flag, scene_name, warnings)
            { 'created' => !!created_flag, 'name' => scene_name.to_s, 'warnings' => Array(warnings) }
        end
        private_class_method :na_scene_outcome
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { 'success' => !!success_flag, 'message' => message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__Rebuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
