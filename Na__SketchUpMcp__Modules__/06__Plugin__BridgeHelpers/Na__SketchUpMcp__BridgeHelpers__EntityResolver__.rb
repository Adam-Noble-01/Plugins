# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - ENTITY RESOLVER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__EntityResolver__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__EntityResolver
# PURPOSE    : Turn the ids, names and colour strings agents send into live
#              SketchUp objects, refusing clearly when they do not resolve
# CREATED    : 2026
#
# IDS ARE PERSISTENT IDS:
# Every entity is addressed by Entity#persistent_id (SketchUp 2017+). It is
# saved with the model, so an id an agent read an hour ago still names the same
# face after the user saves and reopens. Lookups go through
# Model#find_entity_by_persistent_id.
#
# MATERIALS AND TAGS BY NAME:
# - material "none" / ""       -> the default material (nil)
# - material "#RRGGBB"         -> a material of that colour, reused by name
# - material any other string  -> must exist (Material#name, the internal name)
# - tag "Untagged" / "" / "Layer0" -> Layer0 (displayed as Untagged since 2020)
# - tag any other string       -> reused, or created when the tool allows it
#
# =============================================================================

module Na__SketchUpMcp
    module Na__EntityResolver

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_HEX_COLOUR = /\A#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})\z/i.freeze
        NA_UNTAGGED_NAMES = ['', 'untagged', 'layer0'].freeze
        NA_NO_MATERIAL_NAMES = ['', 'none', 'default', 'nil'].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Lookup by Persistent Id
# -----------------------------------------------------------------------------

        def self.Na__EntityResolver__Find(model, persistent_id)
            return nil if persistent_id.nil?

            entity = model.find_entity_by_persistent_id(persistent_id.to_i)
            entity.is_a?(Array) ? entity.first : entity
        rescue ArgumentError, TypeError
            nil
        end

        def self.Na__EntityResolver__RequireEntity(model, persistent_id, label = 'id')
            entity = self.Na__EntityResolver__Find(model, persistent_id)
            return entity if entity && entity.valid?

            raise Na__McpError.new('not_found', "No entity with #{label} #{persistent_id}.",
                                   'Ids are persistent ids from entity_query, outliner_tree or selection_get. ' \
                                   'An id stops existing when its entity is erased or exploded; query again.')
        end

        def self.Na__EntityResolver__RequireEntities(model, ids, label = 'ids')
            unless ids.is_a?(Array) && !ids.empty?
                raise Na__McpError.new('invalid_params', "#{label} must be a non-empty array of persistent ids.",
                                       'Get ids from entity_query, outliner_tree or selection_get.')
            end

            limit = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'max_ids_per_call', 2000).to_i
            if ids.length > limit
                raise Na__McpError.new('invalid_params', "#{label} has #{ids.length} entries; the limit is #{limit} per call.",
                                       'Split the work across several calls, or act on a parent group instead.')
            end

            found = ids.map { |persistent_id| [persistent_id, self.Na__EntityResolver__Find(model, persistent_id)] }
            missing = found.select { |_persistent_id, entity| entity.nil? || !entity.valid? }.map(&:first)
            unless missing.empty?
                raise Na__McpError.new('not_found', "No entity for #{label}: #{missing.first(20).join(', ')}#{missing.length > 20 ? ' ...' : ''}.",
                                       'Query again with entity_query; erased or exploded entities lose their ids.',
                                       { 'missing_ids' => missing })
            end
            found.map(&:last).uniq
        end

        def self.Na__EntityResolver__RequireInstance(model, persistent_id, label = 'id')
            entity = self.Na__EntityResolver__RequireEntity(model, persistent_id, label)
            return entity if self.Na__EntityResolver__IsInstance(entity)

            raise Na__McpError.new('wrong_type', "#{label} #{persistent_id} is a #{self.Na__EntityResolver__TypeName(entity)}, not a Group or ComponentInstance.",
                                   'Wrap loose geometry with group_create first, or pass the id of the group that contains it.')
        end

        def self.Na__EntityResolver__RequireOfClass(model, persistent_id, klass, label = 'id')
            entity = self.Na__EntityResolver__RequireEntity(model, persistent_id, label)
            return entity if entity.is_a?(klass)

            expected = klass.name.split('::').last
            raise Na__McpError.new('wrong_type', "#{label} #{persistent_id} is a #{self.Na__EntityResolver__TypeName(entity)}, not a #{expected}.",
                                   "Pass the id of a #{expected} (entity_query with types: [\"#{expected}\"] lists them).")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Facts
