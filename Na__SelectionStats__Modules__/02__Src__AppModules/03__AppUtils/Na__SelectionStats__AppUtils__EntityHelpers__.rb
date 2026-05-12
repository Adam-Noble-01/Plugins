# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - ENTITY HELPERS
# =============================================================================
#
# FILE       : Na__SelectionStats__AppUtils__EntityHelpers__.rb
# PURPOSE    : Stable tokens, typing, and validity without walking geometry.
#
# =============================================================================

require 'sketchup.rb'

module Na__SelectionStats
    module Na__AppUtils
        module Na__EntityHelpers
            extend self

# -----------------------------------------------------------------------------
# REGION | Identity & Lifespan
# -----------------------------------------------------------------------------

            def na_entity_usable?(entity)
                return false unless entity
                return entity.valid? if entity.respond_to?(:valid?)

                true
            rescue StandardError
                false
            end

            def na_stable_token(entity)
                if entity.respond_to?(:persistent_id)
                    "#{entity.class.name}_pid_#{entity.persistent_id}"
                elsif entity.respond_to?(:entityID)
                    "#{entity.class.name}_eid_#{entity.entityID}"
                else
                    "#{entity.class.name}_oid_#{entity.object_id}"
                end
            rescue StandardError
                "#{entity.class.name}_oid_#{entity.object_id}"
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Naming & Labels
# -----------------------------------------------------------------------------

            def na_entity_type_name(entity)
                return entity.typename.to_s if entity.respond_to?(:typename)

                entity.class.name.to_s
            rescue StandardError
                'Unknown'
            end

            def na_component_definition_name(definition)
                name = definition.respond_to?(:name) ? definition.name.to_s : ''
                name.empty? ? 'Unnamed Component Definition' : name
            rescue StandardError
                'Component Definition'
            end

            def na_model_title(model)
                title = model.title.to_s
                title.empty? ? 'Untitled Model' : title
            rescue StandardError
                'Active Model'
            end

# endregion -------------------------------------------------------------------

        end
    end
end
