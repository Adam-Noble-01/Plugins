# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - PAYLOAD CARRIER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Carrier__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__Carrier
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the hidden ComponentDefinition that carries the serialised
#              scene payload between .skp files, and locate it again after the
#              source model has been pulled in through DefinitionList#load.
# CREATED    : 2026
#
# WHY THIS FILE EXISTS AT ALL:
# Model-level attribute dictionaries written with Sketchup::Model#set_attribute
# do NOT travel when a .skp is pulled into another model through
# Sketchup::DefinitionList#load. Only DEFINITION-level dictionaries survive
# that trip. So the payload is written twice in the source model:
#
#   1. onto Sketchup::Model            - readable when that model is open, and
#                                        visible in the native attribute
#                                        inspector
#   2. onto a carrier ComponentDefinition - the only copy that another model can
#                                        actually reach
#
# WHY THE CARRIER NEEDS A PLACED INSTANCE:
# DefinitionList#load reconstructs the source model's ROOT ENTITIES inside the
# returned definition. A definition with no instance placed in the source
# model's root is not reachable from that reconstruction, and is additionally a
# casualty of any Purge Unused the user runs. One hidden, locked instance at the
# origin makes the payload deterministically findable.
#
# WHY NOT A GROUP:
# A Group's definition is silently made unique the moment the group is edited,
# which would orphan the attributes. A ComponentInstance is stable.
#
# WHY THE DEFINITION CONTAINS AN EDGE:
# SketchUp does not keep empty definitions - they are auto-purged. A single
# hidden one-inch edge is the smallest durable payload anchor. Construction
# geometry is deliberately avoided because Edit > Delete Guides would remove it.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__Carrier

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_ANCHOR_START      = [0, 0, 0].freeze                                     # <-- Anchor edge start, model origin
        NA_ANCHOR_END        = [0, 0, 1].freeze                                     # <-- Anchor edge end, one inch up
        NA_MAX_SEARCH_DEPTH  = 3                                                    # <-- Recursion ceiling when hunting the carrier

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Carrier Creation - Source Model Side
# -----------------------------------------------------------------------------

        # FUNCTION | Fetch or Build the Carrier Definition and Its Placed Instance
        # ------------------------------------------------------------
        # The caller owns the undo operation.
        def self.Na__SceneDataTransfer__EnsureCarrier(model)
            return nil unless model

            definition = Na__SceneDataTransfer__FindCarrierDefinition(model)
            definition = na_create_carrier_definition(model) if definition.nil?
            return nil unless definition

            na_ensure_carrier_instance(model, definition)
            definition
        rescue => error
            puts "[Na__SceneDataTransfer] Carrier creation error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Locate the Carrier Definition Inside a Live Model
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__FindCarrierDefinition(model)
            return nil unless model

            carrier_name = Na__SceneDataTransfer__Schema::NA_CARRIER_DEFINITION_NAME

            model.definitions.find do |definition|
                next false if definition.nil?

                definition.name.to_s == carrier_name ||
                    Na__SceneDataTransfer__Codec.Na__SceneDataTransfer__HasPayload(definition)
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Carrier lookup warning: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Delete the Carrier Definition and Every Instance of It
        # ------------------------------------------------------------
        # The caller owns the undo operation.
        def self.Na__SceneDataTransfer__RemoveCarrier(model)
            return false unless model

            definition = Na__SceneDataTransfer__FindCarrierDefinition(model)
            return false unless definition

            definition.instances.each { |instance| instance.erase! if instance.valid? }

            if model.definitions.respond_to?(:remove)
                model.definitions.remove(definition)                                # <-- SketchUp 2018 and newer
            else
                definition.entities.clear!                                          # <-- Older fallback; SketchUp auto-purges the empty definition
            end

            true
        rescue => error
            puts "[Na__SceneDataTransfer] Carrier removal warning: #{error.class}: #{error.message}"
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Carrier Discovery - Target Model Side
# -----------------------------------------------------------------------------

        # FUNCTION | Find the Payload-Bearing Entity Inside a Loaded Source Definition
        # ------------------------------------------------------------
        # loaded_definition is what DefinitionList#load returned for the source
        # .skp - its entities are that model's reconstructed root entities.
        #
        # Search order:
        #   1. the loaded definition itself, in case a future SketchUp release
        #      starts promoting model-level dictionaries
        #   2. component instances directly in the root
        #   3. a bounded recursive sweep, for models where the carrier ended up
        #      nested inside a group or component
        #
        # Returns the entity that owns the payload dictionary, or nil.
        def self.Na__SceneDataTransfer__FindPayloadEntity(loaded_definition)
            return nil unless loaded_definition

            codec = Na__SceneDataTransfer__Codec
            return loaded_definition if codec.Na__SceneDataTransfer__HasPayload(loaded_definition)

            found = na_scan_entities_for_payload(loaded_definition.entities, 0, {})
            found
        rescue => error
            puts "[Na__SceneDataTransfer] Payload entity search error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Depth-Limited Sweep for a Payload-Bearing Definition
        # ------------------------------------------------------------
        def self.na_scan_entities_for_payload(entities, depth, visited_definitions)
            return nil if entities.nil?
            return nil if depth > NA_MAX_SEARCH_DEPTH

            codec         = Na__SceneDataTransfer__Codec
            nested_holders = []

            entities.each do |entity|
                definition = na_definition_for(entity)
                next unless definition

                definition_id = definition.entityID
                next if visited_definitions.key?(definition_id)

                visited_definitions[definition_id] = true

                return definition if codec.Na__SceneDataTransfer__HasPayload(definition)

                nested_holders << definition
            end

            nested_holders.each do |definition|                                     # <-- Breadth first, so the root wins over deep nesting
                found = na_scan_entities_for_payload(definition.entities, depth + 1, visited_definitions)
                return found if found
            end

            nil
        end
        private_class_method :na_scan_entities_for_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Definition Behind an Instance or Group
        # ------------------------------------------------------------
        def self.na_definition_for(entity)
            return nil unless entity

            return entity.definition if entity.is_a?(Sketchup::ComponentInstance)
            return entity.definition if entity.is_a?(Sketchup::Group) && entity.respond_to?(:definition)

            nil
        rescue
            nil
        end
        private_class_method :na_definition_for
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Construction Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Carrier Definition With Its Anchor Edge
        # ------------------------------------------------------------
        def self.na_create_carrier_definition(model)
            definition             = model.definitions.add(Na__SceneDataTransfer__Schema::NA_CARRIER_DEFINITION_NAME)
            definition.description = 'Serialised scene data written by Na Noble3d Tools. Do not delete or explode.'

            anchor_edge        = definition.entities.add_line(NA_ANCHOR_START, NA_ANCHOR_END)
            anchor_edge.hidden = true if anchor_edge

            definition
        rescue => error
            puts "[Na__SceneDataTransfer] Carrier definition build error: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_create_carrier_definition
        # ------------------------------------------------------------

        # HELPER FUNCTION | Guarantee Exactly One Hidden Locked Instance in the Root
        # ------------------------------------------------------------
        def self.na_ensure_carrier_instance(model, definition)
            instance = definition.instances.find { |candidate| candidate.valid? }
            instance = model.entities.add_instance(definition, Geom::Transformation.new) if instance.nil?
            return nil unless instance

            instance.name   = Na__SceneDataTransfer__Schema::NA_CARRIER_INSTANCE_NAME if instance.respond_to?(:name=)
            instance.hidden = true
            instance.locked = true
            instance
        rescue => error
            puts "[Na__SceneDataTransfer] Carrier instance warning: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_ensure_carrier_instance
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__Carrier
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
