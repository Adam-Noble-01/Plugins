# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - CAMERA FOLLOW OBJECT HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__SpecialObject__CameraFollowObjectHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Special Object - Camera Follow / Billboard Handling
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Hierarchy-preserving GLB export for 2D camera-follow billboard components
# CREATED    : 16-Jun-2026
#
# DESCRIPTION:
# - Detects 2D site vegetation billboards by SSOT name regex and/or tag assignment.
# - Preserves assembly node hierarchy with pivot data baked into glTF node extras.
# - Captures 00__OriginPoint group centre as pivotLocal (geometry excluded from GLB).
# - Reuses door handler transform conjugation and local geometry extraction helpers.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Camera Follow Handler Constants and Configuration
    # -------------------------------------------------------------------------

        # MODULE CONSTANTS | Origin Point Marker and Defaults
        # ------------------------------------------------------------
        CAMERA_FOLLOW_ORIGIN_GROUP_NAME   = "00__OriginPoint".freeze          # <-- Failsafe pivot marker group name
        CAMERA_FOLLOW_DEFAULT_TAG_NAME    = "09__Site__Vegetation__2D".freeze # <-- Tag-driven detection fallback
        CAMERA_FOLLOW_DEFAULT_DETECTION   = '^\d{2}_\d{4}__SiteVegetation__'.freeze # <-- SSOT regex fallback
        # ------------------------------------------------------------

        # MODULE VARIABLES | DataLib-Driven Detection Config
        # ------------------------------------------------------------
        # Each configured Components SSOT section (vegetation, entourage, any
        # future billboard family) becomes one "family" entry here rather than
        # a single set of globals, so multiple 2D camera-follow tag/regex pairs
        # can coexist and be told apart at export time.
        @na_camerafollow_families          = []                                # <-- Array of {tag_name:, regex:, components_map:, behaviours:}
        # ------------------------------------------------------------

        # FUNCTION | Configure Camera Follow Detection from DataLib
        # ------------------------------------------------------------
        def self.Na__CameraFollowHandler__Configure(section_data)
            return unless section_data.is_a?(Hash)

            regex_str = section_data["DetectionRegex"]
            regex     = regex_str ? Regexp.new(regex_str) : Regexp.new(CAMERA_FOLLOW_DEFAULT_DETECTION)

            tag_name = section_data["Tag__SketchUpName"]
            tag_name = tag_name.is_a?(String) && !tag_name.empty? ? tag_name : CAMERA_FOLLOW_DEFAULT_TAG_NAME

            components_map = section_data["Components"]
            components_map = components_map.is_a?(Hash) ? components_map : {}

            behaviours = section_data["Behaviours"]
            behaviours = behaviours.is_a?(Hash) ? behaviours : {}

            @na_camerafollow_families << {
                tag_name:       tag_name,
                regex:          regex,
                components_map: components_map,
                behaviours:     behaviours
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Fail-Safe Default Family
        # ------------------------------------------------------------
        # Used only when the Components SSOT could not be loaded at all, so
        # detection still works via the hardcoded tag/regex fallback.
        def self.Na__CameraFollowHandler__DefaultFamily
            {
                tag_name:       CAMERA_FOLLOW_DEFAULT_TAG_NAME,
                regex:          Regexp.new(CAMERA_FOLLOW_DEFAULT_DETECTION),
                components_map: {},
                behaviours:     {}
            }
        end
        # ------------------------------------------------------------

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | Entity Detection and Naming
    # -------------------------------------------------------------------------

        # HELPER FUNCTION | Get Entity Name (delegates to DoorHandler utility)
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__GetEntityName(entity)
            Na__DoorHandler__GetEntityName(entity)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Configured Family Matching an Entity
        # ---------------------------------------------------------------
        # Checks tag-driven detection first (cheap, unambiguous), then falls
        # through to each family's SSOT name regex. Falls back to the single
        # hardcoded default family when no DataLib families were configured
        # at all (Components SSOT load failure).
        def self.Na__CameraFollowHandler__ResolveFamilyForEntity(entity)
            return nil unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            families = @na_camerafollow_families.empty? ? [Na__CameraFollowHandler__DefaultFamily] : @na_camerafollow_families

            if entity.respond_to?(:layer) && entity.layer
                by_tag = families.find { |family| family[:tag_name] == entity.layer.name }
                return by_tag if by_tag                                          # <-- Tag-driven detection
            end

            name = Na__CameraFollowHandler__GetEntityName(entity)
            return nil if name.empty?

            families.find { |family| family[:regex].match?(name) }              # <-- SSOT name regex detection
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Check if Entity is a Camera Follow Assembly
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__IsCameraFollowAssembly?(entity)
            !!Na__CameraFollowHandler__ResolveFamilyForEntity(entity)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Semantic Export Name from SSOT
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__ResolveSemanticName(raw_name, family)
            entry = family[:components_map][raw_name]
            return raw_name unless entry.is_a?(Hash)

            semantic = entry["SemanticName"]
            semantic.is_a?(String) && !semantic.empty? ? semantic : raw_name
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Clamp a Numeric Value to the 0.0 - 1.0 Range
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__ClampUnitInterval(value)
            f = value.to_f                                                        # <-- Coerce to float
            return 0.0 if f < 0.0                                                 # <-- Lower bound
            return 1.0 if f > 1.0                                                 # <-- Upper bound
            f
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Shade Flatness (component override -> section default)
        # ---------------------------------------------------------------
        # ShadeFlatness drives how flatly the billboard is lit at runtime:
        #   0.0 = full directional shading (default, unchanged behaviour)
        #   1.0 = fully flat (directional darkening removed entirely)
        # Resolution order: per-component Behaviours -> section Behaviours -> 0.0
        def self.Na__CameraFollowHandler__ResolveShadeFlatness(raw_name, family)
            entry = family[:components_map][raw_name]
            if entry.is_a?(Hash) && entry["Behaviours"].is_a?(Hash) && entry["Behaviours"]["ShadeFlatness"].is_a?(Numeric)
                return Na__CameraFollowHandler__ClampUnitInterval(entry["Behaviours"]["ShadeFlatness"])  # <-- Component override
            end

            if family[:behaviours].is_a?(Hash) && family[:behaviours]["ShadeFlatness"].is_a?(Numeric)
                return Na__CameraFollowHandler__ClampUnitInterval(family[:behaviours]["ShadeFlatness"])  # <-- Section default
            end

            0.0                                                                  # <-- Safe default (full directional shading)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Check if Child is the Origin Point Marker
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__IsOriginPointMarker?(entity)
            return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            name = Na__CameraFollowHandler__GetEntityName(entity)
            return true if name == CAMERA_FOLLOW_ORIGIN_GROUP_NAME

            entity.respond_to?(:layer) && entity.layer && entity.layer.name == CAMERA_FOLLOW_ORIGIN_GROUP_NAME
        end
        # ---------------------------------------------------------------

        # FUNCTION | Capture Origin Pivot in Assembly-Local Y-Up Metres
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__CapturePivotLocal(assembly_entity)
            origin_entity = assembly_entity.definition.entities.find do |child|
                Na__CameraFollowHandler__IsOriginPointMarker?(child)
            end

            unless origin_entity
                Na__Log__Warn "        [CameraFollowHandler] WARNING: No #{CAMERA_FOLLOW_ORIGIN_GROUP_NAME} child found — using assembly origin"
                return [0.0, 0.0, 0.0]
            end

            pivot_su = origin_entity.transformation.origin                           # <-- Pivot in assembly-local SU inches
            pivot_yup_transform = Na__DoorHandler__ConjugateToYUp(Geom::Transformation.translation(pivot_su))
            pivot_yup = pivot_yup_transform.origin

            [
                pivot_yup.x.to_f * INCHES_TO_METERS,
                pivot_yup.y.to_f * INCHES_TO_METERS,
                pivot_yup.z.to_f * INCHES_TO_METERS
            ]
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | Camera Follow Assembly Export Orchestration
    # -------------------------------------------------------------------------

        # FUNCTION | Export All Detected Camera Follow Assemblies (Mesh)
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__ExportCameraFollowAssemblies(assemblies, gltf, bin_buffer)
            Na__Log__Puts "\n    [CameraFollowHandler] Exporting #{assemblies.length} mesh camera-follow assembly(ies)..."

            assemblies.each do |assembly_data|
                Na__CameraFollowHandler__BuildAssemblyNodes(
                    assembly_data[:entity],
                    assembly_data[:accumulated_transform],
                    gltf,
                    bin_buffer,
                    :mesh
                )
            end

            Na__Log__Puts "    [CameraFollowHandler] Camera-follow mesh export complete"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Export All Detected Camera Follow Assemblies (Linework)
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__ExportCameraFollowLinework(assemblies, gltf, bin_buffer)
            Na__Log__Puts "\n    [CameraFollowHandler/Linework] Exporting #{assemblies.length} linework camera-follow assembly(ies)..."

            assemblies.each do |assembly_data|
                Na__CameraFollowHandler__BuildAssemblyNodes(
                    assembly_data[:entity],
                    assembly_data[:accumulated_transform],
                    gltf,
                    bin_buffer,
                    :linework
                )
            end

            Na__Log__Puts "    [CameraFollowHandler/Linework] Camera-follow linework export complete"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Hierarchical glTF Nodes for a Camera Follow Assembly
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__BuildAssemblyNodes(assembly_entity, accumulated_transform, gltf, bin_buffer, export_type = :mesh)
            raw_name       = Na__CameraFollowHandler__GetEntityName(assembly_entity)
            family         = Na__CameraFollowHandler__ResolveFamilyForEntity(assembly_entity) || Na__CameraFollowHandler__DefaultFamily
            export_name    = Na__CameraFollowHandler__ResolveSemanticName(raw_name, family)
            type_label     = export_type == :linework ? "Linework" : "Mesh"
            pivot_local    = Na__CameraFollowHandler__CapturePivotLocal(assembly_entity)
            shade_flatness = Na__CameraFollowHandler__ResolveShadeFlatness(raw_name, family)

            Na__Log__Puts "      [CameraFollowHandler/#{type_label}] Building camera-follow assembly: #{export_name}"

            assembly_gltf_transform = accumulated_transform * Y_UP_TO_Z_UP_MATRIX
            assembly_matrix         = Na__DoorHandler__TransformToGltfMatrix(assembly_gltf_transform)

            assembly_node_index = gltf["nodes"].length
            assembly_node = {
                "name"     => export_name,
                "matrix"   => assembly_matrix,
                "children" => [],
                "extras"   => {
                    "generator"     => "TrueVision3D_CameraFollowHandler",
                    "type"          => "CameraFollowBillboard",
                    "cameraFollow"  => true,
                    "yawOnly"       => family[:behaviours]["YawOnly"] != false,
                    "pivotLocal"    => pivot_local,
                    "shadeFlatness" => shade_flatness
                }
            }
            gltf["nodes"] << assembly_node
            gltf["scenes"][0]["nodes"] << assembly_node_index

            assembly_entity.definition.entities.each do |child_entity|
                next unless child_entity.is_a?(Sketchup::Group) || child_entity.is_a?(Sketchup::ComponentInstance)
                next if Na__CameraFollowHandler__IsOriginPointMarker?(child_entity)
                next unless Na__DoorHandler__ChildExportable?(child_entity)

                child_name            = Na__CameraFollowHandler__GetEntityName(child_entity)
                child_yup_transform   = Na__DoorHandler__ConjugateToYUp(child_entity.transformation)
                child_matrix          = Na__DoorHandler__TransformToGltfMatrix(child_yup_transform)

                child_node_index = gltf["nodes"].length
                child_node = {
                    "name"     => child_name,
                    "matrix"   => child_matrix,
                    "children" => [],
                    "extras"   => { "generator" => "TrueVision3D_CameraFollowHandler" }
                }
                gltf["nodes"] << child_node
                assembly_node["children"] << child_node_index

                if export_type == :linework
                    Na__DoorHandler__ExtractChildLinework(child_entity, child_node_index, gltf, bin_buffer)
                else
                    Na__DoorHandler__ExtractChildGeometry(child_entity, child_node_index, gltf, bin_buffer)
                end
            end

            if export_type == :linework
                Na__CameraFollowHandler__ExtractDirectLineworkExcludingOrigin(assembly_entity, assembly_node_index, gltf, bin_buffer)
            else
                Na__CameraFollowHandler__ExtractDirectGeometryExcludingOrigin(assembly_entity, assembly_node_index, gltf, bin_buffer)
            end

            Na__Log__Puts "      [CameraFollowHandler/#{type_label}] Complete: #{export_name} pivotLocal=#{pivot_local.inspect} shadeFlatness=#{shade_flatness}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Bare Faces at Assembly Level (excluding origin marker subtree)
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__ExtractDirectGeometryExcludingOrigin(assembly_entity, parent_node_index, gltf, bin_buffer)
            has_faces = assembly_entity.definition.entities.any? { |e| e.is_a?(Sketchup::Face) }
            return unless has_faces

            local_buckets = Na__GlbEngine__CreateBuckets()
            is_mirrored   = Na__GlbEngine__CalcDeterminant3x3(Z_UP_TO_Y_UP_MATRIX) < 0
            normal_matrix = Na__GlbEngine__CalcNormalMatrix(Z_UP_TO_Y_UP_MATRIX)

            assembly_entity.definition.entities.each do |face_entity|
                next unless face_entity.is_a?(Sketchup::Face)
                next if Na__Helpers__EntityExcluded?(face_entity)

                layer_name = (face_entity.layer.name == "Layer0") ? assembly_entity.layer.name : face_entity.layer.name
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

        # FUNCTION | Extract Bare Edges at Assembly Level (excluding origin marker subtree)
        # ---------------------------------------------------------------
        def self.Na__CameraFollowHandler__ExtractDirectLineworkExcludingOrigin(assembly_entity, parent_node_index, gltf, bin_buffer)
            has_edges = assembly_entity.definition.entities.any? { |e| e.is_a?(Sketchup::Edge) }
            return unless has_edges

            positions = []
            colors    = []

            assembly_entity.definition.entities.each do |edge_entity|
                next unless edge_entity.is_a?(Sketchup::Edge)
                next if Na__Helpers__EntityExcluded?(edge_entity)
                next if edge_entity.hidden?
                next if edge_entity.soft?
                next if edge_entity.smooth?
                next unless edge_entity.layer.visible?

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

    end  # module GlbBuilderUtility
end  # module TrueVision3D
