# =============================================================================
# NA PAINTERLYNPR ASSETS - PLACE - PROXY BUILDER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Place__ProxyBuilder__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__ProxyBuilder
# PURPOSE    : Turns an asset's MOD (read by Na__GlbReader) into a SketchUp
#              component definition: the proxy the register describes for the
#              SKP slot ("the same base proxy as a SketchUp component, named
#              like the file"), so it is also what Write SKP saves.
# CREATED    : 30-Oct-2026
#
# COORDINATES:
#   The new definition is never the active context, so its entities are LOCAL
#   whatever group the person has open: library points go in converted only
#   from the library frame to SketchUp's (Na__Units: metres, +Y up, front +Z
#   to inches, Z up, front -Y). No edit_transform, no inverse. A part group
#   made inside the definition is pinned to the identity on creation anyway,
#   so no point could ever pass through a placement it inherited. Where the
#   component then lands is SketchUp's own placement tool's business
#   (Na__Placement).
#
# WHAT THE BUILD DOES:
# - One part group per material when the MOD has several (a tree's Bark and
#   Tree canopy), named by the factory's material label; one material goes
#   straight into the definition.
# - Corners shared by triangles are welded by position (the factory's GLBs
#   are not indexed), slivers SketchUp would merge away are left out and
#   counted, coplanar triangles merge into faces (Lantern Importer's pass),
#   then edges shallower than the soften angle are softened and smoothed:
#   organic assets read as masses, objects keep their arrises.
# - Materials are named materialPrefix + the material class (NPR__Timber) and
#   coloured from the GLB's linear baseColorFactor turned back into sRGB. An
#   existing NPR__ material of that name is reused as it is.
#
# UNDO CONTRACT:
#   Na__Proxy__Prepare touches nothing in the model; Na__Proxy__Build must run
#   inside the caller's operation, so a failure aborts it whole. Everything
#   that can be checked is checked in Prepare, before the operation opens.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__ProxyBuilder

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MATERIAL_DICT = 'Na__PainterlyAssets__Material'.freeze unless defined?(NA_MATERIAL_DICT)
        NA_COPLANAR_DOT  = 0.99999                                 unless defined?(NA_COPLANAR_DOT)      # <-- Two normals above this lie in one plane (about 0.26 degrees)
        NA_MIN_EDGE_INCH = 0.002                                   unless defined?(NA_MIN_EDGE_INCH)     # <-- SketchUp merges points closer than 0.001 inch
        NA_MIN_CROSS     = 1.0e-6                                  unless defined?(NA_MIN_CROSS)         # <-- Twice a triangle's area, square inches: below it, a sliver

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Prepare the Meshes (nothing in the model is touched)
        # ------------------------------------------------------------
        # @param primitives [Array<Hash>] Na__GlbReader's primitives
        # @return [Array<Hash>] [{ 'primitive', 'mesh', 'polygons', 'skipped' }]
        def self.Na__Proxy__Prepare(primitives)
            decimals = Na__ConfigLoader.Na__Config__GetOr(3, 'proxy', 'weldDecimalsInch').to_i
            prepared = primitives.map do |primitive|
                mesh, polygons, skipped = self.na_mesh(primitive, decimals)
                { 'primitive' => primitive, 'mesh' => mesh, 'polygons' => polygons, 'skipped' => skipped }
            end
            prepared = prepared.reject { |part| part['polygons'].zero? }
            raise 'The MOD holds no triangles SketchUp can build.' if prepared.empty?
            prepared
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Definition (inside the caller's operation)
        # ------------------------------------------------------------
        # @param model    [Sketchup::Model]
        # @param name     [String] the SKP stem: the definition's name, as the file's
        # @param prepared [Array<Hash>] from Na__Proxy__Prepare
        # @param organic  [Boolean] the recipe has a Kind (trees, shrubs, grasses)
        # @return [Hash] { 'definition', 'faces', 'skipped', 'merged', 'softened', 'materials' }
        def self.Na__Proxy__Build(model, name, prepared, organic)
            raise "A component named #{name} is already in this model." if model.definitions[name]

            definition = model.definitions.add(name)
            unless definition.name == name
                raise "SketchUp named the new component #{definition.name}, not #{name}: that name is reserved in this model. Save the model and open it again to free it."
            end

            angle  = Na__ConfigLoader.Na__Config__GetOr(organic ? 45 : 25, 'proxy', organic ? 'softenAngleOrganic' : 'softenAngleObject').to_f
            merge  = Na__ConfigLoader.Na__Config__GetOr(true, 'proxy', 'mergeCoplanar') != false
            flags  = defined?(Geom::PolygonMesh::NO_SMOOTH_OR_HIDE) ? Geom::PolygonMesh::NO_SMOOTH_OR_HIDE : 0
            parts  = prepared.length > 1
            stats  = { 'faces' => 0, 'skipped' => 0, 'merged' => 0, 'softened' => 0, 'materials' => [] }

            prepared.each do |part|
                primitive = part['primitive']
                entities  = definition.entities
                group     = nil
                if parts
                    group                = definition.entities.add_group
                    group.transformation = Geom::Transformation.new                                     # <-- Pinned: the identity, whatever context is open
                    group.name           = self.na_part_name(primitive)
                    entities             = group.entities
                end

                material = self.Na__Proxy__Material(model, primitive['material'])
                back     = primitive['material'] && primitive['material']['doubleSided'] ? material : nil   # <-- glTF doubleSided: both sides carry the colour
                entities.add_faces_from_mesh(part['mesh'], flags, material, back)
                stats['merged']   += self.na_merge_coplanar(entities) if merge
                stats['softened'] += self.na_soften(entities, angle)
                faces = entities.grep(Sketchup::Face).length
                group.erase! if group && faces.zero?                                                   # <-- Never leave an empty part behind
                stats['faces']    += faces
                stats['skipped']  += part['skipped']
                stats['materials'] << material.name if material && !stats['materials'].include?(material.name)
            end

            raise 'SketchUp built no faces from the MOD.' if stats['faces'].zero?
            stats.merge('definition' => definition)
        rescue StandardError
            # A batch of SKPs is one operation that carries on past a failed
            # asset, so a half-built definition is taken out here rather than
            # left for the commit.
            model.definitions.remove(definition) if definition && definition.valid? && model.definitions.respond_to?(:remove)
            raise
        end
        # ---------------------------------------------------------------

        # FUNCTION | The SketchUp Material for One GLB Material
        # ------------------------------------------------------------
        # @return [Sketchup::Material, nil] nil for a primitive with no material
        def self.Na__Proxy__Material(model, glb_material)
            return nil unless glb_material

            key      = [glb_material['materialClass'], glb_material['name']].find { |value| !value.to_s.empty? } || "Material#{glb_material['index']}"
            name     = "#{Na__ConfigLoader.Na__Config__GetOr('NPR__', 'proxy', 'materialPrefix')}#{key}"
            existing = model.materials[name]
            return existing if existing

            red, green, blue, alpha = glb_material['rgba']
            material       = model.materials.add(name)
            material.color = Sketchup::Color.new(self.na_srgb_byte(red), self.na_srgb_byte(green), self.na_srgb_byte(blue))
            material.alpha = [[alpha.to_f, 0.0].max, 1.0].min if alpha.to_f < 0.999
            material.set_attribute(NA_MATERIAL_DICT, 'MaterialClass', key)                             # <-- The class survives a rename: a later exporter maps by this
            material.set_attribute(NA_MATERIAL_DICT, 'Label', glb_material['label']) unless glb_material['label'].to_s.empty?
            material
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - the Mesh
    # -------------------------------------------------------------------------

        # Welds corners by their rounded SketchUp position, so neighbouring
        # triangles share edges (and merge and soften as one surface), and
        # leaves out what SketchUp would only collapse.
        def self.na_mesh(primitive, decimals)
            points    = primitive['positions'].map { |triple| Na__Units.Na__Units__LibraryToSketchUp(triple) }
            triangles = primitive['triangles']
            mesh      = Geom::PolygonMesh.new(points.length, triangles.length)
            slots     = {}
            index     = points.map do |point|
                key = [point.x.to_f.round(decimals), point.y.to_f.round(decimals), point.z.to_f.round(decimals)]
                slots[key] ||= mesh.add_point(point)                                                  # <-- 1-based mesh indices: never nil or 0
            end

            polygons = 0
            skipped  = 0
            triangles.each do |a, b, c|
                ia = index[a]
                ib = index[b]
                ic = index[c]
                if ia == ib || ib == ic || ia == ic || self.na_sliver?(points[a], points[b], points[c])
                    skipped += 1
                    next
                end
                mesh.add_polygon(ia, ib, ic)
                polygons += 1
            end
            [mesh, polygons, skipped]
        end

        def self.na_sliver?(a, b, c)
            return true if a.distance(b) < NA_MIN_EDGE_INCH || b.distance(c) < NA_MIN_EDGE_INCH || a.distance(c) < NA_MIN_EDGE_INCH
            ((b - a) * (c - a)).length.to_f < NA_MIN_CROSS                                            # <-- Vector3d#* is the cross product
        end

        def self.na_part_name(primitive)
            material = primitive['material'] || {}
            [material['label'], material['materialClass'], material['name'], primitive['label']].find { |value| !value.to_s.empty? }.to_s
        end

        # glTF stores colour linear; SketchUp's material colours are sRGB bytes.
        def self.na_srgb_byte(linear)
            c = [[linear.to_f, 0.0].max, 1.0].min
            s = c <= 0.0031308 ? 12.92 * c : 1.055 * (c**(1.0 / 2.4)) - 0.055
            (s * 255.0).round
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - Clean Up and Soften (Lantern Importer's passes)
    # -------------------------------------------------------------------------

        # The edge list is a snapshot taken before anything is erased: erasing
        # an edge merges its two faces and invalidates what either held. Faces
        # of two materials are never merged.
        def self.na_merge_coplanar(entities)
            merged = 0
            entities.grep(Sketchup::Edge).each do |edge|
                next unless edge.valid?
                faces = edge.faces
                next unless faces.length == 2 && faces[0].valid? && faces[1].valid?
                next unless faces[0].material == faces[1].material && faces[0].back_material == faces[1].back_material
                next unless faces[0].normal.dot(faces[1].normal) > NA_COPLANAR_DOT

                edge.erase!
                merged += 1
            end
            merged
        end

        # soft hides the edge and joins its faces into one surface; smooth
        # blends the shading across it. Both, as SketchUp's own Soften Edges
        # does, or the facets still read as flat panels.
        def self.na_soften(entities, angle_degrees)
            limit    = Math.cos(angle_degrees.to_f * Math::PI / 180.0)
            softened = 0
            entities.grep(Sketchup::Edge).each do |edge|
                next unless edge.valid?
                faces = edge.faces
                next unless faces.length == 2
                next if faces[0].normal.dot(faces[1].normal) < limit                                 # <-- Sharper than the angle: a real arris, left hard

                edge.soft   = true
                edge.smooth = true
                softened   += 1
            end
            softened
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
