# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - SHADOW DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__ShadowDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__ShadowDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture sun position, time of day and shadow display, and rebuild
#              them in another model.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# Sketchup::ShadowInfo exposes 23 String keys through #[] / #[]=. They fall into
# three groups, and confusing the groups is the main way this goes wrong.
#
# 1. PER-PAGE keys. Genuinely scene state. Safe to write per scene.
#      ShadowTime, DisplayShadows, Dark, Light, UseSunForAllShading,
#      DisplayOnAllFaces, DisplayOnGroundPlane, EdgesCastShadows, DisplayNorth
#
# 2. MODEL-LEVEL keys. The docs state plainly that north angle, latitude and
#    longitude are managed at the MODEL level and are NOT page-specific.
#      City, Country, Latitude, Longitude, TZOffset, NorthAngle, DaylightSavings
#    Writing these inside a per-scene loop silently mutates the whole target
#    model, once per scene. They are therefore applied ONCE per import, through
#    Na__SceneDataTransfer__ApplyGeoToModel.
#
# 3. READ-ONLY keys. Computed by SketchUp from ShadowTime.
#      SunDirection, SunRise, SunRise_time_t, SunSet, SunSet_time_t, DayOfYear
#    ShadowTime_time_t is also treated as read-only here: ShadowTime is the
#    documented writable form, and writing the epoch twin is unnecessary risk.
#
# SKETCHUP 2026.1 MADE THE SETTER STRICT.
#   ShadowInfo#[]= now raises KeyError for an invalid OR read-only key, and
#   TypeError for a wrong-typed value, where older versions silently returned
#   false. A naive "loop over the hash and assign every key" restore that worked
#   on SketchUp 2023 WILL RAISE on 2026. That is precisely why this module
#   drives every write from an explicit allowlist and never from the payload's
#   own key set.
#
# SHADOWTIME IS A RUBY Time.
#   It is stored as an integer epoch. Any string from Time#to_s, #inspect or an
#   unqualified strftime bakes the exporting machine's OS time zone into the
#   payload and drifts on import. The epoch is the only exact round trip.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__ShadowDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DOMAIN_KEY = 'shadows'.freeze

        NA_PAGE_KEYS = %w[
            ShadowTime
            DisplayShadows
            Dark
            Light
            UseSunForAllShading
            DisplayOnAllFaces
            DisplayOnGroundPlane
            EdgesCastShadows
            DisplayNorth
        ].freeze

        NA_MODEL_KEYS = %w[
            City
            Country
            Latitude
            Longitude
            TZOffset
            NorthAngle
            DaylightSavings
        ].freeze

        # Never written. SketchUp computes these from ShadowTime, and from
        # SketchUp 2026.1 assigning one raises KeyError.
        NA_READ_ONLY_KEYS = %w[
            SunDirection
            SunRise
            SunRise_time_t
            SunSet
            SunSet_time_t
            ShadowTime_time_t
            DayOfYear
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Capture the Per-Scene Shadow State From a Page
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureShadows(page)
            return nil unless page

            shadow_info = page.shadow_info
            return nil unless shadow_info

            { 'page_keys' => na_read_keys(shadow_info, NA_PAGE_KEYS) }
        rescue => error
            puts "[Na__SceneDataTransfer] Shadow capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Capture the Model-Level Geo and North State
        # ------------------------------------------------------------
        # Called once per capture run, not once per scene.
        def self.Na__SceneDataTransfer__CaptureModelGeo(model)
            return nil unless model

            shadow_info = model.shadow_info
            return nil unless shadow_info

            { 'model_keys' => na_read_keys(shadow_info, NA_MODEL_KEYS) }
        rescue => error
            puts "[Na__SceneDataTransfer] Geo capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read and Encode a Named Key Set
        # ------------------------------------------------------------
        def self.na_read_keys(shadow_info, wanted_keys)
            codec    = Na__SceneDataTransfer__ValueCodec
            captured = {}

            wanted_keys.each do |shadow_key|
                begin
                    raw_value = shadow_info[shadow_key]
                    next if raw_value.nil?

                    captured[shadow_key] = codec.Na__SceneDataTransfer__Encode(raw_value)
                rescue => error
                    puts "[Na__SceneDataTransfer] Skipped shadow key '#{shadow_key}': #{error.message}"
                end
            end

            captured
        end
        private_class_method :na_read_keys
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Apply the Captured Shadow State Onto an Existing Page
        # ------------------------------------------------------------
        # The caller owns the undo operation. Returns { applied, warnings }.
        def self.Na__SceneDataTransfer__ApplyShadowsToPage(page, shadow_hash)
            return na_result(false, ['No page supplied.'])        unless page
            return na_result(false, ['No shadow data supplied.']) unless shadow_hash.is_a?(Hash)

            page.use_shadow_info = true                                             # <-- Must be true BEFORE any write

            shadow_info = page.shadow_info
            return na_result(false, ['This page exposes no shadow info.']) unless shadow_info

            warnings = na_write_keys(shadow_info, shadow_hash['page_keys'], NA_PAGE_KEYS)
            na_result(true, warnings)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # FUNCTION | Apply the Captured Geo and North State to the Whole Model
        # ------------------------------------------------------------
        # Called ONCE per import, never inside the per-scene loop, because these
        # keys are model-level and would otherwise be rewritten for every scene.
        def self.Na__SceneDataTransfer__ApplyGeoToModel(model, geo_hash)
            return na_result(false, ['No model supplied.'])     unless model
            return na_result(false, ['No geo data supplied.'])  unless geo_hash.is_a?(Hash)

            shadow_info = model.shadow_info
            return na_result(false, ['This model exposes no shadow info.']) unless shadow_info

            warnings = na_write_keys(shadow_info, geo_hash['model_keys'], NA_MODEL_KEYS)
            warnings << 'Location, time zone and north angle are model-wide in SketchUp, so they were ' \
                        'applied once to this whole model rather than per scene.' unless warnings.any?

            na_result(true, warnings)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write an Allowlisted Key Set, Rescuing Strict Setters
        # ------------------------------------------------------------
        # The allowlist is the load-bearing part. Writes are driven from
        # allowed_keys, NOT from the payload's own keys, so a read-only key that
        # somehow reached the payload can never be written back and can never
        # raise the KeyError that SketchUp 2026.1 introduced.
        def self.na_write_keys(shadow_info, encoded_keys, allowed_keys)
            return ['Shadow keys were missing from the payload.'] unless encoded_keys.is_a?(Hash)

            codec    = Na__SceneDataTransfer__ValueCodec
            warnings = []

            allowed_keys.each do |shadow_key|
                next if NA_READ_ONLY_KEYS.include?(shadow_key)                      # <-- Belt and braces
                next unless encoded_keys.key?(shadow_key)

                decoded_value = codec.Na__SceneDataTransfer__Decode(encoded_keys[shadow_key])
                next if decoded_value.nil?

                na_write_single_key(shadow_info, shadow_key, decoded_value, warnings)
            end

            warnings
        end
        private_class_method :na_write_keys
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write One Shadow Key in Isolation
        # ------------------------------------------------------------
        def self.na_write_single_key(shadow_info, shadow_key, decoded_value, warnings)
            shadow_info[shadow_key] = decoded_value
        rescue KeyError => error
            warnings << "Shadow key '#{shadow_key}' is read-only on this SketchUp version: #{error.message}"
        rescue TypeError => error
            warnings << "Shadow key '#{shadow_key}' rejected the stored value type: #{error.message}"
        rescue => error
            warnings << "Shadow key '#{shadow_key}' failed: #{error.class}: #{error.message}"
        end
        private_class_method :na_write_single_key
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings) }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__ShadowDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