# -----------------------------------------------------------------------------

        def self.Na__EntityResolver__IsInstance(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end

        def self.Na__EntityResolver__TypeName(entity)
            entity.class.name.split('::').last
        end

        # Instance name, falling back to the definition name for components.
        def self.Na__EntityResolver__DisplayName(entity)
            name = entity.respond_to?(:name) ? entity.name.to_s : ''
            return name unless name.empty?
            return entity.definition.name.to_s if entity.is_a?(Sketchup::ComponentInstance)

            ''
        end

        def self.Na__EntityResolver__InstanceEntities(instance)
            instance.definition.entities
        end

        def self.Na__EntityResolver__ParentEntities(entity)
            parent = entity.parent
            parent.respond_to?(:entities) ? parent.entities : nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Colours
# -----------------------------------------------------------------------------

        # "#RRGGBB", [r, g, b], [r, g, b, a] or a SketchUp colour name -> Sketchup::Color
        def self.Na__EntityResolver__ParseColour(specification, label = 'color')
            case specification
            when Array
                unless specification.length.between?(3, 4) && specification.all? { |value| value.is_a?(Numeric) }
                    raise Na__McpError.new('invalid_params', "#{label} array must be [r, g, b] or [r, g, b, a] with 0-255 values.", nil)
                end

                Sketchup::Color.new(*specification.map { |value| value.to_i.clamp(0, 255) })
            when String
                hex = NA_HEX_COLOUR.match(specification.strip)
                return Sketchup::Color.new(hex[1].to_i(16), hex[2].to_i(16), hex[3].to_i(16)) if hex

                named = Sketchup::Color.names.find { |name| name.casecmp?(specification.strip) }
                return Sketchup::Color.new(named) if named

                raise Na__McpError.new('invalid_params', "#{label} '#{specification}' is not a colour I can read.",
                                       'Use "#RRGGBB" (e.g. "#C8B89A"), [r, g, b] or a SketchUp colour name such as "White".')
            else
                raise Na__McpError.new('invalid_params', "#{label} must be \"#RRGGBB\", [r, g, b] or a colour name.", nil)
            end
        end

        def self.Na__EntityResolver__ColourToHex(colour)
            return nil if colour.nil?

            format('#%02X%02X%02X', colour.red, colour.green, colour.blue)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Materials
# -----------------------------------------------------------------------------

        def self.Na__EntityResolver__IsNoMaterial(specification)
            specification.nil? || NA_NO_MATERIAL_NAMES.include?(specification.to_s.strip.downcase)
        end

        # Returns a Sketchup::Material, or nil for "none". Hex colours are created on demand.
        def self.Na__EntityResolver__ResolveMaterial(model, specification, warnings = nil)
            return nil if self.Na__EntityResolver__IsNoMaterial(specification)

            name = specification.to_s.strip
            existing = model.materials[name]
            return existing if existing

            hex = NA_HEX_COLOUR.match(name)
            if hex
                material_name = "##{hex[1]}#{hex[2]}#{hex[3]}".upcase
                reused = model.materials[material_name]
                return reused if reused

                material = model.materials.add(material_name)
                material.color = self.Na__EntityResolver__ParseColour(material_name)
                warnings << "Created material '#{material.name}'." if warnings
                return material
            end

            by_display = model.materials.find { |material| material.display_name.casecmp?(name) }
            return by_display if by_display

            close = model.materials.map(&:name).select { |candidate| candidate.downcase.include?(name.downcase) }.first(8)
            raise Na__McpError.new('not_found', "No material named '#{name}'.",
                                   close.empty? ? 'Create it with material_manage, pass "#RRGGBB" for a plain colour, or list them with collection_list collection="materials".' :
                                                  "Did you mean: #{close.join(', ')}?")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tags (Layers)
# -----------------------------------------------------------------------------

        def self.Na__EntityResolver__IsUntagged(name)
            NA_UNTAGGED_NAMES.include?(name.to_s.strip.downcase)
        end

        def self.Na__EntityResolver__ResolveTag(model, name, create_missing, warnings = nil)
            return model.layers[0] if self.Na__EntityResolver__IsUntagged(name)

            tag_name = name.to_s.strip
            existing = model.layers[tag_name]
            return existing if existing

            unless create_missing
                raise Na__McpError.new('not_found', "No tag named '#{tag_name}'.",
                                       'Create it with tag_manage action="create", or list tags with collection_list collection="tags".')
            end

            warnings << "Created tag '#{tag_name}'." if warnings
            model.layers.add(tag_name)
        end

        def self.Na__EntityResolver__TagDisplayName(layer)
            return nil if layer.nil?

            layer.respond_to?(:display_name) ? layer.display_name : layer.name
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Component Definitions
# -----------------------------------------------------------------------------

        # name_or_id: a definition name (String) or a persistent id (Integer).
        def self.Na__EntityResolver__ResolveDefinition(model, name_or_id, label = 'definition')
            if name_or_id.is_a?(Integer)
                return self.Na__EntityResolver__RequireOfClass(model, name_or_id, Sketchup::ComponentDefinition, label)
            end

            definition = model.definitions[name_or_id.to_s]
            return definition if definition && !definition.group? && !definition.image?

            close = model.definitions.reject { |candidate| candidate.group? || candidate.image? }
                                     .map(&:name).select { |candidate| candidate.downcase.include?(name_or_id.to_s.downcase) }.first(8)
            raise Na__McpError.new('not_found', "No component definition named '#{name_or_id}'.",
                                   close.empty? ? 'List definitions with collection_list collection="definitions", or load a .skp with component_place skp_path.' :
                                                  "Did you mean: #{close.join(', ')}?")
        end

# endregion -------------------------------------------------------------------

    end # module Na__EntityResolver
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
