# =============================================================================
# NA PAINTERLYNPR ASSETS - PROJECT CACHE - ASSET PROXIES
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ProjectCache__AssetProxies__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__AssetProxies
# PURPOSE    : The PainterlyNPR library assets placed in the model (this
#              plugin's proxies: a tree, a pot, a bench), each as a pose in the
#              engine's world, so the NPR Viewport draws them as PainterlyNPR
#              draws them (its generators), not as their proxy geometry.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - A PROXY is any instance whose definition carries an AssetId
#   (Na__PainterlyAssets__Asset), at any depth: Place puts them in whatever
#   context is open. Hidden ones, or ones on a hidden tag, are left out, except
#   on the proxy tag (assets.proxyTag): that is hidden scene by scene to keep
#   proxies out of the whitecard pictures, not out of the drawing. A proxy is
#   never walked into.
# - THE POSE, as ValeVision Cloud Sync's Sync Aura takes it: the origin, the
#   turn about SketchUp's +Z (the same angle about the engine's +Y) and one
#   scale. SketchUp inches go to the GLB builder's glTF metres (x, z, -y), then
#   through the scene's placement (turn about +Y, then move), so a proxy
#   stands where its GLB neighbours do. A tipped proxy keeps its turn and is
#   flagged.
# - THE SEED comes from the proxy's persistent id, so the same tree keeps the
#   same shape every time the viewport opens. The engine makes the plop from
#   the asset's own record (its MakePlacement), never from anything here.
# - WHAT THE NPR VIEWPORT GAVE IT (v0.4.0) stays on the instance, in its
#   Na__PainterlyAssets__Asset dictionary: the shape a drop or Grow a New Shape
#   made (Seed, with SeedFor naming the instance, so a copy made in SketchUp
#   grows its own) and the materials given to its parts (Materials). The engine
#   draws an asset from its generator, so the proxy's own geometry is never
#   repainted: Write SKP would save the paint.
# - Reading is read only, and only with no group open (an open context reports
#   world coordinates): the sync calls it at the same moment as the export.
#   Finding one proxy to change it (Na__Proxies__Find, v0.4.0) follows the
#   coordinate rule through any open group; the changing is Na__ModelEdits'.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__AssetProxies

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_INCH_M       = 0.0254 unless defined?(NA_INCH_M)
        NA_SEED_ATTR    = 'Seed'.freeze      unless defined?(NA_SEED_ATTR)                 # <-- On the instance, as text: an attribute's Integer is 32 bits and signed
        NA_SEED_FOR     = 'SeedFor'.freeze   unless defined?(NA_SEED_FOR)                  # <-- The persistent id that Seed was given to
        NA_PARTS_ATTR   = 'Materials'.freeze unless defined?(NA_PARTS_ATTR)                # <-- On the instance, as JSON: [{ 'Part', 'Face', 'Material' }]

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Every Visible Proxy as an Engine Pose
        # ------------------------------------------------------------
        # @param placement [Hash] the scene's NprScene__ModelPlacement
        # @return [Array<Hash>] [{ 'Uid', 'AssetId', 'PositionM', 'RotationDeg', 'Scale', 'Seed', 'ShapeSeed', 'Materials', 'Tilted' }]
        def self.Na__Proxies__Collect(model, placement)
            dict  = Na__Catalogue::NA_ASSET_DICT
            tag   = Na__ConfigLoader.Na__Config__GetOr('', 'nprViewport', 'assets', 'proxyTag').to_s
            found = []
            walk  = lambda do |entities, parent, depth|
                return if depth > 32
                entities.each do |entity|
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next if entity.hidden? || (entity.layer && !entity.layer.visible? && entity.layer.name != tag)
                    world    = parent * entity.transformation
                    asset_id = entity.definition.get_attribute(dict, 'AssetId').to_s
                    if asset_id.empty?
                        walk.call(entity.definition.entities, world, depth + 1)
                    else
                        found << self.Na__Proxies__Pose(entity, world, asset_id, placement)
                    end
                end
            end
            walk.call(model.entities, Geom::Transformation.new, 0)
            found
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Proxy's Pose in the Engine's World
        # ------------------------------------------------------------
        def self.Na__Proxies__Pose(instance, world, asset_id, placement)
            m       = world.to_a.map(&:to_f)
            w       = m[15].abs > 1e-9 ? m[15] : 1.0                                  # <-- Normally 1: a matrix from elsewhere can carry a uniform scale here
            scale   = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]) / w
            turn    = Math.atan2(m[1], m[0]) * 180.0 / Math::PI                       # <-- The x axis's heading: a turn about +Z
            z_len   = Math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10])
            tilted  = z_len > 0 && (m[10] / z_len).abs < 0.999
            gltf    = [m[12] / w * NA_INCH_M, m[14] / w * NA_INCH_M, -m[13] / w * NA_INCH_M]   # <-- SketchUp (x, y, z) inches -> glTF (x, z, -y) metres
            place   = self.Na__Proxies__Place(gltf, placement)
            pid     = instance.persistent_id.to_i
            {
                'Uid'         => "S#{pid}",
                'AssetId'     => asset_id,
                'PositionM'   => place.map { |v| v.round(4) },
                'RotationDeg' => ((turn + (placement['RotationDeg'] || 0).to_f) % 360.0).round(2),
                'Scale'       => scale.round(4),
                'Seed'        => pid & 0xFFFFFFFF,
                'ShapeSeed'   => self.na_shape_seed(instance, pid),
                'Materials'   => self.na_parts(instance),
                'Tilted'      => tilted
            }
        end
        # ---------------------------------------------------------------

        # A glTF point through the scene's placement: about +Y, then moved (the engine's GlbTransform)
        def self.Na__Proxies__Place(point, placement)
            angle = (placement['RotationDeg'] || 0).to_f * Math::PI / 180.0
            c     = Math.cos(angle)
            s     = Math.sin(angle)
            off   = Array(placement['OffsetM'] || [0, 0, 0]).map(&:to_f)
            x, y, z = point
            [c * x + s * z + off[0], y + off[1], -s * x + c * z + off[2]]
        end

        # FUNCTION | A Point in the Engine's World Back in SketchUp's Inches (Na__Proxies__Place undone)
        # ------------------------------------------------------------
        # @param point_m [Array<Float>] engine metres
        # @return [Geom::Point3d] world, as a raytest and an open group's coordinates read
        def self.Na__Proxies__FromEngine(point_m, placement)
            x, y, z = self.na_unplace(point_m, placement, true)
            Geom::Point3d.new(x / NA_INCH_M, -z / NA_INCH_M, y / NA_INCH_M)
        end
        # ---------------------------------------------------------------

        # A direction in the engine's world: it turns with the placement but never moves
        def self.Na__Proxies__DirectionFromEngine(vector, placement)
            x, y, z = self.na_unplace(vector, placement, false)
            Geom::Vector3d.new(x, -z, y)
        end

        # FUNCTION | One Proxy by Its Persistent Id, With Where Its Parent Stands: { 'instance', 'parent' } or nil
        # ------------------------------------------------------------
        # parent * instance.transformation is the proxy in the world. An open
        # group's contents report world coordinates, and so do instances in it
        # (the coordinate rule), so the chain restarts at the identity inside
        # one. A proxy is never walked into.
        def self.Na__Proxies__Find(model, pid)
            dict   = Na__Catalogue::NA_ASSET_DICT
            active = Array(model.active_path)
            walk   = lambda do |entities, parent, depth|
                return nil if depth > 32
                entities.each do |entity|
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    return { 'instance' => entity, 'parent' => parent } if entity.persistent_id.to_i == pid.to_i
                    next unless entity.definition.get_attribute(dict, 'AssetId').to_s.empty?
                    inner = active.include?(entity) ? Geom::Transformation.new : parent * entity.transformation
                    found = walk.call(entity.definition.entities, inner, depth + 1)
                    return found if found
                end
                nil
            end
            walk.call(model.entities, Geom::Transformation.new, 0)
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # Back through the placement: the offset taken off, then the turn about +Y undone
        def self.na_unplace(point, placement, moved)
            angle = (placement['RotationDeg'] || 0).to_f * Math::PI / 180.0
            c     = Math.cos(angle)
            s     = Math.sin(angle)
            off   = moved ? Array(placement['OffsetM'] || [0, 0, 0]).map(&:to_f) : [0.0, 0.0, 0.0]
            x, y, z = Array(point).map(&:to_f)
            dx = x - off[0]
            dz = z - off[2]
            [c * dx - s * dz, y - off[1], s * dx + c * dz]
        end

        # The shape the NPR Viewport gave this very instance, or nil (a copy made in SketchUp grows its own)
        def self.na_shape_seed(instance, pid)
            dict = Na__Catalogue::NA_ASSET_DICT
            return nil unless instance.get_attribute(dict, NA_SEED_FOR).to_s == pid.to_s
            seed = instance.get_attribute(dict, NA_SEED_ATTR).to_s
            seed.empty? ? nil : seed.to_i
        end

        # What the NPR Viewport gave its parts: [{ 'Part', 'Face', 'Material' }]
        def self.na_parts(instance)
            text = instance.get_attribute(Na__Catalogue::NA_ASSET_DICT, NA_PARTS_ATTR).to_s
            return [] if text.empty?
            parsed = JSON.parse(text)
            parsed.is_a?(Array) ? parsed.select { |part| part.is_a?(Hash) } : []
        rescue JSON::ParserError
            []
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
