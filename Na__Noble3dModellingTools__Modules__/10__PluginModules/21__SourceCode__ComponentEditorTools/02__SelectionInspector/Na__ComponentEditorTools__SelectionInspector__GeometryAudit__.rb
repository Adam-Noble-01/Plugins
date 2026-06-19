# =============================================================================
# NA COMPONENT EDITOR TOOLS - SELECTION INSPECTOR | GEOMETRY AUDIT
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__SelectionInspector__GeometryAudit__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__GeometryAudit
# PURPOSE    : Recursively traverse a component/group hierarchy and collect
#              geometry statistics for the Overview audit panel.
#
# NOTES:
# - All counts traverse nested groups and component instances recursively,
#   visiting each definition once per occurrence in the hierarchy (not once
#   per unique definition), so shared definitions are counted each time they
#   appear in the tree — consistent with "all within the component hierarchy".
# - face.mesh is called with flag 0 (fastest; no UVs or normals) for triangles.
# - Materials are deduped by display_name; tags by display_name.
# - The entire public entry-point is rescue-wrapped so a corrupt entity never
#   crashes the dialog.
#
# =============================================================================

require 'sketchup.rb'
require 'set'

module Na__ComponentEditorTools
    module Na__GeometryAudit

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BuildGeometryStats(instance)
            return self.Na__ComponentEditorTools__EmptyStats unless instance

            definition = instance.respond_to?(:definition) ? instance.definition : nil
            return self.Na__ComponentEditorTools__EmptyStats unless definition

            accum = self.Na__ComponentEditorTools__NewAccumulator
            self.Na__ComponentEditorTools__TraverseEntities(
                definition.entities,
                instance.transformation,
                instance.material,
                accum
            )

            self.Na__ComponentEditorTools__FinaliseStats(instance, definition, accum)
        rescue => error
            self.Na__ComponentEditorTools__EmptyStats.merge(
                error: "#{error.class}: #{error.message}"
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recursive Traversal
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__TraverseEntities(entities, transform, inherited_material, accum)
            entities.each do |entity|
                case entity
                when Sketchup::Face
                    self.Na__ComponentEditorTools__ClassifyFace(entity, inherited_material, accum)
                when Sketchup::Edge
                    self.Na__ComponentEditorTools__ClassifyEdge(entity, accum)
                when Sketchup::Group
                    accum[:nested_groups] += 1
                    accum[:tags] << self.Na__ComponentEditorTools__LayerDisplayName(entity)
                    self.Na__ComponentEditorTools__AccumulateAttributeDicts(entity, accum)
                    child_material = entity.material || inherited_material
                    self.Na__ComponentEditorTools__TraverseEntities(
                        entity.definition.entities,
                        transform * entity.transformation,
                        child_material,
                        accum
                    )
                when Sketchup::ComponentInstance
                    accum[:nested_components] += 1
                    accum[:unique_definitions] << entity.definition.guid
                    accum[:tags] << self.Na__ComponentEditorTools__LayerDisplayName(entity)
                    self.Na__ComponentEditorTools__AccumulateAttributeDicts(entity, accum)
                    child_material = entity.material || inherited_material
                    self.Na__ComponentEditorTools__TraverseEntities(
                        entity.definition.entities,
                        transform * entity.transformation,
                        child_material,
                        accum
                    )
                when Sketchup::ConstructionLine
                    accum[:construction_lines] += 1
                when Sketchup::ConstructionPoint
                    accum[:construction_points] += 1
                when Sketchup::Text
                    accum[:texts] += 1
                when Sketchup::Dimension
                    accum[:dimensions] += 1
                when Sketchup::Image
                    accum[:images] += 1
                when Sketchup::SectionPlane
                    accum[:section_planes] += 1
                end
            end
        rescue => error
            puts "[Na__GeometryAudit] TraverseEntities warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Per-Entity Classifiers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ClassifyFace(face, inherited_material, accum)
            accum[:faces] += 1
            accum[:tags] << self.Na__ComponentEditorTools__LayerDisplayName(face)
            self.Na__ComponentEditorTools__AccumulateAttributeDicts(face, accum)

            mesh = face.mesh
            accum[:triangles] += mesh.count_polygons
            accum[:quads] += 1 if face.outer_loop.vertices.length == 4

            accum[:total_face_area] += face.area

            front_mat = face.material || inherited_material
            accum[:face_materials] << self.Na__ComponentEditorTools__MaterialDescriptor(front_mat) if front_mat
            back_mat  = face.back_material
            accum[:face_materials] << self.Na__ComponentEditorTools__MaterialDescriptor(back_mat)  if back_mat
        rescue => error
            puts "[Na__GeometryAudit] ClassifyFace warning: #{error.class}: #{error.message}"
        end

        def self.Na__ComponentEditorTools__ClassifyEdge(edge, accum)
            accum[:edges] += 1
            accum[:tags] << self.Na__ComponentEditorTools__LayerDisplayName(edge)
            accum[:soft_edges]   += 1 if edge.soft?
            accum[:smooth_edges] += 1 if edge.smooth?
            accum[:hidden_edges] += 1 if edge.hidden?
            self.Na__ComponentEditorTools__AccumulateAttributeDicts(edge, accum)

            face_count = edge.faces.length
            accum[:non_manifold_edges] += 1 if face_count > 2

            edge_mat = edge.material
            accum[:edge_materials] << self.Na__ComponentEditorTools__MaterialDescriptor(edge_mat) if edge_mat
        rescue => error
            puts "[Na__GeometryAudit] ClassifyEdge warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Accumulator Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__NewAccumulator
            {
                faces:               0,
                edges:               0,
                triangles:           0,
                quads:               0,
                soft_edges:          0,
                smooth_edges:        0,
                hidden_edges:        0,
                non_manifold_edges:  0,
                nested_groups:       0,
                nested_components:   0,
                construction_lines:  0,
                construction_points: 0,
                texts:               0,
                dimensions:          0,
                images:              0,
                section_planes:      0,
                attribute_dicts:     0,
                attribute_keys:      0,
                total_face_area:     0.0,
                # Sets for deduplication (converted to arrays in finalise)
                face_materials:      Set.new,
                edge_materials:      Set.new,
                tags:                Set.new,
                unique_definitions:  Set.new
            }
        end

        def self.Na__ComponentEditorTools__AccumulateAttributeDicts(entity, accum)
            dicts = entity.attribute_dictionaries
            return unless dicts

            accum[:attribute_dicts] += dicts.length
            dicts.each { |d| accum[:attribute_keys] += d.length }
        rescue
            # Non-fatal
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Finalisaton & Formatting
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__FinaliseStats(instance, definition, accum)
            face_mats = accum[:face_materials].to_a
            edge_mats = accum[:edge_materials].to_a

            {
                faces:               accum[:faces],
                edges:               accum[:edges],
                triangles:           accum[:triangles],
                quads:               accum[:quads],
                soft_edges:          accum[:soft_edges],
                smooth_edges:        accum[:smooth_edges],
                hidden_edges:        accum[:hidden_edges],
                non_manifold_edges:  accum[:non_manifold_edges],
                nested_groups:       accum[:nested_groups],
                nested_components:   accum[:nested_components],
                unique_definitions:  accum[:unique_definitions].length,
                construction_lines:  accum[:construction_lines],
                construction_points: accum[:construction_points],
                texts:               accum[:texts],
                dimensions:          accum[:dimensions],
                images:              accum[:images],
                section_planes:      accum[:section_planes],
                attribute_dicts:     accum[:attribute_dicts],
                attribute_keys:      accum[:attribute_keys],
                total_face_area:     Sketchup.format_length(Math.sqrt(accum[:total_face_area])) + '²',
                is_solid:            definition.manifold?,
                face_materials:      face_mats,
                edge_materials:      edge_mats,
                tags:                accum[:tags].to_a.reject(&:empty?).sort
            }
        rescue => error
            self.Na__ComponentEditorTools__EmptyStats.merge(error: "Finalise error: #{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__EmptyStats
            {
                faces: 0, edges: 0, triangles: 0, quads: 0,
                soft_edges: 0, smooth_edges: 0, hidden_edges: 0,
                non_manifold_edges: 0, nested_groups: 0, nested_components: 0,
                unique_definitions: 0, construction_lines: 0, construction_points: 0,
                texts: 0, dimensions: 0, images: 0, section_planes: 0,
                attribute_dicts: 0, attribute_keys: 0,
                total_face_area: '0', is_solid: false,
                face_materials: [], edge_materials: [], tags: []
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Value Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LayerDisplayName(entity)
            return '' unless entity.respond_to?(:layer) && entity.layer

            entity.layer.display_name.to_s
        rescue
            ''
        end

        def self.Na__ComponentEditorTools__MaterialDescriptor(material)
            return nil unless material

            type_code = material.respond_to?(:materialType) ? material.materialType : 0
            textured  = (type_code == 1 || type_code == 3)  # MATERIAL_TEXTURED or MATERIAL_COLORIZED_TEXTURED

            texture_file = ''
            if textured && material.respond_to?(:texture) && material.texture
                texture_file = File.basename(material.texture.filename.to_s)
            end

            {
                name:         material.display_name.to_s,
                textured:     textured,
                texture_file: texture_file
            }
        rescue
            nil
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
