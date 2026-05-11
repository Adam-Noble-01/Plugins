# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - SCENE PROFILE REGISTRY
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__SceneProfileRegistry__.rb
# PURPOSE    : Stores and validates scene-picked profile source geometry
# CREATED    : 2026
#
# =============================================================================

require 'time'

module Na__ProfileTools__ProfilePathTracer
    module Na__SceneProfileRegistry

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MM_PER_INCH = 25.4

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Registry State
    # -------------------------------------------------------------------------

        @na_profile_data = nil
        @na_display_name = ''
        @na_definition_pid = nil

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__SceneProfileRegistry__Clear
            @na_profile_data = nil
            @na_display_name = ''
            @na_definition_pid = nil
        end

        def self.Na__SceneProfileRegistry__IsValid?
            @na_profile_data.is_a?(Hash) && !@na_profile_data.empty?
        end

        def self.Na__SceneProfileRegistry__ProfileData
            @na_profile_data
        end

        def self.Na__SceneProfileRegistry__DefinitionPersistentId
            @na_definition_pid
        end

        def self.Na__SceneProfileRegistry__StatusPayload
            if self.Na__SceneProfileRegistry__IsValid?
                {
                    'isValid' => true,
                    'displayName' => @na_display_name,
                    'profileKey' => @na_profile_data['profileKey'],
                    'profileData' => @na_profile_data,
                    'statusMessage' => "Scene profile ready: #{@na_display_name}"
                }
            else
                {
                    'isValid' => false,
                    'displayName' => '',
                    'profileKey' => '',
                    'profileData' => nil,
                    'statusMessage' => 'No scene profile selected.'
                }
            end
        end

        def self.Na__SceneProfileRegistry__SetFromEntity(entity)
            return { 'isValid' => false, 'reason' => 'No entity picked.' } unless entity

            component_definition = self.Na__SceneProfileRegistry__ResolveDefinition(entity)
            unless component_definition && component_definition.valid?
                return { 'isValid' => false, 'reason' => 'Picked entity does not expose a valid definition.' }
            end

            source_entities = self.Na__SceneProfileRegistry__ResolveEntities(entity)
            unless source_entities
                return { 'isValid' => false, 'reason' => 'Picked entity has no readable geometry container.' }
            end

            candidate_faces = source_entities.grep(Sketchup::Face)
            if candidate_faces.length != 1
                return {
                    'isValid' => false,
                    'reason' => 'Scene profile requires exactly one top-level face in the picked Group/Component.'
                }
            end

            profile_face = candidate_faces.first
            if profile_face.loops.length > 1
                return {
                    'isValid' => false,
                    'reason' => 'Scene profile face must be a single outer loop (no inner holes).'
                }
            end

            extracted_geometry = self.Na__SceneProfileRegistry__ExtractUnifiedGeometry(profile_face, entity.transformation)
            if extracted_geometry.nil?
                return { 'isValid' => false, 'reason' => 'Scene profile face needs at least 3 usable points.' }
            end

            profile_key = "SCENE_PROFILE__#{Time.now.getlocal.strftime('%d%m%Y__%H%M%S')}"
            display_name = self.Na__SceneProfileRegistry__ResolveDisplayName(entity, component_definition)
            timestamp = Time.now.getlocal.strftime('%d-%b-%Y__%H:%M')
            asset_data = {
                'meta' => {
                    'fileName' => "#{profile_key}.json",
                    'description' => 'Scene-picked profile from Na__ProfileTools__ProfilePathTracer.',
                    'version' => '1.0.0',
                    'lastUpdated' => Time.now.strftime('%d-%b-%Y'),
                    'namingConvention' => 'All custom keys use Na__ prefixed three-stage naming.',
                    'fieldPrefixes' => {
                        'Na__Asset__' => 'Top-level asset metadata and content blocks',
                        'Na__Geometry__' => 'Geometry fields and coordinate metadata',
                        'Na__PanelPlacement__' => 'Reserved placement metadata'
                    },
                    'Meta_ProfileTimestamp' => timestamp,
                    'Meta_ProfileKeywords' => ['Scene Source']
                },
                'Na__Asset__Metadata' => {
                    'Na__Asset__Name' => display_name,
                    'Na__Asset__Code' => profile_key,
                    'Na__Asset__Type' => 'Profile2D',
                    'Na__Asset__Description' => 'Scene-picked profile source.',
                    'Na__Asset__Has2dPlan' => false,
                    'Na__Asset__Has2dElevation' => false,
                    'Na__Asset__Has2dProfile' => true,
                    'Na__Asset__Has3d' => true
                },
                'Na__Asset__Profile2D' => {
                    'Na__Geometry__OriginNote' => 'Local 0,0 = first loop vertex of scene-picked face.',
                    'Na__Geometry__CoordSystem' => 'Y=profile horizontal axis, Z=profile vertical axis | Units=mm',
                    'Na__Geometry__Vertices' => extracted_geometry['profileVertices'],
                    'Na__Geometry__Edges' => extracted_geometry['profileEdges'],
                    'Na__Geometry__Faces' => extracted_geometry['profileFaces']
                },
                'Na__Asset__Mesh3D' => {
                    'Na__Geometry__OriginNote' => 'Local 0,0,0 = first loop vertex of scene-picked face.',
                    'Na__Geometry__CoordSystem' => 'Right-handed | X=profile-width surrogate, Y=profile-height surrogate, Z=0 | Units=mm',
                    'Na__Geometry__BoundingBox' => extracted_geometry['meshBoundingBox'],
                    'Na__Geometry__Counts' => {
                        'Na__Geometry__VertexCount' => extracted_geometry['meshVertices'].length,
                        'Na__Geometry__FaceCount' => extracted_geometry['meshFaces'].length,
                        'Na__Geometry__EdgeCount' => extracted_geometry['meshEdges'].length,
                        'Na__Geometry__HardEdgeCount' => extracted_geometry['meshEdges'].count { |edge| edge['IsSoft'] != true && edge['IsSmooth'] != true },
                        'Na__Geometry__SoftEdgeCount' => extracted_geometry['meshEdges'].count { |edge| edge['IsSoft'] == true },
                        'Na__Geometry__SmoothEdgeCount' => extracted_geometry['meshEdges'].count { |edge| edge['IsSmooth'] == true }
                    },
                    'Na__Geometry__Vertices' => extracted_geometry['meshVertices'],
                    'Na__Geometry__Faces' => extracted_geometry['meshFaces'],
                    'Na__Geometry__Edges' => extracted_geometry['meshEdges']
                }
            }

            profile_payload = {
                'profileKey' => profile_key,
                'displayName' => display_name,
                'category' => 'Scene Source',
                'isEnabled' => true,
                'sourceType' => 'scene_pick_face',
                'profileData' => {
                    'type' => 'na_unified_asset',
                    'schemaContract' => 'meta + Na__Asset__Metadata + Na__Asset__Profile2D + Na__Asset__Mesh3D',
                    'assetData' => asset_data,
                    'units' => 'mm'
                }
            }

            @na_profile_data = profile_payload
            @na_display_name = display_name
            @na_definition_pid = component_definition.persistent_id

            {
                'isValid' => true,
                'reason' => nil,
                'statusMessage' => "Scene profile selected: #{display_name}",
                'profileData' => profile_payload
            }
        rescue => error
            {
                'isValid' => false,
                'reason' => "Scene profile extraction failed: #{error.message}"
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internal Geometry Extraction
    # -------------------------------------------------------------------------

        def self.Na__SceneProfileRegistry__ResolveDefinition(entity)
            return nil unless entity.respond_to?(:definition)
            entity.definition
        end

        def self.Na__SceneProfileRegistry__ResolveEntities(entity)
            return entity.entities if entity.is_a?(Sketchup::Group)
            return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance)
            nil
        end

        def self.Na__SceneProfileRegistry__ResolveDisplayName(entity, component_definition)
            instance_name = entity.respond_to?(:name) ? entity.name.to_s : ''
            return instance_name unless instance_name.strip.empty?

            definition_name = component_definition.respond_to?(:name) ? component_definition.name.to_s : ''
            return definition_name unless definition_name.strip.empty?

            entity.is_a?(Sketchup::Group) ? '<Unnamed Group>' : '<Unnamed Component>'
        end

        def self.Na__SceneProfileRegistry__ExtractUnifiedGeometry(face, instance_transform)
            world_points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(instance_transform) }
            return nil if world_points.length < 3

            normal = face.normal.transform(instance_transform)                       # <-- Face normal in world space
            return nil if normal.length <= 0.001
            normal.normalize!

            world_up = normal.parallel?(Z_AXIS) ? Y_AXIS.clone : Z_AXIS.clone        # <-- World "up" reference; Y fallback for plan-flat faces
            axis_z = Na__ProfileExporter.Na__Exporter__ProjectVectorOntoPlane(world_up, normal)
            return nil if axis_z.length <= 0.001
            axis_z.normalize!

            axis_y = normal * axis_z                                                 # <-- Profile horizontal = normal x axis_z
            return nil if axis_y.length <= 0.001
            axis_y.normalize!

            origin = world_points.first                                              # <-- Preserve current scene-pick origin (first vertex of outer loop)

            profile_vertices = world_points.each_with_index.map do |point, index|
                vector = point - origin
                y_mm = (vector.dot(axis_y) * NA_MM_PER_INCH).round(6)
                z_mm = (vector.dot(axis_z) * NA_MM_PER_INCH).round(6)
                {
                    'VertexId' => format('V%03d', index + 1),
                    'PosY_mm' => y_mm,
                    'PosZ_mm' => z_mm
                }
            end

            profile_edges = []
            mesh_edges = []
            face.outer_loop.edges.each_with_index do |edge, index|
                start_vertex_id = format('V%03d', index + 1)
                end_vertex_id = format('V%03d', ((index + 1) % profile_vertices.length) + 1)
                edge_id = format('E%03d', index + 1)

                profile_edges << {
                    'EdgeId' => edge_id,
                    'StartVertex' => start_vertex_id,
                    'EndVertex' => end_vertex_id
                }

                material_name = edge.material ? edge.material.display_name.to_s : ''
                colour_id = Na__ProfileExporter.Na__Exporter__ResolveEdgeColourId(material_name)
                colour_hex = Na__ProfileExporter.Na__Exporter__ResolveEdgeColourHex(edge, colour_id)
                mesh_edges << {
                    'EdgeId' => edge_id,
                    'StartVertex' => start_vertex_id,
                    'EndVertex' => end_vertex_id,
                    'IsSoft' => edge.soft? == true,
                    'IsSmooth' => edge.smooth? == true,
                    'IsHidden' => edge.hidden? == true,
                    'CastsShadows' => edge.respond_to?(:casts_shadows?) ? (edge.casts_shadows? == true) : true,
                    'EdgeMaterialName' => material_name,
                    'EdgeColourId' => colour_id,
                    'EdgeColourHex' => colour_hex
                }
            end

            profile_faces = [{
                'FaceId' => 'F001',
                'OuterLoopVertices' => profile_vertices.map { |vertex| vertex['VertexId'] }
            }]

            mesh_vertices = Na__ProfileExporter.Na__Exporter__BuildMeshVertices(profile_vertices)
            mesh_faces = Na__ProfileExporter.Na__Exporter__BuildMeshFaces(profile_faces)
            mesh_bounding_box = Na__ProfileExporter.Na__Exporter__BuildMeshBoundingBox(mesh_vertices)

            {
                'profileVertices' => profile_vertices,
                'profileEdges' => profile_edges,
                'profileFaces' => profile_faces,
                'meshVertices' => mesh_vertices,
                'meshEdges' => mesh_edges,
                'meshFaces' => mesh_faces,
                'meshBoundingBox' => mesh_bounding_box
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
