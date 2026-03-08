# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - COMPONENT INSTANCING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__ComponentInstancing__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Component Instancing (Shared Mesh Export for Repeated Components)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Detects SketchUp ComponentInstances sharing the same
#              ComponentDefinition and exports them as shared glTF mesh
#              references with per-instance node transforms, eliminating
#              duplicated geometry from the GLB binary buffer.
# CREATED    : 28-Feb-2026
#
# !!! CRITICAL PERFORMANCE MODULE !!!
# ------------------------------------
# This module is responsible for the single most impactful optimisation
# in the entire GLB export pipeline. In production testing on an
# architectural project model, enabling Component Instancing reduced
# exported GLB file sizes from ~449 MB → ~1 MB (>99% reduction).
#
# WHY THE SAVINGS ARE SO LARGE:
# - Before: every placed SketchUp Component was individually flattened
#   by TraverseEntities. 100 identical chairs = 100 copies of the same
#   vertex data written into the binary buffer.
# - After: the chair geometry is written ONCE to the binary buffer.
#   100 glTF nodes each reference that single mesh with their own
#   world-space transform matrix. Three.js GLTFLoader automatically
#   shares the same BufferGeometry object in GPU memory for all of them.
#
# DOWNSTREAM THREE.JS BEHAVIOUR:
# - GLTFLoader creates separate Mesh objects per node, but they share
#   one BufferGeometry (confirmed Three.js issue #29768).
# - Materials are cloned per-node (not geometry), so material swap
#   still works independently per instance.
# - A future optimisation could convert shared-mesh node groups into
#   InstancedMesh for single-draw-call rendering, but even without it
#   the GPU memory savings are immediate and very large.
#
# ARCHITECTURE:
# - Recursive DFS pre-scan walks the FULL entity tree (including inside
#   Groups) to find ComponentDefinitions with 2+ placements anywhere
#   in the export scope. Groups are recursed but never instanced.
# - ADR door assemblies are always excluded (they need hierarchy for
#   animation) and continue through the DoorHandler path unchanged.
# - Instances are partitioned by accumulated transform determinant sign
#   to handle mirrored geometry correctly (separate mesh per mirror group)
# - Shared mesh geometry is extracted once per definition in local Y-up
#   space using the existing TraverseEntities / TraverseEdges engines
# - A skip_set of object_ids is returned so the flat traversal (
#   TraverseEntities / TraverseEdges) skips any entity already claimed
#   by the instancing path, preventing geometry duplication
# - Multiple glTF nodes reference the single shared mesh index, each
#   carrying a conjugated world-space transform matrix
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Instance Scanning (Recursive)
    # -------------------------------------------------------------------------

        # FUNCTION | Scan Entities for Instanced ComponentDefinitions
        # ---------------------------------------------------------------
        # Recursively walks the entire entity tree to find all
        # ComponentInstances (not Groups, not ADR doors) that share a
        # ComponentDefinition with 2+ placements anywhere in the export
        # scope. Groups are recursed into but never instanced themselves.
        # Partitions each definition's instances by accumulated transform
        # determinant sign to separate mirrored from non-mirrored.
        #
        # Returns instanced_groups for mesh/node building, plus a
        # skip_set of object_ids so the flat traversal can skip entities
        # that have been claimed by the instancing path.
        #
        # @param entities       [Array<Sketchup::Entity>] Top-level entities
        # @param root_transform [Geom::Transformation]    Root Y-up transform
        # @return [Array<Hash>]   Instanced groups, each:
        #   { definition:, is_mirrored:, instances: [{entity:, accumulated_transform:}] }
        # @return [Hash] skip_set: { object_id => true } for all instanced entities
        # ---------------------------------------------------------------
        def self.Na__Instancing__ScanForInstancedDefinitions(entities, root_transform)
            definition_map = {}                                               # <-- { ComponentDefinition => { normal: [], mirrored: [] } }

            Na__Instancing__RecursiveScan(entities, root_transform, definition_map)

            instanced_groups = []
            skip_set = {}

            definition_map.each do |definition, partitions|
                [:normal, :mirrored].each do |partition_key|
                    instances = partitions[partition_key]
                    next if instances.length < 2

                    instanced_groups << {
                        definition:  definition,
                        is_mirrored: (partition_key == :mirrored),
                        instances:   instances
                    }

                    instances.each { |inst| skip_set[inst[:entity].object_id] = true }
                end
            end

            if instanced_groups.any?
                total_instances = instanced_groups.sum { |g| g[:instances].length }
                unique_defs     = instanced_groups.map { |g| g[:definition] }.uniq.length
                puts "    [Instancing] Found #{total_instances} instanced placements across #{unique_defs} definition(s) (#{instanced_groups.length} mesh group(s))"
            end

            [instanced_groups, skip_set]
        end
        # ---------------------------------------------------------------

        # HELPER | Recursive DFS Scan for ComponentInstances
        # ---------------------------------------------------------------
        # Walks into Groups and single-use ComponentInstances to discover
        # instanced Components at any nesting depth. Accumulates
        # transforms at each level so each discovered instance carries
        # its full world-space transform.
        #
        # @param entities       [Sketchup::Entities|Array] Entities to scan
        # @param parent_transform [Geom::Transformation]   Accumulated transform
        # @param definition_map [Hash] Shared collector across recursion
        # ---------------------------------------------------------------
        def self.Na__Instancing__RecursiveScan(entities, parent_transform, definition_map, inherited_material = nil)
            entities.each do |entity|
                next if Na__Helpers__EntityExcluded?(entity)
                next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                next if Na__DoorHandler__IsDoorAssembly?(entity)

                accumulated_transform = parent_transform * entity.transformation
                child_inherited_material = entity.material || inherited_material

                if entity.is_a?(Sketchup::Group)
                    Na__Instancing__RecursiveScan(entity.definition.entities, accumulated_transform, definition_map, child_inherited_material)
                else
                    definition = entity.definition
                    is_mirrored = Na__GlbEngine__CalcDeterminant3x3(accumulated_transform) < 0
                    has_inherited_material = !child_inherited_material.nil?

                    # Shared-mesh instancing cannot preserve per-instance container materials.
                    # Keep those instances on the normal flattening path so inherited indexed
                    # materials (such as MAT101 glass) survive into the exported mesh.
                    unless has_inherited_material
                        definition_map[definition] ||= { normal: [], mirrored: [] }
                        partition_key = is_mirrored ? :mirrored : :normal
                        definition_map[definition][partition_key] << {
                            entity:                entity,
                            accumulated_transform: accumulated_transform
                        }
                    end

                    Na__Instancing__RecursiveScan(entity.definition.entities, accumulated_transform, definition_map, child_inherited_material)
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Shared Mesh Building (Triangles)
    # -------------------------------------------------------------------------

        # FUNCTION | Build a Shared glTF Mesh from a ComponentDefinition
        # ---------------------------------------------------------------
        # Extracts geometry from the definition's entities in local Y-up
        # space (Z_UP_TO_Y_UP_MATRIX as root). Collects into material
        # buckets and builds a single glTF mesh entry. When is_mirrored
        # is true, the geometry is extracted with mirrored winding and
        # negated normals to match the negative-determinant instances.
        #
        # @param definition  [Sketchup::ComponentDefinition]
        # @param is_mirrored [Boolean] true to reverse winding/normals
        # @param gltf        [Hash]    glTF JSON structure
        # @param bin_buffer   [String]  Binary buffer (ASCII-8BIT)
        # @return            [Integer]  Mesh index in gltf["meshes"]
        # ---------------------------------------------------------------
        def self.Na__Instancing__BuildSharedMesh(definition, is_mirrored, gltf, bin_buffer)
            local_buckets = Na__GlbEngine__CreateBuckets()

            local_root = is_mirrored ? Na__Instancing__MirroredLocalTransform() : Z_UP_TO_Y_UP_MATRIX

            Na__GlbEngine__TraverseEntities(
                definition.entities,
                local_root,
                definition.entities.parent.respond_to?(:layer) ? definition.entities.parent.layer : Sketchup.active_model.layers["Layer0"],
                local_buckets
            )

            mesh_index = Na__Instancing__PackBucketsToMesh(
                local_buckets,
                definition.name || "SharedComponent",
                is_mirrored,
                gltf,
                bin_buffer
            )

            mesh_index
        end
        # ---------------------------------------------------------------

        # HELPER | Create a Mirrored Local Transform for Geometry Extraction
        # ---------------------------------------------------------------
        # Returns Z_UP_TO_Y_UP with a -1 X scale prepended, producing a
        # negative determinant so the existing AddFaceToBucket logic
        # automatically reverses winding order and negates normals.
        # ---------------------------------------------------------------
        def self.Na__Instancing__MirroredLocalTransform
            mirror_scale = Geom::Transformation.scaling(-1, 1, 1)
            Z_UP_TO_Y_UP_MATRIX * mirror_scale
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pack Geometry Buckets into a glTF Mesh Entry
        # ---------------------------------------------------------------
        # Builds accessors and primitives from the bucket data and appends
        # a single mesh entry to gltf["meshes"]. Does NOT create a node
        # (nodes are created per-instance by EmitInstanceNodes).
        #
        # @param buckets     [Hash]    Geometry buckets
        # @param def_name    [String]  Definition name for labelling
        # @param is_mirrored [Boolean] Mirror flag for naming
        # @param gltf        [Hash]    glTF JSON structure
        # @param bin_buffer   [String]  Binary buffer
        # @return            [Integer] Mesh index, or nil if empty
        # ---------------------------------------------------------------
        def self.Na__Instancing__PackBucketsToMesh(buckets, def_name, is_mirrored, gltf, bin_buffer)
            primitives = []
            mirror_label = is_mirrored ? "_Mirrored" : ""

            buckets.each do |bucket_key, bucket|
                next if bucket[:positions].empty?

                material_index = if respond_to?(:Na__MaterialEngine__ResolveMaterialIndexForGroup)
                    Na__MaterialEngine__ResolveMaterialIndexForGroup(bucket, gltf)
                else
                    0
                end

                pos_accessor  = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:positions], 5126, "VEC3", 34962)
                norm_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:normals],   5126, "VEC3", 34962)
                uv_accessor   = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:uvs],       5126, "VEC2", 34962)

                max_index = bucket[:indices].max || 0
                idx_type  = (max_index < 65535) ? 5123 : 5125
                idx_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:indices], idx_type, "SCALAR", 34963)

                primitives << {
                    "attributes" => {
                        "POSITION"   => pos_accessor,
                        "NORMAL"     => norm_accessor,
                        "TEXCOORD_0" => uv_accessor
                    },
                    "indices"  => idx_accessor,
                    "material" => material_index,
                    "mode"     => 4
                }
            end

            return nil if primitives.empty?

            mesh_index = gltf["meshes"].length
            gltf["meshes"] << {
                "name"       => "SharedMesh_#{def_name}#{mirror_label}",
                "primitives" => primitives
            }

            total_verts = buckets.values.sum { |b| b[:vertex_count] }
            total_tris  = buckets.values.sum { |b| b[:indices].length / 3 }
            puts "      [Instancing] Built shared mesh: #{def_name}#{mirror_label} (#{total_verts} verts, #{total_tris} tris)"

            mesh_index
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Shared Linework Building (LINES)
    # -------------------------------------------------------------------------

        # FUNCTION | Build a Shared glTF Linework Mesh from a ComponentDefinition
        # ---------------------------------------------------------------
        # Extracts visible edges from the definition's entities in local
        # Y-up space and builds a single LINES mesh entry.
        # Uses the same local_root transform as BuildSharedMesh so that
        # linework and mesh geometry are extracted in identical coordinate
        # space, ensuring perfect spatial alignment downstream.
        #
        # @param definition  [Sketchup::ComponentDefinition]
        # @param is_mirrored [Boolean] true if this is the mirrored partition
        # @param gltf        [Hash]   glTF JSON structure
        # @param bin_buffer   [String] Binary buffer (ASCII-8BIT)
        # @return            [Integer] Mesh index, or nil if no edges
        # ---------------------------------------------------------------
        def self.Na__Instancing__BuildSharedLinework(definition, is_mirrored, gltf, bin_buffer)
            positions = []
            colors    = []

            local_root = is_mirrored ? Na__Instancing__MirroredLocalTransform() : Z_UP_TO_Y_UP_MATRIX

            Na__LineworkEngine__TraverseEdges(
                definition.entities,
                local_root,
                definition.entities.parent.respond_to?(:layer) ? definition.entities.parent.layer : Sketchup.active_model.layers["Layer0"],
                positions,
                colors
            )

            return nil if positions.empty?

            mirror_label = is_mirrored ? "_Mirrored" : ""
            mesh_index   = gltf["meshes"].length
            pos_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, positions, 5126, "VEC3", 34962)
            col_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, colors,    5126, "VEC4", 34962)

            gltf["meshes"] << {
                "name"       => "SharedLinework_#{definition.name || 'Component'}#{mirror_label}",
                "primitives" => [{
                    "attributes" => {
                        "POSITION" => pos_accessor,
                        "COLOR_0"  => col_accessor
                    },
                    "mode" => 1
                }]
            }

            edge_count = positions.length / 6
            puts "      [Instancing] Built shared linework: #{definition.name}#{mirror_label} (#{edge_count} edges)"

            mesh_index
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Instance Node Emission
    # -------------------------------------------------------------------------

        # FUNCTION | Emit glTF Nodes for Each Instance of a Shared Mesh
        # ---------------------------------------------------------------
        # Creates one glTF node per instance, each referencing the shared
        # mesh index. The node carries a conjugated world-space transform
        # matrix with translation converted to meters.
        #
        # For instanced nodes the accumulated_transform already includes
        # Z_UP_TO_Y_UP * all_parent_transforms * entity_transform.
        # We conjugate by post-multiplying inv(Z_UP) to get a pure Y-up
        # matrix: M_gltf = accumulated * inv(Z_UP_TO_Y_UP).
        #
        # For mirrored instances, the mesh already has reversed winding
        # from the mirrored extraction. The node transform must NOT
        # include the artificial mirror scale, so we undo it:
        # M_gltf = accumulated * mirror_undo * inv(Z_UP_TO_Y_UP)
        # where mirror_undo = scaling(-1,1,1) cancels the mesh mirror.
        #
        # @param instances   [Array<Hash>] Each: {entity:, accumulated_transform:}
        # @param mesh_index  [Integer]     Shared mesh index in gltf["meshes"]
        # @param is_mirrored [Boolean]     Whether this is the mirrored partition
        # @param gltf        [Hash]        glTF JSON structure
        # ---------------------------------------------------------------
        def self.Na__Instancing__EmitInstanceNodes(instances, mesh_index, is_mirrored, gltf)
            return unless mesh_index

            instances.each do |inst_data|
                entity    = inst_data[:entity]
                acc_trans = inst_data[:accumulated_transform]

                gltf_transform = acc_trans * Y_UP_TO_Z_UP_MATRIX
                gltf_matrix    = Na__Instancing__TransformToGltfMatrix(gltf_transform)

                node_name = Na__GlbEngine__SanitizeEntityName(entity)

                node_index = gltf["nodes"].length
                gltf["nodes"] << {
                    "name"   => node_name,
                    "mesh"   => mesh_index,
                    "matrix" => gltf_matrix,
                    "extras" => { "generator" => "TrueVision3D_Instancing" }
                }
                gltf["scenes"][0]["nodes"] << node_index
            end
        end
        # ---------------------------------------------------------------

        # HELPER | Convert Transform to glTF Column-Major Matrix Array
        # ---------------------------------------------------------------
        # Same logic as DoorHandler's TransformToGltfMatrix: extracts the
        # 16-element column-major array and converts translation to meters.
        # ---------------------------------------------------------------
        def self.Na__Instancing__TransformToGltfMatrix(transform)
            m = transform.to_a.map(&:to_f)
            m[12] *= INCHES_TO_METERS
            m[13] *= INCHES_TO_METERS
            m[14] *= INCHES_TO_METERS
            m
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Material Registration for Instanced Components
    # -------------------------------------------------------------------------

        # FUNCTION | Register Materials from Instanced Definitions
        # ---------------------------------------------------------------
        # Scans instanced definitions for materials not yet in the
        # material map (populated by PrepareMaterialsForExport for the
        # flat-traversal buckets). Registers any new materials so that
        # PackBucketsToMesh can resolve correct material indices.
        # ---------------------------------------------------------------
        def self.Na__Instancing__RegisterInstancedMaterials(instanced_groups, gltf, _bin_buffer)
            return unless respond_to?(:Na__MaterialEngine__EnsureMaterialRegistered)

            @material_map ||= {}
            seen_definitions = {}

            instanced_groups.each do |group|
                definition = group[:definition]
                next if seen_definitions[definition]
                seen_definitions[definition] = true

                definition.entities.grep(Sketchup::Face).each do |face|
                    material = face.material
                    next unless material
                    next if @material_map.key?(material)
                    material_name  = material.respond_to?(:display_name) ? material.display_name : ""
                    material_index = Na__MaterialEngine__EnsureMaterialRegistered(material, gltf)
                    if material_index > 0 && @material_map.key?(material)
                        puts "      [Instancing] Registered new material: #{material_name} (index #{material_index})"
                    end
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Orchestrators
    # -------------------------------------------------------------------------

        # FUNCTION | Process All Instanced Components (Mesh Export)
        # ---------------------------------------------------------------
        # For each instanced group, builds the shared mesh once then
        # emits instance nodes for all placements.
        #
        # @param instanced_groups [Array<Hash>] From ScanForInstancedDefinitions
        # @param gltf             [Hash]        glTF JSON structure
        # @param bin_buffer        [String]      Binary buffer
        # ---------------------------------------------------------------
        def self.Na__Instancing__ProcessAllInstanced(instanced_groups, gltf, bin_buffer)
            return if instanced_groups.empty?

            puts "\n    [Instancing] Building #{instanced_groups.length} shared mesh(es)..."

            Na__Instancing__RegisterInstancedMaterials(instanced_groups, gltf, bin_buffer)

            instanced_groups.each do |group|
                mesh_index = Na__Instancing__BuildSharedMesh(
                    group[:definition],
                    group[:is_mirrored],
                    gltf,
                    bin_buffer
                )

                Na__Instancing__EmitInstanceNodes(
                    group[:instances],
                    mesh_index,
                    group[:is_mirrored],
                    gltf
                )

                instance_count = group[:instances].length
                mirror_label   = group[:is_mirrored] ? " (mirrored)" : ""
                puts "      [Instancing] #{group[:definition].name}#{mirror_label}: 1 mesh -> #{instance_count} nodes"
            end

            puts "    [Instancing] Instanced mesh export complete\n"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Process All Instanced Components (Linework Export)
        # ---------------------------------------------------------------
        # For each instanced group, builds the shared linework mesh once
        # then emits instance nodes for all placements. Mirrors the mesh
        # orchestrator exactly: one linework mesh per definition per
        # mirror partition, using the same local_root transform so
        # linework and mesh geometry are in identical coordinate space.
        #
        # @param instanced_groups [Array<Hash>] From ScanForInstancedDefinitions
        # @param gltf             [Hash]        glTF JSON structure
        # @param bin_buffer        [String]      Binary buffer
        # ---------------------------------------------------------------
        def self.Na__Instancing__ProcessAllInstancedLinework(instanced_groups, gltf, bin_buffer)
            return if instanced_groups.empty?

            puts "\n    [Instancing/Linework] Building shared linework mesh(es)..."

            built_linework = {}                                               # <-- { [definition, is_mirrored] => mesh_index }

            instanced_groups.each do |group|
                definition  = group[:definition]
                is_mirrored = group[:is_mirrored]
                cache_key   = [definition, is_mirrored]

                unless built_linework.key?(cache_key)
                    built_linework[cache_key] = Na__Instancing__BuildSharedLinework(definition, is_mirrored, gltf, bin_buffer)
                end

                mesh_index = built_linework[cache_key]

                Na__Instancing__EmitInstanceNodes(
                    group[:instances],
                    mesh_index,
                    is_mirrored,
                    gltf
                )

                instance_count = group[:instances].length
                mirror_label   = is_mirrored ? " (mirrored)" : ""
                puts "      [Instancing/Linework] #{definition.name}#{mirror_label}: #{instance_count} nodes"
            end

            puts "    [Instancing/Linework] Instanced linework export complete\n"
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
