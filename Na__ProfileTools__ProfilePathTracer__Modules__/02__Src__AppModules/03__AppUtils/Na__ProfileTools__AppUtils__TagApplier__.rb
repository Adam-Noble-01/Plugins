# =============================================================================
# NA PROFILE TOOLS - APP UTILS - TAG APPLIER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppUtils__TagApplier__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__TagApplier
# PURPOSE    : Shared helper for resolving, creating, and applying SketchUp
#              tags (layers) from the Na__DataLib__CoreIndex__Tags__.json data.
#              Reads Tag__LineStyle__Config and Tag__EdgeMaterial__Config schema
#              keys, with Layout__LineStyleName / Layout__EdgeColourRGB fallback.
#
# PUBLIC API:
#   Na__TagApplier__EnsureTagFromDataLib(model, tag_name)
#       Resolves or creates the Sketchup::Layer for tag_name, sets its line
#       style from Tag__LineStyle__Config and its colour from the MTE entry
#       referenced by Tag__EdgeMaterial__Config. Returns the layer or nil.
#
#   Na__TagApplier__ApplyTagToEntity(entity, layer)
#       Assigns a pre-resolved Sketchup::Layer to a single entity.
#
#   Na__TagApplier__ApplyTagToEntities(entities_or_array, layer)
#       Assigns a pre-resolved Sketchup::Layer to every entity in a collection.
#
#   Na__TagApplier__PaintEdgesWithMteMaterial(model, edges, mte_id)
#       Delegates to Na__EdgeColourManager to get/create a material by MTE id
#       then assigns it to every edge in the array.
#
#   Na__TagApplier__FindTagEntryByName(tag_name)
#       Recursive DataLib lookup — DRY delegate used by Na__ProfileExporter.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__TagApplier

    # -------------------------------------------------------------------------
    # REGION | Public - Tag Resolution + Creation
    # -------------------------------------------------------------------------

        def self.Na__TagApplier__EnsureTagFromDataLib(model, tag_name)
            return nil unless model && tag_name.is_a?(String) && !tag_name.empty?

            layer = model.layers[tag_name] || model.layers.add(tag_name)
            layer.visible = true if layer.respond_to?(:visible=)

            tag_entry = self.Na__TagApplier__FindTagEntryByName(tag_name)
            self.Na__TagApplier__ApplyLineStyleToLayer(model, layer, tag_entry)
            self.Na__TagApplier__ApplyColourToLayer(model, layer, tag_entry)

            layer
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__TagApplier: tag setup failed for '#{tag_name}': #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Tag Assignment
    # -------------------------------------------------------------------------

        def self.Na__TagApplier__ApplyTagToEntity(entity, layer)
            return unless entity && layer
            return unless entity.respond_to?(:layer=)
            entity.layer = layer
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__TagApplier: entity tag assignment failed: #{error.message}")
        end

        def self.Na__TagApplier__ApplyTagToEntities(entities_or_array, layer)
            return unless layer
            Array(entities_or_array).each do |entity|
                self.Na__TagApplier__ApplyTagToEntity(entity, layer)
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Edge Material Painting
    # -------------------------------------------------------------------------

        def self.Na__TagApplier__PaintEdgesWithMteMaterial(model, edges, mte_id)
            return unless model && mte_id.is_a?(String) && !mte_id.empty?
            material = self.Na__TagApplier__ResolveMteMaterial(model, mte_id)
            return unless material

            Array(edges).each do |edge|
                next unless edge && edge.respond_to?(:material=)
                edge.material = material
            rescue => error
                Na__DebugTools.Na__Debug__Warn("Na__TagApplier: edge paint failed: #{error.message}")
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - DataLib Tag Lookup (shared with Na__ProfileExporter)
    # -------------------------------------------------------------------------

        # @delegate: ../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__
        def self.Na__TagApplier__FindTagEntryByName(target_tag_name)
            data = Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
            return nil unless data.is_a?(Hash)

            tags_root = data['Na__DataLib__CoreIndex__Tags']
            return nil unless tags_root.is_a?(Hash)

            self.Na__TagApplier__FindTagNodeRecursive(tags_root, target_tag_name)
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - DataLib Recursive Walker
    # -------------------------------------------------------------------------

        def self.Na__TagApplier__FindTagNodeRecursive(node, target_tag_name)
            return nil unless node.is_a?(Hash)

            node.each_value do |value|
                next unless value.is_a?(Hash)
                return value if value['Tag__SketchUpName'].to_s == target_tag_name

                nested = self.Na__TagApplier__FindTagNodeRecursive(value, target_tag_name)
                return nested if nested
            end

            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Layer Attribute Writers
    # -------------------------------------------------------------------------

        def self.Na__TagApplier__ApplyLineStyleToLayer(model, layer, tag_entry)
            return unless tag_entry && layer.respond_to?(:line_style=) && model.respond_to?(:line_styles)

            line_style_name = tag_entry['Tag__LineStyle__Config'].to_s
            line_style_name = tag_entry['Layout__LineStyleName'].to_s if line_style_name.empty?
            return if line_style_name.empty?

            styles = model.line_styles
            style = styles[line_style_name] if styles.respond_to?(:[])
            layer.line_style = style if style
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__TagApplier: line style application failed: #{error.message}")
        end

        def self.Na__TagApplier__ApplyColourToLayer(model, layer, tag_entry)
            return unless tag_entry && layer.respond_to?(:color=)

            mte_id = tag_entry['Tag__EdgeMaterial__Config'].to_s
            unless mte_id.empty?
                rgb = self.Na__TagApplier__RgbFromMteId(model, mte_id)
                if rgb
                    layer.color = Sketchup::Color.new(*rgb)
                    return
                end
            end

            legacy_rgb = tag_entry['Layout__EdgeColourRGB']
            if legacy_rgb.is_a?(Array) && legacy_rgb.length == 3
                layer.color = Sketchup::Color.new(*legacy_rgb.map(&:to_i))
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__TagApplier: colour application failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - MTE Material Helpers
    # -------------------------------------------------------------------------

        def self.Na__TagApplier__ResolveMteMaterial(model, mte_id)
            if defined?(Na__EdgeColourManager) &&
               Na__EdgeColourManager.respond_to?(:Na__EdgeColours__EnsureSketchUpMaterial)
                result = Na__EdgeColourManager.Na__EdgeColours__EnsureSketchUpMaterial(model, mte_id)
                return result if result
            end

            self.Na__TagApplier__FallbackMaterialFromMteId(model, mte_id)
        end

        def self.Na__TagApplier__RgbFromMteId(model, mte_id)
            if defined?(Na__EdgeColourManager) &&
               Na__EdgeColourManager.respond_to?(:Na__EdgeColours__GetEntryByName)
                entry = Na__EdgeColourManager.Na__EdgeColours__GetEntryByName(mte_id)
                if entry.is_a?(Hash)
                    r = entry['R'].to_i
                    g = entry['G'].to_i
                    b = entry['B'].to_i
                    return [r, g, b] if r > 0 || g > 0 || b > 0
                end
            end
            nil
        end

        def self.Na__TagApplier__FallbackMaterialFromMteId(model, mte_id)
            material = model.materials[mte_id] || model.materials.add(mte_id)
            material
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
