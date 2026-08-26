# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - SCHEMA
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Schema__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__Schema
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Single source of truth for dictionary names, payload keys,
#              capture domains and the Page flag mapping.
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Every capture domain lives in NA_CAPTURE_DOMAINS and is pushed to the dialog
# as data. The UI builds its toggle list from that payload, so adding a domain
# here plus its serialiser file is the only edit required.
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#   PAGE_USE_* constants live in the TOP-LEVEL namespace, never under
#   Sketchup::. Their integer values are NOT contractual across versions, so
#   this file stores constant NAMES as strings and resolves them at runtime
#   through Object.const_defined? / Object.const_get. That also gives free
#   forward compatibility for PAGE_USE_ENVIRONMENT (SketchUp 2025.0+).
#
#   Exact spellings that do not match their accessor methods:
#     axes     -> PAGE_USE_SKETCHCS          (there is NO PAGE_USE_AXES)
#     shadows  -> PAGE_USE_SHADOWINFO        (method is use_shadow_info?)
#     tags     -> PAGE_USE_LAYER_VISIBILITY  (method is use_hidden_layers?)
#     style    -> no constant at all; the style slot sits outside the flag
#                 system and is driven solely by Page#use_style=(style_object)
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__Schema

# -----------------------------------------------------------------------------
# REGION | Schema and Dictionary Identity
# -----------------------------------------------------------------------------

        NA_TOOL_VERSION              = '0.1.0'.freeze                               # <-- Tracks the DEVLOG version history
        NA_SCHEMA_VERSION            = '1.1.0'.freeze                               # <-- Bump when the payload shape changes

        # 1.0.0 -> 1.1.0 is BACKWARD COMPATIBLE. A 1.0.0 payload carries only a
        # camera block per scene and no model_level block; both read back fine.
        NA_PAYLOAD_DICTIONARY        = 'Na__SceneDataTransfer'.freeze               # <-- Holds the serialised scene payload
        NA_UI_STATE_DICTIONARY       = 'Na__SceneDataTransfer__UiState'.freeze      # <-- Holds this model dialog preferences
        NA_CARRIER_DEFINITION_NAME   = 'Na__SceneDataTransfer__Carrier'.freeze      # <-- Payload carrier component definition

        # A carrier ComponentDefinition is mandatory, not decorative. Model-level
        # attribute dictionaries do NOT travel when a .skp is pulled into another
        # model through Sketchup::DefinitionList#load - only DEFINITION-level
        # dictionaries survive that trip. See the ApiResearch markdown for the
        # full evidence trail.
        NA_CARRIER_INSTANCE_NAME     = 'Na Scene Data Transfer Payload'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Dictionary Keys
