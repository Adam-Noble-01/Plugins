# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - MERGE REGISTRY
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__MergeRegistry__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__MergeRegistry
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Decide, group by group, whether a converted group gets its own
#              component definition or joins one made earlier in the run
# CREATED    : 2026
#
# MODES:
# - :none   Every group gets its own definition.
# - :copies Groups still sharing one definition (SketchUp group copies) join
#           the first copy's component. Exact by construction.
# - :common Groups whose geometry matches join, however they are moved or
#           rotated (Na__GroupComponentConverter__ShapeMatcher). Group copies
#           match too, so this includes :copies.
#
# The scanner and the converter drive one registry each through Lookup,
# Register and AddMember in the same walk order, so the preview reports the
# same templates the conversion makes. Templates remember how many groups
# they absorbed; one is a __Unique definition, two or more a __Common one.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__MergeRegistry

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_TEMPLATES_PER_KEY = 16

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Registry API
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Registry for One Scan or One Conversion
        # ------------------------------------------------------------
        # @param merge_mode   [Symbol] :none, :copies or :common
        # @param work         [Hash, nil] Shared ShapeMatcher work counter
        # @param record_cache [Hash, nil] Shared shape records by definition id
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__MergeRegistry__Build(merge_mode, work = nil, record_cache = nil)
            {
                mode:      merge_mode,
                work:      work || Na__GroupComponentConverter__ShapeMatcher.Na__GroupComponentConverter__ShapeMatcher__NewWork(nil),
                records:   record_cache || {},
                buckets:   {},
                templates: []
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Find the Template an Unconverted Group Should Join
        # ------------------------------------------------------------
        # Call before the group is made unique or converted: its shape is
        # read from its original definition.
        # @return [Hash] { template:, offset:, key:, record: } - template and
        #         offset are nil when the group needs its own definition
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__MergeRegistry__Lookup(registry, group)
            case registry[:mode]
            when :copies
                na_lookup_copy(registry, group)
            when :common
                na_lookup_common(registry, group)
            else
                na_lookup_result(nil, nil, nil, nil)
            end
        rescue => error
            puts "[Na__GroupComponentConverter] Merge lookup warning: #{error.class}: #{error.message}"
            na_lookup_result(nil, nil, nil, nil)
        end
        # ------------------------------------------------------------

        # FUNCTION | Record a Group That Got Its Own Definition as a Template
        # ------------------------------------------------------------
        # @param lookup    [Hash]   The Lookup result for this group
        # @param payload   [Object] The converter's component definition, or
        #                           any truthy marker from the scanner
        # @param base_name [String] The group's name, for the final naming
        # @return [Hash] The template
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__MergeRegistry__Register(registry, lookup, payload, base_name)
            template = {
                record:       lookup[:record],
                payload:      payload,
                base_name:    base_name.to_s,
                member_count: 1
            }

            registry[:templates] << template
            (registry[:buckets][lookup[:key]] ||= []) << template if lookup[:key]
            template
        end
        # ------------------------------------------------------------

        # FUNCTION | Count One More Group Joining a Template
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__MergeRegistry__AddMember(template)
            template[:member_count] += 1
        end
        # ------------------------------------------------------------

        # FUNCTION | Every Template in Creation Order
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__MergeRegistry__Templates(registry)
            registry[:templates]
        end
        # ------------------------------------------------------------

        # FUNCTION | Definition Counts for the Preview and the Result Message
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__MergeRegistry__Summary(registry)
            templates = registry[:templates]
            common    = templates.select { |template| template[:member_count] > 1 }

            {
                new_definition_count:    templates.length,
                common_definition_count: common.length,
                common_group_count:      common.sum { |template| template[:member_count] },
                single_definition_count: templates.length - common.length,
                partial:                 !!registry[:work][:exhausted]
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lookups
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Group Copies Join the First Copy, No Offset
        # ------------------------------------------------------------
        def self.na_lookup_copy(registry, group)
            key = "definition:#{group.definition.entityID}"
            template = (registry[:buckets][key] || []).first
            offset = template ? Geom::Transformation.new : nil

            na_lookup_result(template, offset, key, nil)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Common Groups Join the First Template Their Shape Registers To
        # ------------------------------------------------------------
        def self.na_lookup_common(registry, group)
            record = Na__GroupComponentConverter__ShapeMatcher.Na__GroupComponentConverter__ShapeMatcher__Record(
                group.definition, registry[:records], registry[:work]
            )
            return na_lookup_result(nil, nil, nil, nil) unless record

            key = record[:key]
            (registry[:buckets][key] || []).first(NA_MAX_TEMPLATES_PER_KEY).each do |template|
                offset = Na__GroupComponentConverter__ShapeMatcher.Na__GroupComponentConverter__ShapeMatcher__Register(
                    template[:record], record, registry[:work]
                )
                return na_lookup_result(template, offset, key, record) if offset
            end

            na_lookup_result(nil, nil, key, record)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | One Shape for Every Lookup Answer
        # ------------------------------------------------------------
        def self.na_lookup_result(template, offset, key, record)
            {
                template: template,
                offset:   offset,
                key:      key,
                record:   record
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__MergeRegistry
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
