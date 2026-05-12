# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - STATS BUILDER · MATERIAL TRACKER
# =============================================================================
#
# FILE       : Na__SelectionStats__StatsBuilder__MaterialTracker__.rb
# PURPOSE    : Populate tracker[:materials] with counts and assignment slots.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__MaterialTracker
        extend self

# -----------------------------------------------------------------------------
# REGION | Entity & Face Surfaces
# -----------------------------------------------------------------------------

        def na_record_entity_material(entity, tracker, owner_label)
            return nil unless entity.respond_to?(:material)
            return nil if entity.is_a?(Sketchup::Face)

            na_record_material(entity.material, tracker, owner_label, 'Entity')
            nil
        rescue StandardError
            nil
        end

        def na_record_face_materials(face, tracker, owner_label)
            na_record_material(face.material, tracker, owner_label, 'Face Front')
            na_record_material(face.back_material, tracker, owner_label, 'Face Back')
            nil
        rescue StandardError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bucket Updates
# -----------------------------------------------------------------------------

        def na_record_material(material, tracker, owner_label, slot_label)
            default_label = Na__SelectionStats::Na__AppData::Na__Constants::DEFAULT_MATERIAL_LABEL
            material_name = material ? material.name.to_s : default_label
            tracker[:materials][material_name] ||= {
                name: material_name,
                count: 0,
                slots: {}
            }
            tracker[:materials][material_name][:count] += 1
            tracker[:materials][material_name][:slots][slot_label] ||= 0
            tracker[:materials][material_name][:slots][slot_label] += 1
            nil
        end

# endregion -------------------------------------------------------------------

    end
end
