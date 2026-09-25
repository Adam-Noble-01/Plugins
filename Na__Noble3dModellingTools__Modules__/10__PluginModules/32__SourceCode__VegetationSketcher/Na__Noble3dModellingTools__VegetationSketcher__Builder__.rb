# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Builder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__Builder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Create and update whitecard vegetation components in one undo
# CREATED    : 2026
#
# Millimetre meshes are converted to SketchUp inches only at fill_from_mesh.
# Smooth shading is a 40.3 degree edge threshold, independent of form rounding.
# World transforms are used as-is: in the open context add_instance and
# #transformation are world, so edit_transform would convert twice.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__Builder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_WHITECARD_DICT      = 'Na__VegetationSketcher'.freeze
        NA_WHITECARD_NAME      = 'Noble Whitecard Vegetation'.freeze
        NA_SMOOTH_THRESHOLD    = 40.3 * Math::PI / 180.0
        NA_MM_PER_INCH         = 25.4
        NA_EDIT_OPERATION      = 'Edit Noble Whitecard Vegetation'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Builder API
# -----------------------------------------------------------------------------

        # FUNCTION | True When the Entity Is Noble Vegetation
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Builder__Vegetation?(entity)
            Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__HasData?(entity)
        end
        # ------------------------------------------------------------

        # FUNCTION | Create a Vegetation Instance at a World Transform
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Builder__Create(model, options, world_transform, length = nil)
            resolved = Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(options.merge('length' => length || options['length']))
            data = Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Build(resolved)
            name = 'Noble Whitecard ' + Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Label(resolved)
            started = false
            model.start_operation(name, true)
            started = true
            definition = model.definitions.add(name)
            group = model.active_entities.add_instance(definition, world_transform)
            group.name = name
            group.transformation = world_transform
            na_populate(group, data, resolved, model)
            model.commit_operation
            group
        rescue StandardError
            model.abort_operation if started
            raise
        end
        # ------------------------------------------------------------

        # FUNCTION | Rebuild an Unlocked Vegetation Instance In Place
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Builder__Update(model, group, options)
            unless self.Na__VegetationSketcher__Builder__Vegetation?(group) && !group.locked? && model.active_entities.include?(group)
                raise ArgumentError, 'Select one unlocked Noble vegetation component or group in the current editing context.'
            end

            options = Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(options)
            data = Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Build(options)
            started = false
            model.start_operation(NA_EDIT_OPERATION, true)
            started = true
            group.make_unique if group.definition.instances.length > 1
            Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Entities(group).clear!
            group.name = 'Noble Whitecard ' + Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Label(options) if group.name.start_with?('Noble Whitecard ')
            na_populate(group, data, options, model)
            model.commit_operation
            group
        rescue StandardError
            model.abort_operation if started
            raise
        end
        # ------------------------------------------------------------

        # FUNCTION | Soften, Smooth and Hide Grid Edges
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Builder__ApplyShading(entities, enabled)
            na_apply_shading(entities, enabled)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Mesh Population
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Fill Foliage, Optional Trunk, Material and Dictionary
        # ------------------------------------------------------------
        def self.na_populate(group, data, options, model, remember_model: true)
            material = na_whitecard_material(model)
            root_entities = Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Entities(group)
            foliage = options['preset'] == 'tree' ? root_entities.add_group : group
            foliage.name = 'Whitecard canopy' unless foliage == group
            na_fill_foliage(foliage, data, material, options['smooth'])
            na_fill_trunk(root_entities, data, options, material) if options['preset'] == 'tree'
            group.material = material
            Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Save(model, group, options, data[:quads].length, remember_model: remember_model)
            group
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reuse or Create the Shared Whitecard Material
        # ------------------------------------------------------------
        def self.na_whitecard_material(model)
            material = model.materials.find do |candidate|
                candidate.get_attribute(NA_WHITECARD_DICT, 'whitecard') &&
                    candidate.color.to_a[0, 3] == [255, 255, 255] &&
                    candidate.alpha == 1.0 &&
                    !candidate.texture
            end
            return material if material

            material = model.materials.add(NA_WHITECARD_NAME)
            material.color = Sketchup::Color.new(255, 255, 255)
            material.set_attribute(NA_WHITECARD_DICT, 'whitecard', true)
            material
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Fill the Canopy Mesh From Shared Quad Indices
        # ------------------------------------------------------------
        def self.na_fill_foliage(foliage, data, material, smooth)
            mesh = Geom::PolygonMesh.new(data[:points].length, data[:quads].length * 2)
            ids = data[:points].map { |p| mesh.add_point(na_mm_to_inches(p)) }
            data[:quads].each { |q| na_add_quad(mesh, q.map { |i| ids[i] }) }
            foliage_entities = Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Entities(foliage)
            raise 'Could not create the vegetation mesh.' unless foliage_entities.fill_from_mesh(mesh, true, na_mesh_flags, material, material)

            na_apply_shading(foliage_entities, smooth)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Fill Trunk and Branch Faces
        # ------------------------------------------------------------
        def self.na_fill_trunk(root_entities, data, options, material)
            trunk = root_entities.add_group
            trunk.name = options['tree_type'] == 'english_oak' ? 'Whitecard trunk and branches' : 'Whitecard trunk'
            mesh = Geom::PolygonMesh.new
            ids = data[:trunk][:points].map { |p| mesh.add_point(na_mm_to_inches(p)) }
            data[:trunk][:faces].each do |face|
                indices = face.map { |i| ids[i] }
                if indices.length == 4
                    na_add_quad(mesh, indices)
                else
                    mesh.add_polygon(indices)
                end
            end
            raise 'Could not create the tree trunk and branches.' unless trunk.entities.fill_from_mesh(mesh, true, na_mesh_flags, material, material)

            na_apply_shading(trunk.entities, options['smooth'])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Two Hidden-Diagonal Triangles For a Quad
        # ------------------------------------------------------------
        def self.na_add_quad(mesh, indices)
            a, b, c, d = indices
            mesh.add_polygon(a, b, -c)
            mesh.add_polygon(-a, c, d)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert a Millimetre Triple to SketchUp Inches
        # ------------------------------------------------------------
        def self.na_mm_to_inches(point)
            point.map { |v| v / NA_MM_PER_INCH }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | PolygonMesh Flags For Hidden Diagonals and Soft Edges
        # ------------------------------------------------------------
        def self.na_mesh_flags
            Geom::PolygonMesh::HIDE_BASED_ON_INDEX |
                Geom::PolygonMesh::SOFTEN_BASED_ON_INDEX |
                Geom::PolygonMesh::SMOOTH_SOFT_EDGES
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Soften Rounded Neighbours; Always Hide Grid Edges
        # ------------------------------------------------------------
        def self.na_apply_shading(entities, enabled)
            entities.grep(Sketchup::Edge).each do |edge|
                diagonal = edge.soft?
                faces = edge.faces
                rounded = enabled && faces.length == 2 && faces[0].normal.angle_between(faces[1].normal) <= NA_SMOOTH_THRESHOLD
                edge.soft = diagonal || rounded
                edge.smooth = !!rounded
                edge.hidden = true
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__Builder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
