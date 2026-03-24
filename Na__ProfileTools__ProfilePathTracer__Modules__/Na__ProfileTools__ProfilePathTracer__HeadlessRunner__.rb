# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - HEADLESS RUNNER
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__HeadlessRunner__.rb
# PURPOSE    : Headless execution surface for ecosystem reuse
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__HeadlessRunner

    # -------------------------------------------------------------------------
    # REGION | Execution Mode Constants
    # -------------------------------------------------------------------------

        NA_HEADLESS_MODE_KEY = 'headless'.freeze

    # endregion ----------------------------------------------------------------

        def self.Na__Headless__Run(config_hash = {})
            profile_key = config_hash['profileKey']
            selected_entities = config_hash['pathEntities'] || []
            toggle_states = config_hash['toggleStates'] || {}

            result = Na__ProfilePlacementEngine.Na__Engine__BuildFromSelection(profile_key, selected_entities, toggle_states)
            result.merge('mode' => NA_HEADLESS_MODE_KEY)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Headless run failed.', error)
            { 'isBuilt' => false, 'mode' => NA_HEADLESS_MODE_KEY, 'error' => error.message }
        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
