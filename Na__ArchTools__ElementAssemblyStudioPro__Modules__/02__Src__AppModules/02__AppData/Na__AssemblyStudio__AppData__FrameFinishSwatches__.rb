# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - FRAME FINISH SWATCHES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppData__FrameFinishSwatches__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppData
# MODULE     : Na__FrameFinishSwatches
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the visible swatch list used by the door + window finish
#              card UIs, sourced exclusively from the live materials JSON.
#              Pushes the swatches into the HtmlDialog as window globals and
#              raises a persistent toast when the materials library could not
#              be loaded from the web.
#
# DATA SOURCE
# - Reads meta.uiDefaults.FrameFinishSwatchKeys from the loaded materials hash
#   (Na__DataLib__CoreIndex__Materials__.json).
# - All swatch hex values are derived from each material entry's BaseColor.
# - Returns an empty list when the materials library failed to load -- the
#   front-end then hides the card sections entirely (debug aid).
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AppData__MaterialManager__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'

module Na__AssemblyStudio
    module Na__AppData
        module Na__FrameFinishSwatches

            DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            MaterialManager = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
            UiBridge        = Na__AssemblyStudio::Na__AppCore::Na__UiBridge

            NA_META_UI_DEFAULTS_KEY        = "uiDefaults".freeze
            NA_META_SWATCH_KEYS            = "FrameFinishSwatchKeys".freeze
            NA_META_DEFAULT_KEY            = "DefaultFrameFinishKey".freeze
            NA_META_SWATCH_LABELS          = "FrameFinishSwatchLabels".freeze
            NA_FALLBACK_DEFAULT_KEY        = "MAT001__Default".freeze
            NA_FALLBACK_SWATCH_HEX         = "#FFFFFF".freeze

            NA_TOAST_FAIL_MESSAGE = (
                "Na materials library could not be loaded from the web. " \
                "Finish swatches are hidden - check internet connection."
            ).freeze

            # -----------------------------------------------------------------
            # REGION | Public API
            # -----------------------------------------------------------------

            # FUNCTION | Get Resolved Frame-Finish Swatches
            # ---------------------------------------------------------------
            # Returns an Array<Hash> of { id:, label:, hex: } records, one per
            # swatch declared in meta.uiDefaults.FrameFinishSwatchKeys. Returns
            # [] when the materials library is unavailable.
            # ---------------------------------------------------------------
            def self.na_get_swatches
                return [] unless na_library_ready?

                swatch_keys = na_swatch_keys_from_meta
                return [] if swatch_keys.empty?

                label_map = na_swatch_labels_from_meta
                swatch_keys.map { |id| na_build_swatch_record(id, label_map) }.compact
            end

            # FUNCTION | Get Default Frame-Finish Key
            # ---------------------------------------------------------------
            def self.na_default_key
                meta = MaterialManager.na_meta
                return NA_FALLBACK_DEFAULT_KEY unless meta.is_a?(Hash)
                ui_defaults = meta[NA_META_UI_DEFAULTS_KEY]
                return NA_FALLBACK_DEFAULT_KEY unless ui_defaults.is_a?(Hash)
                (ui_defaults[NA_META_DEFAULT_KEY] || NA_FALLBACK_DEFAULT_KEY).to_s
            end

            # FUNCTION | Push Swatches and Load Status into the HtmlDialog
            # ---------------------------------------------------------------
            # Sets three window globals on the dialog:
            #   window.NA_FRAME_FINISH_SWATCHES     - Array<{id,label,hex}>
            #   window.NA_FRAME_FINISH_DEFAULT_KEY  - String
            #   window.NA_MATERIALS_LOAD_STATUS     - 'ok' | 'failed'
            # Then calls window.Na_FrameFinishCards.na_render_all() if present
            # so both door and window card grids re-render with fresh data.
            # On failure also raises a persistent toast in #na-status-bar.
            # ---------------------------------------------------------------
            def self.na_push_to_dialog(dialog)
                return false unless dialog && dialog.respond_to?(:execute_script)

                swatches    = na_get_swatches
                default_key = na_default_key
                status      = na_status_for_js

                script = na_build_push_script(swatches, default_key, status)
                dialog.execute_script(script)

                if status == "failed"
                    UiBridge.na_send_status(dialog, "error", NA_TOAST_FAIL_MESSAGE, persistent: true)
                end

                DebugTools.na_debug_ui("FrameFinishSwatches: pushed #{swatches.length} swatches (status: #{status})")
                true
            end

            # -----------------------------------------------------------------
            # REGION | Internals - Library Lookup
            # -----------------------------------------------------------------

            def self.na_library_ready?
                MaterialManager.na_load_status != :failed && !MaterialManager.na_meta.nil?
            end

            def self.na_status_for_js
                MaterialManager.na_load_status == :failed ? "failed" : "ok"
            end

            def self.na_swatch_keys_from_meta
                meta = MaterialManager.na_meta
                return [] unless meta.is_a?(Hash)
                ui_defaults = meta[NA_META_UI_DEFAULTS_KEY]
                return [] unless ui_defaults.is_a?(Hash)
                Array(ui_defaults[NA_META_SWATCH_KEYS]).map(&:to_s)
            end

            def self.na_swatch_labels_from_meta
                meta = MaterialManager.na_meta
                return {} unless meta.is_a?(Hash)
                ui_defaults = meta[NA_META_UI_DEFAULTS_KEY]
                return {} unless ui_defaults.is_a?(Hash)
                labels = ui_defaults[NA_META_SWATCH_LABELS]
                labels.is_a?(Hash) ? labels : {}
            end

            # -----------------------------------------------------------------
            # REGION | Internals - Swatch Record Building
            # -----------------------------------------------------------------

            def self.na_build_swatch_record(material_id, label_map)
                material_props = na_lookup_material_props(material_id)
                return nil unless material_props.is_a?(Hash)

                {
                    id:    material_id,
                    label: na_resolve_label(material_id, material_props, label_map),
                    hex:   na_resolve_hex(material_props)
                }
            end

            def self.na_lookup_material_props(material_id)
                library = na_library_hash
                return nil unless library.is_a?(Hash)

                library.each do |_series_name, series_materials|
                    next unless series_materials.is_a?(Hash)
                    return series_materials[material_id] if series_materials.key?(material_id)
                end
                nil
            end

            def self.na_library_hash
                MaterialManager.instance_variable_get(:@na_materials_library)
            end

            def self.na_resolve_label(material_id, material_props, label_map)
                explicit_label = label_map[material_id]
                return explicit_label.to_s if explicit_label && !explicit_label.to_s.empty?

                description = material_props["Description"]
                return description.to_s if description && !description.to_s.empty?

                material_id.to_s
            end

            # -----------------------------------------------------------------
            # REGION | Internals - Colour Conversion
            # -----------------------------------------------------------------

            def self.na_resolve_hex(material_props)
                base_color = material_props["BaseColor"]
                return NA_FALLBACK_SWATCH_HEX if base_color.nil? || base_color.to_s.empty?
                na_rgb_string_to_hex(base_color.to_s) || NA_FALLBACK_SWATCH_HEX
            end

            def self.na_rgb_string_to_hex(rgb_string)
                match = rgb_string.match(/rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
                return nil unless match
                format("#%02X%02X%02X", match[1].to_i, match[2].to_i, match[3].to_i)
            end

            # -----------------------------------------------------------------
            # REGION | Internals - Push Script Builder
            # -----------------------------------------------------------------

            def self.na_build_push_script(swatches, default_key, status)
                <<~JS
                    window.NA_FRAME_FINISH_SWATCHES    = #{JSON.generate(swatches)};
                    window.NA_FRAME_FINISH_DEFAULT_KEY = #{JSON.generate(default_key)};
                    window.NA_MATERIALS_LOAD_STATUS    = #{JSON.generate(status)};
                    if (window.Na_FrameFinishCards && typeof window.Na_FrameFinishCards.na_render_all === 'function') {
                        window.Na_FrameFinishCards.na_render_all();
                    }
                JS
            end

        end
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
