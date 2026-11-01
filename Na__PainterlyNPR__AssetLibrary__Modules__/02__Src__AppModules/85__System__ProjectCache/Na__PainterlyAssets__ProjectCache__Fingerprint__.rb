# =============================================================================
# NA PAINTERLYNPR ASSETS - PROJECT CACHE - FINGERPRINT
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ProjectCache__Fingerprint__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__Fingerprint
# PURPOSE    : A digest of everything the GLB builder would write for one export
#              unit (one tag group, or one storey's element): so the cache knows
#              which GLBs a change made stale, and exports only those.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - WHAT COUNTS is what reaches the GLB: every face's corners, tag, materials
#   (name, colour, opacity) and hidden flag; every edge's ends and its soft,
#   smooth and hidden flags; every group's and component's transformation,
#   tag, material, name and persistent id (an instanced component's node is
#   named by it), down to the last nested definition. Text, dimensions and
#   guides never reach a GLB and are left out.
# - DEFINITIONS ARE DIGESTED ONCE: a component placed a hundred times costs one
#   walk. The digests are kept between syncs (per model) and only the
#   definitions a change can have touched are forgotten (Na__Fp__Forget): the
#   ones the open context ran through, the selection's, and every definition
#   that holds one of them, however deep. Undo, redo, Refresh and turning live
#   updates back on forget them all.
# - POSITIONS ARE LOCAL, so a fingerprint is taken only with no group open
#   (SketchUp reports an open context's entities in world coordinates). The
#   sync refuses to run otherwise.
# - Read only: nothing here changes the model.
#
# =============================================================================

require 'digest'

module Na__PainterlyAssets
    module Na__Fingerprint

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        @na_memo = {} unless defined?(@na_memo)                                    # <-- model key => { definition persistent id => digest }

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | One Export Unit's Fingerprint: a hex digest
        # ------------------------------------------------------------
        # @param unit [Hash] { 'Key', 'Files', 'Entities', 'Transform' (a storey's, or nil) }
        def self.Na__Fp__Unit(model, unit)
            memo   = self.na_memo_for(model)
            digest = Digest::SHA256.new
            digest << "unit|#{unit['Key']}|#{Array(unit['Files']).sort.join(',')}\n"
            digest << "storey|#{self.na_matrix(unit['Transform'])}\n" if unit['Transform']
            Array(unit['Entities']).each { |entity| digest << self.na_entity(entity, memo) }
            digest.hexdigest
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Digests a Change Can Have Touched
        # ------------------------------------------------------------
        # @param definitions [Array<Sketchup::ComponentDefinition>] edited ones
        # @return [Integer] how many digests were forgotten
        def self.Na__Fp__Forget(model, definitions)
            memo  = self.na_memo_for(model)
            seen  = {}
            queue = Array(definitions).compact.dup
            until queue.empty?
                definition = queue.shift
                next unless definition.respond_to?(:instances) && definition.valid?
                key = definition.persistent_id
                next if seen[key]
                seen[key] = true
                memo.delete(key)
                definition.instances.each do |instance|
                    parent = instance.parent
                    queue << parent if parent.is_a?(Sketchup::ComponentDefinition)   # <-- Every definition that holds this one, however deep
                end
            end
            seen.length
        end
        # ---------------------------------------------------------------

        # The definitions inside an instance, all the way down (the selection's
        # contents, painted by a tool from outside: the Materials tab does)
        def self.Na__Fp__Nested(instances)
            found = {}
            queue = Array(instances).select { |e| e.respond_to?(:definition) }.map(&:definition)
            until queue.empty?
                definition = queue.shift
                next if found[definition.persistent_id]
                found[definition.persistent_id] = definition
                definition.entities.each { |e| queue << e.definition if e.respond_to?(:definition) }
            end
            found.values
        end

        def self.Na__Fp__ForgetAll(model = nil)
            model ? @na_memo.delete(self.na_model_key(model)) : @na_memo.clear
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - the Walk
    # -------------------------------------------------------------------------

        def self.na_memo_for(model)
            @na_memo[self.na_model_key(model)] ||= {}
        end

        def self.na_model_key(model)
            model.respond_to?(:guid) ? model.guid.to_s : model.object_id.to_s
        end

        # One entity's line in its parent's digest (binary: corners go in packed,
        # not printed, which keeps a big definition's walk cheap)
        def self.na_entity(entity, memo)
            case entity
            when Sketchup::Group, Sketchup::ComponentInstance
                "i|#{entity.persistent_id}|#{entity.name}|#{self.na_layer(entity)}|#{self.na_material(entity.material)}|#{entity.hidden? ? 1 : 0}|" \
                    "#{self.na_matrix(entity.transformation)}|#{self.na_definition(entity.definition, memo)}\n".b
            when Sketchup::Face
                line = "f|#{self.na_layer(entity)}|#{self.na_material(entity.material)}|#{self.na_material(entity.back_material)}|#{entity.hidden? ? 1 : 0}|".b
                line << entity.vertices.map { |v| v.position.to_a }.flatten.pack('E*') << "\n"
            when Sketchup::Edge
                line = "e|#{self.na_layer(entity)}|#{entity.soft? ? 1 : 0}#{entity.smooth? ? 1 : 0}#{entity.hidden? ? 1 : 0}|#{self.na_material(entity.material)}|".b
                line << (entity.start.position.to_a + entity.end.position.to_a).pack('E*') << "\n"
            else
                ''.b
            end
        end

        # A definition's digest, walked once and kept until it is forgotten
        def self.na_definition(definition, memo)
            key = definition.persistent_id
            return memo[key] if memo.key?(key)
            digest = Digest::SHA256.new
            digest << "d|#{definition.name}\n"
            definition.entities.each { |entity| digest << self.na_entity(entity, memo) }
            memo[key] = digest.hexdigest
        end

        def self.na_layer(entity)
            layer = entity.respond_to?(:layer) ? entity.layer : nil
            layer ? layer.name : ''
        end

        def self.na_material(material)
            return '-' unless material
            color   = material.color
            texture = material.respond_to?(:texture) && material.texture ? material.texture.filename.to_s : ''
            "#{material.name}:#{color.red},#{color.green},#{color.blue}:#{material.alpha.round(3)}:#{texture}"
        end

        def self.na_matrix(transformation)
            return '-' unless transformation
            transformation.to_a.map { |v| v.to_f.round(9) }.join(',')
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
