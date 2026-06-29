# =============================================================================
# NA NOBLE3D MODELLING TOOLS - DIMENSION UTILS
# =============================================================================
#
# FILE      : Na__Noble3dModellingTools__DimensionUtils__Run__.rb
# NAMESPACE : Na__Noble3dModellingTools::Na__DimensionUtils
# PURPOSE   : Recursively manage SketchUp dimension entities across the full
#             model hierarchy — tag linear dimensions to a named tag, or count
#             and delete all dimension entities with user confirmation.
# CREATED   : 2026
#
# DESCRIPTION:
# - Traverses model.entities plus all component definitions using an iterative
#   stack (no recursion depth risk) with a visited-definition guard so shared
#   component definitions are only visited once per run.
# - Tool 1: assigns all Sketchup::DimensionLinear entities to the
#   "90__Dimensions" tag, creating the tag if it does not yet exist.
# - Tool 2: counts all Sketchup::Dimension entities (linear + radial), reports
#   the total in a confirmation dialog, then erases them all on YES or returns
#   gracefully on NO/cancel.
# - Both tools are wrapped in a model operation for single-undo support.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 29-Jun-2026 - Version 1.0.0
# - Initial release. Tag linear dimensions + delete all dimensions tools.
#
# 29-Jun-2026 - Version 1.1.0
# - Added tag text/leaders tool (Na__DimensionUtils__RunTagTextEntities).
# - Added delete text/leaders tool (Na__DimensionUtils__RunDeleteTextEntities).
# - Both target Sketchup::Text — the single API class covering screen text
#   and leader-line text (with leader arrows) in SketchUp.
# - Confirmation dialog reports screen text vs leader count breakdown.
#
# =============================================================================

require 'sketchup.rb'

