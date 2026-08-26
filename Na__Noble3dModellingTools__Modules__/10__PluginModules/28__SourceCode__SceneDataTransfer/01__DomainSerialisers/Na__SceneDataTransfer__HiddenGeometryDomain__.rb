# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - HIDDEN GEOMETRY DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__HiddenGeometryDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__HiddenGeometryDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture and restore a scene's hidden-geometry and hidden-objects
#              display flags.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# WHAT THIS DOMAIN CAN AND CANNOT DO.
#   use_hidden_geometry? / use_hidden_objects? (SketchUp 2020.1+) and the legacy
#   combined use_hidden? are simply FLAGS: they record whether a scene saves the
#   Hidden Geometry and Hidden Objects display state at all. Those flags travel
#   perfectly.
#
#   The per-entity hidden state itself does NOT travel, and deliberately so. It
#   is addressed through Page#set_drawingelement_visibility(element, visible),
#   which needs a live Drawingelement in the TARGET model. Entity identity is
#   not portable across models - entityID is session-local and persistent_id,
#   while stable within one model, is meaningless in another. There is no
#   correct way to say "this specific edge was hidden" across a model boundary
#   unless the geometry itself was also transferred, which this tool does not do.
#
#   So: the scene will be set to honour hidden geometry, but WHICH geometry is
#   hidden comes from the target model's own state. The importer reports this
#   rather than letting it look like a silent failure.
#
# THE LEGACY FLAG.
#   use_hidden? predates the 2020.1 split into geometry and objects. It is
#   captured and restored when present so older source models round-trip, but
#   the two newer flags take precedence where the release supports them.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__HiddenGeometryDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DOMAIN_KEY = 'hidden_geometry'.freeze

        # Payload key => [reader method, writer method]. Read through respond_to?
        # because the newer pair does not exist before SketchUp 2020.1.
        NA_FLAG_METHODS = {
            'use_hidden'          => [:use_hidden?,          :use_hidden=],
            'use_hidden_geometry' => [:use_hidden_geometry?, :use_hidden_geometry=],
            'use_hidden_objects'  => [:use_hidden_objects?,  :use_hidden_objects=]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Capture the Hidden Geometry Flags From a Page
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureHiddenGeometry(page)
            return nil unless page

            captured = {}

            NA_FLAG_METHODS.each do |payload_key, (reader_method, _writer_method)|
                next unless page.respond_to?(reader_method)

                captured[payload_key] = !!page.send(reader_method)
            end

            captured.empty? ? nil : { 'flags' => captured }
        rescue => error
            puts "[Na__SceneDataTransfer] Hidden geometry capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Apply the Captured Hidden Geometry Flags Onto an Existing Page
        # ------------------------------------------------------------
        # The caller owns the undo operation. Returns { applied, warnings }.
        def self.Na__SceneDataTransfer__ApplyHiddenGeometryToPage(page, hidden_hash)
            return na_result(false, ['No page supplied.'])                unless page
            return na_result(false, ['No hidden geometry data supplied.']) unless hidden_hash.is_a?(Hash)

            flags = hidden_hash['flags']
            return na_result(false, ['Hidden geometry flags were missing from the payload.']) unless flags.is_a?(Hash)

            warnings   = []
            any_enabled = false

            NA_FLAG_METHODS.each do |payload_key, (_reader_method, writer_method)|
                next unless flags.key?(payload_key)
                next unless page.respond_to?(writer_method)

                begin
                    flag_value = flags[payload_key] == true
                    page.send(writer_method, flag_value)
                    any_enabled ||= flag_value
                rescue => error
                    warnings << "Flag '#{payload_key}' failed: #{error.class}: #{error.message}"
                end
            end

            if any_enabled
                warnings << 'Hidden geometry flags were restored, but WHICH geometry is hidden comes from ' \
                            'this model. Per-entity hidden state cannot be matched across two different models.'
            end

            na_result(true, warnings)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings) }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__HiddenGeometryDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
