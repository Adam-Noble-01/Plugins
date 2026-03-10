# =============================================================================
# NA EDGE UTIL - PAINT DEEP NESTED EDGES - PALETTE MANAGER
# =============================================================================
#
# FILE       : Na__EdgeUtil__PaintDeepNestedEdges__PaletteManager__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__PaletteManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Manage dynamic quick-access colour palettes for the edge tool
# CREATED    : 2026
#
# DESCRIPTION:
# - Stores the 4 most recently used paint colours for quick re-use.
# - Persists dynamic palette slots using SketchUp default preferences.
# - Builds the quick-palette Html fragment used by the dialog UI.
# - Keeps palette storage and rendering concerns separate from tool logic.
#
# =============================================================================

require 'json'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Dynamic Palette State and Persistence
# -----------------------------------------------------------------------------

    module Na__PaletteManager

        # MODULE CONSTANTS | Preference Storage Keys
        # ------------------------------------------------------------
        NA_DYNAMIC_PALETTE_STORAGE_KEY = 'dynamic_palette_colour_keys'.freeze
        # ------------------------------------------------------------

        # HELPER FUNCTION | Load Persisted Dynamic Palette Keys
        # ---------------------------------------------------------------
        def self.na_load_palette_keys
            stored_palette_json = Sketchup.read_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_DYNAMIC_PALETTE_STORAGE_KEY,
                ''
            ).to_s

            parsed_palette_keys = stored_palette_json.empty? ? [] : JSON.parse(stored_palette_json)
            return na_sanitise_palette_keys(parsed_palette_keys)
        rescue
            return na_default_palette_keys
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Default Dynamic Palette Keys
        # ---------------------------------------------------------------
        def self.na_default_palette_keys
            Array.new(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dynamic_palette_slot_count,
                Na__EdgeUtil__PaintDeepNestedEdges.na_dynamic_palette_default_key
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Persist Dynamic Palette Keys
        # ---------------------------------------------------------------
        def self.na_save_palette_keys(palette_keys)
            Sketchup.write_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_DYNAMIC_PALETTE_STORAGE_KEY,
                JSON.generate(na_sanitise_palette_keys(palette_keys))
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Sanitise Palette Keys Against Known Colours
        # ---------------------------------------------------------------
        def self.na_sanitise_palette_keys(palette_keys)
            valid_colour_keys = Na__EdgeUtil__PaintDeepNestedEdges.na_colours.keys

            sanitised_palette_keys = Array(palette_keys)
                .map(&:to_s)
                .select { |colour_key| valid_colour_keys.include?(colour_key) }

            while sanitised_palette_keys.length < Na__EdgeUtil__PaintDeepNestedEdges.na_dynamic_palette_slot_count
                sanitised_palette_keys << Na__EdgeUtil__PaintDeepNestedEdges.na_dynamic_palette_default_key
            end

            return sanitised_palette_keys.first(Na__EdgeUtil__PaintDeepNestedEdges.na_dynamic_palette_slot_count)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remember Recently Applied Colour
        # ------------------------------------------------------------
        def self.na_remember_colour(colour_key)
            return if colour_key.to_s.empty?
            return if colour_key == Na__EdgeUtil__PaintDeepNestedEdges.na_default_colour_key

            palette_keys = na_load_palette_keys
            palette_keys.delete(colour_key)
            palette_keys.unshift(colour_key)

            na_save_palette_keys(palette_keys)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dynamic Palette Html Rendering
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Dynamic Palette Button Data
        # ---------------------------------------------------------------
        def self.na_palette_entries
            na_load_palette_keys.each_with_index.map do |colour_key, index|
                {
                    slot_index: index + 1,
                    colour_key: colour_key,
                    colour_hex: Na__EdgeUtil__PaintDeepNestedEdges.na_colour_hex_for_key(colour_key),
                    colour_title: Na__EdgeUtil__PaintDeepNestedEdges.na_escape_html(colour_key)
                }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Dynamic Palette Html
        # ------------------------------------------------------------
        def self.na_build_palette_html
            na_palette_entries.map do |palette_entry|
                <<~HTML_BUTTON.strip
                <button class="naQuickPaletteSwatch" title="#{palette_entry[:colour_title]}" onclick='sketchup.apply_palette_colour(#{palette_entry[:colour_key].to_json})'>
                    <span class="naQuickPaletteSwatch__Colour" style="background-color: #{palette_entry[:colour_hex]};"></span>
                    <span class="naQuickPaletteSwatch__Label">#{palette_entry[:slot_index]}</span>
                </button>
                HTML_BUTTON
            end.join
        end
        # ---------------------------------------------------------------

    end # module Na__PaletteManager

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
