# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - LINEWORK MODEL HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__LineworkModelHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Linework Model Handling (Edge/Lines Export)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Exports visible SketchUp edges as LINES primitives in a separate
#              GLB file per tagged series. Uses same virtual flattening transforms
#              as the mesh export for perfect spatial alignment.
# CREATED    : 2026-02-10
#
# ARCHITECTURE:
# - Recursive DFS traversal matching GeometryHandling (same transform accumulation)
# - Visibility filters: hidden?, soft?, smooth?, layer.visible?
# - Layer0 inheritance from parent container
# - Z_UP_TO_Y_UP_MATRIX and INCHES_TO_METERS for coordinate/unit conversion
# - Edge color extraction from entity.material
# - Single LINES primitive with POSITION + COLOR_0 attributes
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Recursive Edge Traversal
    # -------------------------------------------------------------------------

        # FUNCTION | Traverse Entities for Visible Edges (Virtual Flattening)
        # ---------------------------------------------------------------
        # Walks the scene graph depth-first, accumulating world transforms.
        # Collects only visible edges (not hidden, soft, or smooth).
        # Never modifies the SketchUp model.
        #
        # When door_assemblies is non-nil, entities with ADR-prefixed
        # names are detected and diverted to the door handler instead
        # of being flattened into the main linework collection.
        #
        # @param entities         [Sketchup::Entities]      Children to process
        # @param parent_transform [Geom::Transformation]    Accumulated world matrix
        # @param parent_layer     [Sketchup::Layer]         Inherited layer context
        # @param positions        [Array<Float>]            Flat [x,y,z, x,y,z, ...] output
        # @param colors          [Array<Float>]            Flat [r,g,b,a, r,g,b,a, ...] output
        # @param door_assemblies  [Array|nil]               Collected door records (nil = disabled)
        # @param depth            [Integer]                 Current container nesting depth
        # ---------------------------------------------------------------
        def self.Na__LineworkEngine__TraverseEdges(entities, parent_transform, parent_layer, positions, colors, door_assemblies = nil, instanced_skip_set = nil, depth = 0)
            return if depth > MAX_NESTING_DEPTH

            entities.each do |entity|
                next if Na__Helpers__EntityExcluded?(entity)

                if entity.is_a?(Sketchup::Edge)
                    # Visibility checks per user specification
                    next if entity.hidden?
                    next if entity.soft?
                    next if entity.smooth?
                    next unless entity.layer.visible?

                    # Transform endpoints to world space (Y-up, meters)
                    start_pt = parent_transform * entity.start.position
                    end_pt   = parent_transform * entity.end.position

                    positions.push(
                        start_pt.x.to_f * INCHES_TO_METERS,
                        start_pt.y.to_f * INCHES_TO_METERS,
                        start_pt.z.to_f * INCHES_TO_METERS,
                        end_pt.x.to_f   * INCHES_TO_METERS,
                        end_pt.y.to_f   * INCHES_TO_METERS,
                        end_pt.z.to_f   * INCHES_TO_METERS
                    )

                    # Edge color from material (default black)
                    col = entity.material ? entity.material.color : Sketchup::Color.new(0, 0, 0)
                    r = col.red   / 255.0
                    g = col.green / 255.0
                    b = col.blue  / 255.0
                    a = (col.respond_to?(:alpha) ? col.alpha : 255) / 255.0
                    2.times { colors.push(r, g, b, a) }

                elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next if entity.hidden?
                    next unless entity.layer.visible?
                    next if instanced_skip_set && instanced_skip_set.key?(entity.object_id)

                    child_transform = parent_transform * entity.transformation
                    child_layer = (entity.layer.name == "Layer0") ? parent_layer : entity.layer

                    # Door assembly detection: divert ADR-prefixed entities
                    if door_assemblies && Na__DoorHandler__IsDoorAssembly?(entity)
                        door_assemblies << {
                            entity:                entity,
                            accumulated_transform: child_transform
                        }
                        puts "      [DoorHandler/Linework] Detected door assembly: #{Na__DoorHandler__GetEntityName(entity)}"
                        next                                                  # <-- Skip normal flattening for this subtree
                    end

                    Na__LineworkEngine__TraverseEdges(entity.definition.entities, child_transform, child_layer, positions, colors, door_assemblies, instanced_skip_set, depth + 1)
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | glTF Structure Assembly
    # -------------------------------------------------------------------------

        # FUNCTION | Build glTF from Edge Data
        # ---------------------------------------------------------------
        # Assembles a minimal glTF structure with a single LINES primitive
        # (POSITION + COLOR_0). Reuses Na__GltfHelpers__AddAccessor from
        # GeometryHandling for binary packing.
        #
        # @param positions [Array<Float>] Flat vertex positions (2 per edge)
        # @param colors    [Array<Float>] Flat vertex colors (2 per edge, RGBA)
        # @return         [Array] [gltf_hash, binary_buffer_string]
        # ---------------------------------------------------------------
        def self.Na__LineworkEngine__BuildGltfFromEdgeData(positions, colors)
            gltf = {
                "asset"       => { "version" => "2.0", "generator" => "TrueVision3D GLB Builder Linework v1.5.0" },
                "scene"       => 0,
                "scenes"      => [{ "nodes" => [0] }],
                "nodes"       => [{ "mesh" => 0 }],
                "meshes"      => [],
                "accessors"   => [],
                "bufferViews" => [],
                "buffers"     => []
            }

            bin_buffer = String.new("", encoding: Encoding::ASCII_8BIT)
            vertex_count = positions.length / 3

            pos_accessor  = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, positions, 5126, "VEC3", 34962)
            col_accessor  = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, colors,   5126, "VEC4", 34962)

            gltf["meshes"] << {
                "name"       => "Linework",
                "primitives" => [{
                    "attributes" => {
                        "POSITION" => pos_accessor,
                        "COLOR_0"  => col_accessor
                    },
                    "mode" => 1   # LINES
                }]
            }

            [gltf, bin_buffer]
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Public Export Entry Point
    # -------------------------------------------------------------------------

        # FUNCTION | Export Linework to GLB
        # ---------------------------------------------------------------
        # Public entry point. Traverses entities, collects visible edges
        # with color, builds glTF, and writes the GLB file. Uses the same
        # root transform (Z_UP_TO_Y_UP_MATRIX) as mesh export for alignment.
        #
        # @param entities         [Array<Sketchup::Entity>] Top-level entities to export
        # @param filepath         [String] Output GLB file path (without .glb)
        # @param parent_transform [Geom::Transformation|nil] Optional parent container transform
        #                         (e.g. storey container transform for world-space baking)
        # @return                 [Boolean] true on success, false on failure
        # ---------------------------------------------------------------
        def self.Na__LineworkEngine__ExportLineworkToGlb(entities, filepath, parent_transform = nil)
            filepath += GLB_FILE_EXTENSION unless filepath.end_with?(GLB_FILE_EXTENSION)
            puts "  Using virtual flattening for linework export (same transforms as mesh)..."

            begin
                positions        = []
                colors           = []
                door_assemblies  = []                                         # <-- Collects ADR door assemblies during traversal
                root_transform   = parent_transform ? Z_UP_TO_Y_UP_MATRIX * parent_transform : Z_UP_TO_Y_UP_MATRIX  # <-- Include parent (e.g. storey) transform when present
                entity_count     = 0

                # Recursive pre-scan for instanced ComponentDefinitions (same scan as mesh export)
                instanced_groups, instanced_skip_set = Na__Instancing__ScanForInstancedDefinitions(entities, root_transform)

                entities.each do |entity|
                    next if Na__Helpers__EntityExcluded?(entity)

                    if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                        next if instanced_skip_set.key?(entity.object_id)

                        entity_count += 1
                        entity_name = Na__GlbEngine__SanitizeEntityName(entity)
                        puts "    Traversing linework: #{entity_name}..."

                        accumulated_transform = root_transform * entity.transformation
                        entity_layer = entity.layer

                        # Check if this top-level entity itself is a door assembly
                        if Na__DoorHandler__IsDoorAssembly?(entity)
                            door_assemblies << {
                                entity:                entity,
                                accumulated_transform: accumulated_transform
                            }
                            puts "      [DoorHandler/Linework] Detected top-level door assembly: #{entity_name}"
                            next                                              # <-- Skip traversal, door handler will process it
                        end

                        Na__LineworkEngine__TraverseEdges(
                            entity.definition.entities,
                            accumulated_transform,
                            entity_layer,
                            positions,
                            colors,
                            door_assemblies,                                  # <-- Pass door collector for nested ADR detection
                            instanced_skip_set,                               # <-- Skip nested instanced components
                            1                                                 # <-- Top-level export container depth
                        )

                    elsif entity.is_a?(Sketchup::Edge)
                        next if entity.hidden?
                        next if entity.soft?
                        next if entity.smooth?
                        next unless entity.layer.visible?

                        start_pt = root_transform * entity.start.position
                        end_pt   = root_transform * entity.end.position
                        positions.push(
                            start_pt.x.to_f * INCHES_TO_METERS,
                            start_pt.y.to_f * INCHES_TO_METERS,
                            start_pt.z.to_f * INCHES_TO_METERS,
                            end_pt.x.to_f   * INCHES_TO_METERS,
                            end_pt.y.to_f   * INCHES_TO_METERS,
                            end_pt.z.to_f   * INCHES_TO_METERS
                        )
                        col = entity.material ? entity.material.color : Sketchup::Color.new(0, 0, 0)
                        r = col.red / 255.0
                        g = col.green / 255.0
                        b = col.blue / 255.0
                        a = (col.respond_to?(:alpha) ? col.alpha : 255) / 255.0
                        2.times { colors.push(r, g, b, a) }
                    end
                end

                # Report traversal results
                edge_count = positions.length / 6
                puts "    Linework traversal complete: #{entity_count} entities -> #{edge_count} edges"

                if door_assemblies.any?
                    puts "    [DoorHandler/Linework] #{door_assemblies.length} door assembly(ies) detected — will export with hierarchy preservation"
                end

                # Build glTF structure from collected edges (if any)
                if positions.empty? && door_assemblies.empty? && instanced_groups.empty?
                    puts "  No visible edges, door assemblies, or instanced components found - skipping linework file"
                    return false
                end

                # Build glTF structure (initialize even if no flat-traversal edges)
                if positions.empty?
                    # No flat edges, but we have door assemblies or instanced components — initialize minimal glTF
                    gltf = {
                        "asset"       => { "version" => "2.0", "generator" => "TrueVision3D GLB Builder Linework v1.5.0" },
                        "scene"       => 0,
                        "scenes"      => [{ "nodes" => [] }],
                        "nodes"       => [],
                        "meshes"      => [],
                        "accessors"   => [],
                        "bufferViews" => [],
                        "buffers"     => []
                    }
                    bin_buffer = String.new("", encoding: Encoding::ASCII_8BIT)
                else
                    # Normal linework export with edges
                    gltf, bin_buffer = Na__LineworkEngine__BuildGltfFromEdgeData(positions, colors)
                end

                # Append instanced shared linework meshes and per-instance nodes
                Na__Instancing__ProcessAllInstancedLinework(instanced_groups, gltf, bin_buffer)

                # Export door assemblies with preserved hierarchy (if any detected)
                if door_assemblies.any?
                    Na__DoorHandler__ExportDoorLinework(door_assemblies, gltf, bin_buffer)
                end

                Na__GlbEngine__WriteGlbFile(filepath, gltf, bin_buffer)

                puts "  ✓ Linework export complete"
                true

            rescue => e
                puts "  ERROR: Linework export failed - #{e.message}"
                puts "  #{e.backtrace.first(5).join("\n  ")}"
                false
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
