# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUPS TO COMPONENT - VALIDATOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupsToComponent__Validator__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupsToComponent__Validator
# PURPOSE    : Collect candidate groups and validate geometry consistency
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupsToComponent__Validator

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIMENSION_TOLERANCE_INCHES = 0.01
        NA_SCALE_TOLERANCE            = 1.0e-4

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Validation API
# -----------------------------------------------------------------------------

        # FUNCTION | Collect Unlocked Selected Groups
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Validator__CollectCandidateGroups(model)
            return [] unless model

            model.selection.grep(Sketchup::Group).select do |entity|
                na_convertible_group?(entity)
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Build a Geometry Fingerprint for a Group
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Validator__BuildFingerprint(group)
            return nil unless na_convertible_group?(group)

            definition = group.definition
            bounds     = definition.bounds
            entities   = definition.entities

            {
                width:         bounds.width,
                height:        bounds.height,
                depth:         bounds.depth,
                face_count:    entities.grep(Sketchup::Face).length,
                edge_count:    entities.grep(Sketchup::Edge).length,
                vertex_count:  na_count_vertices(entities)
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Check Consistency Across Candidate Groups
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Validator__CheckConsistency(groups)
            return na_empty_consistency_result if groups.nil? || groups.empty?

            reference_fingerprint = Na__GroupsToComponent__Validator__BuildFingerprint(groups.first)
            mismatch_indices      = []
            non_uniform_indices   = []

            groups.each_with_index do |group, index|
                mismatch_indices << index unless na_fingerprints_match?(
                    reference_fingerprint,
                    Na__GroupsToComponent__Validator__BuildFingerprint(group)
                )

                non_uniform_indices << index if na_non_uniform_scale?(group)
            end

            {
                consistent:                 mismatch_indices.empty?,
                mismatch_indices:           mismatch_indices,
                non_uniform_scale_indices:  non_uniform_indices
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Warning Message Text for Consistency Issues
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Validator__BuildWarningMessage(groups, consistency_result)
            lines = []

            unless consistency_result[:consistent]
                mismatch_labels = consistency_result[:mismatch_indices].map { |index| index + 1 }
                lines << "Some selected groups may not match the first group's internal geometry (bounds or entity counts)."
                lines << "Mismatched selection indices: #{mismatch_labels.join(', ')}."
            end

            unless consistency_result[:non_uniform_scale_indices].empty?
                scale_labels = consistency_result[:non_uniform_scale_indices].map { |index| index + 1 }
                lines << "Some groups have non-uniform scale, which can distort component instances."
                lines << "Non-uniform scale indices: #{scale_labels.join(', ')}."
            end

            return nil if lines.empty?

            lines << ''
            lines << 'Continue anyway?'
            lines.join("\n")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check Group Can Be Converted
        # ------------------------------------------------------------
        def self.na_convertible_group?(entity)
            entity.is_a?(Sketchup::Group) &&
                entity.valid? &&
                !entity.deleted? &&
                !entity.locked?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Two Geometry Fingerprints
        # ------------------------------------------------------------
        def self.na_fingerprints_match?(fingerprint_a, fingerprint_b)
            return false unless fingerprint_a.is_a?(Hash) && fingerprint_b.is_a?(Hash)

            return false unless fingerprint_a[:face_count] == fingerprint_b[:face_count]
            return false unless fingerprint_a[:edge_count] == fingerprint_b[:edge_count]
            return false unless fingerprint_a[:vertex_count] == fingerprint_b[:vertex_count]

            na_dimension_close?(fingerprint_a[:width], fingerprint_b[:width]) &&
                na_dimension_close?(fingerprint_a[:height], fingerprint_b[:height]) &&
                na_dimension_close?(fingerprint_a[:depth], fingerprint_b[:depth])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Dimensions Within Tolerance
        # ------------------------------------------------------------
        def self.na_dimension_close?(value_a, value_b)
            (value_a.to_f - value_b.to_f).abs <= NA_DIMENSION_TOLERANCE_INCHES
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detect Non-Uniform Scale on a Group Transformation
        # ------------------------------------------------------------
        def self.na_non_uniform_scale?(group)
            transform_array = group.transformation.to_a
            scale_x         = Geom::Vector3d.new(transform_array[0], transform_array[1], transform_array[2]).length
            scale_y         = Geom::Vector3d.new(transform_array[4], transform_array[5], transform_array[6]).length
            scale_z         = Geom::Vector3d.new(transform_array[8], transform_array[9], transform_array[10]).length

            max_scale = [scale_x, scale_y, scale_z].max
            min_scale = [scale_x, scale_y, scale_z].min
            return false if max_scale <= NA_SCALE_TOLERANCE

            ((max_scale - min_scale) / max_scale) > NA_SCALE_TOLERANCE
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count Unique Vertices in an Entities Collection
        # ------------------------------------------------------------
        def self.na_count_vertices(entities)
            vertex_ids = {}

            entities.grep(Sketchup::Edge).each do |edge|
                vertex_ids[edge.start.position.to_a] = true
                vertex_ids[edge.end.position.to_a]   = true
            end

            vertex_ids.length
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Empty Consistency Result
        # ------------------------------------------------------------
        def self.na_empty_consistency_result
            {
                consistent:                true,
                mismatch_indices:          [],
                non_uniform_scale_indices: []
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupsToComponent__Validator
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
