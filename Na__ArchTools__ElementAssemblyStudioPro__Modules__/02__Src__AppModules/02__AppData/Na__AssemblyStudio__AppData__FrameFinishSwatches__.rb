# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - FRAME FINISH SWATCHES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppData__FrameFinishSwatches__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppData
# MODULE     : Na__FrameFinishSwatches
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the visible swatch lists used by the door + window finish
#              card UIs, sourced exclusively from the live materials JSON.
#              Pushes the swatches into the HtmlDialog as window globals and
#              raises a persistent toast when the materials library could not
#              be loaded from the web.
#
# PALETTES
# - :frame_finish  -> Window Frame Finish + Door Joinery Finish (wood / paint)
# - :handle_finish -> Door Handle Finish                       (metal ironmongery)
#
# DATA SOURCE
# - Reads meta.Na__DataLib__UiDefaults.<palette>.SwatchKeys
#                                            .DefaultSwatchKey
#                                            .SwatchLabels
#   from the loaded materials hash (Na__DataLib__CoreIndex__Materials__.json).
# - All swatch hex values are derived from each material entry's BaseColor.
# - Returns an empty list when the materials library failed to load -- the
#   front-end then hides the affected card section entirely (debug aid).
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

            # -----------------------------------------------------------------
            # REGION | Palette Configuration (Per-Palette Meta Keys + JS Globals)
            # -----------------------------------------------------------------

            NA_META_UI_DEFAULTS_KEY   = "Na__DataLib__UiDefaults".freeze

            # Each palette declares:
            #   :group_key       -> nested group inside Na__DataLib__UiDefaults
            #   :swatch_keys     -> array of MAT IDs to render as cards
            #   :default_key     -> the default swatch ID
            #   :labels_key      -> map of MAT ID -> human label
            #   :js_swatches     -> JS window global for the swatch array
            #   :js_default_key  -> JS window global for the default key
            NA_PALETTES = {
                :frame_finish => {
                    :group_key      => "Na__DataLib__UiDefaults__FrameFinish".freeze,
                    :swatch_keys    => "Na__DataLib__UiDefaults__FrameFinish__SwatchKeys".freeze,
                    :default_key    => "Na__DataLib__UiDefaults__FrameFinish__DefaultSwatchKey".freeze,
                    :labels_key     => "Na__DataLib__UiDefaults__FrameFinish__SwatchLabels".freeze,
                    :js_swatches    => "NA_FRAME_FINISH_SWATCHES".freeze,
                    :js_default_key => "NA_FRAME_FINISH_DEFAULT_KEY".freeze,
                    :fallback_key   => "MAT001__Default".freeze
                },
                :handle_finish => {
                    :group_key      => "Na__DataLib__UiDefaults__HandleFinish".freeze,
                    :swatch_keys    => "Na__DataLib__UiDefaults__HandleFinish__SwatchKeys".freeze,
                    :default_key    => "Na__DataLib__UiDefaults__HandleFinish__DefaultSwatchKey".freeze,
                    :labels_key     => "Na__DataLib__UiDefaults__HandleFinish__SwatchLabels".freeze,
                    :js_swatches    => "NA_HANDLE_FINISH_SWATCHES".freeze,
                    :js_default_key => "NA_HANDLE_FINISH_DEFAULT_KEY".freeze,
                    :fallback_key   => "MAT612__Metal__Ironmongery__Brass".freeze
                }
            }.freeze

            NA_FALLBACK_SWATCH_HEX = "#FFFFFF".freeze

            NA_TOAST_FAIL_MESSAGE = (
                "Na materials library could not be loaded from the web. " \
                "Finish swatches are hidden - check internet connection."
            ).freeze

            # -----------------------------------------------------------------
            # REGION | Public API
            # -----------------------------------------------------------------

            # FUNCTION | Get Resolved Swatches for a Palette
            # ---------------------------------------------------------------
            # Returns an Array<Hash> of { id:, label:, hex: } records, one per
            # swatch declared in the palette's SwatchKeys array. Returns []
            # when the materials library is unavailable or the palette has
            # no entries in meta.
            # ---------------------------------------------------------------
            def self.na_get_swatches(palette = :frame_finish)
                return [] unless na_library_ready?

                palette_config = NA_PALETTES[palette]
                return [] unless palette_config

                swatch_keys = na_swatch_keys_from_meta(palette_config)
                return [] if swatch_keys.empty?

                label_map = na_swatch_labels_from_meta(palette_config)
                swatch_keys.map { |id| na_build_swatch_record(id, label_map) }.compact
            end

            # FUNCTION | Get Default Swatch Key for a Palette
            # ---------------------------------------------------------------
            def self.na_default_key(palette = :frame_finish)
                palette_config = NA_PALETTES[palette]
                return nil unless palette_config

                meta = MaterialManager.na_meta
                fallback = palette_config[:fallback_key]
                return fallback unless meta.is_a?(Hash)

                ui_defaults = meta[NA_META_UI_DEFAULTS_KEY]
                return fallback unless ui_defaults.is_a?(Hash)

                group = ui_defaults[palette_config[:group_key]]
                return fallback unless group.is_a?(Hash)

                (group[palette_config[:default_key]] || fallback).to_s
            end

            # FUNCTION | Push Both Palettes + Load Status into the HtmlDialog
            # ---------------------------------------------------------------
            # Sets these window globals on the dialog:
            #   window.NA_FRAME_FINISH_SWATCHES      - Array<{id,label,hex}>
            #   window.NA_FRAME_FINISH_DEFAULT_KEY   - String
            #   window.NA_HANDLE_FINISH_SWATCHES     - Array<{id,label,hex}>
            #   window.NA_HANDLE_FINISH_DEFAULT_KEY  - String
            #   window.NA_MATERIALS_LOAD_STATUS      - 'ok' | 'failed'
            # Then calls window.Na_FrameFinishCards.na_render_all() if present
            # so both door card grids + the window's Frame Finish row repaint.
            # On failure also raises a persistent toast in #na-status-bar.
            # ---------------------------------------------------------------
            def self.na_push_to_dialog(dialog)
                return false unless dialog && dialog.respond_to?(:execute_script)

                frame_swatches  = na_get_swatches(:frame_finish)
                handle_swatches = na_get_swatches(:handle_finish)
                frame_default   = na_default_key(:frame_finish)
                handle_default  = na_default_key(:handle_finish)
                status          = na_status_for_js

                script = na_build_push_script(
                    frame_swatches, frame_default,
                    handle_swatches, handle_default,
                    status
                )
                dialog.execute_script(script)

                if status == "failed"
                    UiBridge.na_send_status(dialog, "error", NA_TOAST_FAIL_MESSAGE, persistent: true)
                end

                DebugTools.na_debug_ui(
                    "FrameFinishSwatches: pushed " \
                    "frame=#{frame_swatches.length} handle=#{handle_swatches.length} " \
                    "(status: #{status})"
                )
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

            def self.na_swatch_keys_from_meta(palette_config)
                group = na_palette_group(palette_config)
                return [] unless group.is_a?(Hash)
                Array(group[palette_config[:swatch_keys]]).map(&:to_s)
            end

            def self.na_swatch_labels_from_meta(palette_config)
                group = na_palette_group(palette_config)
                return {} unless group.is_a?(Hash)
                labels = group[palette_config[:labels_key]]
                labels.is_a?(Hash) ? labels : {}
            end

            def self.na_palette_group(palette_config)
                meta = MaterialManager.na_meta
                return nil unless meta.is_a?(Hash)
                ui_defaults = meta[NA_META_UI_DEFAULTS_KEY]
                return nil unless ui_defaults.is_a?(Hash)
                ui_defaults[palette_config[:group_key]]
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

            def self.na_build_push_script(frame_swatches, frame_default,
                                          handle_swatches, handle_default,
                                          status)
                <<~JS
                    window.NA_FRAME_FINISH_SWATCHES     = #{JSON.generate(frame_swatches)};
                    window.NA_FRAME_FINISH_DEFAULT_KEY  = #{JSON.generate(frame_default)};
                    window.NA_HANDLE_FINISH_SWATCHES    = #{JSON.generate(handle_swatches)};
                    window.NA_HANDLE_FINISH_DEFAULT_KEY = #{JSON.generate(handle_default)};
                    window.NA_MATERIALS_LOAD_STATUS     = #{JSON.generate(status)};
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
