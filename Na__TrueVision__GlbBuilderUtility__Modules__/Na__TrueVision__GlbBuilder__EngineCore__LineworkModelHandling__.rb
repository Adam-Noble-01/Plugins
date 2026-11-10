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
#
# DEVELOPMENT LOG:
# 10-Nov-2026 - Version 1.7.0
# - A component placed from Adam's SketchUp library (the Na__ComponentLibrary
#   dictionary on its definition, or a library code at the front of its name)
#   now writes its edges to a node of its OWN, named like an instanced node
#   (<name>_ID<persistent id>) and carrying extras.Na__LibraryAsset (Code, Type,
#   Category, Name, Definition). Until now a library part placed once was
#   flattened into the category's unnamed node and nothing downstream could
#   tell a door handle or a pilaster from the wall behind it. ValeVision 3D's
#   ornament fade reads this to draw library parts lightly from a distance.
# - The same position ranges as the modifier tags: outermost wins, and an asset
#   that holds a modifier tag is left as before so that node is never lost.
#   Door children (ADR) split their library parts the same way (DoorHandler).
# 20-Sep-2026 - Version 1.6.0
# - Edges below a nested LineworkModifier tag (SSOT 76-79) are now written to a
#   node of their OWN, named with that tag, instead of being flattened with
#   everything else into one unnamed node. Until now this file carried no tag
#   identity whatsoever: a category's whole linework arrived downstream as a
#   single nameless blob, so a stonework or joinery detail drawn inside a wall
#   could only ever be styled and switched as the wall. The mesh export had
#   carried per-tag node names all along - this is the half that was missing,
#   and it is the half that draws the crisp authored lines a drawing reads.
# - The split is recorded as POSITION RANGES taken around the recursion, not as
#   a parallel per-edge array, because positions/colors are filled by five
#   separate paths (this walk, root-level edges, door assemblies, camera-follow
#   assemblies, instancing) and a parallel array would desynchronise the moment
#   one of them was missed. Edges outside any range still write one unnamed
#   node, byte-for-byte as before, so every existing consumer is untouched.
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
    # REGION | Library Assets (Adam's SketchUp component library)
    # -------------------------------------------------------------------------

        # MODULE CONSTANTS | How a Library Asset Is Known
        # ---------------------------------------------------------------
        # The Component Editor Tools file every library asset with the
        # Na__ComponentLibrary dictionary on its definition (type, category,
        # gallery_name) and a code at the front of the definition name
        # (10_1001__..., 20__1003__..., the older 03_85__...). Either marks
        # it. Code 00 is the modelling helpers (origin points): never an asset.
        # ---------------------------------------------------------------
        NA__LIBRARY_DICTIONARY   = 'Na__ComponentLibrary'.freeze
        NA__LIBRARY_CODE_PATTERN = /\A(\d{2})_{1,2}(\d{2,4})__/
        NA__LIBRARY_NESTED_DEPTH = 3                                           # <-- How deep a wrapper is searched for the asset it holds
        # ---------------------------------------------------------------

        # FUNCTION | What the Library Says About a Definition, or nil
        # ---------------------------------------------------------------
        # @param definition [Sketchup::ComponentDefinition]
        # @return [Hash|nil] glTF extras: Code, Type, Category, Name, Definition
        # ---------------------------------------------------------------
        def self.Na__LibraryAsset__InfoForDefinition(definition)
            return nil unless definition.is_a?(Sketchup::ComponentDefinition)
            return nil if definition.group? || definition.image?
            name  = definition.name.to_s
            match = name.match(NA__LIBRARY_CODE_PATTERN)
            dict  = definition.attribute_dictionary(NA__LIBRARY_DICTIONARY)
            return nil unless match || dict
            return nil if match && match[1] == '00'                            # <-- A modelling helper, not an asset
            {
                'Code'       => match ? "#{match[1]}_#{match[2]}" : dict['code'].to_s.sub(/_+\z/, ''),
                'Type'       => dict ? dict['type'].to_s : '',
                'Category'   => dict ? dict['category'].to_s : '',
                'Name'       => dict ? dict['gallery_name'].to_s : '',
                'Definition' => name
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Library Asset an Entity Is, or Holds (a renamed wrapper of one)
        # ---------------------------------------------------------------
        # A component Adam made around library parts (Handles__DoubleDoor
        # round two lever handles) is marked with the first asset found
        # inside it, and 'Via' => 'Nested'. Groups are searched the same way.
        # ---------------------------------------------------------------
        def self.Na__LibraryAsset__InfoForEntity(entity, depth = NA__LIBRARY_NESTED_DEPTH)
            return nil unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            own = entity.is_a?(Sketchup::ComponentInstance) ? Na__LibraryAsset__InfoForDefinition(entity.definition) : nil
            return own if own
            return nil if depth <= 0
            entity.definition.entities.each do |child|
                next unless child.is_a?(Sketchup::ComponentInstance) || child.is_a?(Sketchup::Group)
                found = Na__LibraryAsset__InfoForEntity(child, depth - 1)
                return found.merge('Via' => 'Nested') if found
            end
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | glTF Extras for a Node Drawn From This Entity
        # ---------------------------------------------------------------
        def self.Na__LibraryAsset__ExtrasFor(entity)
            info = Na__LibraryAsset__InfoForEntity(entity)
            info ? { 'Na__LibraryAsset' => info } : {}
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Definition Hold a LineworkModifier Tag Anywhere Below
        # ---------------------------------------------------------------
        # A modifier keeps its own node for the drawings; an asset that holds
        # one is left to flatten as before, so that node is never lost.
        # ---------------------------------------------------------------
        def self.Na__LibraryAsset__HoldsModifierTag?(definition, depth = 6)
            return false if depth <= 0
            definition.entities.any? do |child|
                next false unless child.is_a?(Sketchup::ComponentInstance) || child.is_a?(Sketchup::Group)
                (child.layer.name.to_s =~ NA__LINEWORK_MODIFIER_TAG_PATTERN) || Na__LibraryAsset__HoldsModifierTag?(child.definition, depth - 1)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Should This Entity's Edges Be a Node of Their Own
        # ---------------------------------------------------------------
        # Only a component placed from the library itself (not a wrapper: its
        # own node would cut a renamed group in two), never one that holds a
        # modifier tag. Returns [node_name, extras] or nil.
        # ---------------------------------------------------------------
        def self.Na__LibraryAsset__RangeFor(entity)
            return nil unless entity.is_a?(Sketchup::ComponentInstance)
            info = Na__LibraryAsset__InfoForDefinition(entity.definition)
            return nil unless info
            return nil if Na__LibraryAsset__HoldsModifierTag?(entity.definition)
            [Na__GlbEngine__SanitizeEntityName(entity), { 'Na__LibraryAsset' => info }]
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



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
        # ---------------------------------------------------------------
        # LINEWORK MODIFIER TAGS | Nested detail tags that keep their own node
        # ---------------------------------------------------------------
        # The SSOT's LineworkModifierConfig.TagNamePatternRegex. Edges below a
        # group on one of these tags are recorded as a POSITION RANGE rather
        # than pushed to a second array, because positions/colors are filled by
        # five different paths (this walk, root-level edges, door assemblies,
        # camera-follow assemblies, instancing) and a parallel per-edge array
        # would fall out of step the moment any one of them was missed. A range
        # captured around the recursion cannot drift: whatever landed in the
        # buffer while we were inside that subtree belongs to that tag.
        # ---------------------------------------------------------------
        NA__LINEWORK_MODIFIER_TAG_PATTERN = /\A\d{2}__LineworkModifier__/

        def self.Na__LineworkEngine__TraverseEdges(entities, parent_transform, parent_layer, positions, colors, door_assemblies = nil, instanced_skip_set = nil, camera_follow_assemblies = nil, layer_ranges = nil, inside_modifier = false, library_ranges = nil)
            entities.each do |entity|
                next if Na__Helpers__EntityExcluded?(entity)

                if entity.is_a?(Sketchup::Edge)
                    next if entity.hidden?
                    next if entity.soft?
                    next if entity.smooth?
                    next unless entity.layer.visible?
                    next if Na__Helpers__LayerLineworkHidden?(entity.layer.name)  # <-- suppress edges on linework-hidden tags

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
                    next if Na__Helpers__LayerLineworkHidden?(entity.layer.name)  # <-- short-circuit whole subtree on linework-hidden tags
                    next if Na__Helpers__EntityProfileLineExcluded?(entity)       # <-- short-circuit whole subtree on name-based profile-line exclusion

                    child_transform = parent_transform * entity.transformation
                    child_layer = (entity.layer.name == "Layer0") ? parent_layer : entity.layer

                    if door_assemblies && Na__DoorHandler__IsDoorAssembly?(entity)
                        door_assemblies << {
                            entity:                entity,
                            accumulated_transform: child_transform
                        }
                        Na__Log__Puts "      [DoorHandler/Linework] Detected door assembly: #{Na__DoorHandler__GetEntityName(entity)}"
                        next
                    end

                    if camera_follow_assemblies && Na__CameraFollowHandler__IsCameraFollowAssembly?(entity)
                        camera_follow_assemblies << {
                            entity:                entity,
                            accumulated_transform: child_transform
                        }
                        Na__Log__Puts "      [CameraFollowHandler/Linework] Detected camera-follow assembly: #{Na__CameraFollowHandler__GetEntityName(entity)}"
                        next
                    end

                    # A modifier tag opens a range; only the OUTERMOST one is
                    # recorded, so a modifier nested inside a modifier stays
                    # with its parent rather than producing overlapping ranges.
                    own_layer_name = entity.layer.name.to_s
                    opens_range    = !inside_modifier &&
                                     !layer_ranges.nil? &&
                                     own_layer_name =~ NA__LINEWORK_MODIFIER_TAG_PATTERN
                    range_start    = opens_range ? positions.length : nil

                    # A library asset opens a range of its own the same way, named
                    # for the asset and carrying its library data (outermost only).
                    library_range  = (!inside_modifier && !opens_range && !library_ranges.nil?) ? Na__LibraryAsset__RangeFor(entity) : nil
                    library_start  = library_range ? positions.length : nil

                    Na__LineworkEngine__TraverseEdges(entity.definition.entities, child_transform, child_layer, positions, colors, door_assemblies, instanced_skip_set, camera_follow_assemblies, layer_ranges, inside_modifier || opens_range || !library_range.nil?, library_ranges)

                    if opens_range && positions.length > range_start
                        layer_ranges << { :name => own_layer_name, :from => range_start, :to => positions.length }
                    end
                    if library_range && positions.length > library_start
                        library_ranges << { :name => library_range[0], :extras => library_range[1], :from => library_start, :to => positions.length }
                    end
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | glTF Structure Assembly
    # -------------------------------------------------------------------------

        # HELPER FUNCTION | Cut a Buffer Into Its Ranges, in Order
        # ---------------------------------------------------------------
        # Returns [ [name_or_nil, from, to, extras_or_nil], ... ] covering the
        # whole buffer once: unnamed runs between the named ranges.
        # ---------------------------------------------------------------
        def self.Na__LineworkEngine__SplitRanges(ranges, length)
            sorted   = Array(ranges).select { |r| r[:to] > r[:from] }.sort_by { |r| r[:from] }
            segments = []
            cursor   = 0
            sorted.each do |range|
                next if range[:from] < cursor                                      # <-- Defensive: never emit an overlap
                segments << [nil, cursor, range[:from], nil] if range[:from] > cursor
                segments << [range[:name], range[:from], range[:to], range[:extras]]
                cursor = range[:to]
            end
            segments << [nil, cursor, length, nil] if length > cursor
            segments
        end
        # ---------------------------------------------------------------

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
        def self.Na__LineworkEngine__BuildGltfFromEdgeData(positions, colors, layer_ranges = nil)
            gltf = {
                "asset"       => { "version" => "2.0", "generator" => "TrueVision3D GLB Builder Linework v1.7.0" },
                "scene"       => 0,
                "scenes"      => [{ "nodes" => [] }],
                "nodes"       => [],
                "meshes"      => [],
                "accessors"   => [],
                "bufferViews" => [],
                "buffers"     => []
            }

            bin_buffer = String.new("", encoding: Encoding::ASCII_8BIT)

            # SPLIT THE BUFFER BY TAG. Everything outside a modifier range stays
            # in one unnamed node, exactly as this file has always written it, so
            # nothing downstream that reads the whole category changes. Each
            # modifier range becomes a node of its own, NAMED with its tag, which
            # is the only way the drawing editors can tell those edges apart -
            # the flat single-node file carried no tag identity at all.
            segments = Na__LineworkEngine__SplitRanges(layer_ranges, positions.length)

            segments.each do |(name, from, to, extras)|
                next if to <= from

                slice_positions = positions[from...to]
                slice_colors    = colors[(from / 3) * 4...(to / 3) * 4]

                pos_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, slice_positions, 5126, "VEC3", 34962)
                col_accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, slice_colors,    5126, "VEC4", 34962)

                mesh_index = gltf["meshes"].length
                gltf["meshes"] << {
                    "name"       => name ? "Linework_#{name}" : "Linework",
                    "primitives" => [{
                        "attributes" => {
                            "POSITION" => pos_accessor,
                            "COLOR_0"  => col_accessor
                        },
                        "mode" => 1   # LINES
                    }]
                }

                node_index = gltf["nodes"].length
                node       = { "mesh" => mesh_index }
                node["name"] = name if name                                        # <-- The tag name, read back by the drawing editors (or a library asset's)
                node["extras"] = extras if extras                                  # <-- A library asset's Na__LibraryAsset data
                gltf["nodes"] << node
                gltf["scenes"][0]["nodes"] << node_index
            end

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
            Na__Log__Puts "  Using virtual flattening for linework export (same transforms as mesh)..."

            begin
                positions       = []
                colors          = []
                layer_ranges    = []                                               # <-- Position ranges owned by a nested LineworkModifier tag
                door_assemblies = []
                camera_follow_assemblies = []
                root_transform  = parent_transform ? Z_UP_TO_Y_UP_MATRIX * parent_transform : Z_UP_TO_Y_UP_MATRIX
                entity_count    = 0

                instanced_groups, instanced_skip_set = Na__Instancing__ScanForInstancedDefinitions(entities, root_transform)

                entities.each do |entity|
                    next if Na__Helpers__EntityExcluded?(entity)

                    if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                        next if Na__Helpers__LayerLineworkHidden?(entity.layer.name)  # <-- short-circuit whole subtree on linework-hidden tags
                        next if Na__Helpers__EntityProfileLineExcluded?(entity)       # <-- short-circuit whole subtree on name-based profile-line exclusion

                        entity_count  += 1
                        entity_name    = Na__GlbEngine__SanitizeEntityName(entity)
                        Na__Log__Puts "    Traversing linework: #{entity_name}..."

                        accumulated_transform = root_transform * entity.transformation
                        entity_layer          = entity.layer

                        if Na__DoorHandler__IsDoorAssembly?(entity)
                            door_assemblies << {
                                entity:                entity,
                                accumulated_transform: accumulated_transform
                            }
                            Na__Log__Puts "      [DoorHandler/Linework] Detected top-level door assembly: #{entity_name}"
                            next
                        end

                        if Na__CameraFollowHandler__IsCameraFollowAssembly?(entity)
                            camera_follow_assemblies << {
                                entity:                entity,
                                accumulated_transform: accumulated_transform
                            }
                            Na__Log__Puts "      [CameraFollowHandler/Linework] Detected top-level camera-follow assembly: #{entity_name}"
                            next
                        end

                        next if instanced_skip_set.key?(entity.object_id)

                        # A top-level entity can itself be on a modifier tag when
                        # the element group handed to this export IS the tagged
                        # group; open its range here, the same way the recursion
                        # does for a nested one.
                        top_layer_name = entity.layer.name.to_s
                        top_opens      = (top_layer_name =~ NA__LINEWORK_MODIFIER_TAG_PATTERN) ? true : false
                        top_start      = top_opens ? positions.length : nil
                        top_library    = top_opens ? nil : Na__LibraryAsset__RangeFor(entity)
                        top_lib_start  = top_library ? positions.length : nil

                        Na__LineworkEngine__TraverseEdges(
                            entity.definition.entities,
                            accumulated_transform,
                            entity_layer,
                            positions,
                            colors,
                            door_assemblies,
                            instanced_skip_set,
                            camera_follow_assemblies,
                            layer_ranges,
                            top_opens || !top_library.nil?,
                            layer_ranges                                           # <-- Library ranges share the list: they never overlap a modifier's
                        )

                        if top_opens && positions.length > top_start
                            layer_ranges << { :name => top_layer_name, :from => top_start, :to => positions.length }
                        end
                        if top_library && positions.length > top_lib_start
                            layer_ranges << { :name => top_library[0], :extras => top_library[1], :from => top_lib_start, :to => positions.length }
                        end

                    elsif entity.is_a?(Sketchup::Edge)
                        next if entity.hidden?
                        next if entity.soft?
                        next if entity.smooth?
                        next unless entity.layer.visible?
                        next if Na__Helpers__LayerLineworkHidden?(entity.layer.name)  # <-- suppress bare root-level edges on linework-hidden tags

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
                        r = col.red   / 255.0
                        g = col.green / 255.0
                        b = col.blue  / 255.0
                        a = (col.respond_to?(:alpha) ? col.alpha : 255) / 255.0
                        2.times { colors.push(r, g, b, a) }
                    end
                end

                edge_count = positions.length / 6
                Na__Log__Puts "    Linework traversal complete: #{entity_count} entities -> #{edge_count} edges"

                if door_assemblies.any?
                    Na__Log__Puts "    [DoorHandler/Linework] #{door_assemblies.length} door assembly(ies) detected — will export with hierarchy preservation"
                end

                if camera_follow_assemblies.any?
                    Na__Log__Puts "    [CameraFollowHandler/Linework] #{camera_follow_assemblies.length} camera-follow assembly(ies) detected — will export with hierarchy preservation"
                end

                if positions.empty? && door_assemblies.empty? && camera_follow_assemblies.empty? && instanced_groups.empty?
                    Na__Log__Puts "  No visible edges, door assemblies, or instanced components found - skipping linework file"
                    return false
                end

                if positions.empty?
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
                    gltf, bin_buffer = Na__LineworkEngine__BuildGltfFromEdgeData(positions, colors, layer_ranges)
                end

                Na__Instancing__ProcessAllInstancedLinework(instanced_groups, gltf, bin_buffer)

                Na__DoorHandler__ExportDoorLinework(door_assemblies, gltf, bin_buffer) if door_assemblies.any?
                Na__CameraFollowHandler__ExportCameraFollowLinework(camera_follow_assemblies, gltf, bin_buffer) if camera_follow_assemblies.any?

                Na__GlbEngine__WriteGlbFile(filepath, gltf, bin_buffer)

                Na__Log__Puts "  ✓ Linework export complete"
                true

            rescue => e
                Na__Log__Warn "  ERROR: Linework export failed - #{e.message}"
                Na__Log__Warn "  #{e.backtrace.first(5).join("\n  ")}"
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
