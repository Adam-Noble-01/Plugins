# =============================================================================
# NA PAINTERLYNPR ASSETS - AUTHOR - THE SELECTED COMPONENT
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Author__Selection__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__AuthorSelection
# PURPOSE    : Reads the one selected component (or group) that would become a
#              new library asset: whether it can, its size, where its origin
#              sits against the centre of its base, and its bounds in the
#              library's frame, as the DAT will record them.
# CREATED    : 30-Oct-2026
#
# COORDINATES:
#   Everything here is read from the DEFINITION (its bounds are local and
#   unscaled, whatever context is open), never from the instance's world
#   bounds, because the asset IS the definition: the SKP saves it at its own
#   size, origin and axes. A definition that is itself open (the person is
#   editing inside it, or inside a copy of it) is refused, because its
#   entities then report world coordinates and the asset's own frame cannot
#   be read honestly. The instance's transformation is read only for its
#   scale, through transformed points (note 02: the matrix's w can hide a
#   uniform scale).
#
# =============================================================================

module Na__PainterlyAssets
    module Na__AuthorSelection

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | What the Selection Offers as a New Asset
        # ------------------------------------------------------------
        # @return [Hash] for the Author tab and for Na__AuthorPlan; 'ok' false
        #   with 'blocked' reasons when it cannot become an asset as it is
        def self.Na__Author__ReadSelection(model = Sketchup.active_model)
            return self.na_blocked('Open a model first.') unless model

            selection = model.selection.to_a
            return self.na_blocked('Select the component (or group) to make into a library asset.') if selection.empty?

            picked = selection.select { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }   # <-- A Group is not a ComponentInstance in Ruby
            unless selection.length == 1 && picked.length == 1
                return self.na_blocked("Select just one component or group (the selection holds #{selection.length} things).")
            end

            instance   = picked.first
            definition = instance.definition
            reasons    = []
            reasons << 'It is locked: unlock it first.' if instance.locked?
            reasons << 'It is a Dynamic Component: its own attributes redraw it, so it cannot be filed as a fixed asset.' if definition.respond_to?(:live_component?) && definition.live_component?
            reasons << 'It is open for editing: close it (step out of it), then select it again.' if Array(model.active_path).any? { |open| open.definition == definition }

            dict     = Na__Catalogue::NA_ASSET_DICT
            asset_id = definition.get_attribute(dict, 'AssetId')
            stem     = definition.get_attribute(dict, 'SkpStem')
            if asset_id && stem && definition.name == stem
                reasons << "It is #{asset_id} from the library already. Make it unique first (right-click, Make Unique) to author a new asset from it."
            end

            bounds = definition.bounds
            reasons << 'It holds no geometry.' if bounds.empty?
            return self.na_blocked(reasons.first, reasons) if bounds.empty?

            low      = bounds.min
            high     = bounds.max
            centre   = [(low.x.to_f + high.x.to_f) / 2.0, (low.y.to_f + high.y.to_f) / 2.0, low.z.to_f]   # <-- The centre of its base, in its own axes (inches)
            offset   = centre.map { |value| Na__Units.Na__Units__InchesToMm(value) }
            limit_mm = Na__ConfigLoader.Na__Config__GetOr(1.0, 'author', 'originToleranceMm').to_f
            scale    = self.na_scale(instance.transformation)
            seat     = Geom::Vector3d.new(*centre)
            {
                'ok'              => reasons.empty?,
                'blocked'         => reasons,
                'message'         => reasons.empty? ? "#{definition.name} can become a library asset." : reasons.first,
                'persistentId'    => instance.persistent_id,
                'kind'            => instance.is_a?(Sketchup::Group) ? 'Group' : 'Component',
                'definitionName'  => definition.name,
                'instanceName'    => instance.name.to_s,
                'instances'       => definition.count_instances,
                'faces'           => definition.entities.grep(Sketchup::Face).length,
                'parts'           => definition.entities.count { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) },
                'sizeMm'          => [high.x - low.x, high.y - low.y, high.z - low.z].map { |value| Na__Units.Na__Units__InchesToMm(value).round(1) },
                'originOffsetMm'  => offset.map { |value| value.round(1) },
                'originOk'        => offset.all? { |value| value.abs <= limit_mm },
                'originInches'    => centre,
                'scale'           => scale.map { |value| value.round(4) },
                'scaled'          => scale.any? { |value| (value - 1.0).abs > 1.0e-4 },
                'assetId'         => asset_id,
                'geometryAsIs'    => self.na_geometry(low, high),
                'geometryCentred' => self.na_geometry(low.offset(seat.reverse), high.offset(seat.reverse))
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Selected Entity Again, by the Id the Plan Recorded
        # ------------------------------------------------------------
        # It must still be the one thing selected: an asset is never authored
        # from something the person has since moved on from.
        def self.Na__Author__FindTarget(model, persistent_id)
            return nil unless model && persistent_id
            selection = model.selection.to_a
            return nil unless selection.length == 1

            entity = selection.first
            return nil unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            entity.persistent_id == persistent_id.to_i ? entity : nil
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # The DAT's Geometry numbers from a box in SketchUp's frame (inches).
        def self.na_geometry(low, high)
            bounds = Na__Units.Na__Units__BoundsToLibrary(low, high)
            size   = bounds['Size']
            {
                'NominalHeightM' => Na__Units.Na__Units__Round(size[1], 2),
                'NominalSpreadM' => Na__Units.Na__Units__Round([size[0], size[2]].max, 2),
                'Bounds'         => bounds
            }
        end

        # Per-axis scale through transformed points (magnitude only).
        def self.na_scale(transformation)
            origin = Geom::Point3d.new(0, 0, 0).transform(transformation)
            [[1, 0, 0], [0, 1, 0], [0, 0, 1]].map do |axis|
                Geom::Point3d.new(*axis).transform(transformation).distance(origin).to_f
            end
        end

        def self.na_blocked(message, reasons = [message])
            { 'ok' => false, 'blocked' => reasons, 'message' => message }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
