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
#   context is open. Hidden ones, or ones on a hidden tag, are left out. A
#   proxy is never walked into.
# - THE POSE, as ValeVision Cloud Sync's Sync Aura takes it: the origin, the
#   turn about SketchUp's +Z (the same angle about the engine's +Y) and one
#   scale. SketchUp inches go to the GLB builder's glTF metres (x, z, -y), then
#   through the scene's placement (turn about +Y, then move), so a proxy
#   stands where its GLB neighbours do. A tipped proxy keeps its turn and is
#   flagged.
# - THE SEED comes from the proxy's persistent id, so the same tree keeps the
#   same shape every time the viewport opens. The engine makes the plop from
#   the asset's own record (its MakePlacement), never from anything here.
# - Read only, and only with no group open (an open context reports world
#   coordinates): the sync calls it at the same moment as the export.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__AssetProxies

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_INCH_M = 0.0254 unless defined?(NA_INCH_M)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Every Visible Proxy as an Engine Pose
        # ------------------------------------------------------------
        # @param placement [Hash] the scene's NprScene__ModelPlacement
        # @return [Array<Hash>] [{ 'Uid', 'AssetId', 'PositionM', 'RotationDeg', 'Scale', 'Seed', 'Tilted' }]
        def self.Na__Proxies__Collect(model, placement)
            dict  = Na__Catalogue::NA_ASSET_DICT
            found = []
            walk  = lambda do |entities, parent, depth|
                return if depth > 32
                entities.each do |entity|
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next if entity.hidden? || (entity.layer && !entity.layer.visible?)
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
            scale   = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
            turn    = Math.atan2(m[1], m[0]) * 180.0 / Math::PI                       # <-- The x axis's heading: a turn about +Z
            z_len   = Math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10])
            tilted  = z_len > 0 && (m[10] / z_len).abs < 0.999
            gltf    = [m[12] * NA_INCH_M, m[14] * NA_INCH_M, -m[13] * NA_INCH_M]      # <-- SketchUp (x, y, z) inches -> glTF (x, z, -y) metres
            place   = self.Na__Proxies__Place(gltf, placement)
            pid     = instance.persistent_id.to_i
            {
                'Uid'         => "S#{pid}",
                'AssetId'     => asset_id,
                'PositionM'   => place.map { |v| v.round(4) },
                'RotationDeg' => ((turn + (placement['RotationDeg'] || 0).to_f) % 360.0).round(2),
                'Scale'       => scale.round(4),
                'Seed'        => pid & 0xFFFFFFFF,
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

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
