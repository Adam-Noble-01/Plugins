# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - EXPORT SELECTION
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__ExportSelection__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Remember which GLB files a model exports, in the model itself
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Per-file export toggles, persisted in the model's attribute dictionary so a
#   model keeps its choices between sessions. One model can leave furniture off
#   permanently while another exports everything.
#
# - The store holds the DESELECTED file names, never the selected ones. That is
#   deliberate: a file the model has never seen - a new tag, a new storey, a
#   renamed element - is absent from the store and therefore ON. Everything
#   defaults to exporting, which is the behaviour the plugin has always had.
#
# DICTIONARY:
#   Name : Na__TrueVision__GlbBuilder__ExportSelection
#   Key  : deselected  -> JSON array of output file names
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.10.0
# - Initial per-file export selection.
#
# =============================================================================

require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Dictionary Constants
    # -----------------------------------------------------------------------------

        unless defined?(NA_EXPORT_SELECTION_DICT)
            NA_EXPORT_SELECTION_DICT = 'Na__TrueVision__GlbBuilder__ExportSelection'.freeze
            NA_EXPORT_SELECTION_KEY  = 'deselected'.freeze
        end

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Read
    # -----------------------------------------------------------------------------

        # FUNCTION | Read The Set Of Deselected Output File Names
        # ---------------------------------------------------------------
        # Always answers a Hash used as a set, so lookups stay O(1) inside the
        # export loop.
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__DeselectedSet(model = Sketchup.active_model)
            return {} unless model

            dict = model.attribute_dictionary(NA_EXPORT_SELECTION_DICT, false)
            return {} unless dict

            raw = dict[NA_EXPORT_SELECTION_KEY]
            return {} if raw.nil? || raw.to_s.empty?

            names = raw.is_a?(Array) ? raw : JSON.parse(raw.to_s)
            names.each_with_object({}) { |name, set| set[name.to_s] = true }
        rescue => e
            Na__Log__Warn "[ExportSelection] Could not read the export selection: #{e.message}"
            {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | Report Whether One Output File Is Selected For Export
        # ---------------------------------------------------------------
        # Unknown file names are selected. See the note at the top of the file.
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__Selected?(file_name, deselected_set = nil)
            set = deselected_set || self.Na__ExportSelection__DeselectedSet
            !set[file_name.to_s]
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Write
    # -----------------------------------------------------------------------------

        # FUNCTION | Set One File's Selection State
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__SetSelected(model, file_name, selected)
            self.Na__ExportSelection__SetManySelected(model, [file_name], selected)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set Several Files' Selection State At Once
        # ---------------------------------------------------------------
        # Used by the group headers and by Enable All / Disable All.
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__SetManySelected(model, file_names, selected)
            return { success: false, message: 'No active model.' } unless model

            set = self.Na__ExportSelection__DeselectedSet(model)

            Array(file_names).each do |name|
                key = name.to_s
                next if key.empty?

                if selected
                    set.delete(key)
                else
                    set[key] = true
                end
            end

            self.Na__ExportSelection__Persist(model, set)
            { success: true, message: 'Export selection saved.', deselected_count: set.length }
        rescue => e
            Na__Log__Warn "[ExportSelection] Could not save the export selection: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Select Every File Again
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__SelectAll(model)
            return { success: false, message: 'No active model.' } unless model

            self.Na__ExportSelection__Persist(model, {})
            { success: true, message: 'Every file is selected for export.', deselected_count: 0 }
        rescue => e
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Write The Set Back To The Model
        # ---------------------------------------------------------------
        # Stored as a JSON string: an attribute dictionary will take an Array,
        # but a JSON string round-trips predictably across SketchUp versions.
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__Persist(model, deselected_set)
            dict = model.attribute_dictionary(NA_EXPORT_SELECTION_DICT, true)
            dict[NA_EXPORT_SELECTION_KEY] = deselected_set.keys.sort.to_json
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop Remembered Names That The Model No Longer Produces
        # ---------------------------------------------------------------
        # Keeps the store from growing forever as tags are renamed. Called with
        # the manifest's current file names whenever the dialog rescans.
        # ---------------------------------------------------------------
        def self.Na__ExportSelection__PruneToKnown(model, known_file_names)
            return unless model

            set   = self.Na__ExportSelection__DeselectedSet(model)
            return if set.empty?

            known = Array(known_file_names).each_with_object({}) { |name, hash| hash[name.to_s] = true }
            pruned = set.keys.select { |name| known[name] }
            return if pruned.length == set.length                        # <-- Nothing stale

            self.Na__ExportSelection__Persist(model, pruned.each_with_object({}) { |n, h| h[n] = true })
        rescue => e
            Na__Log__Warn "[ExportSelection] Could not prune the export selection: #{e.message}"
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
