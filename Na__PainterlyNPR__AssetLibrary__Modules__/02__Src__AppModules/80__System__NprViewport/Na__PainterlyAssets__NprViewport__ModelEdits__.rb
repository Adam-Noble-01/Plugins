# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - MODEL EDITS
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__ModelEdits__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__ModelEdits
# PURPOSE    : What the NPR Viewport's Assets drawer does, made in the SketchUp
#              model: a library asset dropped on the drawing placed as a proxy;
#              a plop moved, turned, sized, swapped, grown again or taken out;
#              a material given to a group, a component or one face, painted.
# CREATED    : 03-Nov-2026 (v0.4.0)
#
# DESCRIPTION:
# - Adam, 03-Nov-2026: "Assets need to sync with the SketchUp Model, so when a
#   new material is dragged and assigned it updates the corresponding SketchUp
#   Model, same with dragging in a asset like a plant etc."
# - THE DRAWER IS THE ENGINE'S; this module is only the other end of it. The
#   page compares the engine's lists with what the model last held and sends
#   what moved (HostEditing): Add, Pose, Remove, PlopMaterials, Paint.
# - ONE BATCH, ONE UNDO STEP, named for what it did, and nothing kept when
#   nothing changed. A batch's failure is the edit's own: the rest still land
#   and the page is told which did not, so it takes them back out of the drawing.
# - WHERE A NEW PROXY GOES: the model's root, on the proxy tag
#   (nprViewport.assets.proxyTag: in the GLB builder's skip range, as Sync Aura's
#   are), so its mesh never reaches a GLB and the engine draws the plop alone.
# - WHERE IT LANDS (Adam: the surface under the pointer): the first drawn face
#   the pointer's ray meets, when it faces upward (assets.landUpwardZ), so a pot
#   stands on the patio and a plant on the terrain; otherwise the engine's own
#   ground point, y = 0.
# - WHAT OBJECT PAINTS (Adam: the group under the pointer): every face in the
#   innermost closed group or component the ray meets, by Na__MaterialPainter's
#   own rules (glass kept, locked and PainterlyNPR proxies left alone, every copy
#   of a component changing). Loose geometry paints its connected faces. FACE
#   paints the face the ray meets, and any joined to it across a soft or hidden
#   edge, so a curved wall takes it whole.
# - A RAY PASSES THROUGH what the drawing does not show: the proxies (the engine
#   draws their plops, not their meshes), edges, and whatever the GLB builder
#   leaves out. A hit on a plop's part never comes here: it is the instance's
#   Materials attribute (PlopMaterials), since the engine draws an asset from
#   its generator and its proxy's faces are never painted.
#
# COORDINATES (the coordinate rule, Adam's global CLAUDE.md):
#   Model#raytest, its point and the engine's world are all world. A new proxy
#   is added to model.entities, the root or a parent of any open group, so its
#   transformation is world either way. A proxy that moves is moved by
#   Entities#transform_entities in its parent's terms: parent.inverse * delta *
#   parent, where parent (Na__Proxies__Find) restarts at the identity inside an
#   open group, whose contents report world. Unmeasured inside an open group.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__ModelEdits

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_RAY_STEPS      = 24                 unless defined?(NA_RAY_STEPS)               # <-- How many things a ray may pass through
        NA_RAY_STEP_INCH  = 0.02               unless defined?(NA_RAY_STEP_INCH)           # <-- Past SketchUp's own 0.001 inch tolerance
        NA_SAME_INCH      = 0.04               unless defined?(NA_SAME_INCH)               # <-- About a millimetre: the same place, whatever the rounding
        NA_MAX_JOINED     = 20_000             unless defined?(NA_MAX_JOINED)              # <-- Hard stop for a very large smooth surface
        NA_PROXY_UID      = /\AS(\d+)\z/.freeze unless defined?(NA_PROXY_UID)

        @na_aliases = {} unless defined?(@na_aliases)                                       # <-- A plop's first Uid (A0001) => its proxy's persistent id, for an edit sent before the page had the answer

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Make One Batch From the Page in the Model, Then Answer It
        # ------------------------------------------------------------
        # @param payload [Hash] { 'Seq', 'Edits' => [{ 'Kind', ... }] }
        # The answer always goes, and the live sync is always told, whatever
        # happened: the page holds its own lists until a scene shows this batch.
        def self.Na__Edits__Apply(payload)
            seq     = payload['Seq'].to_i
            edits   = Array(payload['Edits']).select { |edit| edit.is_a?(Hash) }
            model   = Sketchup.active_model
            reply   = { 'Seq' => seq, 'Placed' => {}, 'Poses' => {}, 'FailedPlops' => [], 'FailedPaints' => [], 'Said' => [], 'Level' => 'info' }
            touched = []
            begin
                model ? self.na_run(model, edits, reply, touched) : edits.each { |edit| self.na_failed(edit, reply, 'there is no model') }
            rescue StandardError => error
                Na__DebugTools.Na__Debug__Error('The NPR Viewport\'s edit could not be made in the model.', error)
                edits.each { |edit| self.na_failed(edit, reply, error.message) }
            ensure
                Na__LiveSync.Na__Live__ModelEdited(model, seq, touched)
                Na__NprWindows.Na__Windows__Send('viewport', 'edited', reply)
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | One Batch, One Undo Step
    # -------------------------------------------------------------------------

        def self.na_run(model, edits, reply, touched)
            return if edits.empty?
            placement = Na__LiveSync.Na__Live__Placement(model)
            operation_started = false
            model.start_operation("PainterlyNPR Assets: #{self.na_words(edits)}", true)
            operation_started = true
            made = edits.count { |edit| self.na_one(model, edit, placement, reply, touched) }
            made > 0 ? model.commit_operation : model.abort_operation
            operation_started = false
            Na__Catalogue.Na__Catalogue__RefreshInModel(model) if made > 0 && edits.any? { |edit| edit['Kind'] == 'Add' }
        rescue Exception                                                                    # <-- Anything at all: abort, then raise it on
            model.abort_operation if operation_started
            raise
        end

        # One edit: true when it changed the model. Its failure is its own.
        def self.na_one(model, edit, placement, reply, touched)
            case edit['Kind'].to_s
            when 'Add'           then self.na_add(model, edit, placement, reply)
            when 'Pose'          then self.na_pose(model, edit, placement, reply)
            when 'Remove'        then self.na_remove(model, edit)
            when 'PlopMaterials' then self.na_give_parts(model, edit)
            when 'Paint'         then self.na_paint(model, edit, placement, reply, touched)
            else false
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The NPR Viewport's #{edit['Kind']} of #{edit['Name'] || edit['Uid']} failed: #{error.message}")
            self.na_failed(edit, reply, error.message)
            false
        end

        def self.na_failed(edit, reply, message)
            (edit['Kind'].to_s == 'Paint' ? reply['FailedPaints'] : reply['FailedPlops']) << edit['Uid'].to_s
            reply['Level'] = 'warn'
            reply['Said'] << "#{edit['Name'].to_s.empty? ? edit['Uid'] : edit['Name']} was not changed in SketchUp: #{message}."
        end

        # What the Edit menu's Undo names
        def self.na_words(edits)
            words = edits.map do |edit|
                name = edit['Name'].to_s
                case edit['Kind'].to_s
                when 'Add'           then "Place #{name}"
                when 'Pose'          then "Move #{name}"
                when 'Remove'        then "Remove #{name}"
                when 'PlopMaterials' then "Give #{name} Materials"
                when 'Paint'         then "Paint #{edit['Material']}"
                else 'NPR Viewport Edit'
                end
            end.uniq
            words.length == 1 ? words.first : 'NPR Viewport Edit'
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Plops
    # -------------------------------------------------------------------------

        # A new proxy at the root, where the pointer put it. The page is given
        # its pose, under the persistent id it will be known by from now on.
        def self.na_add(model, edit, placement, reply)
            asset_id   = edit['AssetId'].to_s
            definition = Na__PainterlyAssets.Na__PublicApi__DefinitionForAsset(model, asset_id, in_operation: true)
            foot       = self.na_landing(model, edit['Ray'], placement) || Na__AssetProxies.Na__Proxies__FromEngine(edit['PositionM'], placement)
            turn       = edit['RotationDeg'].to_f - placement['RotationDeg'].to_f
            scale      = edit['Scale'].to_f > 0 ? edit['Scale'].to_f : 1.0
            pose       = Geom::Transformation.translation(ORIGIN.vector_to(foot)) *
                         Geom::Transformation.rotation(ORIGIN, Z_AXIS, turn.degrees) *
                         Geom::Transformation.scaling(ORIGIN, scale, scale, scale)
            instance   = model.entities.add_instance(definition, pose)
            tag        = Na__ConfigLoader.Na__Config__GetOr('', 'nprViewport', 'assets', 'proxyTag').to_s
            instance.layer = model.layers[tag] || model.layers.add(tag) unless tag.empty?
            instance.name  = edit['Name'].to_s unless edit['Name'].to_s.empty?
            self.na_stamp_seed(instance, edit['ShapeSeed']) if edit['ShapeSeed']
            @na_aliases[edit['Uid'].to_s] = instance.persistent_id.to_i
            reply['Placed'][edit['Uid'].to_s] = Na__AssetProxies.Na__Proxies__Pose(instance, instance.transformation, asset_id, placement)
            true
        end

        # A proxy moved, turned, sized, swapped or grown again. Only what moved
        # is changed, as a delta over what it has, so a tipped or squashed proxy
        # keeps its tip and its squash.
        def self.na_pose(model, edit, placement, reply)
            found = self.na_find(model, edit['Uid'])
            raise 'its proxy is no longer in the model' unless found
            instance = found['instance']
            parent   = found['parent']
            dict     = Na__Catalogue::NA_ASSET_DICT
            asset_id = instance.definition.get_attribute(dict, 'AssetId').to_s
            wanted   = edit['AssetId'].to_s
            unless wanted.empty? || wanted == asset_id
                raise 'a group cannot be swapped for another asset' unless instance.is_a?(Sketchup::ComponentInstance)
                instance.definition = Na__PainterlyAssets.Na__PublicApi__DefinitionForAsset(model, wanted, in_operation: true)
                instance.name = edit['Name'].to_s unless edit['Name'].to_s.empty?
                asset_id = wanted
            end
            self.na_stamp_seed(instance, edit['ShapeSeed']) if edit['ShapeSeed']
            self.na_move(instance, parent, edit, placement)
            reply['Poses'][edit['Uid'].to_s] = Na__AssetProxies.Na__Proxies__Pose(instance, parent * instance.transformation, asset_id, placement)
            true
        end

        def self.na_move(instance, parent, edit, placement)
            world = parent * instance.transformation
            now   = Na__AssetProxies.Na__Proxies__Pose(instance, world, '', placement)
            m     = world.to_a.map(&:to_f)
            w     = m[15].abs > 1e-9 ? m[15] : 1.0
            from  = Geom::Point3d.new(m[12] / w, m[13] / w, m[14] / w)
            to    = Na__AssetProxies.Na__Proxies__FromEngine(edit['PositionM'], placement)
            to    = from if from.distance(to) < NA_SAME_INCH
            turn  = edit['RotationDeg'].to_f - now['RotationDeg'].to_f
            size  = now['Scale'].to_f > 0 && edit['Scale'].to_f > 0 ? edit['Scale'].to_f / now['Scale'].to_f : 1.0
            still = to == from && turn.abs < 0.01 && (size - 1.0).abs < 0.0005
            return if still
            delta = Geom::Transformation.translation(ORIGIN.vector_to(to)) *
                    Geom::Transformation.rotation(ORIGIN, Z_AXIS, turn.degrees) *
                    Geom::Transformation.scaling(ORIGIN, size, size, size) *
                    Geom::Transformation.translation(from.vector_to(ORIGIN))
            instance.parent.entities.transform_entities(parent.inverse * delta * parent, instance)
        end

        def self.na_remove(model, edit)
            found = self.na_find(model, edit['Uid'])
            return false unless found                                                       # <-- Already gone
            instance = found['instance']
            raise 'it is open for editing, so close it first' if Array(model.active_path).include?(instance)
            instance.erase!
            true
        end

        # What the page gave a plop's parts, kept on the instance: the engine's
        # to draw, and a copy made in SketchUp carries them with it.
        def self.na_give_parts(model, edit)
            found = self.na_find(model, edit['Uid'])
            raise 'its proxy is no longer in the model' unless found
            instance = found['instance']
            dict     = Na__Catalogue::NA_ASSET_DICT
            parts    = Array(edit['Materials']).select { |part| part.is_a?(Hash) }.map { |part| { 'Part' => part['Part'].to_s, 'Face' => part['Face'], 'Material' => part['Material'].to_s } }
            if parts.empty?
                instance.delete_attribute(dict, Na__AssetProxies::NA_PARTS_ATTR)
            else
                instance.set_attribute(dict, Na__AssetProxies::NA_PARTS_ATTR, JSON.generate(parts))
            end
            true
        end

        def self.na_stamp_seed(instance, seed)
            dict = Na__Catalogue::NA_ASSET_DICT
            instance.set_attribute(dict, Na__AssetProxies::NA_SEED_ATTR, seed.to_i.to_s)
            instance.set_attribute(dict, Na__AssetProxies::NA_SEED_FOR, instance.persistent_id.to_s)
        end

        # A Uid as a proxy: S<persistent id>, or the Uid it had before it was placed
        def self.na_find(model, uid)
            match = NA_PROXY_UID.match(uid.to_s)
            pid   = match ? match[1].to_i : @na_aliases[uid.to_s]
            pid ? Na__AssetProxies.Na__Proxies__Find(model, pid) : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Materials
    # -------------------------------------------------------------------------

        def self.na_paint(model, edit, placement, reply, touched)
            swatch = Na__MaterialPalette.Na__Palette__FindClass(edit['Material'])
            raise "the materials SSOT has no swatch for #{edit['Material']}" unless swatch
            hit = self.na_hit(model, edit['Ray'], placement)
            raise 'nothing is there in the SketchUp model, so it may have changed since it was drawn' unless hit
            faces, containers = edit['Target'].to_s == 'Face' ? [self.na_joined_faces(hit['face']), []] : self.na_object_at(model, hit)
            raise 'the pointer did not land on a face' if faces.empty? && containers.empty?
            result = Na__MaterialPainter.Na__Painter__PaintNow(model, swatch, faces, containers)
            raise result['message'].to_s.sub(/\.\z/, '') unless result['ok']
            reply['Said'] << result['message']
            touched.concat(hit['instances'].map(&:definition))
            touched.concat(Na__Fingerprint.Na__Fp__Nested(containers))
            result['painted'].to_i > 0
        end

        # The innermost closed group or component, or (loose or in the open group) the connected faces
        def self.na_object_at(model, hit)
            active    = Array(model.active_path)
            container = hit['instances'].reverse.find { |instance| !active.include?(instance) }
            return [[], [container]] if container
            return [[], []] unless hit['face']
            [hit['face'].all_connected.grep(Sketchup::Face), []]
        end

        # The face, and any joined to it across a soft or hidden edge: what reads as one surface
        def self.na_joined_faces(face)
            return [] unless face
            found = {}.compare_by_identity
            queue = [face]
            until queue.empty? || found.length >= NA_MAX_JOINED
                current = queue.shift
                next if found[current]
                found[current] = true
                current.edges.each do |edge|
                    next unless edge.soft? || edge.hidden?
                    edge.faces.each { |other| queue << other unless found[other] }
                end
            end
            found.keys
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Ray: What the Pointer Lands On
    # -------------------------------------------------------------------------

        # FUNCTION | The First Thing the Drawing Shows Along a Ray From the Page: { 'point', 'face', 'instances' } or nil
        # ------------------------------------------------------------
        # @param ray [Hash] { 'OriginM', 'DirM' } in the engine's world
        def self.na_hit(model, ray, placement)
            return nil unless ray.is_a?(Hash) && ray['OriginM'].is_a?(Array) && ray['DirM'].is_a?(Array)
            origin = Na__AssetProxies.Na__Proxies__FromEngine(ray['OriginM'], placement)
            dir    = Na__AssetProxies.Na__Proxies__DirectionFromEngine(ray['DirM'], placement)
            return nil unless dir.valid?
            dir.normalize!
            NA_RAY_STEPS.times do
                answer = model.raytest([origin, dir], true)
                return nil unless answer
                point, path = answer
                entities  = Array(path)
                instances = entities.select { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
                face      = entities.last.is_a?(Sketchup::Face) ? entities.last : nil
                return { 'point' => point, 'face' => face, 'instances' => instances, 'dir' => dir } if face && self.na_drawn?(entities, instances)
                origin = point.offset(dir, NA_RAY_STEP_INCH)
            end
            nil
        end
        # ---------------------------------------------------------------

        # Does the drawing show it? Not a proxy (its plop is drawn instead), and
        # not what the GLB builder leaves out: it exports root entities on tags
        # numbered outside its skip ranges. With no builder, everything counts.
        def self.na_drawn?(entities, instances)
            dict = Na__Catalogue::NA_ASSET_DICT
            return false if instances.any? { |instance| !instance.definition.get_attribute(dict, 'AssetId').to_s.empty? }
            builder = Na__GlbBridge.Na__GlbBridge__Builder
            top     = entities.first
            return true unless builder && builder.respond_to?(:Na__ExportConfig__SkipRanges) && top.respond_to?(:layer)
            number = top.layer.name.to_s[/\A(\d{2})__/, 1]
            return false unless number
            !Array(builder.Na__ExportConfig__SkipRanges).include?(number.to_i)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Whether the drawing shows what the pointer landed on could not be read: #{error.message}")
            true
        end

        # FUNCTION | Where a Dropped Asset Stands: the Surface Under the Pointer, When It Faces Up (or nil)
        # ------------------------------------------------------------
        def self.na_landing(model, ray, placement)
            hit = self.na_hit(model, ray, placement)
            return nil unless hit
            active = Array(model.active_path)
            chain  = hit['instances'].reject { |instance| active.include?(instance) }.inject(Geom::Transformation.new) { |tr, instance| tr * instance.transformation }
            normal = hit['face'].normal.transform(chain)                                    # <-- Local in a closed group, world in an open one: the chain holds only the closed ones
            return nil unless normal.valid?
            normal.normalize!
            normal.reverse! if normal.dot(hit['dir']) > 0                                   # <-- A reversed face, seen from above
            limit = Na__ConfigLoader.Na__Config__GetOr(0.7, 'nprViewport', 'assets', 'landUpwardZ').to_f
            normal.z >= limit ? hit['point'] : nil
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