# -----------------------------------------------------------------------------

        NA_KEY_SCHEMA_VERSION        = 'schema_version'.freeze
        NA_KEY_CAPTURED_AT           = 'captured_at'.freeze
        NA_KEY_CAPTURED_BY           = 'captured_by'.freeze
        NA_KEY_SOURCE_MODEL_NAME     = 'source_model_name'.freeze
        NA_KEY_SOURCE_MODEL_PATH     = 'source_model_path'.freeze
        NA_KEY_SOURCE_MODEL_GUID     = 'source_model_guid'.freeze
        NA_KEY_SKETCHUP_VERSION      = 'sketchup_version'.freeze
        NA_KEY_SCENE_COUNT           = 'scene_count'.freeze
        NA_KEY_DOMAINS_CAPTURED      = 'domains_captured'.freeze
        NA_KEY_PAYLOAD_ENCODING      = 'payload_encoding'.freeze
        NA_KEY_PAYLOAD_CHUNK_COUNT   = 'payload_chunk_count'.freeze
        NA_KEY_PAYLOAD_BYTE_LENGTH   = 'payload_byte_length'.freeze
        NA_PAYLOAD_CHUNK_PREFIX      = 'payload_'.freeze                            # <-- payload_0000, payload_0001, ...

        NA_ENCODING_RAW              = 'raw'.freeze                                 # <-- Plain JSON string
        NA_ENCODING_DEFLATE_B64      = 'deflate_base64'.freeze                      # <-- Zlib deflate then Base64

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chunking Limits
# -----------------------------------------------------------------------------

        # There is no documented maximum length for an attribute String, but the
        # .skp file-size cost is severe and superlinear. Chunking keeps each
        # stored value small and keeps the native attribute inspector usable.
        NA_CHUNK_SIZE_BYTES          = 16_000                                       # <-- Characters per payload chunk
        NA_COMPRESS_THRESHOLD_BYTES  = 8_000                                        # <-- Deflate above this raw size

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Import Naming
# -----------------------------------------------------------------------------

        NA_DEFAULT_IMPORT_SUFFIX     = '__IMPORTED'.freeze                          # <-- Appended to every rebuilt scene name
        NA_MAX_NAME_ATTEMPTS         = 999                                          # <-- Ceiling on the de-duplication counter

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture Domain Registry
# -----------------------------------------------------------------------------

        # The implemented flag gates a domain in the UI. Phase 1 ships camera
        # only, so every other domain renders as a disabled toggle with its
        # planned scope visible. Flipping implemented to true and adding the
        # matching serialiser file is all that is needed to bring one online.
        NA_CAPTURE_DOMAINS = [
            {
                'key'         => 'camera',
                'label'       => 'Camera',
                'summary'     => 'Eye, target, up, projection mode, field of view or ortho height, aspect ratio.',
                'page_flags'  => %w[PAGE_USE_CAMERA],
                'implemented' => true
            },
            {
                'key'         => 'axes',
                'label'       => 'Global Axis Position',
                'summary'     => 'The model drawing axes origin and the three axis vectors saved on the scene.',
                'page_flags'  => %w[PAGE_USE_SKETCHCS],
                'implemented' => true
            },
            {
                'key'         => 'style',
                'label'       => 'Style',
                'summary'     => 'Every rendering option except fog: background, sky, ground, face and edge modes, ' \
                                 'profiles, depth cue, extension, section cut appearance and transparency.',
                'page_flags'  => %w[PAGE_USE_RENDERING_OPTIONS],
                'shares_flag' => 'Style and Fog are one SketchUp scene property.',
                'implemented' => true
            },
            {
                'key'         => 'fog',
                'label'       => 'Fog',
                'summary'     => 'DisplayFog, FogColor, FogUseBkColor, FogStartDist and FogEndDist.',
                'page_flags'  => %w[PAGE_USE_RENDERING_OPTIONS],
                'shares_flag' => 'Style and Fog are one SketchUp scene property.',
                'implemented' => true
            },
            {
                'key'         => 'shadows',
                'label'       => 'Shadows and Sun Position',
                'summary'     => 'Shadow time, light and dark levels and the shadow display flags. Location, time zone ' \
                                 'and north angle are model-wide in SketchUp, so they are applied once, not per scene.',
                'page_flags'  => %w[PAGE_USE_SHADOWINFO],
                'implemented' => true
            },
            {
                'key'         => 'sections',
                'label'       => 'Sections and Cuts',
                'summary'     => 'Model-level section planes recreated at their captured plane, plus which plane each ' \
                                 'scene activates. Planes nested inside groups or components are not transferred.',
                'page_flags'  => %w[PAGE_USE_SECTION_PLANES],
                'implemented' => true
            },
            {
                'key'         => 'tags',
                'label'       => 'Tag Visibility',
                'summary'     => 'Per-scene tag and tag-folder visibility, creating any tag missing from this model.',
                'page_flags'  => %w[PAGE_USE_LAYER_VISIBILITY],
                'implemented' => true
            },
            {
                'key'         => 'hidden_geometry',
                'label'       => 'Hidden Geometry and Objects',
                'summary'     => 'The scene level hidden-geometry and hidden-objects flags. Which geometry is hidden ' \
                                 'always comes from this model - entity identity is not portable across models.',
                'page_flags'  => %w[PAGE_USE_HIDDEN_GEOMETRY PAGE_USE_HIDDEN_OBJECTS],
                'implemented' => true
            },
            {
                'key'         => 'environment',
                'label'       => 'Environment (HDRI)',
                'summary'     => 'The scene environment reference and its use flag. Requires SketchUp 2025 or newer.',
                'page_flags'  => %w[PAGE_USE_ENVIRONMENT],
                'implemented' => false
            }
        ].freeze

        # Domains that ALSO carry model-level state, captured once per run rather
        # than once per scene, and applied once per import BEFORE any page is
        # built. Getting this wrong is a real bug, not a tidiness issue:
        #   tags     - Page#set_visibility needs the Layer to already exist
        #   sections - the plane entities must exist before a scene activates one
        #   shadows  - latitude, longitude, time zone and north angle are
        #              model-wide, so writing them per scene would rewrite the
        #              whole model once for every scene imported
        #   style    - a named Sketchup::Style must be created in the model
        #              before a page can be bound to it with Page#use_style=
        NA_MODEL_LEVEL_DOMAINS = %w[style tags sections shadows].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Domain Lookup Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | List the Domain Keys That Are Live in This Build
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ImplementedDomainKeys
            NA_CAPTURE_DOMAINS.select { |domain| domain['implemented'] }
                              .map    { |domain| domain['key'] }
        end
        # ------------------------------------------------------------

        # FUNCTION | Fetch a Single Domain Record by Key
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__DomainByKey(domain_key)
            NA_CAPTURE_DOMAINS.find { |domain| domain['key'] == domain_key.to_s }
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether a Domain Key Is Live in This Build
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__DomainIsImplemented(domain_key)
            domain = Na__SceneDataTransfer__DomainByKey(domain_key)
            !domain.nil? && domain['implemented'] == true
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Page Flag Resolution
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Pages Add Bitmask From Constant Names
        # ------------------------------------------------------------
        # Constants are resolved by name at call time. A constant that does not
        # exist on this SketchUp release is skipped rather than raising, which
        # is what keeps PAGE_USE_ENVIRONMENT safe on SketchUp 2024 and older.
        def self.Na__SceneDataTransfer__FlagMaskForConstants(constant_names)
            Array(constant_names).reduce(0) do |mask, constant_name|
                next mask unless Object.const_defined?(constant_name)

                mask | Object.const_get(constant_name).to_i
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Flag mask warning: #{error.class}: #{error.message}"
            0
        end
        # ------------------------------------------------------------

        # FUNCTION | Build the Combined Bitmask for a Set of Domain Keys
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__FlagMaskForDomains(domain_keys)
            constant_names = Array(domain_keys).flat_map do |domain_key|
                domain = Na__SceneDataTransfer__DomainByKey(domain_key)
                domain ? domain['page_flags'] : []
            end.uniq

            Na__SceneDataTransfer__FlagMaskForConstants(constant_names)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Choice Payload
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Domain List the Dialog Renders Its Toggles From
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ChoiceLists
            {
                'domains'        => NA_CAPTURE_DOMAINS.map { |domain| domain.dup },
                'default_suffix' => NA_DEFAULT_IMPORT_SUFFIX,
                'schema_version' => NA_SCHEMA_VERSION
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__Schema
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
