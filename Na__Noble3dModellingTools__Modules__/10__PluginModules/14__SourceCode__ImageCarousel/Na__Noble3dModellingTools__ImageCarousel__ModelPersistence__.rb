# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - MODEL PERSISTENCE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__ModelPersistence__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__ModelPersistence
# PURPOSE    : Remember the Image Viewer's last selected folder per model
# CREATED    : 30-Sep-2026
#
# DESIGN NOTES:
# - Same approach as the SketchUp Notepad plugin (na_notebook_dictionary): a
#   custom model attribute dictionary holding one serialised string, so the
#   folder travels inside the .skp and is restored the next time that model
#   is opened.
# - Per model only. Nothing is written to Sketchup defaults here, so a new or
#   different model has no dictionary and the user must choose a folder.
# - The state is serialised as a small versioned JSON string rather than a
#   bare path, so later fields (e.g. the last viewed image) can be added
#   without breaking models saved with this version.
# - Paths are stored with forward slashes, matching the FolderScanner output.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ImageCarousel__ModelPersistence

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DICTIONARY_NAME    = 'Na__Noble3dModellingTools__ImageCarousel'.freeze
        NA_KEY_FOLDER_STATE   = 'last_folder_state'.freeze
        NA_STATE_SCHEMA       = 1
        NA_OPERATION_NAME     = 'Image Viewer: Remember Folder'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # Write the chosen folder into the model's dictionary (one undo step).
        def self.Na__ImageCarousel__ModelPersistence__SaveFolder(model, folder_path)
            return false if model.nil? || folder_path.to_s.strip.empty?

            state_text = na_serialise_state(folder_path)
            return true if model.get_attribute(NA_DICTIONARY_NAME, NA_KEY_FOLDER_STATE) == state_text

            model.start_operation(NA_OPERATION_NAME, true)
            model.set_attribute(NA_DICTIONARY_NAME, NA_KEY_FOLDER_STATE, state_text)
            model.commit_operation
            true
        rescue => error
            model.abort_operation rescue nil
            puts "[Na__ImageCarousel] save folder to model failed: #{error.class}: #{error.message}"
            false
        end

        # The folder remembered by this model, or nil when it has none.
        def self.Na__ImageCarousel__ModelPersistence__LoadFolder(model)
            return nil if model.nil?

            dict = model.attribute_dictionary(NA_DICTIONARY_NAME)
            return nil if dict.nil?

            na_deserialise_state(dict[NA_KEY_FOLDER_STATE])
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Serialise / Deserialise
# -----------------------------------------------------------------------------

        def self.na_serialise_state(folder_path)
            JSON.generate(
                'schema' => NA_STATE_SCHEMA,
                'folder' => na_normalise_path(folder_path)
            )
        end

        # Returns the folder string, or nil for a missing or unreadable value.
        def self.na_deserialise_state(state_text)
            return nil unless state_text.is_a?(String) && !state_text.strip.empty?

            state = JSON.parse(state_text)
            folder = state.is_a?(Hash) ? state['folder'] : nil
            return nil unless folder.is_a?(String) && !folder.strip.empty?

            na_normalise_path(folder)
        rescue JSON::ParserError
            # Tolerate a hand-edited dictionary holding a bare path.
            na_normalise_path(state_text)
        end

        def self.na_normalise_path(folder_path)
            folder_path.to_s.strip.gsub('\\', '/')
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__ModelPersistence
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