module Na__Noble3dModellingTools
    module Na__DimensionUtils

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Dimension Tag Configuration
        # ------------------------------------------------------------
        NA_DIMENSION_TAG_NAME = '90__Dimensions'.freeze # <-- Target tag name for linear dimensions
        NA_TEXT_TAG_NAME      = '90__Text'.freeze        # <-- Target tag name for text and leader entities
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Tag All Linear Dimensions as 90__Dimensions
        # ------------------------------------------------------------
        def self.Na__DimensionUtils__RunTagDimensions
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model available.') unless model

            target_tag      = na_ensure_tag_exists(model, NA_DIMENSION_TAG_NAME)
            dimensions      = na_collect_linear_dimensions(model)
            reassigned_count = 0

            model.start_operation('Tag Linear Dimensions', true)

            dimensions.each do |entity|
                next unless entity.valid?
                next if entity.layer == target_tag # <-- Skip if already on target tag

                entity.layer      = target_tag
                reassigned_count += 1
            end

            model.commit_operation
            na_result(true, "Tagged #{reassigned_count} of #{dimensions.length} linear dimension(s) to \"#{NA_DIMENSION_TAG_NAME}\".")
        rescue => error
            model.abort_operation rescue nil
            na_result(false, "Tag Linear Dimensions failed: #{error.class}: #{error.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tag All Text and Leader Entities as 90__Text
        # ------------------------------------------------------------
        # In SketchUp's Ruby API, both plain screen text and leader-line text
        # (with an arrow pointing to 3D geometry) are represented by the single
        # class Sketchup::Text. has_leader? distinguishes them but both share
        # the same class, so this tool tags all text/leader entities at once.
        def self.Na__DimensionUtils__RunTagTextEntities
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model available.') unless model

            target_tag       = na_ensure_tag_exists(model, NA_TEXT_TAG_NAME)
            text_entities    = na_collect_text_entities(model)
            reassigned_count = 0

            model.start_operation('Tag Text and Leaders', true)

            text_entities.each do |entity|
                next unless entity.valid?
                next if entity.layer == target_tag # <-- Skip if already on target tag

                entity.layer      = target_tag
                reassigned_count += 1
            end

            model.commit_operation
            na_result(true, "Tagged #{reassigned_count} of #{text_entities.length} text/leader entit#{text_entities.length == 1 ? 'y' : 'ies'} to \"#{NA_TEXT_TAG_NAME}\".")
        rescue => error
            model.abort_operation rescue nil
            na_result(false, "Tag Text and Leaders failed: #{error.class}: #{error.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Count and Delete All Text and Leader Entities
        # ------------------------------------------------------------
        def self.Na__DimensionUtils__RunDeleteTextEntities
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model available.') unless model

            text_entities = na_collect_text_entities(model)
            count         = text_entities.length

            if count.zero?
                return na_result(true, 'No text or leader entities found in the model.')
            end

            leader_count   = text_entities.count { |e| e.valid? && e.has_leader? }
            screen_count   = count - leader_count
            summary        = "#{count} text/leader #{count == 1 ? 'entity' : 'entities'} found:\n" \
                             "  - #{screen_count} screen text #{screen_count == 1 ? 'entity' : 'entities'}\n" \
                             "  - #{leader_count} leader text #{leader_count == 1 ? 'entity' : 'entities'}\n\n" \
                             "Delete ALL text and leaders? This cannot be undone."

            response = UI.messagebox(summary, MB_YESNO, 'Delete All Text and Leaders')

            return na_result(true, 'Cancelled — no text or leaders deleted.') unless response == IDYES

            deleted_count = 0

            model.start_operation('Delete All Text and Leaders', true)

            text_entities.each do |entity|
                next unless entity.valid? # <-- Guard against already-erased entities

                entity.erase!
                deleted_count += 1
            end

            model.commit_operation
            na_result(true, "Deleted #{deleted_count} text/leader #{deleted_count == 1 ? 'entity' : 'entities'} from the model.")
        rescue => error
            model.abort_operation rescue nil
            na_result(false, "Delete All Text and Leaders failed: #{error.class}: #{error.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Count and Delete All Dimension Entities
        # ------------------------------------------------------------
        def self.Na__DimensionUtils__RunDeleteDimensions
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model available.') unless model

            dimensions = na_collect_all_dimensions(model)
            count      = dimensions.length

            if count.zero?
                return na_result(true, 'No dimension entities found in the model.')
            end

            response = UI.messagebox(
                "#{count} dimension #{count == 1 ? 'entity' : 'entities'} found in this model.\n\n" \
                "Delete ALL dimensions? This cannot be undone.",
                MB_YESNO,
                'Delete All Dimensions'
            )

            return na_result(true, 'Cancelled — no dimensions deleted.') unless response == IDYES

            deleted_count = 0

            model.start_operation('Delete All Dimensions', true)

            dimensions.each do |entity|
                next unless entity.valid? # <-- Guard against already-erased entities

                entity.erase!
                deleted_count += 1
            end

            model.commit_operation
            na_result(true, "Deleted #{deleted_count} dimension(s) from the model.")
        rescue => error
            model.abort_operation rescue nil
            na_result(false, "Delete All Dimensions failed: #{error.class}: #{error.message}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Collection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect All Linear Dimension Entities (Sketchup::DimensionLinear)
        # ------------------------------------------------------------
        def self.na_collect_linear_dimensions(model)
            na_traverse_model_for_type(model, Sketchup::DimensionLinear)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Collect All Dimension Entities (Linear + Radial)
        # ------------------------------------------------------------
        def self.na_collect_all_dimensions(model)
            na_traverse_model_for_type(model, Sketchup::Dimension)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Collect All Text Entities (Screen Text + Leader Text)
        # ------------------------------------------------------------
        # Sketchup::Text covers both plain screen text and leader-line text
        # (entities with an arrow pointing to a 3D point / attached geometry).
        # has_leader? can be used to distinguish them, but both share this class.
        def self.na_collect_text_entities(model)
            na_traverse_model_for_type(model, Sketchup::Text)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Iterative Model Traversal — Collect Entities of Given Type
        # ------------------------------------------------------------
        # Uses an iterative stack rather than recursion to avoid call-stack
        # overflow on deeply nested models. Component definitions are visited
        # once per run via a persistent_id guard so shared definitions
        # (e.g. repeated components) are not double-counted or double-erased.
        def self.na_traverse_model_for_type(model, entity_class)
            collected    = []
            visited_defs = {}
            stack        = [model.entities] # <-- Seed stack with root entities

            until stack.empty?
                entities = stack.pop

                entities.each do |entity|
                    if entity.is_a?(Sketchup::Group)
                        stack << entity.entities # <-- Descend into group

                    elsif entity.is_a?(Sketchup::ComponentInstance)
                        defn = entity.definition
                        guid = defn.persistent_id
                        unless visited_defs[guid]       # <-- Visit each definition once only
                            visited_defs[guid] = true
                            stack << defn.entities
                        end

                    elsif entity.is_a?(entity_class)
                        collected << entity # <-- Collect matching entity
                    end
                end
            end

            collected
        rescue => error
            puts "[Na__DimensionUtils] Traversal warning: #{error.class}: #{error.message}"
            []
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Ensure Named Tag Exists in Model
        # ------------------------------------------------------------
        # model.layers.add returns the existing layer if the name is already
        # present, so this is safe to call unconditionally.
        def self.na_ensure_tag_exists(model, tag_name)
            model.layers.add(tag_name) # <-- Creates or returns existing tag
        rescue => error
            puts "[Na__DimensionUtils] Tag creation warning: #{error.class}: #{error.message}"
            nil
        end
        # ---------------------------------------------------------------

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
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DimensionUtils
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
