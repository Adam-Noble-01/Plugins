# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DEV TOOLS - UNIFIED 2D + 3D ASSET JSON EXPORTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__DevTools__JsonExporter3D__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__DevTools
# MODULE     : Na__JsonExporter3D
# AUTHOR     : Noble Architecture
# PURPOSE    : Forked and moved from legacy Interior Door dev exporter
#              (pre-refactor Na__InteriorDoorConfigurator JSON exporter).
#              Exports a unified asset JSON containing optional Plan2D,
#              Elevation2D, Profile2D and Mesh3D blocks for handles,
#              architraves, hinges and any future asset type.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Selection requirements (in the active model):
#     * Exactly one Sketchup::Group named "00__OriginPoint" - its bounding
#       box centre defines local 0,0,0.
#     * Optionally one Sketchup::Group named "01__PlanView" containing
#       loose 2D edges/faces in the XY plane.
#     * Optionally one Sketchup::Group named "02__ElevationView" containing
#       loose 2D edges/faces in the XZ plane.
#     * Optionally one Sketchup::Group named "03__Model3D" containing the
#       3D mesh of the asset, expressed in the same XYZ frame.
#     * Optionally one Sketchup::Group named "04__Profile2D" for architrave
#       profiles (rich vertices/edges/faces in the YZ plane).
# - Output JSON structure (Na__Asset__* keys, three-stage column-aligned
#   style) - any block whose source group is missing is omitted, and the
#   matching Na__Asset__Has* flag is set to false.
#
#     {
#       "meta"                : { ... },
#       "Na__Asset__Metadata" : { ... },
#       "Na__Asset__Plan2D"      : { Paths, BoundingBox, ... },
#       "Na__Asset__Elevation2D" : { Paths, BoundingBox, ... },
#       "Na__Asset__Profile2D"   : { Vertices, Edges, Faces, ... },
#       "Na__Asset__Mesh3D"      : { Vertices, Faces, BoundingBox, ... }
#     }
#
# - Saves via UI.savepanel.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
# - Inner helpers are private_class_method so only na_run_export is public.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module Na__AssemblyStudio
module Na__DevTools
    module Na__JsonExporter3D

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM             = 25.4

        NA_GROUP_ORIGIN           = "00__OriginPoint".freeze
        NA_GROUP_PLAN             = "01__PlanView".freeze
        NA_GROUP_ELEVATION        = "02__ElevationView".freeze
        NA_GROUP_MODEL3D          = "03__Model3D".freeze
        NA_GROUP_PROFILE2D        = "04__Profile2D".freeze

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Single Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the Unified Asset Exporter
        # ------------------------------------------------------------
        # Single public entry point. Bind to a UI button or call directly
        # from the Ruby Console:
        #     Na__DevTools::Na__JsonExporter3D.na_run_export
        def self.na_run_export
            model     = Sketchup.active_model
            selection = model.selection.to_a

            origin_container = na_find_named_container(selection, NA_GROUP_ORIGIN)
            unless origin_container
                puts "\n!! Na__JsonExporter3D : No group named '#{NA_GROUP_ORIGIN}' found in selection."
                return
            end
            origin_local = if origin_container[:entity].respond_to?(:definition) && origin_container[:entity].definition
                               origin_container[:entity].definition.bounds.center
                           else
                               origin_container[:entity].bounds.center
                           end
            origin_pt    = origin_local.transform(origin_container[:world_transform])

            plan_container      = na_find_named_container(selection, NA_GROUP_PLAN)
            elevation_container = na_find_named_container(selection, NA_GROUP_ELEVATION)
            profile_container   = na_find_named_container(selection, NA_GROUP_PROFILE2D)
            explicit_model_container = na_find_named_container(selection, NA_GROUP_MODEL3D)
            fallback_model_container = na_find_first_face_container(selection, origin_container[:entity])

            puts ">> Optional block '#{NA_GROUP_PLAN}' not found."         unless plan_container
            puts ">> Optional block '#{NA_GROUP_ELEVATION}' not found."    unless elevation_container
            puts ">> Optional block '#{NA_GROUP_PROFILE2D}' not found."    unless profile_container
            puts ">> Optional block '#{NA_GROUP_MODEL3D}' not found."      unless explicit_model_container
            if explicit_model_container
                puts ">> 3D mesh source: explicit '#{NA_GROUP_MODEL3D}' container."
            elsif fallback_model_container
                puts ">> 3D mesh source: selection-hierarchy fallback scan (nested groups/components)."
            else
                puts ">> 3D mesh source: none (no faces found in selection hierarchy)."
            end

            plan_block       = na_extract_plan_block(plan_container, origin_pt)
            elevation_block  = na_extract_elevation_block(elevation_container, origin_pt)
            profile_block    = na_extract_profile_block(profile_container, origin_pt)
            mesh_block, hierarchy_block = if explicit_model_container
                                              na_extract_mesh_bundle(explicit_model_container, origin_pt)
                                          else
                                              na_extract_mesh_bundle_from_selection(
                                                  selection,
                                                  origin_pt,
                                                  [
                                                      origin_container && origin_container[:entity],
                                                      plan_container && plan_container[:entity],
                                                      elevation_container && elevation_container[:entity],
                                                      profile_container && profile_container[:entity]
                                                  ].compact
                                              )
                                          end

            metadata = na_build_metadata_placeholder(
                :has_plan      => !plan_block.nil?,
                :has_elevation => !elevation_block.nil?,
                :has_profile   => !profile_block.nil?,
                :has_3d        => !mesh_block.nil?
            )

            full_document = {
                "meta"                  => na_build_meta_block,
                "Na__Asset__Metadata"   => metadata
            }
            full_document["Na__Asset__Plan2D"]      = plan_block      if plan_block
            full_document["Na__Asset__Elevation2D"] = elevation_block if elevation_block
            full_document["Na__Asset__Profile2D"]   = profile_block   if profile_block
            full_document["Na__Asset__Mesh3D"]      = mesh_block      if mesh_block
            full_document["Na__Asset__ObjectHierarchy3D"] = hierarchy_block if hierarchy_block

            json_string = na_serialize_root(full_document)

            na_print_to_console(json_string)
            na_save_to_disk(json_string)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find Named Group/Component in Selection (Recursive)
        # ------------------------------------------------------------
        def self.na_find_named_container(selection, target_name)
            selection.each do |entity|
                result = na_find_named_container_in_entity(
                    entity,
                    target_name,
                    Geom::Transformation.new,
                    {}
                )
                return result if result
            end
            nil
        end
        private_class_method :na_find_named_container
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Recursive Entity Search for Named Containers
        # ------------------------------------------------------------
        def self.na_find_named_container_in_entity(entity, target_name, parent_world_transform, definition_guard)
            case entity
            when Sketchup::Group
                world_transform = parent_world_transform * entity.transformation
                if na_entity_matches_name?(entity, target_name)
                    return { :entity => entity, :world_transform => world_transform }
                end
                entity.entities.each do |child|
                    result = na_find_named_container_in_entity(
                        child,
                        target_name,
                        world_transform,
                        definition_guard
                    )
                    return result if result
                end
            when Sketchup::ComponentInstance
                world_transform = parent_world_transform * entity.transformation
                if na_entity_matches_name?(entity, target_name)
                    return { :entity => entity, :world_transform => world_transform }
                end

                definition_id = entity.definition.object_id
                return nil if definition_guard[definition_id]
                definition_guard[definition_id] = true
                entity.definition.entities.each do |child|
                    result = na_find_named_container_in_entity(
                        child,
                        target_name,
                        world_transform,
                        definition_guard
                    )
                    if result
                        definition_guard.delete(definition_id)
                        return result
                    end
                end
                definition_guard.delete(definition_id)
            end
            nil
        end
        private_class_method :na_find_named_container_in_entity
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Check if Entity Name or Tag Matches
        # ------------------------------------------------------------
        def self.na_entity_matches_name?(entity, target_name)
            entity_name = entity.respond_to?(:name) ? entity.name.to_s : ""
            tag_name = if entity.respond_to?(:layer) && entity.layer
                           entity.layer.name.to_s
                       else
                           ""
                       end
            na_names_match?(entity_name, target_name) || na_names_match?(tag_name, target_name)
        end
        private_class_method :na_entity_matches_name?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Relaxed Name Match for Group/Tag Labels
        # ------------------------------------------------------------
        # Matches exact, normalized exact, and normalized "contains".
        def self.na_names_match?(candidate_name, target_name)
            return false if candidate_name.nil? || target_name.nil?
            candidate = candidate_name.to_s.strip
            target    = target_name.to_s.strip
            return false if candidate.empty? || target.empty?
            return true if candidate == target

            candidate_norm = na_normalize_name(candidate)
            target_norm    = na_normalize_name(target)
            return false if candidate_norm.empty? || target_norm.empty?

            candidate_norm == target_norm || candidate_norm.include?(target_norm)
        end
        private_class_method :na_names_match?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Normalize Label for Fuzzy Matching
        # ------------------------------------------------------------
        def self.na_normalize_name(value)
            value.to_s.downcase.gsub(/[^a-z0-9]/, '')
        end
        private_class_method :na_normalize_name
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Find First Selected Group/Component with Faces
        # ------------------------------------------------------------
        # Used as a 3D-export fallback when 03__Model3D cannot be matched.
        def self.na_find_first_face_container(selection, excluded_entity = nil)
            selection.each do |entity|
                result = na_find_first_face_container_in_entity(
                    entity,
                    Geom::Transformation.new,
                    excluded_entity,
                    {}
                )
                return result if result
            end
            nil
        end
        private_class_method :na_find_first_face_container
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Recursive Search for Face-Bearing Container
        # ------------------------------------------------------------
        def self.na_find_first_face_container_in_entity(entity, parent_world_transform, excluded_entity, definition_guard)
            case entity
            when Sketchup::Group
                return nil if excluded_entity && entity == excluded_entity
                world_transform = parent_world_transform * entity.transformation
                return { :entity => entity, :world_transform => world_transform } if na_entities_contain_faces?(entity.entities, {})

                entity.entities.each do |child|
                    result = na_find_first_face_container_in_entity(
                        child,
                        world_transform,
                        excluded_entity,
                        definition_guard
                    )
                    return result if result
                end
            when Sketchup::ComponentInstance
                return nil if excluded_entity && entity == excluded_entity
                world_transform = parent_world_transform * entity.transformation
                return { :entity => entity, :world_transform => world_transform } if na_entities_contain_faces?(entity.definition.entities, {})

                definition_id = entity.definition.object_id
                return nil if definition_guard[definition_id]
                definition_guard[definition_id] = true
                entity.definition.entities.each do |child|
                    result = na_find_first_face_container_in_entity(
                        child,
                        world_transform,
                        excluded_entity,
                        definition_guard
                    )
                    if result
                        definition_guard.delete(definition_id)
                        return result
                    end
                end
                definition_guard.delete(definition_id)
            end
            nil
        end
        private_class_method :na_find_first_face_container_in_entity
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Recursive Face Presence Test
        # ------------------------------------------------------------
        def self.na_entities_contain_faces?(entities, definition_guard)
            entities.each do |entity|
                return true if entity.is_a?(Sketchup::Face)
                if entity.is_a?(Sketchup::Group)
                    return true if na_entities_contain_faces?(entity.entities, definition_guard)
                elsif entity.is_a?(Sketchup::ComponentInstance)
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    return true if na_entities_contain_faces?(entity.definition.entities, definition_guard)
                    definition_guard.delete(definition_id)
                end
            end
            false
        end
        private_class_method :na_entities_contain_faces?
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | 2D Plan / Elevation Extraction
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Extract the 2D Plan Block (XY Plane, Z Discarded)
        # ------------------------------------------------------------
        def self.na_extract_plan_block(container, origin_pt)
            return nil unless container

            edge_records, face_records = na_collect_edges_and_faces_recursive(
                container[:entity].entities,
                container[:world_transform]
            )
            arcs, arc_ids = na_extract_arcs_2d(edge_records, origin_pt, :xy)
            lines         = na_extract_lines_2d(edge_records, origin_pt, arc_ids, :xy)
            polygons      = na_extract_faces_2d(face_records, origin_pt, :xy)
            bbox          = na_calc_bbox_2d(arcs, lines, polygons)

            {
                "Na__Geometry__OriginNote"   => "Local 0,0 = centre of 00__OriginPoint group; right-hand plan orientation.",
                "Na__Geometry__CoordSystem"  => "XY plane | X=right, Y=forward (away from door face) | Units=mm | Z discarded",
                "Na__Geometry__BoundingBox"  => bbox,
                "Na__Geometry__Counts"       => na_build_2d_counts(edge_records.length, arcs, lines, polygons),
                "Na__Geometry__Paths"        => polygons + arcs + lines
            }
        end
        private_class_method :na_extract_plan_block
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract the 2D Elevation Block (XZ Plane, Y Discarded)
        # ------------------------------------------------------------
        def self.na_extract_elevation_block(container, origin_pt)
            return nil unless container

            edge_records, face_records = na_collect_edges_and_faces_recursive(
                container[:entity].entities,
                container[:world_transform]
            )
            arcs, arc_ids = na_extract_arcs_2d(edge_records, origin_pt, :xz)
            lines         = na_extract_lines_2d(edge_records, origin_pt, arc_ids, :xz)
            polygons      = na_extract_faces_2d(face_records, origin_pt, :xz)
            bbox          = na_calc_bbox_2d(arcs, lines, polygons)

            {
                "Na__Geometry__OriginNote"   => "Local 0,0 = centre of 00__OriginPoint group; XZ plane.",
                "Na__Geometry__CoordSystem"  => "XY plane | X=right, Y=up | Units=mm | source axis Y discarded",
                "Na__Geometry__BoundingBox"  => bbox,
                "Na__Geometry__Counts"       => na_build_2d_counts(edge_records.length, arcs, lines, polygons),
                "Na__Geometry__Paths"        => polygons + arcs + lines
            }
        end
        private_class_method :na_extract_elevation_block
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract the 2D Profile Block (YZ Plane, Architrave-style)
        # ------------------------------------------------------------
        # Profile blocks are stored as rich vertex/edge/face indices to
        # match the Profile Path Tracer's authoring format.
        def self.na_extract_profile_block(container, origin_pt)
            return nil unless container

            edge_records, face_records = na_collect_edges_and_faces_recursive(
                container[:entity].entities,
                container[:world_transform]
            )

            vertex_table = {}
            vertices_out = []
            edge_records.each do |edge_record|
                edge = edge_record[:edge]
                tr   = edge_record[:world_transform]
                [edge.start, edge.end].each do |vertex|
                    key = "#{vertex.object_id}|#{na_transform_key(tr)}"
                    next if vertex_table.key?(key)
                    pos     = vertex.position.transform(tr)
                    pos_y   = ((pos.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
                    pos_z   = ((pos.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
                    vid     = "V%03d" % (vertices_out.length + 1)
                    vertex_table[key] = vid
                    vertices_out << { "VertexId" => vid, "PosY_mm" => pos_y, "PosZ_mm" => pos_z }
                end
            end

            edges_out = []
            edge_records.each_with_index do |edge_record, idx|
                edge = edge_record[:edge]
                tr   = edge_record[:world_transform]
                eid = "E%03d" % (idx + 1)
                start_key = "#{edge.start.object_id}|#{na_transform_key(tr)}"
                end_key   = "#{edge.end.object_id}|#{na_transform_key(tr)}"
                edges_out << {
                    "EdgeId"        => eid,
                    "StartVertex"   => vertex_table[start_key],
                    "EndVertex"     => vertex_table[end_key]
                }
            end

            faces_out = []
            face_records.each_with_index do |face_record, idx|
                face = face_record[:face]
                tr   = face_record[:world_transform]
                fid     = "F%03d" % (idx + 1)
                loop_v  = face.outer_loop.vertices.map do |v|
                    vertex_table["#{v.object_id}|#{na_transform_key(tr)}"]
                end.compact
                faces_out << { "FaceId" => fid, "OuterLoopVertices" => loop_v }
            end

            {
                "Na__Geometry__OriginNote"   => "Local 0,0 = inner-bottom corner; profile authored in YZ plane.",
                "Na__Geometry__CoordSystem"  => "Y=horizontal width, Z=projection | Units=mm",
                "Na__Geometry__Vertices"     => vertices_out,
                "Na__Geometry__Edges"        => edges_out,
                "Na__Geometry__Faces"        => faces_out
            }
        end
        private_class_method :na_extract_profile_block
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | 3D Mesh Extraction
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Extract Mesh + Object Hierarchy for 03__Model3D
        # ------------------------------------------------------------
        def self.na_extract_mesh_bundle(container, origin_pt)
            return [nil, nil] unless container

            root_entity         = container[:entity]
            root_world          = container[:world_transform]
            hierarchy_nodes     = []
            face_records        = []
            node_seq            = 0

            root_node_id        = na_next_node_id(node_seq)
            node_seq            += 1
            hierarchy_nodes << na_build_hierarchy_node_hash(
                root_node_id,
                nil,
                root_entity,
                root_world,
                root_world
            )

            child_entities = if root_entity.is_a?(Sketchup::Group)
                                 root_entity.entities
                             elsif root_entity.is_a?(Sketchup::ComponentInstance)
                                 root_entity.definition.entities
                             else
                                 []
                             end

            node_seq = na_collect_mesh_tree(
                child_entities,
                root_world,
                root_node_id,
                hierarchy_nodes,
                face_records,
                node_seq,
                {}
            )

            return [nil, nil] if face_records.empty?

            mesh_block      = na_build_mesh_block(face_records, origin_pt)
            hierarchy_block = na_build_hierarchy_block(hierarchy_nodes, face_records)
            [mesh_block, hierarchy_block]
        end
        private_class_method :na_extract_mesh_bundle
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Mesh + Hierarchy from Entire Selection
        # ------------------------------------------------------------
        # Used when a named 03__Model3D container is not present. This path
        # traverses every selected group/component recursively so deeply nested
        # structures (component -> child groups/components -> grandchildren ...)
        # are exported in one pass.
        def self.na_extract_mesh_bundle_from_selection(selection, origin_pt, excluded_entities = [])
            hierarchy_nodes = []
            face_records    = []
            node_seq        = 0

            root_node_id = na_next_node_id(node_seq)
            node_seq += 1
            hierarchy_nodes << {
                "Na__Object__NodeId"                    => root_node_id,
                "Na__Object__ParentNodeId"              => nil,
                "Na__Object__EntityType"                => "SelectionRoot",
                "Na__Object__Name"                      => "SelectedEntities",
                "Na__Object__DefinitionName"            => "",
                "Na__Object__TagName"                   => "",
                "Na__Object__LocalTransform__Matrix4x4" => na_transform_to_matrix(Geom::Transformation.new),
                "Na__Object__WorldTransform__Matrix4x4" => na_transform_to_matrix(Geom::Transformation.new),
                "Na__Object__DirectFaceCount"           => 0
            }

            definition_guard = {}
            selection.each do |entity|
                next if excluded_entities.include?(entity)

                case entity
                when Sketchup::Face
                    face_records << {
                        :face            => entity,
                        :world_transform => Geom::Transformation.new,
                        :node_id         => root_node_id
                    }
                when Sketchup::Group
                    local_transform = entity.transformation
                    world_transform = local_transform
                    node_id         = na_next_node_id(node_seq)
                    node_seq       += 1
                    hierarchy_nodes << na_build_hierarchy_node_hash(
                        node_id,
                        root_node_id,
                        entity,
                        local_transform,
                        world_transform
                    )
                    node_seq = na_collect_mesh_tree(
                        entity.entities,
                        world_transform,
                        node_id,
                        hierarchy_nodes,
                        face_records,
                        node_seq,
                        definition_guard
                    )
                when Sketchup::ComponentInstance
                    local_transform = entity.transformation
                    world_transform = local_transform
                    node_id         = na_next_node_id(node_seq)
                    node_seq       += 1
                    hierarchy_nodes << na_build_hierarchy_node_hash(
                        node_id,
                        root_node_id,
                        entity,
                        local_transform,
                        world_transform
                    )
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    node_seq = na_collect_mesh_tree(
                        entity.definition.entities,
                        world_transform,
                        node_id,
                        hierarchy_nodes,
                        face_records,
                        node_seq,
                        definition_guard
                    )
                    definition_guard.delete(definition_id)
                end
            end

            return [nil, nil] if face_records.empty?

            mesh_block      = na_build_mesh_block(face_records, origin_pt)
            hierarchy_block = na_build_hierarchy_block(hierarchy_nodes, face_records)
            [mesh_block, hierarchy_block]
        end
        private_class_method :na_extract_mesh_bundle_from_selection
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Geometry Collection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect Edges/Faces Recursively with World Transform
        # ------------------------------------------------------------
        def self.na_collect_edges_and_faces_recursive(entities, world_transform, edges = [], faces = [], definition_guard = {})
            entities.each do |entity|
                case entity
                when Sketchup::Edge
                    edges << {
                        :edge            => entity,
                        :world_transform => world_transform
                    }
                when Sketchup::Face
                    faces << {
                        :face            => entity,
                        :world_transform => world_transform
                    }
                when Sketchup::Group
                    child_world = world_transform * entity.transformation
                    na_collect_edges_and_faces_recursive(entity.entities, child_world, edges, faces, definition_guard)
                when Sketchup::ComponentInstance
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    child_world = world_transform * entity.transformation
                    na_collect_edges_and_faces_recursive(
                        entity.definition.entities,
                        child_world,
                        edges,
                        faces,
                        definition_guard
                    )
                    definition_guard.delete(definition_id)
                end
            end
            [edges, faces]
        end
        private_class_method :na_collect_edges_and_faces_recursive
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Transform Key for Deduping Curve Instances
        # ------------------------------------------------------------
        def self.na_transform_key(transform)
            transform.to_a.map { |val| val.round(6) }.join("|")
        end
        private_class_method :na_transform_key
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | 2D Projection Helpers (XY/XZ)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Project World Point into Export 2D Plane
        # ------------------------------------------------------------
        def self.na_project_point_mm(pt_world, origin_pt, plane)
            if plane == :xz
                {
                    "X" => ((pt_world.x - origin_pt.x) * NA_INCH_TO_MM).round(3),
                    "Y" => ((pt_world.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
                }
            else
                {
                    "X" => ((pt_world.x - origin_pt.x) * NA_INCH_TO_MM).round(3),
                    "Y" => ((pt_world.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
                }
            end
        end
        private_class_method :na_project_point_mm
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Arc/Circle Paths from Edge Records
        # ------------------------------------------------------------
        def self.na_extract_arcs_2d(edge_records, origin_pt, plane)
            seen = {}
            arcs = []
            edge_records.each do |edge_record|
                edge  = edge_record[:edge]
                tr    = edge_record[:world_transform]
                curve = edge.curve
                next unless curve.is_a?(Sketchup::ArcCurve)
                curve_key = "#{curve.object_id}|#{na_transform_key(tr)}"
                next if seen[curve_key]
                seen[curve_key] = true

                arcs << na_arc_to_hash(curve, tr, origin_pt, plane)
            end
            [arcs, seen]
        end
        private_class_method :na_extract_arcs_2d
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Line Paths from Edge Records
        # ------------------------------------------------------------
        def self.na_extract_lines_2d(edge_records, origin_pt, arc_ids, plane)
            lines = []
            edge_records.each do |edge_record|
                edge  = edge_record[:edge]
                tr    = edge_record[:world_transform]
                curve = edge.curve
                if curve.is_a?(Sketchup::ArcCurve)
                    curve_key = "#{curve.object_id}|#{na_transform_key(tr)}"
                    next if arc_ids[curve_key]
                end
                start_world = edge.start.position.transform(tr)
                end_world   = edge.end.position.transform(tr)
                lines << {
                    "PathType"   => "Line",
                    "VertexName" => "",
                    "Start_mm"   => na_project_point_mm(start_world, origin_pt, plane),
                    "End_mm"     => na_project_point_mm(end_world, origin_pt, plane)
                }
            end
            lines
        end
        private_class_method :na_extract_lines_2d
        # ---------------------------------------------------------------

        # SUB FUNCTION | Extract Polygon Paths from Face Records
        # ------------------------------------------------------------
        def self.na_extract_faces_2d(face_records, origin_pt, plane)
            polygons = []
            face_records.each do |face_record|
                face = face_record[:face]
                tr   = face_record[:world_transform]
                vertices = face.outer_loop.vertices.map do |vertex|
                    world_pt = vertex.position.transform(tr)
                    na_project_point_mm(world_pt, origin_pt, plane)
                end
                polygons << {
                    "PathType"    => "Polygon",
                    "VertexName"  => "",
                    "Vertices_mm" => vertices
                }
            end
            polygons
        end
        private_class_method :na_extract_faces_2d
        # ---------------------------------------------------------------

        # SUB FUNCTION | Calculate Bounding Box for 2D Paths
        # ------------------------------------------------------------
        def self.na_calc_bbox_2d(arcs, lines, polygons)
            xs = []
            ys = []
            lines.each do |l|
                xs << l["Start_mm"]["X"] << l["End_mm"]["X"]
                ys << l["Start_mm"]["Y"] << l["End_mm"]["Y"]
            end
            arcs.each do |a|
                cx = a["Center_mm"]["X"]; cy = a["Center_mm"]["Y"]; r = a["Radius_mm"]
                xs << (cx - r) << (cx + r)
                ys << (cy - r) << (cy + r)
            end
            polygons.each do |p|
                p["Vertices_mm"].each { |v| xs << v["X"]; ys << v["Y"] }
            end
            return {} if xs.empty?
            {
                "Na__Geometry__MinX_mm"   => xs.min.round(3),
                "Na__Geometry__MaxX_mm"   => xs.max.round(3),
                "Na__Geometry__MinY_mm"   => ys.min.round(3),
                "Na__Geometry__MaxY_mm"   => ys.max.round(3),
                "Na__Geometry__Width_mm"  => (xs.max - xs.min).round(3),
                "Na__Geometry__Height_mm" => (ys.max - ys.min).round(3)
            }
        end
        private_class_method :na_calc_bbox_2d
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Mesh Hierarchy + Geometry Builder
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect Mesh Faces + Hierarchy from Entity Tree
        # ------------------------------------------------------------
        def self.na_collect_mesh_tree(entities, parent_world, parent_node_id, hierarchy_nodes, face_records, node_seq, definition_guard = {})
            entities.each do |entity|
                case entity
                when Sketchup::Face
                    face_records << {
                        :face            => entity,
                        :world_transform => parent_world,
                        :node_id         => parent_node_id
                    }
                when Sketchup::Group
                    local_transform = entity.transformation
                    world_transform = parent_world * local_transform
                    node_id         = na_next_node_id(node_seq)
                    node_seq        += 1
                    hierarchy_nodes << na_build_hierarchy_node_hash(
                        node_id,
                        parent_node_id,
                        entity,
                        local_transform,
                        world_transform
                    )
                    node_seq = na_collect_mesh_tree(
                        entity.entities,
                        world_transform,
                        node_id,
                        hierarchy_nodes,
                        face_records,
                        node_seq,
                        definition_guard
                    )
                when Sketchup::ComponentInstance
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    local_transform = entity.transformation
                    world_transform = parent_world * local_transform
                    node_id         = na_next_node_id(node_seq)
                    node_seq        += 1
                    hierarchy_nodes << na_build_hierarchy_node_hash(
                        node_id,
                        parent_node_id,
                        entity,
                        local_transform,
                        world_transform
                    )
                    node_seq = na_collect_mesh_tree(
                        entity.definition.entities,
                        world_transform,
                        node_id,
                        hierarchy_nodes,
                        face_records,
                        node_seq,
                        definition_guard
                    )
                    definition_guard.delete(definition_id)
                end
            end
            node_seq
        end
        private_class_method :na_collect_mesh_tree
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Stable Hierarchy Node ID
        # ------------------------------------------------------------
        def self.na_next_node_id(node_index)
            "OBJ%04d" % (node_index + 1)
        end
        private_class_method :na_next_node_id
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build One Hierarchy Node Hash
        # ------------------------------------------------------------
        def self.na_build_hierarchy_node_hash(node_id, parent_node_id, entity, local_transform, world_transform)
            {
                "Na__Object__NodeId"                         => node_id,
                "Na__Object__ParentNodeId"                   => parent_node_id,
                "Na__Object__EntityType"                     => entity.class.name.split('::').last,
                "Na__Object__Name"                           => entity.respond_to?(:name) ? entity.name.to_s : "",
                "Na__Object__DefinitionName"                 => entity.respond_to?(:definition) ? entity.definition.name.to_s : "",
                "Na__Object__TagName"                        => (entity.respond_to?(:layer) && entity.layer) ? entity.layer.name.to_s : "",
                "Na__Object__LocalTransform__Matrix4x4"      => na_transform_to_matrix(local_transform),
                "Na__Object__WorldTransform__Matrix4x4"      => na_transform_to_matrix(world_transform),
                "Na__Object__DirectFaceCount"                => 0
            }
        end
        private_class_method :na_build_hierarchy_node_hash
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Convert SketchUp Transformation to 4x4 Matrix
        # ------------------------------------------------------------
        def self.na_transform_to_matrix(transform)
            arr = transform.to_a.map { |v| v.to_f.round(6) }
            [
                [arr[0],  arr[1],  arr[2],  arr[3]],
                [arr[4],  arr[5],  arr[6],  arr[7]],
                [arr[8],  arr[9],  arr[10], arr[11]],
                [arr[12], arr[13], arr[14], arr[15]]
            ]
        end
        private_class_method :na_transform_to_matrix
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Mesh Block from Face Records
        # ------------------------------------------------------------
        def self.na_build_mesh_block(face_records, origin_pt)
            vertex_id_lookup   = {}
            vertices_out       = []
            faces_out          = []
            edge_lookup        = {}

            face_records.each_with_index do |face_record, idx|
                face      = face_record[:face]
                transform = face_record[:world_transform]
                node_id   = face_record[:node_id]

                outer_ids = na_loop_vertex_ids(face.outer_loop.vertices, transform, origin_pt, vertex_id_lookup, vertices_out)
                next if outer_ids.length < 3

                inner_loops = face.loops.reject(&:outer?).map do |loop|
                    na_loop_vertex_ids(loop.vertices, transform, origin_pt, vertex_id_lookup, vertices_out)
                end

                normal_vec = face.normal.transform(transform)
                normal_vec.length = 1.0 if normal_vec.respond_to?(:length=) && normal_vec.length > 0.0

                area_mm2 = begin
                    (face.area(transform).to_f * NA_INCH_TO_MM * NA_INCH_TO_MM).round(3)
                rescue StandardError
                    nil
                end
                material_name = face.material ? face.material.display_name.to_s : ""

                face_id = "F%03d" % (idx + 1)
                faces_out << {
                    "FaceId"               => face_id,
                    "FaceName"             => "Na__Mesh__Face__#{face_id}",
                    "OuterLoop_VertexIds"  => outer_ids,
                    "InnerLoops"           => inner_loops,
                    "Normal"               => [
                        normal_vec.x.to_f.round(6),
                        normal_vec.y.to_f.round(6),
                        normal_vec.z.to_f.round(6)
                    ],
                    "Area_mm2"             => area_mm2,
                    "MaterialName"         => material_name,
                    "Na__Object__NodeId"   => node_id
                }

                na_add_loop_edges_to_lookup(edge_lookup, outer_ids)
                inner_loops.each { |loop_ids| na_add_loop_edges_to_lookup(edge_lookup, loop_ids) }
            end

            edges_out = na_edges_from_lookup(edge_lookup)
            bbox      = na_calc_bbox_xyz(vertices_out)

            {
                "Na__Geometry__OriginNote"  => "Local 0,0,0 = centre of 00__OriginPoint group.",
                "Na__Geometry__CoordSystem" => "Right-handed | X=right, Y=front, Z=up | Units=mm",
                "Na__Geometry__BoundingBox" => bbox,
                "Na__Geometry__Counts"      => {
                    "Na__Geometry__VertexCount" => vertices_out.length,
                    "Na__Geometry__FaceCount"   => faces_out.length,
                    "Na__Geometry__EdgeCount"   => edges_out.length
                },
                "Na__Geometry__Vertices"    => vertices_out,
                "Na__Geometry__Faces"       => faces_out,
                "Na__Geometry__Edges"       => edges_out
            }
        end
        private_class_method :na_build_mesh_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Hierarchy Block and Face Counts
        # ------------------------------------------------------------
        def self.na_build_hierarchy_block(hierarchy_nodes, face_records)
            per_node_count = Hash.new(0)
            face_records.each do |record|
                per_node_count[record[:node_id]] += 1
            end
            hierarchy_nodes.each do |node|
                node_id = node["Na__Object__NodeId"]
                node["Na__Object__DirectFaceCount"] = per_node_count[node_id] || 0
            end
            {
                "Na__Hierarchy__OriginNote"  => "Hierarchy captured from 03__Model3D with nested groups/components preserved.",
                "Na__Hierarchy__CoordSystem" => "Right-handed | X=right, Y=front, Z=up | Units=mm",
                "Na__Hierarchy__Objects"     => hierarchy_nodes
            }
        end
        private_class_method :na_build_hierarchy_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Vertex IDs for Loop Vertices
        # ------------------------------------------------------------
        def self.na_loop_vertex_ids(loop_vertices, transform, origin_pt, vertex_id_lookup, vertices_out)
            loop_vertices.map do |vertex|
                world_point = vertex.position.transform(transform)
                point_hash = {
                    "PosX_mm" => ((world_point.x - origin_pt.x) * NA_INCH_TO_MM).round(3),
                    "PosY_mm" => ((world_point.y - origin_pt.y) * NA_INCH_TO_MM).round(3),
                    "PosZ_mm" => ((world_point.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
                }
                key = "#{point_hash["PosX_mm"]}|#{point_hash["PosY_mm"]}|#{point_hash["PosZ_mm"]}"
                unless vertex_id_lookup[key]
                    vertex_id = "V%03d" % (vertices_out.length + 1)
                    vertex_id_lookup[key] = vertex_id
                    vertices_out << {
                        "VertexId"   => vertex_id,
                        "VertexName" => "Na__Mesh__Vertex__#{vertex_id}",
                        "PosX_mm"    => point_hash["PosX_mm"],
                        "PosY_mm"    => point_hash["PosY_mm"],
                        "PosZ_mm"    => point_hash["PosZ_mm"]
                    }
                end
                vertex_id_lookup[key]
            end
        end
        private_class_method :na_loop_vertex_ids
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add Edges from Closed Loop Vertex IDs
        # ------------------------------------------------------------
        def self.na_add_loop_edges_to_lookup(edge_lookup, loop_ids)
            return if loop_ids.length < 2
            loop_ids.each_with_index do |start_vid, idx|
                end_vid = loop_ids[(idx + 1) % loop_ids.length]
                next if start_vid == end_vid
                key = [start_vid, end_vid].sort.join("|")
                edge_lookup[key] = [start_vid, end_vid] unless edge_lookup[key]
            end
        end
        private_class_method :na_add_loop_edges_to_lookup
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Convert Edge Lookup into Na__Geometry__Edges
        # ------------------------------------------------------------
        def self.na_edges_from_lookup(edge_lookup)
            edges = []
            edge_lookup.values.each_with_index do |pair, idx|
                edge_id = "E%03d" % (idx + 1)
                edges << {
                    "EdgeId"      => edge_id,
                    "StartVertex" => pair[0],
                    "EndVertex"   => pair[1]
                }
            end
            edges
        end
        private_class_method :na_edges_from_lookup
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Generic Helpers (Bounding Box / Arc Hash)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert an ArcCurve to a Plain Hash
        # ------------------------------------------------------------
        def self.na_arc_to_hash(curve, transform, origin_pt, plane)
            center_world = curve.center.transform(transform)
            start_world  = curve.edges.first.start.position.transform(transform)
            end_world    = curve.edges.last.end.position.transform(transform)

            center_2d = na_project_point_mm(center_world, origin_pt, plane)
            start_2d  = na_project_point_mm(start_world, origin_pt, plane)
            end_2d    = na_project_point_mm(end_world, origin_pt, plane)

            radius_mm = Math.sqrt(
                (start_2d["X"] - center_2d["X"]) ** 2 +
                (start_2d["Y"] - center_2d["Y"]) ** 2
            ).round(3)

            start_deg = (Math.atan2(start_2d["Y"] - center_2d["Y"], start_2d["X"] - center_2d["X"]) * 180.0 / Math::PI).round(3)
            end_deg   = (Math.atan2(end_2d["Y"] - center_2d["Y"], end_2d["X"] - center_2d["X"]) * 180.0 / Math::PI).round(3)
            is_circle = curve.circular?

            if is_circle
                end_deg = (start_deg + 360.0).round(3)
            end
            sweep_deg = (end_deg - start_deg).round(3)
            sweep_deg += 360.0 if !is_circle && sweep_deg <= 0.0

            {
                "PathType"        => is_circle ? "Circle" : "Arc",
                "VertexName"      => "",
                "Center_mm"       => center_2d,
                "Radius_mm"       => radius_mm,
                "StartAngle_deg"  => start_deg,
                "EndAngle_deg"    => end_deg,
                "Sweep_deg"       => sweep_deg.round(3),
                "StartPoint_mm"   => start_2d,
                "EndPoint_mm"     => end_2d,
                "IsCircle"        => is_circle
            }
        end
        private_class_method :na_arc_to_hash
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build 2D Counts Block (Na__StandardTemplate Shape)
        # ------------------------------------------------------------
        def self.na_build_2d_counts(edge_count, arcs, lines, polygons)
            circle_count = arcs.count { |entry| entry["IsCircle"] == true }
            {
                "Na__Geometry__EdgeCount"    => edge_count,
                "Na__Geometry__ArcCount"     => arcs.length,
                "Na__Geometry__LineCount"    => lines.length,
                "Na__Geometry__PolygonCount" => polygons.length,
                "Na__Geometry__CircleCount"  => circle_count
            }
        end
        private_class_method :na_build_2d_counts
        # ---------------------------------------------------------------

        # HELPER FUNCTION | 3D Bounding Box Across Vertex Hashes
        # ------------------------------------------------------------
        def self.na_calc_bbox_xyz(vertices)
            return {} if vertices.empty?
            xs = vertices.map { |v| v["PosX_mm"] }
            ys = vertices.map { |v| v["PosY_mm"] }
            zs = vertices.map { |v| v["PosZ_mm"] }
            {
                "Na__Geometry__MinX_mm" => xs.min.round(3),
                "Na__Geometry__MaxX_mm" => xs.max.round(3),
                "Na__Geometry__MinY_mm" => ys.min.round(3),
                "Na__Geometry__MaxY_mm" => ys.max.round(3),
                "Na__Geometry__MinZ_mm" => zs.min.round(3),
                "Na__Geometry__MaxZ_mm" => zs.max.round(3)
            }
        end
        private_class_method :na_calc_bbox_xyz
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Metadata Placeholder Builders
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the meta Block (File-Level Metadata)
        # ------------------------------------------------------------
        def self.na_build_meta_block
            {
                "fileName"    => "",
                "description" => "Unified asset file exported by Na__DevTools::Na__JsonExporter3D.",
                "version"     => "1.0.0",
                "lastUpdated" => Time.now.strftime("%Y-%m-%d"),
                "namingConvention" => "All custom keys prefixed Na__. Three-stage form Na__Section__SubSection__FieldName.",
                "fieldPrefixes"    => {
                    "Na__Asset__"          => "Top-level asset metadata and content blocks",
                    "Na__Geometry__"       => "Geometry-related sub-fields (BoundingBox, Counts, OriginNote, CoordSystem)",
                    "Na__PanelPlacement__" => "Door-panel mounting transforms (RH/LH handing, vertical datum)"
                }
            }
        end
        private_class_method :na_build_meta_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Na__Asset__Metadata Block (Placeholders + Flags)
        # ------------------------------------------------------------
        def self.na_build_metadata_placeholder(opts)
            has_plan      = opts[:has_plan]      ? true : false
            has_elevation = opts[:has_elevation] ? true : false
            has_profile   = opts[:has_profile]   ? true : false
            has_3d        = opts[:has_3d]        ? true : false
            {
                "Na__Asset__Name"                  => "",
                "Na__Asset__Code"                  => "",
                "Na__Asset__Type"                  => "",
                "Na__Asset__Description"           => "",
                "Na__Asset__Notes"                 => "",
                "Na__Asset__Has2dPlan"             => has_plan,
                "Na__Asset__Has2dElevation"        => has_elevation,
                "Na__Asset__Has2dProfile"          => has_profile,
                "Na__Asset__Has3d"                 => has_3d,
                "Na__Asset__Supplier"              => "",
                "Na__Asset__SupplierProductCode"   => "",
                "Na__Asset__SupplierPrice_GBP"     => "",
                "Na__PanelPlacement__DefaultHeight_mm" => nil,
                "Na__PanelPlacement__RightHand"        => {
                    "Na__PanelPlacement__OffsetX_mm" => nil,
                    "Na__PanelPlacement__OffsetY_mm" => nil,
                    "Na__PanelPlacement__ScaleX"     => nil
                },
                "Na__PanelPlacement__LeftHand"         => {
                    "Na__PanelPlacement__OffsetX_mm" => nil,
                    "Na__PanelPlacement__OffsetY_mm" => nil,
                    "Na__PanelPlacement__ScaleX"     => nil
                },
                "Na__Asset__AvailableFinishes"     => []
            }
        end
        private_class_method :na_build_metadata_placeholder
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Column-Aligned JSON Pretty-Printer (3-Stage Style)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Indent for a Given Depth
        # ------------------------------------------------------------
        def self.na_indent(depth)
            return ""    if depth < 1
            return "  "  if depth == 1
            " " * (4 * (depth - 1))
        end
        private_class_method :na_indent
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Format a Scalar Value
        # ------------------------------------------------------------
        def self.na_scalar(value)
            case value
            when NilClass    then "null"
            when TrueClass   then "true"
            when FalseClass  then "false"
            when Float
                value.nan? || value.infinite? ? "null" : value.to_json
            else
                value.to_json
            end
        end
        private_class_method :na_scalar
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Padded Key + " : " for Column Alignment
        # ------------------------------------------------------------
        def self.na_padded_key(key, column_width)
            kjs = key.to_json
            pad = [0, column_width - kjs.length].max
            "#{kjs}#{' ' * pad} : "
        end
        private_class_method :na_padded_key
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format One Key/Value Pair at a Given Depth
        # ------------------------------------------------------------
        def self.na_format_pair(key, value, depth, column_width)
            ind  = na_indent(depth)
            kcol = na_padded_key(key, column_width)
            case value
            when Hash
                return "#{ind}#{kcol}{}" if value.empty?
                body  = na_format_object_body(value, depth + 1)
                close = na_indent(depth)
                "#{ind}#{kcol}{\n#{body}\n#{close}}"
            when Array
                return "#{ind}#{kcol}[]" if value.empty?
                inner = na_format_array_body(value, depth)
                "#{ind}#{kcol}[\n#{inner}\n#{ind}]"
            else
                "#{ind}#{kcol}#{na_scalar(value)}"
            end
        end
        private_class_method :na_format_pair
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format Object Body
        # ------------------------------------------------------------
        def self.na_format_object_body(hash, depth)
            return "" if hash.empty?
            width = hash.keys.map { |k| k.to_json.length }.max
            hash.map { |k, v| na_format_pair(k, v, depth, width) }.join(",\n")
        end
        private_class_method :na_format_object_body
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format Array Body
        # ------------------------------------------------------------
        def self.na_format_array_body(arr, parent_depth)
            elem_depth = parent_depth + 1
            arr.map { |el| na_format_array_element(el, elem_depth) }.join(",\n")
        end
        private_class_method :na_format_array_body
        # ---------------------------------------------------------------

        # SUB FUNCTION | Format One Array Element
        # ------------------------------------------------------------
        def self.na_format_array_element(element, depth)
            case element
            when Hash
                return "#{na_indent(depth)}{}" if element.empty?
                body = na_format_object_body(element, depth + 1)
                open = na_indent(depth)
                "#{open}{\n#{body}\n#{open}}"
            else
                "#{na_indent(depth)}#{na_scalar(element)}"
            end
        end
        private_class_method :na_format_array_element
        # ---------------------------------------------------------------

        # FUNCTION | Serialise the Root Hash to a Column-Aligned JSON String
        # ------------------------------------------------------------
        def self.na_serialize_root(root_hash)
            width = root_hash.keys.map { |k| k.to_json.length }.max
            parts = root_hash.map { |k, v| na_format_pair(k, v, 1, width) }
            "{\n#{parts.join(",\n")}\n}\n"
        end
        private_class_method :na_serialize_root
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Output Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Print the JSON to the Ruby Console
        # ------------------------------------------------------------
        def self.na_print_to_console(json_string)
            puts "\n" + ("=" * 70)
            puts "NA DEV TOOLS | UNIFIED 2D + 3D ASSET JSON OUTPUT"
            puts ("=" * 70)
            puts json_string
            puts ("=" * 70)
        end
        private_class_method :na_print_to_console
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Save the JSON String to Disk via Save Panel
        # ------------------------------------------------------------
        def self.na_save_to_disk(json_string)
            output_path = UI.savepanel(
                "Save Na Unified Asset JSON",
                "",
                "Na__Asset__3D__Untitled__.json"
            )

            if output_path.nil?
                puts "\n>> Save cancelled. Copy the JSON from the console above."
                return
            end

            output_path += ".json" unless output_path.downcase.end_with?(".json")

            begin
                File.open(output_path, "w") { |f| f.write(json_string) }
                puts "\n>> Saved to : #{output_path}"
            rescue => e
                puts "\n!! File write failed : #{e.message}"
            end

            puts "\n>> Export complete."
        end
        private_class_method :na_save_to_disk
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__JsonExporter3D
end # module Na__DevTools
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
