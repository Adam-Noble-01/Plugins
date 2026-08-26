# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - RENDERING DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__RenderingDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__RenderingDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture and rebuild Sketchup::RenderingOptions, split into the
#              style domain and the fog domain.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# RenderingOptions is a FIXED-SCHEMA hash-like collection of roughly 69 String
# keys. You cannot add or delete keys, only read and write through #[] and #[]=.
# Values come back as exactly four Ruby classes: TrueClass/FalseClass, Integer,
# Float and Sketchup::Color.
#
# THE KEY SET IS NOT CONSTANT ACROSS VERSIONS, SO IT IS NEVER HARD-CODED.
#   AmbientOcclusion* keys are 2024+/2026+, FaceColorMode was REMOVED in 2019.1,
#   and DrawHiddenGeometry / DrawHiddenObjects are 2020+. This module always
#   enumerates the LIVE keys at runtime and intersects source against target,
#   so a key the target does not know about is skipped instead of raising.
#
# "STYLE AND FOG" IS ONE SKETCHUP FLAG.
#   In the Scene Manager the checkbox is literally labelled "Style and Fog", and
#   it maps to Page#use_rendering_options. SketchUp cannot separate them, so
#   ticking EITHER the style domain or the fog domain enables that one property.
#   The two domains simply write different subsets of the same key set:
#     fog domain   -> the five fog keys only
#     style domain -> every other key
#   Splitting them this way is what lets you pull a scene's fog across without
#   dragging its whole visual style with it, and vice versa.
#
# THE STYLE OBJECT ITSELF CARRIES ALMOST NOTHING.
#   Sketchup::Style has six methods: name, name=, description, description=,
#   path (2025+) and duplicate (2026.2+). There is NO Style#save_as - no Ruby
#   method writes a .style file, so a style can be imported from disk but never
#   exported. The real settings live here in RenderingOptions, which is why
#   replaying these keys IS the style transfer.
#
# NOT REACHABLE FROM RUBY, AND THEREFORE NOT TRANSFERABLE:
#   watermarks, sketchy-edge stroke sets, background images and photo-match
#   overlays. Only the DisplayWatermarks on/off flag and the EdgeType
#   standard-versus-sketchy switch cross the boundary.
#
# STRICT SETTERS:
#   From SketchUp 2024.0, RenderingOptions#[]= raises ArgumentError on a value
#   it will not accept. Every write is therefore individually rescued and
#   reported rather than being allowed to abort the whole import.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__RenderingDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_STYLE_DOMAIN_KEY = 'style'.freeze
        NA_FOG_DOMAIN_KEY   = 'fog'.freeze

        # The five keys the SketchUp docs call out as safe to change from a
        # scene, because they are NOT governed by the selected style.
        NA_FOG_KEYS = %w[
            DisplayFog
            FogColor
            FogUseBkColor
            FogStartDist
            FogEndDist
        ].freeze

        # Keys that describe the section CUT appearance. They live in
        # RenderingOptions rather than with the section planes, so they are
        # recorded here and noted for the section domain.
        NA_SECTION_DISPLAY_KEYS = %w[
            DisplaySectionPlanes
            DisplaySectionCuts
            SectionCutWidth
            SectionCutFilled
            SectionCutDrawEdges
            SectionDefaultCutColor
            SectionDefaultFillColor
            SectionActiveColor
            SectionInactiveColor
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Capture the Non-Fog Rendering Options Plus the Style Identity
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureStyle(page)
            return nil unless page

            options = na_capture_options(page.rendering_options) { |key| !NA_FOG_KEYS.include?(key) }
            return nil if options.nil?

            {
                'style_name'        => na_style_name(page),
                'style_description' => na_style_description(page),
                'options'           => options
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Style capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Capture Only the Fog Rendering Options
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureFog(page)
            return nil unless page

            options = na_capture_options(page.rendering_options) { |key| NA_FOG_KEYS.include?(key) }
            return nil if options.nil? || options.empty?

            { 'options' => options }
        rescue => error
            puts "[Na__SceneDataTransfer] Fog capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Encode Every Live Key That Passes the Filter Block
        # ------------------------------------------------------------
        def self.na_capture_options(rendering_options)
            return nil unless rendering_options

            codec    = Na__SceneDataTransfer__ValueCodec
            captured = {}

            na_option_keys(rendering_options).each do |option_key|
                next unless yield(option_key)

                begin
                    captured[option_key] = codec.Na__SceneDataTransfer__Encode(rendering_options[option_key])
                rescue => error
                    puts "[Na__SceneDataTransfer] Skipped rendering key '#{option_key}': #{error.message}"
                end
            end

            captured
        end
        private_class_method :na_capture_options
        # ------------------------------------------------------------

        # HELPER FUNCTION | Enumerate the Live Key Names of a RenderingOptions
        # ------------------------------------------------------------
        # #keys is the documented accessor, but #each_key is used as a fallback
        # so the module keeps working on any release that lacks it.
        def self.na_option_keys(rendering_options)
            return rendering_options.keys.map(&:to_s) if rendering_options.respond_to?(:keys)

            collected = []
            rendering_options.each_key { |option_key| collected << option_key.to_s }
            collected
        rescue => error
            puts "[Na__SceneDataTransfer] Rendering key enumeration warning: #{error.message}"
            []
        end
        private_class_method :na_option_keys
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Bound Style Name Defensively
        # ------------------------------------------------------------
        def self.na_style_name(page)
            style = page.style
            style ? style.name.to_s : ''
        rescue
            ''
        end
        private_class_method :na_style_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Bound Style Description Defensively
        # ------------------------------------------------------------
        def self.na_style_description(page)
            style = page.style
            style ? style.description.to_s : ''
        rescue
            ''
        end
        private_class_method :na_style_description
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Apply the Captured Style Options Onto an Existing Page
        # ------------------------------------------------------------
        # The caller owns the undo operation. Returns { applied, warnings }.
        def self.Na__SceneDataTransfer__ApplyStyleToPage(page, style_hash, style_lookup = nil)
            return na_result(false, ['No page supplied.'])       unless page
            return na_result(false, ['No style data supplied.']) unless style_hash.is_a?(Hash)

            warnings = na_apply_options(page, style_hash['options'])
            warnings.concat(na_bind_style(page, style_hash['style_name'], style_lookup))

            na_result(true, warnings)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # FUNCTION | Apply the Captured Fog Options Onto an Existing Page
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ApplyFogToPage(page, fog_hash)
            return na_result(false, ['No page supplied.'])     unless page
            return na_result(false, ['No fog data supplied.']) unless fog_hash.is_a?(Hash)

            na_result(true, na_apply_options(page, fog_hash['options']))
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write a Key Set Onto a Page's Rendering Options
        # ------------------------------------------------------------
        # Only keys the TARGET model knows about are written, so a payload from
        # a newer SketchUp cannot raise on an older one, and vice versa.
        def self.na_apply_options(page, encoded_options)
            return ['Rendering options were missing from the payload.'] unless encoded_options.is_a?(Hash)

            page.use_rendering_options = true                                       # <-- Must be true BEFORE any write

            target_options = page.rendering_options
            return ['This page exposes no rendering options.'] unless target_options

            codec        = Na__SceneDataTransfer__ValueCodec
            target_keys  = na_option_keys(target_options)
            warnings     = []
            skipped_keys = []

            encoded_options.each do |option_key, encoded_value|
                unless target_keys.include?(option_key.to_s)
                    skipped_keys << option_key.to_s                                 # <-- Key does not exist on this SketchUp release
                    next
                end

                decoded_value = codec.Na__SceneDataTransfer__Decode(encoded_value)
                next if decoded_value.nil?

                na_write_option(target_options, option_key.to_s, decoded_value, warnings)
            end

            unless skipped_keys.empty?
                warnings << "#{skipped_keys.length} rendering option(s) not supported by this SketchUp version " \
                            "were skipped: #{skipped_keys.sort.join(', ')}."
            end

            warnings
        end
        private_class_method :na_apply_options
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write One Rendering Option, Rescuing Strict Setters
        # ------------------------------------------------------------
        # From SketchUp 2024.0 an unacceptable value raises ArgumentError. One
        # bad key must not abort an entire scene import, so each write stands
        # alone and failures are collected.
        def self.na_write_option(target_options, option_key, decoded_value, warnings)
            codec = Na__SceneDataTransfer__ValueCodec

            current_value = target_options[option_key]
            return if codec.Na__SceneDataTransfer__ValuesMatch(current_value, decoded_value)

            target_options[option_key] = decoded_value
        rescue ArgumentError => error
            warnings << "Rendering option '#{option_key}' rejected the stored value: #{error.message}"
        rescue => error
            warnings << "Rendering option '#{option_key}' failed: #{error.class}: #{error.message}"
        end
        private_class_method :na_write_option
        # ------------------------------------------------------------

        # HELPER FUNCTION | Bind the Page to Its Named Style
        # ------------------------------------------------------------
        # Page#use_style= expects a Sketchup::Style OBJECT, not a boolean, and it
        # is the only writer for a page's style - there is no Page#style=.
        #
        # The style itself is created earlier, in the import's prepare phase, by
        # Na__SceneDataTransfer__StyleFactory. This looks up what that produced
        # and falls back to a by-name search for styles that were already here.
        def self.na_bind_style(page, style_name, style_lookup)
            clean_name = style_name.to_s.strip
            return [] if clean_name.empty?

            model = page.model
            return [] unless model

            match = (style_lookup || {})[clean_name]
            match = model.styles.find { |style| style.name.to_s == clean_name } if match.nil? || !match.valid?

            # The factory already explained why, so this stays silent rather than
            # repeating the same warning once per imported scene.
            return [] if match.nil?

            page.use_style = match
            []
        rescue => error
            ["Could not bind style '#{style_name}': #{error.class}: #{error.message}"]
        end
        private_class_method :na_bind_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings) }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__RenderingDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
