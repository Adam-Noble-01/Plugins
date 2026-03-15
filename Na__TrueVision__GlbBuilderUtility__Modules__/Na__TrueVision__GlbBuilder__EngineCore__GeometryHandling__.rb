# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - GEOMETRY HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__GeometryHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Geometry Handling (Virtual Flattening Engine)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Non-destructive geometry extraction with recursive traversal,
#              mirror correction, normal matrix transforms, vertex deduplication,
#              and direct binary buffer packing for glTF 2.0 / GLB export.
# CREATED    : 2025
# REWRITTEN  : 2026-02-10 (v1.1.0 - Virtual Flattening Engine)
#
# ARCHITECTURE:
# - Recursive DFS traversal of the SketchUp scene graph
# - Matrix accumulation for world-space vertex extraction (non-destructive)
# - Determinant check for mirrored geometry with winding order correction
# - Inverse-transpose normal matrix for correct normal transformation
# - Vertex deduplication cache for compact binary output
# - BucketManager: collects geometry by layer::material for glTF mesh generation
# - Direct binary packing with 4-byte alignment per glTF 2.0 spec
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        # CONSTANT | Z-Up to Y-Up Coordinate System Conversion Matrix
        # ---------------------------------------------------------------
        # SketchUp uses Z-up right-handed; glTF uses Y-up right-handed.
        # This is a -90 degree rotation around the X axis.
        # Column-major order for Geom::Transformation.new:
        #   Col0: [1, 0, 0, 0]   Col1: [0, 0,-1, 0]
        #   Col2: [0, 1, 0, 0]   Col3: [0, 0, 0, 1]
        # Maps SketchUp (x, y, z) to glTF (x, z, -y)
        # Determinant = +1 (pure rotation, no mirroring introduced)
        # ---------------------------------------------------------------
        Z_UP_TO_Y_UP_MATRIX = Geom::Transformation.new([
            1.0,  0.0,  0.0, 0.0,
            0.0,  0.0, -1.0, 0.0,
            0.0,  1.0,  0.0, 0.0,
            0.0,  0.0,  0.0, 1.0
        ])
        # ---------------------------------------------------------------

        # CONSTANT | Include Hard Edges in Mesh GLB
        # ---------------------------------------------------------------
        # Set to true to include hard edges as LINES primitives inside mesh GLBs.
        # Set to false for clean separation (edges only in LineworkModel GLBs).
        # ---------------------------------------------------------------
        MESH_MODEL_INCLUDE_EDGES = false
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Recursive Scene Graph Traversal
    # -------------------------------------------------------------------------

        # FUNCTION | Traverse Entities Recursively (Virtual Flattening)
        # ---------------------------------------------------------------
        # Walks the scene graph depth-first, accumulating world transforms.
        # Faces are extracted at their final world-space coordinates.
        # Hard edges are collected for optional LINES primitive export.
        # Never modifies the SketchUp model.
        #
        # When door_assemblies is non-nil, entities with ADR-prefixed
        # names are detected and diverted to the door handler instead
        # of being flattened into material buckets. When nil (default),
        # no door detection occurs — zero overhead for non-door exports.
        #
        # Material resolution is FACE-ONLY: only face.material and
        # face.back_material are used. Group/component container
        # materials are intentionally NOT inherited.
        #
        # @param entities         [Sketchup::Entities]      Children to process
        # @param parent_transform [Geom::Transformation]    Accumulated world matrix
        # @param parent_layer     [Sketchup::Layer]         Inherited layer context
        # @param buckets          [Hash]                    BucketManager geometry store
        # @param door_assemblies  [Array|nil]               Collected door records (nil = disabled)
        # @param instanced_skip_set [Hash|nil]              Object IDs to skip (instancing)
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__TraverseEntities(entities, parent_transform, parent_layer, buckets, door_assemblies = nil, instanced_skip_set = nil)
            is_mirrored   = Na__GlbEngine__CalcDeterminant3x3(parent_transform) < 0
            normal_matrix = Na__GlbEngine__CalcNormalMatrix(parent_transform)

            entities.each do |entity|
                next if Na__Helpers__EntityExcluded?(entity)

                if entity.is_a?(Sketchup::Face)
                    raw_layer = entity.layer.name
                    layer_name = (raw_layer == "Layer0" || Na__Helpers__LayerTreatedAsUntagged?(raw_layer)) ? parent_layer.name : raw_layer
                    Na__GlbEngine__AddFaceToBucket(entity, parent_transform, normal_matrix, is_mirrored, layer_name, buckets)

                elsif entity.is_a?(Sketchup::Edge) && MESH_MODEL_INCLUDE_EDGES
                    if !entity.soft? && !entity.smooth?
                        raw_layer = entity.layer.name
                        layer_name = (raw_layer == "Layer0" || Na__Helpers__LayerTreatedAsUntagged?(raw_layer)) ? parent_layer.name : raw_layer
                        Na__GlbEngine__AddEdgeToBucket(entity, parent_transform, layer_name, buckets)
                    end

                elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next if instanced_skip_set && instanced_skip_set.key?(entity.object_id)

                    child_transform = parent_transform * entity.transformation
                    raw_layer = entity.layer.name
                    child_layer = (raw_layer == "Layer0" || Na__Helpers__LayerTreatedAsUntagged?(raw_layer)) ? parent_layer : entity.layer

                    if door_assemblies && Na__DoorHandler__IsDoorAssembly?(entity)
                        door_assemblies << {
                            entity:                entity,
                            accumulated_transform: child_transform
                        }
                        puts "      [DoorHandler] Detected door assembly: #{Na__DoorHandler__GetEntityName(entity)}"
                        next
                    end

                    Na__GlbEngine__TraverseEntities(entity.definition.entities, child_transform, child_layer, buckets, door_assemblies, instanced_skip_set)
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Linear Algebra Utilities
    # -------------------------------------------------------------------------

        # FUNCTION | Calculate 3x3 Determinant of Transform
        # ---------------------------------------------------------------
        # Extracts the upper-left 3x3 rotation/scale sub-matrix from the
        # Geom::Transformation (column-major to_a) and computes its
        # determinant. A negative determinant indicates mirrored geometry
        # (e.g. from SketchUp "Flip Along" or scale -1).
        #
        # Column-major layout of Geom::Transformation#to_a:
        #   | m[0] m[4] m[8]  |     Row 0: m00  m01  m02
        #   | m[1] m[5] m[9]  |     Row 1: m10  m11  m12
        #   | m[2] m[6] m[10] |     Row 2: m20  m21  m22
        #
        # @param transform [Geom::Transformation]
        # @return [Float] determinant (negative = mirrored)
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__CalcDeterminant3x3(transform)
            m = transform.to_a
            m[0] * (m[5] * m[10] - m[6] * m[9]) -
            m[4] * (m[1] * m[10] - m[2] * m[9]) +
            m[8] * (m[1] * m[6]  - m[2] * m[5])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Normal Matrix (Cofactor of Upper-Left 3x3)
        # ---------------------------------------------------------------
        # The correct transform for normal vectors is the inverse-transpose
        # of the upper-left 3x3: N = (M^-1)^T = cofactor(M) / det(M).
        # Since we normalize the result after transformation, the 1/det
        # factor is unnecessary and we return just the cofactor matrix.
        #
        # This preserves perpendicularity of normals under non-uniform
        # scaling and shearing transforms.
        #
        # @param transform [Geom::Transformation]
        # @return [Array<Float>] 9-element flat array [C00..C22] row-major
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__CalcNormalMatrix(transform)
            m = transform.to_a
            [
                 (m[5] * m[10] - m[9] * m[6]),  -(m[1] * m[10] - m[9] * m[2]),   (m[1] * m[6] - m[5] * m[2]),
                -(m[4] * m[10] - m[8] * m[6]),   (m[0] * m[10] - m[8] * m[2]),  -(m[0] * m[6] - m[4] * m[2]),
                 (m[4] * m[9]  - m[8] * m[5]),  -(m[0] * m[9]  - m[8] * m[1]),   (m[0] * m[5] - m[4] * m[1])
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Transform Normal Vector Using Cofactor Matrix
        # ---------------------------------------------------------------
        # Applies the cofactor (normal) matrix to a direction vector and
        # normalizes the result. Falls back to Y-up if degenerate.
        #
        # @param normal_matrix [Array<Float>] 9-element cofactor matrix
        # @param nx, ny, nz    [Float]        Local-space normal components
        # @return              [Array<Float>] [nx, ny, nz] world-space normalized
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__TransformNormal(normal_matrix, nx, ny, nz)
            c = normal_matrix
            rx = c[0] * nx + c[1] * ny + c[2] * nz
            ry = c[3] * nx + c[4] * ny + c[5] * nz
            rz = c[6] * nx + c[7] * ny + c[8] * nz

            len = Math.sqrt(rx * rx + ry * ry + rz * rz)
            if len > 1.0e-10
                [rx / len, ry / len, rz / len]
            else
                [0.0, 1.0, 0.0]  # Fallback: Y-up normal
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Bucket Management (Geometry Collection by Layer::Material)
    # -------------------------------------------------------------------------

        # FUNCTION | Create Empty Bucket Store
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__CreateBuckets
            {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get or Create a Geometry Bucket
        # ---------------------------------------------------------------
        # Each bucket collects geometry for one layer::material combination.
        # Includes vertex deduplication cache and separate edge storage.
        #
        # @param buckets    [Hash]                    Main bucket store
        # @param bucket_key [String]                  "LayerName::MaterialName"
        # @param material   [Sketchup::Material|nil]  SketchUp material reference
        # @return           [Hash]                    The bucket for this key
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__GetOrCreateBucket(buckets, bucket_key, material)
            buckets[bucket_key] ||= {
                :material          => material,
                :positions         => [],        # Flat Float array [x,y,z, x,y,z, ...]
                :normals           => [],        # Flat Float array [nx,ny,nz, ...]
                :uvs               => [],        # Flat Float array [u,v, u,v, ...]
                :indices           => [],        # Triangle vertex indices
                :vertex_cache      => {},        # Dedup: [pos+norm+uv key] => index
                :vertex_count      => 0,         # Next available vertex index
                :edge_positions    => [],        # Flat Float array for edge vertices
                :edge_indices      => [],        # Line segment indices
                :edge_vertex_count => 0          # Next available edge vertex index
            }
            buckets[bucket_key]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Effective Face Material (Face-Only)
        # ---------------------------------------------------------------
        # Returns the face's own front material, or back material as
        # fallback. Does NOT inherit from parent groups/components --
        # unpainted faces resolve to nil (Default whitecard).
        #
        # @param face [Sketchup::Face]
        # @return     [Sketchup::Material|nil]
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__ResolveEffectiveFaceMaterial(face)
            face.material || face.back_material
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add Face Geometry to Bucket
        # ---------------------------------------------------------------
        # Extracts a triangulated mesh from a SketchUp Face, transforms
        # vertex positions to world space (Y-up, meters), transforms
        # normals via the inverse-transpose cofactor matrix, extracts UVs,
        # deduplicates vertices, and corrects winding order for mirrored
        # geometry (det < 0 → swap 2nd and 3rd triangle indices).
        #
        # Material resolution is face-only (face.material || face.back_material).
        #
        # @param face           [Sketchup::Face]
        # @param transform      [Geom::Transformation] Accumulated world transform
        # @param normal_matrix  [Array<Float>]          9-element cofactor matrix
        # @param is_mirrored    [Boolean]               true if det(M) < 0
        # @param layer_name     [String]                Resolved layer name
        # @param buckets        [Hash]                  BucketManager store
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__AddFaceToBucket(face, transform, normal_matrix, is_mirrored, layer_name, buckets)
            material = Na__GlbEngine__ResolveEffectiveFaceMaterial(face)
            material_name = material ? material.display_name : "Default"
            bucket_key = "#{layer_name}::#{material_name}"
            bucket = Na__GlbEngine__GetOrCreateBucket(buckets, bucket_key, material)

            # Extract triangulated mesh with UV data
            # Flags: 4 (PolygonMeshPoints) | 1 (UVQFront) | 2 (UVQBack) = 7
            mesh = face.mesh(7)

            (1..mesh.count_polygons).each do |poly_index|
                polygon = mesh.polygon_at(poly_index)
                next unless polygon && polygon.length >= 3

                tri_indices = []

                polygon.each do |signed_index|
                    point_index = signed_index.abs

                    # --- Position: local → world (Y-up, inches) → meters ---
                    local_point = mesh.point_at(point_index)
                    world_point = transform * local_point
                    px = world_point.x.to_f * INCHES_TO_METERS
                    py = world_point.y.to_f * INCHES_TO_METERS
                    pz = world_point.z.to_f * INCHES_TO_METERS

                    # --- Normal: transform via inverse-transpose cofactor matrix ---
                    # The cofactor matrix = det(M) * (M^-1)^T. When det(M) < 0
                    # (mirrored geometry), this introduces an extra sign flip that
                    # causes normals to point inward. We correct by negating the
                    # normal when mirrored, restoring the correct outward direction.
                    local_normal = mesh.normal_at(point_index)
                    nx, ny, nz = Na__GlbEngine__TransformNormal(
                        normal_matrix,
                        local_normal.x.to_f,
                        local_normal.y.to_f,
                        local_normal.z.to_f
                    )
                    if is_mirrored
                        nx = -nx
                        ny = -ny
                        nz = -nz
                    end

                    # --- UVs: extract with perspective correction (UVQ) ---
                    u = 0.0
                    v = 0.0
                    begin
                        uvq = mesh.uv_at(point_index, true)  # Front-face UVs
                        if uvq
                            q = (uvq.z.to_f.abs < 1.0e-10) ? 1.0 : uvq.z.to_f
                            u = uvq.x.to_f / q
                            v = 1.0 - (uvq.y.to_f / q)  # Flip V for glTF (top-left origin)
                        end
                    rescue => _uv_error
                        u = 0.0
                        v = 0.0
                    end

                    # --- Vertex deduplication via cache ---
                    cache_key = [
                        px.round(6), py.round(6), pz.round(6),
                        nx.round(6), ny.round(6), nz.round(6),
                        u.round(6),  v.round(6)
                    ]

                    if bucket[:vertex_cache].key?(cache_key)
                        tri_indices << bucket[:vertex_cache][cache_key]
                    else
                        idx = bucket[:vertex_count]
                        bucket[:vertex_cache][cache_key] = idx
                        bucket[:positions].push(px, py, pz)
                        bucket[:normals].push(nx, ny, nz)
                        bucket[:uvs].push(u, v)
                        bucket[:vertex_count] = idx + 1
                        tri_indices << idx
                    end
                end

                # --- Winding order correction for mirrored geometry ---
                # If determinant < 0, the transform inverts handedness.
                # Swap 2nd and 3rd indices to restore CCW winding order.
                # Original: [A, B, C]  →  Corrected: [A, C, B]
                if is_mirrored
                    bucket[:indices].push(tri_indices[0], tri_indices[2], tri_indices[1])
                else
                    bucket[:indices].push(tri_indices[0], tri_indices[1], tri_indices[2])
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add Hard Edge to Bucket
        # ---------------------------------------------------------------
        # Exports hard (non-soft, non-smooth) edges as LINES primitives
        # in the glTF output for architectural line-work visualization.
        #
        # @param edge       [Sketchup::Edge]
        # @param transform  [Geom::Transformation] Accumulated world transform
        # @param layer_name [String]                Resolved layer name
        # @param buckets    [Hash]                  BucketManager store
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__AddEdgeToBucket(edge, transform, layer_name, buckets)
            material = edge.material
            material_name = material ? material.display_name : "Default"
            bucket_key = "#{layer_name}::#{material_name}"
            bucket = Na__GlbEngine__GetOrCreateBucket(buckets, bucket_key, material)

            # Transform edge endpoints to world space (Y-up, meters)
            start_pt = transform * edge.start.position
            end_pt   = transform * edge.end.position

            idx = bucket[:edge_vertex_count]

            bucket[:edge_positions].push(
                start_pt.x.to_f * INCHES_TO_METERS,
                start_pt.y.to_f * INCHES_TO_METERS,
                start_pt.z.to_f * INCHES_TO_METERS,
                end_pt.x.to_f   * INCHES_TO_METERS,
                end_pt.y.to_f   * INCHES_TO_METERS,
                end_pt.z.to_f   * INCHES_TO_METERS
            )

            bucket[:edge_indices].push(idx, idx + 1)
            bucket[:edge_vertex_count] = idx + 2
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | glTF / GLB Binary Packing
    # -------------------------------------------------------------------------

        # FUNCTION | Add Accessor + BufferView to glTF Structure
        # ---------------------------------------------------------------
        # Packs a flat numeric array into the binary buffer with correct
        # 4-byte alignment, creates a bufferView and accessor in the glTF
        # JSON, and returns the accessor index.
        #
        # Binary data types (Ruby pack templates):
        #   5126 = FLOAT          → 'e' (32-bit LE float)
        #   5123 = UNSIGNED_SHORT → 'v' (16-bit LE unsigned)
        #   5125 = UNSIGNED_INT   → 'V' (32-bit LE unsigned)
        #
        # Buffer targets:
        #   34962 = ARRAY_BUFFER         (vertex attributes)
        #   34963 = ELEMENT_ARRAY_BUFFER (indices)
        #
        # @param gltf           [Hash]    glTF JSON hash
        # @param bin_buffer     [String]  Binary buffer (ASCII-8BIT)
        # @param data_array     [Array]   Flat numeric values
        # @param component_type [Integer] 5126 / 5123 / 5125
        # @param accessor_type  [String]  "SCALAR" / "VEC2" / "VEC3" / "VEC4"
        # @param buffer_target  [Integer] 34962 / 34963
        # @return               [Integer] Accessor index in gltf["accessors"]
        # ---------------------------------------------------------------
        def self.Na__GltfHelpers__AddAccessor(gltf, bin_buffer, data_array, component_type, accessor_type, buffer_target)
            return nil if data_array.nil? || data_array.empty?

            # Pack binary data based on component type
            packed = case component_type
                when 5126 then data_array.pack('e*')    # Float32 little-endian
                when 5123 then data_array.pack('v*')    # UInt16  little-endian
                when 5125 then data_array.pack('V*')    # UInt32  little-endian
                else raise "Unknown glTF componentType: #{component_type}"
            end

            # Ensure 4-byte alignment before appending new data
            current_size  = bin_buffer.bytesize
            alignment_pad = (4 - (current_size % 4)) % 4
            bin_buffer << ("\x00" * alignment_pad) if alignment_pad > 0

            byte_offset = bin_buffer.bytesize
            byte_length = packed.bytesize
            bin_buffer << packed

            # Create bufferView
            buffer_view_index = gltf["bufferViews"].length
            gltf["bufferViews"] << {
                "buffer"     => 0,
                "byteOffset" => byte_offset,
                "byteLength" => byte_length,
                "target"     => buffer_target
            }

            # Determine element count from accessor type
            components_per_element = case accessor_type
                when "SCALAR" then 1
                when "VEC2"   then 2
                when "VEC3"   then 3
                when "VEC4"   then 4
                else 1
            end
            count = data_array.length / components_per_element

            # Calculate min/max bounds (required for POSITION, recommended for others)
            min_vals = Array.new(components_per_element,  Float::INFINITY)
            max_vals = Array.new(components_per_element, -Float::INFINITY)
            data_array.each_with_index do |val, i|
                comp = i % components_per_element
                fval = val.to_f
                min_vals[comp] = fval if fval < min_vals[comp]
                max_vals[comp] = fval if fval > max_vals[comp]
            end

            # Create accessor
            accessor_index = gltf["accessors"].length
            gltf["accessors"] << {
                "bufferView"    => buffer_view_index,
                "byteOffset"    => 0,
                "componentType" => component_type,
                "count"         => count,
                "type"          => accessor_type,
                "min"           => min_vals,
                "max"           => max_vals
            }

            accessor_index
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | glTF Structure Assembly
    # -------------------------------------------------------------------------

        # FUNCTION | Build Complete glTF from Geometry Buckets
        # ---------------------------------------------------------------
        # Assembles the full glTF JSON structure and binary buffer from
        # the collected geometry buckets. Integrates with the material
        # engine for PBR material generation.
        #
        # @param buckets [Hash] Geometry buckets from traversal phase
        # @return [Array] [gltf_hash, binary_buffer_string]
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__BuildGltfFromBuckets(buckets)
            gltf = {
                "asset"       => { "version" => "2.0", "generator" => "TrueVision3D GLB Builder v2.0.0" },
                "scene"       => 0,
                "scenes"      => [{ "nodes" => [] }],
                "nodes"       => [],
                "meshes"      => [],
                "accessors"   => [],
                "bufferViews" => [],
                "buffers"     => [],
                "materials"   => [],
                "textures"    => [],
                "images"      => [],
                "samplers"    => []
            }

            bin_buffer = String.new("", encoding: Encoding::ASCII_8BIT)

            # Prepare materials (integrates with MaterialHandling module)
            if respond_to?(:Na__MaterialEngine__PrepareMaterialsForExport)
                Na__MaterialEngine__PrepareMaterialsForExport(buckets, gltf, bin_buffer)
            else
                puts "    Warning: Material module not loaded - using default fallback."
                gltf["materials"] << {
                    "name" => "Default",
                    "pbrMetallicRoughness" => {
                        "baseColorFactor" => [0.8, 0.8, 0.8, 1.0],
                        "metallicFactor"  => 0.0,
                        "roughnessFactor" => 1.0
                    }
                }
            end

            # Build a mesh + node for each non-empty bucket
            mesh_count = 0
            buckets.each do |bucket_key, bucket|
                next if bucket[:positions].empty?

                puts "    Building mesh: #{bucket_key} (#{bucket[:vertex_count]} verts, #{bucket[:indices].length / 3} tris)"
                Na__GlbEngine__BuildMeshPrimitive(bucket_key, bucket, gltf, bin_buffer)
                mesh_count += 1
            end

            puts "    Total meshes built: #{mesh_count}"
            [gltf, bin_buffer]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Mesh Primitive with Accessors
        # ---------------------------------------------------------------
        # Creates a complete glTF mesh entry with a TRIANGLES primitive
        # (positions, normals, UVs, indices) and an optional LINES
        # primitive for hard edges. Adds a corresponding node to the scene.
        #
        # @param bucket_key [String]  "LayerName::MaterialName"
        # @param bucket     [Hash]    Geometry data bucket
        # @param gltf       [Hash]    glTF JSON hash
        # @param bin_buffer  [String]  Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__BuildMeshPrimitive(bucket_key, bucket, gltf, bin_buffer)
            mesh_index = gltf["meshes"].length
            primitives = []

            material_index = if respond_to?(:Na__MaterialEngine__ResolveMaterialIndexForGroup)
                Na__MaterialEngine__ResolveMaterialIndexForGroup(bucket, gltf, bin_buffer)
            else
                0
            end

            # --- TRIANGLES primitive (mode 4) ---
            pos_accessor  = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:positions], 5126, "VEC3", 34962)
            norm_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:normals],   5126, "VEC3", 34962)
            uv_accessor   = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:uvs],       5126, "VEC2", 34962)

            # Index type: UNSIGNED_SHORT (5123) if < 65535 vertices, else UNSIGNED_INT (5125)
            max_index = bucket[:indices].max || 0
            idx_type  = (max_index < 65535) ? 5123 : 5125
            idx_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:indices], idx_type, "SCALAR", 34963)

            tri_primitive = {
                "attributes" => {
                    "POSITION"   => pos_accessor,
                    "NORMAL"     => norm_accessor,
                    "TEXCOORD_0" => uv_accessor
                },
                "indices"  => idx_accessor,
                "material" => material_index,
                "mode"     => 4                 # TRIANGLES
            }
            primitives << tri_primitive

            # --- LINES primitive (mode 1) for hard edges (when MESH_MODEL_INCLUDE_EDGES is true) ---
            if MESH_MODEL_INCLUDE_EDGES && bucket[:edge_positions] && !bucket[:edge_positions].empty?
                edge_pos_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:edge_positions], 5126, "VEC3", 34962)

                max_edge_idx  = bucket[:edge_indices].max || 0
                edge_idx_type = (max_edge_idx < 65535) ? 5123 : 5125
                edge_idx_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:edge_indices], edge_idx_type, "SCALAR", 34963)

                line_primitive = {
                    "attributes" => { "POSITION" => edge_pos_accessor },
                    "indices"    => edge_idx_accessor,
                    "mode"       => 1             # LINES
                }
                primitives << line_primitive
            end

            # Create mesh entry
            gltf["meshes"] << {
                "name"       => "Mesh_#{mesh_index}_#{bucket_key}",
                "primitives" => primitives
            }

            # Create node and add to scene root
            node_index = gltf["nodes"].length
            gltf["nodes"] << {
                "name"   => bucket_key,
                "mesh"   => mesh_index,
                "extras" => { "generator" => "TrueVision3D_VirtualFlattening" }
            }
            gltf["scenes"][0]["nodes"] << node_index
        end
        # ---------------------------------------------------------------

        # HELPER | Sanitize Entity Name for Debugging
        # ---------------------------------------------------------------
        # Creates a debug-friendly name from a SketchUp entity using its
        # name and persistent_id for traceability in web viewers.
        # Example: "Chair_Leg_ID12345"
        #
        # @param entity [Sketchup::Entity]
        # @return       [String] sanitized debug name
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__SanitizeEntityName(entity)
            raw_name = if entity.respond_to?(:name) && entity.name && !entity.name.empty?
                entity.name
            elsif entity.respond_to?(:definition)
                entity.definition.name || "Unnamed"
            else
                "Unnamed"
            end

            clean = raw_name.gsub(/[^0-9A-Za-z.\-]/, '_')
            pid   = entity.respond_to?(:persistent_id) ? entity.persistent_id : 0
            "#{clean}_ID#{pid}"
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
