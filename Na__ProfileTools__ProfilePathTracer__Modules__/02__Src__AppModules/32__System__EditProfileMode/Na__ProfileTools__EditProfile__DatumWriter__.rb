# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - DATUM WRITER
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__DatumWriter__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__DatumWriter
# PURPOSE    : Move a profile's authored 0,0 datum — its insertion point — and
#              write the result back into the library data file, so the new
#              point is what every later use of the profile starts from.
#
# WHY THIS EXISTS
#   The Apply Profile tab can already re-datum a profile on the fly, but that
#   choice lives only for the length of one placement: switch profile, or come
#   back tomorrow, and the profile is back on whatever origin happened to be
#   clicked when it was captured. For a profile whose authored origin is simply
#   wrong, that meant re-picking the same vertex every single time. This makes
#   the pick stick.
#
# HOW IT WORKS — translation, not a flag
#   The datum is moved by subtracting the picked point from every stored
#   coordinate, exactly as the 2D preview does when it shows a custom datum.
#   Nothing gains a new schema field, so every consumer — gallery thumbnails,
#   the Apply preview, the placement engine, dynamic regeneration — picks the
#   new origin up with no changes at all. The profile's shape and size are
#   untouched; only its position relative to 0,0 changes.
#
# COORDINATE MAP (the two blocks store the same section on different axes)
#   Na__Asset__Profile2D   PosY_mm  = profile horizontal   <- offset_y
#                          PosZ_mm  = profile vertical     <- offset_z
#   Na__Asset__Mesh3D      PosX_mm  = profile horizontal   <- offset_y
#                          PosY_mm  = profile vertical     <- offset_z
#                          PosZ_mm  = flat, always 0       <- untouched
#   Na__Asset__Mesh3D BoundingBox   MinX/MaxX <- offset_y, MinY/MaxY <- offset_z
#
#   Edges are stored as vertex-id PAIRS in both blocks, and faces as id loops,
#   so neither needs touching — a translation changes no connectivity, no
#   winding and no length, which is what edge styling is matched on.
#
# NOT IN SCOPE
#   Runs already placed in the model are not moved. Their geometry was baked at
#   generate time. A placed run carrying its own OriginOffset was datumed in the
#   OLD coordinate space, so that offset no longer names the same point — the
#   dialog says so before writing, the same caveat Flip Profile already carries.
#
# PUBLIC API
#   Na__DatumWriter__ReDatum(data, offset_y, offset_z) -> Boolean
#       Mutates the parsed JSON hash in place. True if anything was moved.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__DatumWriter

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        # Matches the precision the exporter writes. Without it, subtracting a
        # vertex from itself lands on 1.4210854715202004e-14 rather than 0.0,
        # and the datum marker sits a hair off the vertex the user just clicked.
        NA_COORDINATE_DECIMALS = 6

        # Below this, the pick and the current datum are the same point and the
        # write would be a no-op that still burned the .bak.
        NA_ZERO_OFFSET_TOLERANCE = 1e-9

        NA_REDATUMED_ORIGIN_NOTE =
            'Local 0,0 = insertion point set from the Edit Profile tab.'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__DatumWriter__ReDatum(data, offset_y, offset_z)
            return false unless data.is_a?(Hash)

            resolved_y = offset_y.to_f
            resolved_z = offset_z.to_f
            return false if self.Na__DatumWriter__IsZeroOffset?(resolved_y, resolved_z)

            # Profile2D is the authoritative geometry — it drives both the 2D
            # preview and the swept cross-section. Mesh3D is archival, so it is
            # translated to stay in step but its absence is not a failure.
            moved_profile = self.Na__DatumWriter__MoveProfile2dBlock(
                data['Na__Asset__Profile2D'], resolved_y, resolved_z
            )
            return false unless moved_profile

            self.Na__DatumWriter__MoveMesh3dBlock(data['Na__Asset__Mesh3D'], resolved_y, resolved_z)
            true
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__DatumWriter__ReDatum failed.', error)
            false
        end

        # Reads the offset off a dialog payload. Returns nil when no datum was
        # picked, so callers can tell "leave the datum alone" apart from "move
        # it to 0,0" — which is the profile's current datum and a no-op anyway.
        def self.Na__DatumWriter__ReadOffsetParam(params)
            return nil unless params.is_a?(Hash)

            offset = params['originOffset']
            return nil unless offset.is_a?(Hash)

            offset_y = offset['y']
            offset_z = offset['z']
            return nil unless offset_y.is_a?(Numeric) && offset_z.is_a?(Numeric)

            { 'y' => offset_y.to_f, 'z' => offset_z.to_f }
        end

        def self.Na__DatumWriter__IsZeroOffset?(offset_y, offset_z)
            offset_y.abs < NA_ZERO_OFFSET_TOLERANCE && offset_z.abs < NA_ZERO_OFFSET_TOLERANCE
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Profile2D Block
    # -------------------------------------------------------------------------

        def self.Na__DatumWriter__MoveProfile2dBlock(profile_block, offset_y, offset_z)
            return false unless profile_block.is_a?(Hash)

            vertices = profile_block['Na__Geometry__Vertices']
            return false unless vertices.is_a?(Array) && !vertices.empty?

            vertices.each do |vertex|
                next unless vertex.is_a?(Hash)
                vertex['PosY_mm'] = self.Na__DatumWriter__Shift(vertex['PosY_mm'], offset_y)
                vertex['PosZ_mm'] = self.Na__DatumWriter__Shift(vertex['PosZ_mm'], offset_z)
            end

            # The captured note claims 0,0 is where the origin helper was
            # clicked. After a re-datum that is no longer true, and a stale note
            # is worse than none for anyone reading the file by hand.
            profile_block['Na__Geometry__OriginNote'] = NA_REDATUMED_ORIGIN_NOTE

            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mesh3D Block
    # -------------------------------------------------------------------------

        # Each sub-block moves independently. An early return on a missing vertex
        # array would leave the bounding box describing the old datum while the
        # vertices had already moved — a half-translated file written over the
        # user's only backup. The library validator permits a Mesh3D block with
        # edges but no vertices, so that shape is reachable.
        def self.Na__DatumWriter__MoveMesh3dBlock(mesh_block, offset_y, offset_z)
            return false unless mesh_block.is_a?(Hash)

            Array(mesh_block['Na__Geometry__Vertices']).each do |vertex|
                next unless vertex.is_a?(Hash)
                vertex['PosX_mm'] = self.Na__DatumWriter__Shift(vertex['PosX_mm'], offset_y)
                vertex['PosY_mm'] = self.Na__DatumWriter__Shift(vertex['PosY_mm'], offset_z)
            end

            self.Na__DatumWriter__MoveBoundingBox(mesh_block['Na__Geometry__BoundingBox'], offset_y, offset_z)

            mesh_block['Na__Geometry__OriginNote'] = NA_REDATUMED_ORIGIN_NOTE if mesh_block.key?('Na__Geometry__OriginNote')

            true
        end

        # A translation maps [min, max] to [min - offset, max - offset]; unlike a
        # mirror, the two bounds keep their sides.
        def self.Na__DatumWriter__MoveBoundingBox(bounding_box, offset_y, offset_z)
            return unless bounding_box.is_a?(Hash)

            {
                'Na__Geometry__MinX_mm' => offset_y,
                'Na__Geometry__MaxX_mm' => offset_y,
                'Na__Geometry__MinY_mm' => offset_z,
                'Na__Geometry__MaxY_mm' => offset_z
            }.each do |bound_key, bound_offset|
                next unless bounding_box.key?(bound_key)
                bounding_box[bound_key] = self.Na__DatumWriter__Shift(bounding_box[bound_key], bound_offset)
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private Helpers
    # -------------------------------------------------------------------------

        # Leaves anything non-numeric (nil, "") exactly as authored, and rounds
        # so the picked vertex lands on a clean 0.0 rather than float dust.
        def self.Na__DatumWriter__Shift(value, offset)
            return value unless value.is_a?(Numeric)
            shifted = (value.to_f - offset).round(NA_COORDINATE_DECIMALS)
            shifted.zero? ? 0.0 : shifted
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
