# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - HEADLESS RUNNER
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__HeadlessRunner__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__HeadlessRunner
# PURPOSE    : Headless execution surface for ecosystem reuse
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

            result = Na__ProfilePlacementEngine.Na__Engine__BuildFromSelection(
                profile_key,
                selected_entities,
                toggle_states,
                rotation_step:     config_hash['rotationStep'].to_i % 4,
                reverse_direction: config_hash['reverseDirection'] == true,
                origin_offset:     self.Na__Headless__NormalizedOriginOffset(config_hash['originOffset'])
            )
            result.merge('mode' => NA_HEADLESS_MODE_KEY)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Headless run failed.', error)
            { 'isBuilt' => false, 'mode' => NA_HEADLESS_MODE_KEY, 'error' => error.message }
        end

        # Mirrors the dialog's contract: { 'y' => mm, 'z' => mm }, nil when the
        # caller wants the profile's own authored origin.
        def self.Na__Headless__NormalizedOriginOffset(origin_offset)
            return nil unless origin_offset.is_a?(Hash)
            y_mm = (origin_offset['y'] || origin_offset[:y]).to_f
            z_mm = (origin_offset['z'] || origin_offset[:z]).to_f
            return nil if y_mm.zero? && z_mm.zero?
            { 'y' => y_mm, 'z' => z_mm }
        rescue
            nil
        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
