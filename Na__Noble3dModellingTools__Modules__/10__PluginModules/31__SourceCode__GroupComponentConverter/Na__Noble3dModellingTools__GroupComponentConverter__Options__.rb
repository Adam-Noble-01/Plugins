# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - OPTIONS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__Options__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__Options
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : One definition of the dialog switches and toggles, shared by the
#              scanner, the converter and the dialog manager
# CREATED    : 2026
#
# SWITCHES:
# - direction : groups_to_components | components_to_groups
# - scope     : current_level        | deep_nesting
#
# TOGGLES:
# - merge_common_groups : Groups to Components only. Groups with the same
#                         geometry, however they are moved or rotated, become
#                         instances of one shared component. Includes group
#                         copies. Off by default.
# - merge_group_copies  : Groups to Components only. Group copies (groups
#                         still sharing one definition) become instances of
#                         one shared component. On by default; redundant
#                         while merge_common_groups is on.
# - include_locked      : Locked containers are converted and relocked, and
#                         their contents are reached. Off by default.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__Options

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIRECTION_GROUPS_TO_COMPONENTS = 'groups_to_components'.freeze
        NA_DIRECTION_COMPONENTS_TO_GROUPS = 'components_to_groups'.freeze
        NA_SCOPE_CURRENT_LEVEL            = 'current_level'.freeze
        NA_SCOPE_DEEP_NESTING             = 'deep_nesting'.freeze

        NA_VALID_DIRECTIONS = [
            NA_DIRECTION_GROUPS_TO_COMPONENTS,
            NA_DIRECTION_COMPONENTS_TO_GROUPS
        ].freeze

        NA_VALID_SCOPES = [
            NA_SCOPE_CURRENT_LEVEL,
            NA_SCOPE_DEEP_NESTING
        ].freeze

        NA_DEFAULT_OPTIONS = {
            direction:           NA_DIRECTION_GROUPS_TO_COMPONENTS,
            scope:               NA_SCOPE_CURRENT_LEVEL,
            merge_common_groups: false,
            merge_group_copies:  true,
            include_locked:      false
        }.freeze

        NA_BOOLEAN_KEYS = [
            :merge_common_groups,
            :merge_group_copies,
            :include_locked
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Options API
# -----------------------------------------------------------------------------

        # FUNCTION | Normalise Raw Options Into the Full Symbol-Keyed Set
        # ------------------------------------------------------------
        # @param raw_options [Hash, String, nil] Symbol or string keys, or a
        #                    JSON string posted from the dialog
        # @return [Hash] Every option present, invalid values replaced by
        #                the defaults
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Options__Resolve(raw_options)
            parsed = na_parse_raw_options(raw_options)
            resolved = NA_DEFAULT_OPTIONS.dup

            direction = na_fetch(parsed, :direction).to_s
            resolved[:direction] = direction if NA_VALID_DIRECTIONS.include?(direction)

            scope = na_fetch(parsed, :scope).to_s
            resolved[:scope] = scope if NA_VALID_SCOPES.include?(scope)

            NA_BOOLEAN_KEYS.each do |key|
                raw_value = na_fetch(parsed, key)
                resolved[key] = na_parse_boolean(raw_value) unless raw_value.nil?
            end

            resolved
        rescue => error
            puts "[Na__GroupComponentConverter] Options resolve warning: #{error.class}: #{error.message}"
            NA_DEFAULT_OPTIONS.dup
        end
        # ------------------------------------------------------------

        # FUNCTION | First-Run Defaults
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Options__Defaults
            NA_DEFAULT_OPTIONS.dup
        end
        # ------------------------------------------------------------

        # FUNCTION | String-Keyed Copy of the Options for the Dialog
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Options__ToPayload(options)
            resolved = self.Na__GroupComponentConverter__Options__Resolve(options)

            {
                'direction'           => resolved[:direction],
                'scope'               => resolved[:scope],
                'merge_common_groups' => resolved[:merge_common_groups],
                'merge_group_copies'  => resolved[:merge_group_copies],
                'include_locked'      => resolved[:include_locked]
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | True When the Groups to Components Direction Is Chosen
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Options__GroupsToComponents?(options)
            options[:direction] == NA_DIRECTION_GROUPS_TO_COMPONENTS
        end
        # ------------------------------------------------------------

        # FUNCTION | True When Deep Nesting Is Chosen
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Options__DeepNesting?(options)
            options[:scope] == NA_SCOPE_DEEP_NESTING
        end
        # ------------------------------------------------------------

        # FUNCTION | How Converted Groups Share Component Definitions
        # ------------------------------------------------------------
        # @return [Symbol] :common, :copies or :none
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Options__MergeMode(options)
            return :common if options[:merge_common_groups]
            return :copies if options[:merge_group_copies]

            :none
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Parse a Hash or JSON String Into a Hash
        # ------------------------------------------------------------
        def self.na_parse_raw_options(raw_options)
            parsed = if raw_options.is_a?(String)
                         raw_options.strip.empty? ? {} : JSON.parse(raw_options)
                     elsif raw_options.is_a?(Hash)
                         raw_options
                     else
                         {}
                     end

            parsed.is_a?(Hash) ? parsed : {}
        rescue
            {}
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a Key Posted as Either a Symbol or a String
        # ------------------------------------------------------------
        def self.na_fetch(hash, key)
            return hash[key] if hash.key?(key)

            hash[key.to_s]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Coerce Any Stored or Posted Value Into a Boolean
        # ------------------------------------------------------------
        def self.na_parse_boolean(raw_value)
            return raw_value if raw_value == true || raw_value == false

            %w[true 1].include?(raw_value.to_s.strip.downcase)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__Options
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
