# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC TAG VISIBILITY CAPTURE
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__TagVisibilityCapture__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__TagVisibilityCapture
# PURPOSE    : Capture per-scene SketchUp tag (layer) visibility for the
#              toggle-relevant categories, keyed to match ValeVision3D's
#              model-toggle category keys, so TrueVision3D can show/hide the
#              same "Model Parts List" groups automatically per tour scene.
# CREATED    : 01-Jul-2026
#
# DESCRIPTION:
# - Reads the shared Tags SSOT JSON (Na__DataLib__CoreIndex__Tags__.json,
#   the same file TrueVision3D::GlbBuilderUtility uses to segment GLB
#   exports) and flattens it into { Tag__SketchUpName => Glb__ExportFileNameStem }.
#   Only tags with a non-null Glb__ExportFileNameStem produce their own GLB
#   file, so only those are toggle-relevant — everything else is ignored.
# - For a given Sketchup::Page (scene), determines the true visibility of
#   every relevant tag on that page WITHOUT switching to it, using the
#   confirmed page/layer override algorithm (see DEVELOPMENT LOG).
# - Groups tags by their GLB export stem (stripped of the "TrueVision__"
#   namespace and re-prefixed "ValeVision__") into a flat hash that matches
#   ValeVision3D's Na__ModelToggle__StateMap category keys 1:1, e.g.:
#     { "ValeVision__MainBuildingModel__Existing" => true,
#       "ValeVision__SiteBoundaries"              => false,
#       "ValeVision__LandscapeEnvironment"        => true }
# - If more than one tag ever shares the same export stem, categories are
#   OR-combined (visible if ANY constituent tag is visible on that page).
# - Fails soft: any missing/invalid DataLib JSON yields an empty hash rather
#   than aborting camera capture for the scene.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 01-Jul-2026 - Version 1.0.0
# - Initial implementation.
# - Page-visibility algorithm confirmed against the official SketchUp Ruby
#   API docs (Sketchup::Page#layers, Sketchup::Layer#page_behavior) and the
#   SketchUp/api-issue-tracker GitHub issues #382 and #673, which correct the
#   misleading official docs for Page#layers ("layers that don't use their
#   default visibility on this page", NOT "hidden layers"):
#     hidden_by_default = (layer.page_behavior & LAYER_HIDDEN_BY_DEFAULT) != 0
#     visible_on_page   = page.layers.include?(layer) == hidden_by_default
#
# =============================================================================

require 'json'

module Na__ValeVisionCloudSync
    module Na__TagVisibilityCapture

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        VALEVISION_KEY_PREFIX  = 'ValeVision__'.freeze     # <-- Matches Na__ModelToggle__StateMap category key namespace
        TRUEVISION_STEM_PREFIX = /\ATrueVision__/.freeze   # <-- Stripped from Glb__ExportFileNameStem before re-prefixing

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Toggle-Relevant Tag Visibility For One Scene
        # ------------------------------------------------------------
        # page {Sketchup::Page} - the IMG## scene being captured
        # Returns { "ValeVision__<Category>" => true/false, ... }
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__CaptureTagVisibilityForScene(page)
            return {} unless page && page.model

            stem_by_tag_name = na_tag_to_glb_stem_map
            return {} if stem_by_tag_name.empty?

            use_hidden_layers      = page.use_hidden_layers?
            visibility_by_category = {}

            page.model.layers.each do |layer|
                stem = stem_by_tag_name[layer.name.to_s]
                next unless stem                                            # <-- Not a toggle-relevant tag; skip

                category_key = na_category_key_from_stem(stem)
                visible      = na_layer_visible_on_page?(layer, page, use_hidden_layers)

                visibility_by_category[category_key] = visibility_by_category.fetch(category_key, false) || visible
            end

            visibility_by_category
        rescue => error
            puts "[Na__ValeVisionCloudSync] Tag visibility capture error on #{page&.name}: #{error.message}"
            {}
        end

        # FUNCTION | Invalidate The Cached Tags SSOT Map
        # ------------------------------------------------------------
        # Call after editing the DataLib JSON during development/testing.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__InvalidateTagsCache
            @na_cached_stem_map = nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Page / Layer Visibility Algorithm
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Determine True Visibility Of A Layer On A Page
        # ---------------------------------------------------------------
        # Does NOT switch the active page. Falls back to the layer's live
        # global visibility when the page does not store per-page layer
        # state at all (use_hidden_layers? false — "Visible Layers" scene
        # property unticked).
        # ---------------------------------------------------------------
        def self.na_layer_visible_on_page?(layer, page, use_hidden_layers)
            return layer.visible? unless use_hidden_layers

            hidden_by_default = (layer.page_behavior & LAYER_HIDDEN_BY_DEFAULT) == LAYER_HIDDEN_BY_DEFAULT
            page.layers.include?(layer) == hidden_by_default                # <-- XOR: override list means "flip from default"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tags SSOT Loading
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert A Glb Export Stem Into A ValeVision Category Key
        # ---------------------------------------------------------------
        def self.na_category_key_from_stem(stem)
            VALEVISION_KEY_PREFIX + stem.to_s.sub(TRUEVISION_STEM_PREFIX, '')
        end

        # HELPER FUNCTION | Load + Cache The Tag Name -> Glb Export File Name Stem Map
        # ---------------------------------------------------------------
        def self.na_tag_to_glb_stem_map
            return @na_cached_stem_map if @na_cached_stem_map

            json_path = Na__PathResolver.Na__ValeVisionCloudSync__TagsDataLibFilePath
            unless File.exist?(json_path)
                puts "[Na__ValeVisionCloudSync] Tags DataLib JSON not found at: #{json_path}"
                return @na_cached_stem_map = {}
            end

            data = JSON.parse(File.read(json_path, encoding: 'utf-8'))
            @na_cached_stem_map = na_flatten_tags_index(data['Na__DataLib__CoreIndex__Tags'] || {})
        rescue => error
            puts "[Na__ValeVisionCloudSync] Tags DataLib load error: #{error.class}: #{error.message}"
            @na_cached_stem_map = {}
        end

        # HELPER FUNCTION | Flatten The Nested Tags Index Into A Flat Stem Map
        # ---------------------------------------------------------------
        def self.na_flatten_tags_index(tags_index)
            flat = {}

            tags_index.each_value do |category_group|
                next unless category_group.is_a?(Hash)

                category_group.each_value do |tag_entry|
                    next unless tag_entry.is_a?(Hash)

                    tag_name = tag_entry['Tag__SketchUpName']
                    stem     = tag_entry['Glb__ExportFileNameStem']
                    flat[tag_name] = stem if tag_name && stem              # <-- Only toggle-relevant tags (own GLB file)
                end
            end

            flat
        end

# endregion -------------------------------------------------------------------

    end # module Na__TagVisibilityCapture
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
