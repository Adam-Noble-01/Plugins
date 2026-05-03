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

            NA_META_UI_DEFAULTS_KEY        = "Na__DataLib__UiDefaults".freeze
            NA_META_UI_DEFAULTS_LEGACY_KEY = "uiDefaults".freeze              # <-- Pre-v1.0.8 flat-keys block

            # Each palette declares:
            #   :group_key             -> NEW nested group inside Na__DataLib__UiDefaults
            #   :swatch_keys           -> NEW array key inside the nested group
            #   :default_key           -> NEW default swatch key inside the nested group
            #   :labels_key            -> NEW labels map key inside the nested group
            #   :legacy_swatch_keys    -> OLD flat key under meta.uiDefaults (frame palette only)
            #   :legacy_default_key    -> OLD flat default key
            #   :legacy_labels_key     -> OLD flat labels map key
            #   :js_swatches           -> JS window global for the swatch array
            #   :js_default_key        -> JS window global for the default key
            NA_PALETTES = {
                :frame_finish => {
                    :group_key             => "Na__DataLib__UiDefaults__FrameFinish".freeze,
                    :swatch_keys           => "Na__DataLib__UiDefaults__FrameFinish__SwatchKeys".freeze,
                    :default_key           => "Na__DataLib__UiDefaults__FrameFinish__DefaultSwatchKey".freeze,
                    :labels_key            => "Na__DataLib__UiDefaults__FrameFinish__SwatchLabels".freeze,
                    :legacy_swatch_keys    => "FrameFinishSwatchKeys".freeze,
                    :legacy_default_key    => "DefaultFrameFinishKey".freeze,
                    :legacy_labels_key     => "FrameFinishSwatchLabels".freeze,
                    :js_swatches           => "NA_FRAME_FINISH_SWATCHES".freeze,
                    :js_default_key        => "NA_FRAME_FINISH_DEFAULT_KEY".freeze,
                    :fallback_key          => "MAT001__Default".freeze
                },
                :handle_finish => {
                    :group_key             => "Na__DataLib__UiDefaults__HandleFinish".freeze,
                    :swatch_keys           => "Na__DataLib__UiDefaults__HandleFinish__SwatchKeys".freeze,
                    :default_key           => "Na__DataLib__UiDefaults__HandleFinish__DefaultSwatchKey".freeze,
                    :labels_key            => "Na__DataLib__UiDefaults__HandleFinish__SwatchLabels".freeze,
                    :legacy_swatch_keys    => nil,                            # <-- No legacy form (handle palette is v1.0.8+)
                    :legacy_default_key    => nil,
                    :legacy_labels_key     => nil,
                    :js_swatches           => "NA_HANDLE_FINISH_SWATCHES".freeze,
                    :js_default_key        => "NA_HANDLE_FINISH_DEFAULT_KEY".freeze,
                    :fallback_key          => "MAT615__Metal__Ironmongery__Chrome".freeze
                }
            }.freeze

            NA_FALLBACK_SWATCH_HEX = "#FFFFFF".freeze
            NA_HANDLE_DEFAULT_SWATCH_ID = "MAT001__Default".freeze

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
                swatches = swatch_keys.map { |id| na_build_swatch_record(id, label_map) }.compact
                na_ensure_handle_default_card_first(swatches, label_map, palette)
            end

            # FUNCTION | Get Default Swatch Key for a Palette
            # ---------------------------------------------------------------
            def self.na_default_key(palette = :frame_finish)
                palette_config = NA_PALETTES[palette]
                return nil unless palette_config

                fallback = palette_config[:fallback_key]
                meta     = MaterialManager.na_meta
                return fallback unless meta.is_a?(Hash)

                # Try NEW nested structure first
                group = na_palette_group_new(palette_config, meta)
                if group.is_a?(Hash) && group[palette_config[:default_key]]
                    return group[palette_config[:default_key]].to_s
                end

                # Fall back to LEGACY flat structure (frame palette only)
                legacy = na_legacy_uidefaults(meta)
                legacy_key = palette_config[:legacy_default_key]
                if legacy.is_a?(Hash) && legacy_key && legacy[legacy_key]
                    return legacy[legacy_key].to_s
                end

                fallback
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
                puts "    [FrameFinishSwatches] na_push_to_dialog called"
                unless dialog && dialog.respond_to?(:execute_script)
                    puts "    [FrameFinishSwatches] ERROR: dialog not pushable (nil or no execute_script)"
                    return false
                end

                meta_present = !MaterialManager.na_meta.nil?
                load_status  = MaterialManager.na_load_status
                puts "    [FrameFinishSwatches] meta_present=#{meta_present} load_status=#{load_status.inspect}"

                frame_swatches  = na_get_swatches(:frame_finish)
                handle_swatches = na_get_swatches(:handle_finish)
                frame_default   = na_default_key(:frame_finish)
                handle_default  = na_default_key(:handle_finish)
                status          = na_status_for_js

                puts "    [FrameFinishSwatches] frame=#{frame_swatches.length} (default=#{frame_default}), handle=#{handle_swatches.length} (default=#{handle_default}), status=#{status}"

                script = na_build_push_script(
                    frame_swatches, frame_default,
                    handle_swatches, handle_default,
                    status
                )
                dialog.execute_script(script)
                puts "    [FrameFinishSwatches] execute_script delivered (#{script.length} chars)"

                if status == "failed"
                    UiBridge.na_send_status(dialog, "error", NA_TOAST_FAIL_MESSAGE, persistent: true)
                end

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
                meta = MaterialManager.na_meta
                return [] unless meta.is_a?(Hash)

                # NEW nested structure
                group = na_palette_group_new(palette_config, meta)
                if group.is_a?(Hash)
                    keys = group[palette_config[:swatch_keys]]
                    return Array(keys).map(&:to_s) if keys
                end

                # LEGACY flat structure (frame palette only)
                legacy     = na_legacy_uidefaults(meta)
                legacy_key = palette_config[:legacy_swatch_keys]
                if legacy.is_a?(Hash) && legacy_key && legacy[legacy_key]
                    return Array(legacy[legacy_key]).map(&:to_s)
                end

                []
            end

            def self.na_swatch_labels_from_meta(palette_config)
                meta = MaterialManager.na_meta
                return {} unless meta.is_a?(Hash)

                # NEW nested structure
                group = na_palette_group_new(palette_config, meta)
                if group.is_a?(Hash)
                    labels = group[palette_config[:labels_key]]
                    return labels if labels.is_a?(Hash)
                end

                # LEGACY flat structure (frame palette only)
                legacy     = na_legacy_uidefaults(meta)
                legacy_key = palette_config[:legacy_labels_key]
                if legacy.is_a?(Hash) && legacy_key && legacy[legacy_key].is_a?(Hash)
                    return legacy[legacy_key]
                end

                {}
            end

            # Resolve the per-palette group object from the NEW nested
            # meta.Na__DataLib__UiDefaults.<palette_group> structure.
            # Returns nil if the new structure is absent.
            def self.na_palette_group_new(palette_config, meta)
                ui_defaults = meta[NA_META_UI_DEFAULTS_KEY]
                return nil unless ui_defaults.is_a?(Hash)
                ui_defaults[palette_config[:group_key]]
            end

            # Resolve the LEGACY pre-v1.0.8 meta.uiDefaults flat-keys block.
            # Returns nil if the legacy block is absent.
            def self.na_legacy_uidefaults(meta)
                meta[NA_META_UI_DEFAULTS_LEGACY_KEY]
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

            # Ensure the handle finish row always includes MAT001__Default as the
            # first card, independent of remote meta ordering or omissions.
            def self.na_ensure_handle_default_card_first(swatches, label_map, palette)
                return swatches unless palette == :handle_finish
                return swatches unless swatches.is_a?(Array)

                default_index = swatches.find_index { |row| row.is_a?(Hash) && row[:id].to_s == NA_HANDLE_DEFAULT_SWATCH_ID }
                if default_index
                    default_row = swatches[default_index]
                    default_row[:label] = "Default"
                    remaining_rows = swatches.each_with_index.filter_map { |row, idx| row unless idx == default_index }
                    return [default_row] + remaining_rows
                end

                default_row = na_build_swatch_record(NA_HANDLE_DEFAULT_SWATCH_ID, label_map || {})
                return swatches unless default_row.is_a?(Hash)

                default_row[:label] = "Default"
                [default_row] + swatches
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
