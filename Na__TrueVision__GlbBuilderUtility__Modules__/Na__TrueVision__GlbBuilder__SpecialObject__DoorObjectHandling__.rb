# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - DOOR OBJECT HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__SpecialObject__DoorObjectHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Special Object - Door Assembly Handling
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Hierarchy-preserving GLB export for door assemblies (ADR/MOD/ROT)
# CREATED    : 14-Feb-2026
#
# DESCRIPTION:
# - Detects door assemblies by scanning for ADR-prefixed entity names.
# - Preserves the ADR > MOD/ROT/OuterShell node hierarchy in the GLB output.
# - Converts SketchUp Z-up local transforms to glTF Y-up via conjugation.
# - Reuses the existing TraverseEntities engine for local geometry extraction.
# - Integrates with the material engine for consistent PBR material assignment.
# - Zero overhead when no door assemblies are present in the model.
#
# NAMING CONVENTION (SketchUp Scene Graph → glTF Node Tree):
# - ADR = Door Assembly   (e.g. ADR002__InternalDoor__GroundFloor__PorchToLounge)
# - MOD = Modifier Object  (e.g. MOD001__ROT__90-Deg__DoorPanel)
# - ROT = Rotation Point   (e.g. ROT001__RotationPoint__DoorHingeCentre)
#
# COORDINATE SYSTEM:
# - ADR node matrix:  Z_UP * accumulated_SU_transform * inv(Z_UP) (meters)
# - Child matrices:   Z_UP * local_SU_transform * inv(Z_UP) (meters)
# - Mesh vertices:    Extracted in Y-up local space via TraverseEntities
#                     with Z_UP_TO_Y_UP_MATRIX as root transform
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Door Handler Constants
    # -------------------------------------------------------------------------

        # MODULE CONSTANTS | Door Detection Prefix
        # ------------------------------------------------------------
        DOOR_ASSEMBLY_PREFIX  = "ADR".freeze                                  # <-- Entity name prefix for door assemblies
        # ------------------------------------------------------------

        # CONSTANT | Y-Up to Z-Up Inverse Conversion Matrix
        # ---------------------------------------------------------------
        # Precomputed inverse of Z_UP_TO_Y_UP_MATRIX.
        # Z_UP_TO_Y_UP maps (x, y, z) → (x, z, -y)
        # Inverse maps     (x, y, z) → (x, -z, y)
        # Used for transform conjugation: M_yup = Z_UP * M_su * inv(Z_UP)
        # ---------------------------------------------------------------
        Y_UP_TO_Z_UP_MATRIX = Geom::Transformation.new([
            1.0,  0.0,  0.0, 0.0,
            0.0,  0.0,  1.0, 0.0,
            0.0, -1.0,  0.0, 0.0,
            0.0,  0.0,  0.0, 1.0
        ])
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Entity Name Utilities
    # -------------------------------------------------------------------------

        # HELPER FUNCTION | Get Entity Name (Group or ComponentInstance)
        # ---------------------------------------------------------------
        # Returns the entity's instance name, falling back to definition
        # name for ComponentInstances. Returns empty string if unnamed.
        #
        # @param entity [Sketchup::Entity]
        # @return       [String] entity name or ""
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__GetEntityName(entity)
            if entity.respond_to?(:name) && entity.name && !entity.name.empty?
                entity.name                                                   # <-- Instance name (Group or ComponentInstance)
            elsif entity.respond_to?(:definition)
                entity.definition.name || ""                                  # <-- Definition name fallback
            else
                ""                                                            # <-- No name available
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Check if Entity is a Door Assembly
        # ---------------------------------------------------------------
        # Returns true if the entity name starts with the ADR prefix.
        #
        # @param entity [Sketchup::Entity]
        # @return       [Boolean]
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__IsDoorAssembly?(entity)
            return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            name = Na__DoorHandler__GetEntityName(entity)                     # <-- Resolve entity name
            name.start_with?(DOOR_ASSEMBLY_PREFIX)                            # <-- Check ADR prefix
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Transform Conversion (Z-Up → Y-Up Conjugation)
    # -------------------------------------------------------------------------

        # FUNCTION | Conjugate SketchUp Transform to Y-Up Space
        # ---------------------------------------------------------------
        # Converts a SketchUp Z-up transform to Y-up via conjugation:
        #   M_yup = Z_UP_TO_Y_UP * M_su * inv(Z_UP_TO_Y_UP)
        #
        # This ensures child coordinate spaces are in Y-up convention,
        # so downstream Three.js animation code uses (0, 1, 0) as the
        # vertical rotation axis.
        #
        # @param su_transform [Geom::Transformation] SketchUp local transform
        # @return             [Geom::Transformation] Conjugated Y-up transform
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ConjugateToYUp(su_transform)
            Z_UP_TO_Y_UP_MATRIX * su_transform * Y_UP_TO_Z_UP_MATRIX         # <-- Similarity transform
        end
        # ---------------------------------------------------------------

        # FUNCTION | Convert Transform to glTF Column-Major Matrix Array
        # ---------------------------------------------------------------
        # Extracts a Geom::Transformation as a 16-element column-major
        # Float array suitable for glTF node "matrix" property.
        # Translation components (indices 12-14) are converted from
        # inches to meters.
        #
        # @param transform [Geom::Transformation]
        # @return          [Array<Float>] 16-element column-major matrix
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__TransformToGltfMatrix(transform)
            m = transform.to_a.map(&:to_f)                                   # <-- Column-major 16-element array
            m[12] *= INCHES_TO_METERS                                         # <-- Tx: inches → meters
            m[13] *= INCHES_TO_METERS                                         # <-- Ty: inches → meters
            m[14] *= INCHES_TO_METERS                                         # <-- Tz: inches → meters
            m
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Door Assembly Export Orchestration
    # -------------------------------------------------------------------------

        # FUNCTION | Export All Detected Door Assemblies to glTF (Mesh Model)
        # ---------------------------------------------------------------
        # Iterates the collected door assembly records and builds
        # hierarchical glTF node subtrees for each. Called from the
        # EngineCore after normal bucket-based export completes.
        #
        # @param door_assemblies [Array<Hash>] Each: {entity:, accumulated_transform:}
        # @param gltf            [Hash]        glTF JSON structure
        # @param bin_buffer      [String]      Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ExportDoorAssemblies(door_assemblies, gltf, bin_buffer)
            puts "\n    [DoorHandler] Exporting #{door_assemblies.length} door assembly(ies)..."

            door_assemblies.each do |door_data|
                Na__DoorHandler__BuildDoorAssemblyNodes(
                    door_data[:entity],
                    door_data[:accumulated_transform],
                    gltf,
                    bin_buffer,
                    :mesh                                                     # <-- Export type: mesh geometry
                )
            end

            puts "    [DoorHandler] Door assembly export complete\n"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Export All Detected Door Assemblies to glTF (Linework Model)
        # ---------------------------------------------------------------
        # Iterates the collected door assembly records and builds
        # hierarchical glTF node subtrees for linework (edges). Called from
        # LineworkEngine after normal edge collection completes.
        #
        # @param door_assemblies [Array<Hash>] Each: {entity:, accumulated_transform:}
        # @param gltf            [Hash]        glTF JSON structure
        # @param bin_buffer      [String]      Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ExportDoorLinework(door_assemblies, gltf, bin_buffer)
            puts "\n    [DoorHandler/Linework] Exporting #{door_assemblies.length} door assembly(ies)..."

            door_assemblies.each do |door_data|
                Na__DoorHandler__BuildDoorAssemblyNodes(
                    door_data[:entity],
                    door_data[:accumulated_transform],
                    gltf,
                    bin_buffer,
                    :linework                                                 # <-- Export type: edge linework
                )
            end

            puts "    [DoorHandler/Linework] Door assembly linework export complete\n"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Hierarchical glTF Nodes for a Door Assembly
        # ---------------------------------------------------------------
        # Creates the ADR parent node with conjugated world transform,
        # then iterates direct children (MOD, ROT, OuterShell, etc.)
        # creating named child nodes with conjugated local transforms
        # and extracted local-space geometry (either mesh or linework).
        #
        # @param adr_entity            [Sketchup::Entity]         Door assembly group/component
        # @param accumulated_transform [Geom::Transformation]     Z_UP * SU accumulated (from traversal)
        # @param gltf                  [Hash]                     glTF JSON structure
        # @param bin_buffer            [String]                   Binary buffer (ASCII-8BIT)
        # @param export_type           [Symbol]                   :mesh or :linework
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__BuildDoorAssemblyNodes(adr_entity, accumulated_transform, gltf, bin_buffer, export_type = :mesh)
            adr_name = Na__DoorHandler__GetEntityName(adr_entity)
            type_label = export_type == :linework ? "Linework" : "Mesh"
            puts "      [DoorHandler/#{type_label}] Building door assembly: #{adr_name}"

            # -------------------------------------------------------
            # ADR node: conjugated accumulated transform
            # accumulated_transform = Z_UP * su_parents * adr_local
            # M_adr_gltf = Z_UP * su_acc * inv(Z_UP) = accumulated * inv(Z_UP)
            # -------------------------------------------------------
            adr_gltf_transform = accumulated_transform * Y_UP_TO_Z_UP_MATRIX  # <-- Conjugate to Y-up
            adr_matrix         = Na__DoorHandler__TransformToGltfMatrix(adr_gltf_transform)

            # Create ADR node and add to scene root
            adr_node_index = gltf["nodes"].length
            adr_node = {
                "name"     => adr_name,
                "matrix"   => adr_matrix,
                "children" => [],
                "extras"   => { "generator" => "TrueVision3D_DoorHandler", "type" => "DoorAssembly" }
            }
            gltf["nodes"] << adr_node
            gltf["scenes"][0]["nodes"] << adr_node_index                      # <-- Root-level scene node

            # -------------------------------------------------------
            # Process each direct child of ADR
            # -------------------------------------------------------
            adr_entity.definition.entities.each do |child_entity|
                next unless child_entity.is_a?(Sketchup::Group) || child_entity.is_a?(Sketchup::ComponentInstance)
                next if Na__Helpers__EntityExcluded?(child_entity)
                next if child_entity.hidden?                                  # <-- Skip hidden children
                next unless child_entity.layer.visible?                       # <-- Skip invisible layers

                child_name = Na__DoorHandler__GetEntityName(child_entity)

                # Conjugate child's local SU transform to Y-up
                child_yup_transform = Na__DoorHandler__ConjugateToYUp(child_entity.transformation)
                child_matrix        = Na__DoorHandler__TransformToGltfMatrix(child_yup_transform)

                # Create child node as child of ADR
                child_node_index = gltf["nodes"].length
                child_node = {
                    "name"     => child_name,
                    "matrix"   => child_matrix,
                    "children" => [],
                    "extras"   => { "generator" => "TrueVision3D_DoorHandler" }
                }
                gltf["nodes"] << child_node
                adr_node["children"] << child_node_index

                puts "        [DoorHandler/#{type_label}] Child node: #{child_name}"

                # Extract geometry from this child's subtree in Y-up local space
                if export_type == :linework
                    Na__DoorHandler__ExtractChildLinework(child_entity, child_node_index, gltf, bin_buffer)
                else
                    Na__DoorHandler__ExtractChildGeometry(child_entity, child_node_index, gltf, bin_buffer)
                end
            end

            # Handle bare geometry directly at ADR level (uncommon but possible)
            if export_type == :linework
                Na__DoorHandler__ExtractDirectLinework(adr_entity, adr_node_index, gltf, bin_buffer)
            else
                Na__DoorHandler__ExtractDirectGeometry(adr_entity, adr_node_index, gltf, bin_buffer)
            end

            puts "      [DoorHandler/#{type_label}] Door assembly complete: #{adr_name}"
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Local Geometry Extraction for Door Children
    # -------------------------------------------------------------------------

        # FUNCTION | Extract Mesh Geometry from a Child Entity Subtree
        # ---------------------------------------------------------------
        # Uses the existing TraverseEntities function with Z_UP_TO_Y_UP
        # as the root transform to extract all geometry in Y-up local
        # space (relative to the child entity origin). Geometry is
        # collected into per-material buckets and built as mesh child
        # nodes of the parent glTF node.
        #
        # @param child_entity      [Sketchup::Entity] Child group/component
        # @param parent_node_index [Integer]           glTF node index for parent
        # @param gltf              [Hash]              glTF JSON structure
        # @param bin_buffer        [String]            Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ExtractChildGeometry(child_entity, parent_node_index, gltf, bin_buffer)
            # Create isolated bucket store for this child's geometry
            local_buckets = Na__GlbEngine__CreateBuckets()
            # Traverse child entities with Z_UP_TO_Y_UP as root transform.
            # This produces vertices in Y-up local space, in meters.
            # Material resolution is face-only (no container inheritance).
            Na__GlbEngine__TraverseEntities(
                child_entity.definition.entities,                             # <-- Child's entities
                Z_UP_TO_Y_UP_MATRIX,                                          # <-- Root: Y-up conversion
                child_entity.layer,                                           # <-- Layer context
                local_buckets,                                                # <-- Isolated bucket store
                nil,                                                          # <-- No door detection inside a door child subtree
                nil                                                           # <-- No instancing skip set for local extraction
            )

            # Build mesh primitives from local buckets and attach to parent node
            Na__DoorHandler__BuildMeshesForNode(local_buckets, parent_node_index, gltf, bin_buffer)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Linework from a Child Entity Subtree
        # ---------------------------------------------------------------
        # Collects visible edges from the child entity subtree in Y-up
        # local space and builds LINES primitives attached to the parent
        # glTF node.
        #
        # @param child_entity      [Sketchup::Entity] Child group/component
        # @param parent_node_index [Integer]           glTF node index for parent
        # @param gltf              [Hash]              glTF JSON structure
        # @param bin_buffer        [String]            Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ExtractChildLinework(child_entity, parent_node_index, gltf, bin_buffer)
            # Create isolated edge collection arrays for this child
            positions = []
            colors    = []

            # Traverse child entities with Z_UP_TO_Y_UP as root transform.
            # This produces edge endpoints in Y-up local space, in meters.
            # The 6th argument (door_assemblies) is omitted → defaults to nil,
            # so no further door detection occurs inside the child subtree.
            Na__LineworkEngine__TraverseEdges(
                child_entity.definition.entities,                             # <-- Child's entities
                Z_UP_TO_Y_UP_MATRIX,                                          # <-- Root: Y-up conversion
                child_entity.layer,                                           # <-- Layer context
                positions,                                                    # <-- Edge positions array
                colors                                                        # <-- Edge colors array
            )

            # Build LINES primitives from edge data and attach to parent node
            Na__DoorHandler__BuildLineworkForNode(positions, colors, parent_node_index, gltf, bin_buffer)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Bare Faces Directly at Entity Level
        # ---------------------------------------------------------------
        # Handles the uncommon case where bare faces exist directly in
        # the ADR entity alongside child groups. Extracts only the
        # direct faces (not those in nested groups) and builds mesh
        # nodes attached to the parent.
        #
        # @param entity            [Sketchup::Entity] Parent entity
        # @param parent_node_index [Integer]           glTF node index
        # @param gltf              [Hash]              glTF JSON structure
        # @param bin_buffer        [String]            Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ExtractDirectGeometry(entity, parent_node_index, gltf, bin_buffer)
            # Check for bare faces at this level (not in child groups)
            has_faces = entity.definition.entities.any? { |e| e.is_a?(Sketchup::Face) }
            return unless has_faces                                           # <-- Skip if no bare faces

            local_buckets = Na__GlbEngine__CreateBuckets()
            is_mirrored   = Na__GlbEngine__CalcDeterminant3x3(Z_UP_TO_Y_UP_MATRIX) < 0
            normal_matrix = Na__GlbEngine__CalcNormalMatrix(Z_UP_TO_Y_UP_MATRIX)

            entity.definition.entities.each do |face_entity|
                next unless face_entity.is_a?(Sketchup::Face)
                next if Na__Helpers__EntityExcluded?(face_entity)

                layer_name = (face_entity.layer.name == "Layer0") ? entity.layer.name : face_entity.layer.name
                Na__GlbEngine__AddFaceToBucket(
                    face_entity,
                    Z_UP_TO_Y_UP_MATRIX,
                    normal_matrix,
                    is_mirrored,
                    layer_name,
                    local_buckets
                )
            end

            Na__DoorHandler__BuildMeshesForNode(local_buckets, parent_node_index, gltf, bin_buffer)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Bare Edges Directly at Entity Level
        # ---------------------------------------------------------------
        # Handles the uncommon case where bare edges exist directly in
        # the ADR entity alongside child groups. Extracts only the
        # direct edges (not those in nested groups) and builds LINES
        # nodes attached to the parent.
        #
        # @param entity            [Sketchup::Entity] Parent entity
        # @param parent_node_index [Integer]           glTF node index
        # @param gltf              [Hash]              glTF JSON structure
        # @param bin_buffer        [String]            Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__ExtractDirectLinework(entity, parent_node_index, gltf, bin_buffer)
            # Check for bare edges at this level (not in child groups)
            has_edges = entity.definition.entities.any? { |e| e.is_a?(Sketchup::Edge) }
            return unless has_edges                                           # <-- Skip if no bare edges

            positions = []
            colors    = []

            entity.definition.entities.each do |edge_entity|
                next unless edge_entity.is_a?(Sketchup::Edge)
                next if Na__Helpers__EntityExcluded?(edge_entity)
                next if edge_entity.hidden?
                next if edge_entity.soft?
                next if edge_entity.smooth?
                next unless edge_entity.layer.visible?

                # Transform endpoints to Y-up local space
                start_pt = Z_UP_TO_Y_UP_MATRIX * edge_entity.start.position
                end_pt   = Z_UP_TO_Y_UP_MATRIX * edge_entity.end.position

                positions.push(
                    start_pt.x.to_f * INCHES_TO_METERS,
                    start_pt.y.to_f * INCHES_TO_METERS,
                    start_pt.z.to_f * INCHES_TO_METERS,
                    end_pt.x.to_f   * INCHES_TO_METERS,
                    end_pt.y.to_f   * INCHES_TO_METERS,
                    end_pt.z.to_f   * INCHES_TO_METERS
                )

                # Edge color from material (default black)
                col = edge_entity.material ? edge_entity.material.color : Sketchup::Color.new(0, 0, 0)
                r = col.red   / 255.0
                g = col.green / 255.0
                b = col.blue  / 255.0
                a = (col.respond_to?(:alpha) ? col.alpha : 255) / 255.0
                2.times { colors.push(r, g, b, a) }
            end

            Na__DoorHandler__BuildLineworkForNode(positions, colors, parent_node_index, gltf, bin_buffer)
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Mesh and Linework Building for Door Nodes
    # -------------------------------------------------------------------------

        # FUNCTION | Build glTF Meshes from Buckets and Attach to Parent Node
        # ---------------------------------------------------------------
        # Creates glTF mesh entries with TRIANGLES primitives from the
        # provided geometry buckets. Each non-empty bucket produces a
        # mesh + node pair added as a child of the specified parent node.
        #
        # @param buckets           [Hash]    Geometry buckets from local extraction
        # @param parent_node_index [Integer] glTF node index to parent meshes under
        # @param gltf              [Hash]    glTF JSON structure
        # @param bin_buffer        [String]  Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__BuildMeshesForNode(buckets, parent_node_index, gltf, bin_buffer)
            buckets.each do |bucket_key, bucket|
                next if bucket[:positions].empty?                             # <-- Skip empty buckets

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
                max_index    = bucket[:indices].max || 0
                idx_type     = (max_index < 65535) ? 5123 : 5125
                idx_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, bucket[:indices], idx_type, "SCALAR", 34963)

                tri_primitive = {
                    "attributes" => {
                        "POSITION"   => pos_accessor,
                        "NORMAL"     => norm_accessor,
                        "TEXCOORD_0" => uv_accessor
                    },
                    "indices"  => idx_accessor,
                    "material" => material_index,
                    "mode"     => 4                                           # <-- TRIANGLES
                }
                primitives << tri_primitive

                # Create mesh entry
                gltf["meshes"] << {
                    "name"       => "DoorMesh_#{mesh_index}_#{bucket_key}",
                    "primitives" => primitives
                }

                # Create mesh node as child of parent
                mesh_node_index = gltf["nodes"].length
                gltf["nodes"] << {
                    "name" => bucket_key,
                    "mesh" => mesh_index
                }

                # Attach to parent node's children
                parent_node = gltf["nodes"][parent_node_index]
                parent_node["children"] ||= []
                parent_node["children"] << mesh_node_index

                puts "          [DoorHandler] Mesh: #{bucket_key} (#{bucket[:vertex_count]} verts, #{bucket[:indices].length / 3} tris)"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build glTF Linework and Attach to Parent Node
        # ---------------------------------------------------------------
        # Creates a glTF mesh entry with a LINES primitive from the
        # provided edge positions and colors. Attached as a child of
        # the specified parent node.
        #
        # @param positions         [Array<Float>] Flat edge positions [x,y,z, ...]
        # @param colors            [Array<Float>] Flat edge colors [r,g,b,a, ...]
        # @param parent_node_index [Integer]       glTF node index to parent under
        # @param gltf              [Hash]          glTF JSON structure
        # @param bin_buffer        [String]        Binary buffer (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__DoorHandler__BuildLineworkForNode(positions, colors, parent_node_index, gltf, bin_buffer)
            return if positions.empty?                                        # <-- Skip if no edges

            vertex_count = positions.length / 3
            mesh_index   = gltf["meshes"].length

            # Pack edge positions and colors into binary buffers
            pos_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, positions, 5126, "VEC3", 34962)
            col_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, colors,    5126, "VEC4", 34962)

            # Create LINES primitive (mode 1)
            line_primitive = {
                "attributes" => {
                    "POSITION" => pos_accessor,
                    "COLOR_0"  => col_accessor
                },
                "mode" => 1                                                   # <-- LINES
            }

            # Create mesh entry
            gltf["meshes"] << {
                "name"       => "DoorLinework_#{mesh_index}",
                "primitives" => [line_primitive]
            }

            # Create mesh node as child of parent
            mesh_node_index = gltf["nodes"].length
            gltf["nodes"] << {
                "name" => "Linework",
                "mesh" => mesh_index
            }

            # Attach to parent node's children
            parent_node = gltf["nodes"][parent_node_index]
            parent_node["children"] ||= []
            parent_node["children"] << mesh_node_index

            edge_count = vertex_count / 2
            puts "          [DoorHandler/Linework] Lines: #{edge_count} edges"
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
