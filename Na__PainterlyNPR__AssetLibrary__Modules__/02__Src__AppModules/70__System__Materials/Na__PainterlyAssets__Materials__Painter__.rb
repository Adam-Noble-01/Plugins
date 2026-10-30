# =============================================================================
# NA PAINTERLYNPR ASSETS - MATERIALS - PAINTER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Materials__Painter__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__MaterialPainter
# PURPOSE    : What a click on a swatch does, by the selection:
#                faces selected          - those faces take it
#                groups or components    - every face inside them, at every
#                                          depth, takes it; glass is kept
#                nothing (or only edges) - SketchUp's Paint Bucket picks it up
# CREATED    : 30-Oct-2026
#
# WHY FACES, NOT THE GROUP:
#   TrueVision's GLB builder (Sync Aura exports through it) reads each face's
#   own material and nothing it inherits: a painted group exports as Default.
#   So painting an object here paints its faces.
#
# THE RULES (Adam, 30-Oct-2026: "Paint faces inside, keep glass"):
#   - Inside a group or component a face already glass (named like glass, or
#     see-through: Na__MaterialPalette's test) keeps it, so a window's panes
#     survive the frame's swatch. The Glass swatch repaints glass too. A face
#     selected on its own always takes the swatch.
#   - Front and back as Paint Deep Nested Faces (Noble 3D Tools): an opaque
#     swatch paints the front and clears the back; a see-through one both.
#   - A component's copies share its faces: every copy changes, as SketchUp's
#     own paint inside a component does; the status line says how many.
#   - Left alone: edges, locked groups and components, and PainterlyNPR assets
#     (a definition stamped with an AssetId: Write SKP would save it repainted).
#
# COORDINATES:
#   None: materials only, reached through each container's definition.
#
# UNDO CONTRACT:
#   One click, one operation ("PainterlyNPR Assets: Paint Brick"); making the
#   swatch's material joins it. Arming the Paint Bucket opens one only when
#   the material had to be made or put right.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__MaterialPainter

        NA_MAX_DEPTH = 64 unless defined?(NA_MAX_DEPTH)                                                   # <-- Hard stop for pathological nesting

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # @return [Hash] { 'ok', 'level', 'message' }
        def self.Na__Painter__Apply(swatch_key, model = Sketchup.active_model)
            return self.na_result(false, 'error', 'No SketchUp model is open.') unless model
            swatch = Na__MaterialPalette.Na__Palette__Find(swatch_key)
            return self.na_result(false, 'error', "#{swatch_key} is not one of the swatches: Read the Library Again in Settings.") unless swatch

            faces, containers = self.na_split_selection(model.selection)
            return self.na_arm(model, swatch) if faces.empty? && containers.empty?

            self.na_paint(model, swatch, faces, containers)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Two Paths
    # -------------------------------------------------------------------------

        def self.na_arm(model, swatch)
            material = model.materials[swatch['name']]
            unless Na__MaterialPalette.Na__Palette__MaterialMatches?(material, swatch)
                material = self.na_with_operation(model, "PainterlyNPR Assets: Add #{swatch['label']} Swatch") { Na__MaterialPalette.Na__Palette__EnsureMaterial(model, swatch) }
            end
            model.materials.current = material
            Sketchup.send_action('selectPaintTool:')
            self.na_result(true, 'success', "The Paint Bucket has #{swatch['label']} (#{swatch['name']}): click faces to paint them. For a whole group or component, select it and click the swatch instead.")
        end

        def self.na_paint(model, swatch, faces, containers)
            walk = self.na_collect(faces, containers, swatch['glass'] ? nil : Na__MaterialPalette.Na__Palette__GlassTest)
            stats = walk['stats']
            return self.na_result(false, 'warn', "Nothing to paint: #{self.na_left_alone(stats, walk['kept'])}") if walk['faces'].empty?

            painted = self.na_with_operation(model, "PainterlyNPR Assets: Paint #{swatch['label']}") do
                material = Na__MaterialPalette.Na__Palette__EnsureMaterial(model, swatch)
                both     = material.alpha.to_f < 0.999 || material.use_alpha?
                walk['faces'].count { |face| self.na_paint_face(face, material, both) }
            end

            parts = ["Painted #{self.na_count(painted)} of #{self.na_count(walk['faces'].length)} faces #{swatch['label']} (#{swatch['name']})"]
            parts << "in #{self.na_count(stats['containers'])} groups and components" if stats['containers'] > 0
            message = parts.join(' ') + '.'
            message += " Kept #{self.na_count(walk['kept'])} glass faces." if walk['kept'] > 0
            message += " #{stats['shared']} of them are shared by #{stats['copies']} copies: every copy took it." if stats['shared'] > 0
            left = self.na_left_alone(stats, 0)
            message += " Left alone: #{left}" unless left.empty?
            self.na_result(true, 'success', message)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_split_selection(selection)
            faces      = []
            containers = []
            selection.each do |entity|
                next unless entity.valid?
                if entity.is_a?(Sketchup::Face)
                    faces << entity
                elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    containers << entity
                end
            end
            [faces, containers]
        end

        # Reads only; the model is changed later, inside the operation.
        def self.na_collect(faces, containers, glass_test)
            found = {}.compare_by_identity
            seen  = {}.compare_by_identity
            stats = { 'containers' => 0, 'locked' => 0, 'assets' => 0, 'shared' => 0, 'copies' => 0, 'kept' => 0 }
            faces.each { |face| found[face] = true }
            containers.each { |container| self.na_walk(container, glass_test, found, seen, stats, 0) }
            { 'faces' => found.keys, 'kept' => stats['kept'], 'stats' => stats }
        end

        def self.na_walk(container, glass_test, found, seen, stats, depth)
            if container.locked?
                stats['locked'] += 1
                return
            end
            definition = container.definition
            return if seen[definition] || depth > NA_MAX_DEPTH
            seen[definition] = true
            unless definition.get_attribute(Na__Catalogue::NA_ASSET_DICT, 'AssetId').to_s.empty?
                stats['assets'] += 1
                return
            end

            stats['containers'] += 1
            copies = definition.instances.length
            if copies > 1
                stats['shared'] += 1
                stats['copies'] += copies
            end
            definition.entities.each do |entity|
                next unless entity.valid?
                if entity.is_a?(Sketchup::Face)
                    next if found[entity]
                    if glass_test && [entity.material, entity.back_material].any? { |material| material && glass_test.call(material) }
                        stats['kept'] += 1
                        next
                    end
                    found[entity] = true
                elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    self.na_walk(entity, glass_test, found, seen, stats, depth + 1)
                end
            end
        end

        # @return [Boolean] whether the face changed
        def self.na_paint_face(face, material, both)
            changed = false
            unless face.material == material
                face.material = material
                changed = true
            end
            back = both ? material : nil
            unless face.back_material == back
                face.back_material = back
                changed = true
            end
            changed
        end

        def self.na_left_alone(stats, kept)
            parts = []
            parts << "#{stats['locked']} locked" if stats['locked'] > 0
            parts << "#{stats['assets']} PainterlyNPR assets" if stats['assets'] > 0
            parts << "#{kept} glass faces kept" if kept > 0
            parts.empty? ? '' : parts.join(', ') + '.'
        end

        # The operation this helper opened, and only it, aborts on anything.
        def self.na_with_operation(model, name)
            operation_started = false
            model.start_operation(name, true)
            operation_started = true
            result = yield
            model.commit_operation
            result
        rescue Exception
            model.abort_operation if operation_started
            raise
        end

        def self.na_count(number)
            number.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
        end

        def self.na_result(ok, level, message)
            { 'ok' => ok, 'level' => level, 'message' => message }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
