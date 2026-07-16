# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EDGE COLOUR SWATCHES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppData__EdgeColourSwatches__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppData
# MODULE     : Na__EdgeColourSwatches
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the Edge Colours material-card swatch list from DataLib
#              EdgeMaterials SSOT and push it into the HtmlDialog.
#
# DATA SOURCE
# - meta.uiDefaults.AssemblyStudioEdgeColourSwatchKeys
# - meta.uiDefaults.AssemblyStudioEdgeColourSwatchLabels
# - meta.uiDefaults.AssemblyStudioEdgeColourPartDefaults
# - Per-entry HexValue / SwatchName from the edge materials library
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'

module Na__AssemblyStudio
    module Na__AppData
        module Na__EdgeColourSwatches

            DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
            UiBridge          = Na__AssemblyStudio::Na__AppCore::Na__UiBridge

            NA_SWATCH_KEYS_META   = 'AssemblyStudioEdgeColourSwatchKeys'.freeze
            NA_SWATCH_LABELS_META = 'AssemblyStudioEdgeColourSwatchLabels'.freeze
            NA_PART_DEFAULTS_META = 'AssemblyStudioEdgeColourPartDefaults'.freeze
            NA_DEFAULT_ID         = 'Default'.freeze
            NA_DEFAULT_HEX        = '#888888'.freeze

            NA_FALLBACK_SWATCH_KEYS = [
                'Default',
                'MTE102__LineColour__SoftBlack__L20',
                'MTE103__LineColour__DarkGrey__L40',
                'MTE103__LineColour__MediumDarkGrey__L50',
                'MTE104__LineColour__MidGrey__L60',
                'MTE107__LineColour__LightGrey__L85'
            ].freeze

            NA_FALLBACK_LABELS = {
                'Default' => 'Default',
                'MTE102__LineColour__SoftBlack__L20' => 'Soft Black',
                'MTE103__LineColour__DarkGrey__L40' => 'Dark Grey',
                'MTE103__LineColour__MediumDarkGrey__L50' => 'Medium Dark Grey',
                'MTE104__LineColour__MidGrey__L60' => 'Mid Grey',
                'MTE107__LineColour__LightGrey__L85' => 'Light Grey'
            }.freeze

            NA_FALLBACK_PART_DEFAULTS = {
                'frame' => 'MTE102__LineColour__SoftBlack__L20',
                'casement' => 'MTE103__LineColour__DarkGrey__L40',
                'glazebar' => 'MTE103__LineColour__DarkGrey__L40',
                'leaded' => 'MTE104__LineColour__MidGrey__L60',
                'fielded_panel' => 'MTE103__LineColour__DarkGrey__L40'
            }.freeze

            NA_TOAST_FAIL_MESSAGE = (
                'Na edge-colour library could not be loaded. ' \
                'Edge colour swatches may be incomplete - check internet connection.'
            ).freeze

            # FUNCTION | Build Swatch Array For UI
            # ------------------------------------------------------------
            def self.na_get_swatches
                EdgeColourManager.na_load_edge_colours_library if EdgeColourManager.na_meta.nil?

                keys = na_swatch_keys
                labels = na_swatch_labels
                keys.map { |id| na_build_swatch_record(id, labels) }.compact
            end

            # FUNCTION | Part Defaults Hash From Meta (Or Fallback)
            # ------------------------------------------------------------
            def self.na_part_defaults
                meta = EdgeColourManager.na_meta
                ui = meta.is_a?(Hash) ? meta['uiDefaults'] : nil
                if ui.is_a?(Hash) && ui[NA_PART_DEFAULTS_META].is_a?(Hash)
                    return ui[NA_PART_DEFAULTS_META].transform_keys(&:to_s).transform_values(&:to_s)
                end
                NA_FALLBACK_PART_DEFAULTS.dup
            end

            # FUNCTION | Push Swatches Into HtmlDialog
            # ------------------------------------------------------------
            def self.na_push_to_dialog(dialog)
                DebugTools.na_debug_ui('[EdgeColourSwatches] na_push_to_dialog called')
                return false unless dialog && dialog.respond_to?(:execute_script)

                EdgeColourManager.na_load_edge_colours_library if EdgeColourManager.na_meta.nil?

                swatches = na_get_swatches
                defaults = na_part_defaults
                status = EdgeColourManager.na_load_status == :failed ? 'failed' : 'ok'

                script = <<~JS
                    window.NA_EDGE_COLOUR_SWATCHES = #{JSON.generate(swatches)};
                    window.NA_EDGE_COLOUR_PART_DEFAULTS = #{JSON.generate(defaults)};
                    window.NA_EDGE_COLOURS_LOAD_STATUS = #{JSON.generate(status)};
                    if (window.Na_DynamicUI && typeof window.Na_DynamicUI.na_rebuild_edge_colour_controls === 'function') {
                        window.Na_DynamicUI.na_rebuild_edge_colour_controls();
                    }
                JS
                dialog.execute_script(script)
                DebugTools.na_debug_ui("[EdgeColourSwatches] pushed #{swatches.length} swatches (status=#{status})")

                if status == 'failed'
                    UiBridge.na_send_status(dialog, 'error', NA_TOAST_FAIL_MESSAGE, persistent: true)
                end
                true
            end

            def self.na_swatch_keys
                meta = EdgeColourManager.na_meta
                ui = meta.is_a?(Hash) ? meta['uiDefaults'] : nil
                if ui.is_a?(Hash) && ui[NA_SWATCH_KEYS_META].is_a?(Array) && !ui[NA_SWATCH_KEYS_META].empty?
                    return ui[NA_SWATCH_KEYS_META].map(&:to_s)
                end
                NA_FALLBACK_SWATCH_KEYS.dup
            end
            private_class_method :na_swatch_keys

            def self.na_swatch_labels
                meta = EdgeColourManager.na_meta
                ui = meta.is_a?(Hash) ? meta['uiDefaults'] : nil
                if ui.is_a?(Hash) && ui[NA_SWATCH_LABELS_META].is_a?(Hash)
                    return ui[NA_SWATCH_LABELS_META]
                end
                NA_FALLBACK_LABELS.dup
            end
            private_class_method :na_swatch_labels

            def self.na_build_swatch_record(id, labels)
                id = id.to_s
                if id == NA_DEFAULT_ID || id.empty?
                    return {
                        id: NA_DEFAULT_ID,
                        label: (labels[NA_DEFAULT_ID] || 'Default').to_s,
                        hex: NA_DEFAULT_HEX
                    }
                end

                entry = EdgeColourManager.na_library_entry(id)
                return nil unless entry.is_a?(Hash)

                hex = entry['HexValue']
                hex = NA_DEFAULT_HEX if hex.nil? || hex.to_s.empty?
                {
                    id: id,
                    label: (labels[id] || entry['SwatchName'] || entry['Description'] || id).to_s,
                    hex: hex.to_s
                }
            end
            private_class_method :na_build_swatch_record

        end
    end
end
