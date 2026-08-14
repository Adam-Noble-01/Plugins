# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - GEOMETRY WRITER
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__GeometryWriter__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__GeometryWriter
# PURPOSE    : In-place geometry edits for profile JSON data files. Currently a
#              single operation: mirror the profile about its own vertical datum
#              so an existing library asset can be re-handed without rebuilding it.
#
# WHY THIS EXISTS
#   Profiles are authored from whatever face happened to be selected, so the
#   library ends up with mixed handing and the Gallery gives no reliable clue
#   which way a profile will sweep. Flipping in place lets the whole library be
#   normalised to one handing, and lets a future mis-handed export be corrected
#   without re-exporting the asset.
#
# MIRROR CONTRACT (horizontal, about the profile's own datum at Y = 0)
#   Na__Asset__Profile2D
#     Vertices  PosY_mm            negated   (Y is the profile's horizontal axis)
#     Faces     OuterLoopVertices  reversed  (keeps winding matching the normal)
#
#   Na__Asset__Mesh3D
#     Vertices  PosX_mm, Normal_X  negated   (X is the profile-width surrogate)
#     Faces     OuterLoop_VertexIds / InnerLoops  reversed
#     Faces     Normal[0]          negated
#     BoundingBox MinX/MaxX        swapped and negated
#
#   Edges in both blocks are stored as vertex-id PAIRS, not as an ordered walk,
#   so they stay valid untouched. Edge styling is matched by length elsewhere
#   (Na__Geometry__FindClosestStyleReference), and a mirror preserves length,
#   so edge colours and soft/smooth flags survive the flip unchanged.
#
# PUBLIC API
#   Na__GeometryWriter__FlipHorizontal(data) -> Boolean
#       Mutates the parsed JSON hash in place. True if anything was mirrored.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__GeometryWriter

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__GeometryWriter__FlipHorizontal(data)
            return false unless data.is_a?(Hash)

            # Profile2D is the authoritative geometry — it drives both the 2D
            # preview and the swept cross-section. Mesh3D is archival, so it is
            # mirrored to stay in step but its absence is not a failure.
            mirrored_profile = self.Na__GeometryWriter__FlipProfile2dBlock(data['Na__Asset__Profile2D'])
            return false unless mirrored_profile

            self.Na__GeometryWriter__FlipMesh3dBlock(data['Na__Asset__Mesh3D'])
            true
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__GeometryWriter__FlipHorizontal failed.', error)
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Profile2D Block
    # -------------------------------------------------------------------------

        def self.Na__GeometryWriter__FlipProfile2dBlock(profile_block)
            return false unless profile_block.is_a?(Hash)

            vertices = profile_block['Na__Geometry__Vertices']
            return false unless vertices.is_a?(Array) && !vertices.empty?

            vertices.each do |vertex|
                next unless vertex.is_a?(Hash)
                vertex['PosY_mm'] = self.Na__GeometryWriter__Negate(vertex['PosY_mm'])
            end

            Array(profile_block['Na__Geometry__Faces']).each do |face|
                next unless face.is_a?(Hash)
                loop_ids = face['OuterLoopVertices']
                face['OuterLoopVertices'] = loop_ids.reverse if loop_ids.is_a?(Array)
            end

            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mesh3D Block
    # -------------------------------------------------------------------------

        # Each sub-block is mirrored independently. An early `return` on a missing
        # vertex array would leave the faces and bounding box un-mirrored while
        # Profile2D had already flipped — a half-mirrored file written over the
        # user's only backup. The library validator permits a Mesh3D block with
        # edges but no vertices, so that shape is reachable.
        def self.Na__GeometryWriter__FlipMesh3dBlock(mesh_block)
            return false unless mesh_block.is_a?(Hash)

            Array(mesh_block['Na__Geometry__Vertices']).each do |vertex|
                next unless vertex.is_a?(Hash)
                vertex['PosX_mm']  = self.Na__GeometryWriter__Negate(vertex['PosX_mm'])
                vertex['Normal_X'] = self.Na__GeometryWriter__Negate(vertex['Normal_X']) if vertex.key?('Normal_X')
            end

            self.Na__GeometryWriter__FlipMeshFaces(mesh_block['Na__Geometry__Faces'])
            self.Na__GeometryWriter__FlipBoundingBox(mesh_block['Na__Geometry__BoundingBox'])

            true
        end

        def self.Na__GeometryWriter__FlipMeshFaces(faces)
            Array(faces).each do |face|
                next unless face.is_a?(Hash)

                outer_loop = face['OuterLoop_VertexIds']
                face['OuterLoop_VertexIds'] = outer_loop.reverse if outer_loop.is_a?(Array)

                inner_loops = face['InnerLoops']
                if inner_loops.is_a?(Array)
                    face['InnerLoops'] = inner_loops.map do |inner_loop|
                        inner_loop.is_a?(Array) ? inner_loop.reverse : inner_loop
                    end
                end

                normal = face['Normal']
                normal[0] = self.Na__GeometryWriter__Negate(normal[0]) if normal.is_a?(Array) && !normal.empty?
            end
        end

        # A mirror maps [min, max] to [-max, -min], so the two bounds swap sides.
        def self.Na__GeometryWriter__FlipBoundingBox(bounding_box)
            return unless bounding_box.is_a?(Hash)
            return unless bounding_box.key?('Na__Geometry__MinX_mm') && bounding_box.key?('Na__Geometry__MaxX_mm')

            previous_min = bounding_box['Na__Geometry__MinX_mm']
            previous_max = bounding_box['Na__Geometry__MaxX_mm']

            bounding_box['Na__Geometry__MinX_mm'] = self.Na__GeometryWriter__Negate(previous_max)
            bounding_box['Na__Geometry__MaxX_mm'] = self.Na__GeometryWriter__Negate(previous_min)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private Helpers
    # -------------------------------------------------------------------------

        # Guards against writing "-0.0" into the data file, and leaves anything
        # non-numeric (nil, "") exactly as authored.
        def self.Na__GeometryWriter__Negate(value)
            return value unless value.is_a?(Numeric)
            return value if value.zero?
            -value
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
