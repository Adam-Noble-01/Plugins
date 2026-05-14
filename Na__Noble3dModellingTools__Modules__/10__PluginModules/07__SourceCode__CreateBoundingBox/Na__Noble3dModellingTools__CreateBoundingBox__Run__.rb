# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CREATE BOUNDING BOX - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CreateBoundingBox__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__CreateBoundingBox
# PURPOSE    : Create a grouped wire bounding box around selected objects
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__CreateBoundingBox

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_BOUNDING_BOX_GROUP_NAME = 'Na__BoundingBox__Selection'.freeze
        NA_BOUNDING_BOX_OPERATION_NAME = 'Create Bounding Box'.freeze
        NA_CORNER_INDICES = (0..7).to_a.freeze
        NA_EDGE_INDEX_PAIRS = [
            [0, 1], [1, 3], [3, 2], [2, 0],
            [4, 5], [5, 7], [7, 6], [6, 4],
            [0, 4], [1, 5], [2, 6], [3, 7]
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Create Bounding Box Around the Active Selection
        # ------------------------------------------------------------
        def self.Na__CreateBoundingBox__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model
            return na_result(false, 'Select one or more objects, then run Create Bounding Box again.') if model.selection.empty?

            combined_bounds = na_combined_selection_bounds(model.selection)
            return na_result(false, 'Selection does not contain any valid objects with bounds.') unless combined_bounds&.valid?

            operation_started = false
            Sketchup.status_text = 'Creating bounding box around selected objects...'

            model.start_operation(NA_BOUNDING_BOX_OPERATION_NAME, true)
            operation_started = true
            bounding_box_group = na_create_bounding_box_group(model.active_entities, combined_bounds)
            model.selection.clear
            model.selection.add(bounding_box_group) if bounding_box_group&.valid?
            model.commit_operation
            operation_started = false

            Sketchup.status_text = ''
            na_result(true, 'Created bounding box around selected object(s).')
        rescue => error
            model.abort_operation if model && operation_started
            Sketchup.status_text = ''
            na_result(false, "Create Bounding Box failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bounds Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build One Combined BoundingBox from Selection
        # ------------------------------------------------------------
        def self.na_combined_selection_bounds(selection)
            combined_bounds = Geom::BoundingBox.new

            selection.each do |entity|
                next unless na_entity_has_valid_bounds?(entity)

                na_bounds_corners(entity.bounds).each do |point|
                    combined_bounds.add(point)
                end
            end

            combined_bounds
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Entity Has Usable Bounds
        # ------------------------------------------------------------
        def self.na_entity_has_valid_bounds?(entity)
            entity.respond_to?(:bounds) &&
                entity.valid? &&
                !entity.deleted? &&
                entity.bounds &&
                entity.bounds.valid?
        rescue
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Extract All Bounding Box Corners
        # ------------------------------------------------------------
        def self.na_bounds_corners(bounds)
            NA_CORNER_INDICES.map { |corner_index| bounds.corner(corner_index) }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Box Geometry Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Create a Group Containing Bounding Box Edges
        # ------------------------------------------------------------
        def self.na_create_bounding_box_group(entities, bounds)
            group = entities.add_group
            group.name = NA_BOUNDING_BOX_GROUP_NAME

            corners = na_bounds_corners(bounds)
            na_add_unique_bounding_edges(group.entities, corners)

            group
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Add Non-Duplicate Bounding Box Edges
        # ------------------------------------------------------------
        def self.na_add_unique_bounding_edges(entities, corners)
            created_edge_keys = {}

            NA_EDGE_INDEX_PAIRS.each do |start_index, end_index|
                start_point = corners[start_index]
                end_point = corners[end_index]
                next if start_point == end_point

                edge_key = na_edge_key(start_point, end_point)
                next if created_edge_keys[edge_key]

                entities.add_edges(start_point, end_point)
                created_edge_keys[edge_key] = true
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Direction-Independent Edge Key
        # ------------------------------------------------------------
        def self.na_edge_key(start_point, end_point)
            [na_point_key(start_point), na_point_key(end_point)].sort.join('|')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Stable Point Key
        # ------------------------------------------------------------
        def self.na_point_key(point)
            point.to_a.map { |coordinate| coordinate.to_f.round(6) }.join(',')
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__CreateBoundingBox
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
