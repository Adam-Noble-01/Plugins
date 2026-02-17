# ==================================================================================================
# SketchUp 2026 | Vale Roof Lantern | Hip Rafter Generation From Datum Hypotenuse Lines
# --------------------------------------------------------------------------------------------------
# IMPORTANT: JSON paths use Windows Long Path API prefix to bypass 260-character limit
# REVISION: Fixed Windows 260-character path limit using \\?\ prefix for long JSON paths
# --------------------------------------------------------------------------------------------------
# USER ACTION:
#   - Select one or more "RoofAngleTriangle__HipRafter-XX" groups (any nesting level).
#   - Run: ValeDesignSuite::Create3dStandardHipRafterObject.run
#
# WHAT SCRIPT DOES:
#   - Recursively traverses all selected groups (and nested groups).
#   - Finds groups named like:
#        "HR01__3dDatumLine__Hypotenuse"
#        "HR02__3dDatumLine__Hypotenuse"
#        "HRnn__3dDatumLine__Hypotenuse"
#        "HRContinued__3dDatumLine__Hypotenuse"
#   - Each such group contains a single edge: this is the hypotenuse datum line.
#   - Loads the hip rafter JSON profile (with fallback path).
#   - Places profile at START of edge, aligns +Z to edge direction, extrudes full length using
#     Face#followme, then smooth/softens at 20°.
#   - Creates output geometry in the SAME parent entities as the hypotenuse group.
#
# --------------------------------------------------------------------------------------------------
# PROFILE LIBRARY JSON PATHS:
#   PRIMARY :
#     D:\02_CoreLib__SketchUp\01_CoreLib__Components\60-Series__ProfilesLibrary__/
#   
# ==================================================================================================

require 'sketchup.rb'
require 'json'

module ValeDesignSuite
    module Create3dStandardHipRafterObject
        extend self

        # -----------------------------------------------------------------------------
        # REGION | Constants and Configuration
        # -----------------------------------------------------------------------------
        
        MM_PER_INCH      = 25.4                                          # <-- Unit conversion
        SMOOTH_ANGLE_DEG = 23.0                                          # <-- Smoothing threshold
        
        # Regex filter for hip rafter hypotenuse datum groups
        HYPOTENUSE_RX = /\A(?:HR\d+|HRContinued)__3dDatumLine__Hypotenuse\z/
        
        # JSON profile paths
        PRIMARY_JSON  = '\\\\?\\D:\\02_CoreLib__SketchUp\\01_CoreLib__Components\\60-Series__ProfilesLibrary__ValeProfilesLib\\PFL700-PFL720__RoofLantern__RoofStructureElements\\PFL710-PFL720__RoofLanternStructure__HipRafterParts\\PFL711__RoofLantern__TypicalHipRafters__HipBeamsAndMouldings__SketchUpToJsonData__.json'.freeze
        CAPPING_JSON  = '\\\\?\\D:\\02_CoreLib__SketchUp\\01_CoreLib__Components\\60-Series__ProfilesLibrary__ValeProfilesLib\\PFL700-PFL720__RoofLantern__RoofStructureElements\\PFL710-PFL720__RoofLanternStructure__HipRafterParts\\PFL721__RoofLantern__TypicalHipRafters__LeadedCappingPeice__SketchUpToJsonData__.json'.freeze
        
        # endregion -------------------------------------------------------------------

        # -----------------------------------------------------------------------------
        # REGION | Helper Methods - Core Utilities
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Get container entities safely from group/component/model
        # ------------------------------------------------------------
        def container_entities(container)
            return container.entities if container.is_a?(Sketchup::Group)
            return container.definition.entities if container.is_a?(Sketchup::ComponentInstance)
            return container.entities if container.respond_to?(:entities)
            nil
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Main Entry Point
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Main entry point for hip rafter generation
        # ------------------------------------------------------------
        def run
            model = Sketchup.active_model
            return UI.messagebox('No active model.') unless model

            sel = model.selection
            roots = sel.grep(Sketchup::Group) + sel.grep(Sketchup::ComponentInstance)
            if roots.empty?
                UI.messagebox('Select one or more RoofAngleTriangle__HipRafter groups.')
                return
            end

            # Load hip rafter profile
            loop_xy_mm = load_profile_loop
            unless loop_xy_mm
                UI.messagebox('Could not load hip rafter profile JSON.')
                return
            end

            # Load capping piece profile  
            capping_loop_xy_mm = load_capping_profile_loop
            unless capping_loop_xy_mm
                UI.messagebox('Could not load capping piece profile JSON.')
                return
            end

            model.start_operation('Vale Lantern Hip Rafters', true)

            prof_def = build_profile_definition_preserving_datum(model, loop_xy_mm)
            unless prof_def
                model.abort_operation
                UI.messagebox('Failed to build hip rafter profile definition.')
                return
            end

            capping_prof_def = build_profile_definition_preserving_datum(model, capping_loop_xy_mm)
            unless capping_prof_def
                model.abort_operation
                UI.messagebox('Failed to build capping piece profile definition.')
                return
            end

            total_edges = 0
            hip_rafter_groups = []  # Collect hip rafter groups
            capping_groups = []     # Collect capping piece groups

            # First pass: Create hip rafter groups
            roots.each do |root|
                each_hypotenuse_group_recursive(root) do |hyp|
                    edge = pick_hypotenuse_edge(hyp)
                    next unless edge

                    # Get parent entities safely
                    parent_ents = container_entities(hyp.parent)
                    next unless parent_ents

                    # Transform edge points from local space to parent space
                    t_inst = hyp.transformation
                    p1 = edge.start.position.transform(t_inst)
                    p2 = edge.end.position.transform(t_inst)

                    # New group for hip rafter
                    out_grp = parent_ents.add_group
                    out_grp.name = "NOBLE_HipRafterFrom_#{hyp.name}"
                    gents = out_grp.entities

                    # Copy edge in parent space
                    ge = gents.add_line(p1, p2)
                    next unless ge && ge.valid?

                    # Build local frame at edge start
                    origin = p1
                    zaxis  = p2 - p1
                    next if zaxis.length <= 0.0
                    zaxis.normalize!
                    xaxis, yaxis = robust_xy_from_z(zaxis)
                    t_axes = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)

                    # Place profile, explode, find face
                    inst = gents.add_instance(prof_def, t_axes)
                    faces_before = gents.grep(Sketchup::Face)
                    inst.explode
                    profile_face = (gents.grep(Sketchup::Face) - faces_before).first
                    profile_face ||= gents.grep(Sketchup::Face).first
                    next unless profile_face && profile_face.valid? && profile_face.area > 0.0

                    # Orient face normal to +Z
                    profile_face.reverse! if profile_face.normal.dot(zaxis) < 0.0

                    # Extrude along edge
                    profile_face.followme([ge])
                    profile_face.erase! if profile_face.valid?

                    # Store group for post-processing
                    hip_rafter_groups << out_grp
                    total_edges += 1
                end
            end

            # Second pass: Create capping piece groups
            roots.each do |root|
                each_hypotenuse_group_recursive(root) do |hyp|
                    edge = pick_hypotenuse_edge(hyp)
                    next unless edge

                    # Get parent entities safely
                    parent_ents = container_entities(hyp.parent)
                    next unless parent_ents

                    # Transform edge points from local space to parent space
                    t_inst = hyp.transformation
                    p1 = edge.start.position.transform(t_inst)
                    p2 = edge.end.position.transform(t_inst)

                    # New group for capping piece
                    out_grp = parent_ents.add_group
                    out_grp.name = "NOBLE_CappingFrom_#{hyp.name}"
                    gents = out_grp.entities

                    # Copy edge in parent space
                    ge = gents.add_line(p1, p2)
                    next unless ge && ge.valid?

                    # Build local frame at edge start
                    origin = p1
                    zaxis  = p2 - p1
                    next if zaxis.length <= 0.0
                    zaxis.normalize!
                    xaxis, yaxis = robust_xy_from_z(zaxis)
                    t_axes = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)

                    # Place profile, explode, find face
                    inst = gents.add_instance(capping_prof_def, t_axes)
                    faces_before = gents.grep(Sketchup::Face)
                    inst.explode
                    profile_face = (gents.grep(Sketchup::Face) - faces_before).first
                    profile_face ||= gents.grep(Sketchup::Face).first
                    next unless profile_face && profile_face.valid? && profile_face.area > 0.0

                    # Orient face normal to +Z
                    profile_face.reverse! if profile_face.normal.dot(zaxis) < 0.0

                    # Extrude along edge
                    profile_face.followme([ge])
                    profile_face.erase! if profile_face.valid?

                    # Store group for post-processing
                    capping_groups << out_grp
                end
            end

            # Post-process: Group hip rafters and capping pieces together
            grouped_assemblies = group_hip_parts_together(model, hip_rafter_groups, capping_groups)
            
            # Apply tag and rename
            process_hip_rafter_groups(model, grouped_assemblies, roots)

            model.commit_operation
            
            # Now move the hip rafter groups to model root in a separate operation
            move_hip_rafters_to_model_root(model)
            
            # Apply softening and smoothing to all hip rafter groups as final step
            soften_all_hip_rafter_groups(model)
            
            UI.messagebox("Generated hip rafters on #{total_edges} hypotenuse edge#{total_edges == 1 ? '' : 's'}.")
        rescue JSON::ParserError => ex
            Sketchup.active_model.abort_operation rescue nil
            UI.messagebox("JSON Parse Error:\n#{ex.message}")
        rescue => ex
            Sketchup.active_model.abort_operation rescue nil
            UI.messagebox("Error: #{ex.class}: #{ex.message}")
            raise ex
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Helper Methods - Group Traversal and Processing  
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Recursively yield each group matching HYPOTENUSE_RX
        # ------------------------------------------------------------
        def each_hypotenuse_group_recursive(container, &block)
            ents = container_entities(container)
            return unless ents

            ents.each do |ent|
                case ent
                when Sketchup::Group
                    if ent.name =~ HYPOTENUSE_RX
                        yield ent
                    end
                    each_hypotenuse_group_recursive(ent, &block)
                when Sketchup::ComponentInstance
                    each_hypotenuse_group_recursive(ent, &block)
                end
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Pick the single edge (or longest if multiple) inside hypotenuse group
        # ------------------------------------------------------------
        def pick_hypotenuse_edge(hyp_group)
            edges = hyp_group.entities.grep(Sketchup::Edge)
            return nil if edges.empty?
            return edges.first if edges.length == 1
            edges.max_by(&:length)
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Helper Methods - Geometry and Mathematical Operations
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Generate robust X/Y axes from given Z axis
        # ------------------------------------------------------------
        def robust_xy_from_z(zaxis)
            helper = zaxis.parallel?(Geom::Vector3d.new(0, 0, 1)) ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1)
            xaxis  = helper.cross(zaxis)
            if xaxis.length == 0.0
                helper = Geom::Vector3d.new(0, 1, 0)
                xaxis  = helper.cross(zaxis)
            end
            xaxis.normalize!
            yaxis = zaxis.cross(xaxis)
            yaxis.normalize!
            [xaxis, yaxis]
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Apply smooth and soften to group edges based on angle threshold
        # ------------------------------------------------------------
        def apply_smooth_and_soften(group, deg_threshold = 20.0)
            thr  = deg_threshold.degrees
            eps  = 1.0e-6
            group.entities.grep(Sketchup::Edge).each do |e|
                faces = e.faces
                if faces.length == 2
                    ang = faces[0].normal.angle_between(faces[1].normal)
                    if ang > eps && ang < thr
                        e.smooth = true
                        e.soft   = true
                        e.hidden = true
                    else
                        e.smooth = false
                        e.soft   = false
                        e.hidden = false
                    end
                else
                    e.smooth = false
                    e.soft   = false
                    e.hidden = false
                end
            end
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Helper Methods - Profile and JSON Processing
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Load hip rafter profile loop from JSON (primary path)
        # ------------------------------------------------------------
        def load_profile_loop
            path = PRIMARY_JSON if File.exist?(PRIMARY_JSON)
            return nil unless path
            data = JSON.parse(File.read(path))
            extract_first_profile_loop_from_schema(data)
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Load capping piece profile loop from JSON
        # ------------------------------------------------------------
        def load_capping_profile_loop
            path = CAPPING_JSON if File.exist?(CAPPING_JSON)
            return nil unless path
            data = JSON.parse(File.read(path))
            extract_first_profile_loop_from_schema(data)
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Extract first profile loop from JSON schema
        # ------------------------------------------------------------
        def extract_first_profile_loop_from_schema(data)
            verts = data.dig('vertices', 'items')
            faces = data.dig('faces', 'items')
            return nil unless verts.is_a?(Array) && faces.is_a?(Array) && faces.any?
            outer_idx = faces[0]['outer']
            return nil unless outer_idx.is_a?(Array) && outer_idx.length >= 3
            pts = outer_idx.map do |i|
                v = verts[i.to_i]
                return nil unless v
                [v['PosX'].to_f, v['PosY'].to_f, v['PosZ'].to_f]
            end
            z0 = pts[0][2]
            return nil unless pts.all? { |_, _, z| (z - z0).abs <= 1.0e-6 }
            pts.map { |x, y, _| [x, y] }
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Build profile definition from loop points in millimeters
        # ------------------------------------------------------------
        def build_profile_definition_preserving_datum(model, loop_mm)
            defn   = model.definitions.add("NOBLE_Profile_#{Time.now.to_i}")
            ents   = defn.entities
            pts_in = loop_mm.map { |x, y| Geom::Point3d.new(x / MM_PER_INCH, y / MM_PER_INCH, 0.0) }
            pts_in.pop if pts_in.length >= 2 && pts_in.first == pts_in.last
            face = ents.add_face(pts_in)
            return nil unless face && face.valid? && face.area > 0.0
            face.reverse! if face.normal.z < 0.0
            defn
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Processing Methods - Group Combination
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Group hip rafters and capping pieces together
        # ------------------------------------------------------------
        def group_hip_parts_together(model, hip_rafter_groups, capping_groups)
            assembled_groups = []
            
            # Simple approach: Just rename the groups to indicate pairing
            hip_rafter_groups.each_with_index do |hip_group, index|
                next unless hip_group && hip_group.valid?
                capping_group = capping_groups[index]
                next unless capping_group && capping_group.valid?
                
                # Rename to show they are paired
                hip_group.name = "HipRafter-#{index + 1}"
                capping_group.name = "CappingPiece-#{index + 1}"
                
                # For now, just track them as separate groups
                # They will be grouped in a final step after moving to model root
                assembled_groups << hip_group
                assembled_groups << capping_group
            end
            
            assembled_groups
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Processing Methods - Hip Rafter Group Operations
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Process hip rafter groups - rename sequentially and apply tag
        # ------------------------------------------------------------
        def process_hip_rafter_groups(model, hip_rafter_groups, root_containers)
            return if hip_rafter_groups.empty?

            # Use layers API (works for all SketchUp versions - "tags" in UI are "layers" in API)
            tag_name = "97__ValeRoofLantern__3dHipRafters"
            layers = model.layers
            layer = layers[tag_name]
            unless layer
                layer = layers.add(tag_name)
            end

            # Simple approach: Just rename and tag the groups where they are
            # This avoids crashes from complex geometry copying
            hip_rafter_groups.each_with_index do |group, index|
                next unless group && group.valid?

                # Rename sequentially
                group.name = format("RoofLanternElement__3dObject__HipRafter-%02d", index + 1)
                
                # Apply layer (tag)
                group.layer = layer
            end

            hip_rafter_groups
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Move hip rafter groups to model root using safer approach
        # ------------------------------------------------------------
        def move_hip_rafters_to_model_root(model)
            model.start_operation('Move Hip Rafters to Model Root', true)
            
            root_entities = model.entities
            moved_count = 0
            
            # Collect all hip rafter groups with their paths
            hip_rafter_data = []
            collect_hip_rafter_groups(model.entities, [], hip_rafter_data)
            
            # Process each hip rafter group
            hip_rafter_data.each do |data|
                hip_rafter_group = data[:group]
                parent_chain = data[:parents]
                
                next unless hip_rafter_group.valid?
                next if hip_rafter_group.parent == model  # Already at root
                
                begin
                    # Calculate cumulative transformation
                    transform = Geom::Transformation.new
                    
                    # Build transformation from parent chain
                    parent_chain.each do |parent|
                        transform = transform * parent.transformation
                    end
                    transform = transform * hip_rafter_group.transformation
                    
                    # Create new group at model root with same contents
                    new_group = root_entities.add_group
                    new_group.name = hip_rafter_group.name
                    new_group.layer = hip_rafter_group.layer
                    
                    # Copy geometry using make_unique
                    copy_group_geometry(hip_rafter_group, new_group)
                    
                    # Apply the cumulative transformation
                    new_group.transformation = transform
                    
                    # Remove original group
                    hip_rafter_group.erase! if hip_rafter_group.valid?
                    
                    moved_count += 1
                rescue => e
                    puts "Error moving hip rafter: #{e.message}"
                end
            end
            
            model.commit_operation
            puts "Moved #{moved_count} hip rafter groups to model root"
        rescue => e
            model.abort_operation
            UI.messagebox("Error moving hip rafters: #{e.message}")
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Collect hip rafter groups with their parent chains
        # ------------------------------------------------------------
        def collect_hip_rafter_groups(entities, parent_chain, results)
            entities.each do |entity|
                if entity.is_a?(Sketchup::Group)
                    # Check if this is a hip rafter group
                    if entity.name =~ /\ARoofLanternElement__3dObject__HipRafter-\d+\z/
                        results << { group: entity, parents: parent_chain.dup }
                    end
                    # Recurse into group
                    collect_hip_rafter_groups(entity.entities, parent_chain + [entity], results)
                elsif entity.is_a?(Sketchup::ComponentInstance)
                    # Check if this is a hip rafter component
                    if entity.name =~ /\ARoofLanternElement__3dObject__HipRafter-\d+\z/
                        results << { group: entity, parents: parent_chain.dup }
                    end
                    # Recurse into component definition
                    collect_hip_rafter_groups(entity.definition.entities, parent_chain + [entity], results)
                end
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Soften all hip rafter groups as final step
        # ------------------------------------------------------------
        def soften_all_hip_rafter_groups(model)
            model.start_operation('Soften Hip Rafter Edges', true)
            
            softened_count = 0
            
            # Find all hip rafter and capping groups at model root
            model.entities.grep(Sketchup::Group).each do |group|
                next unless group.name =~ /\A(RoofLanternElement__3dObject__HipRafter-\d+|HipRafter-\d+|CappingPiece-\d+)\z/
                
                # Apply softening to this group
                apply_smooth_and_soften(group, SMOOTH_ANGLE_DEG)
                softened_count += 1
            end
            
            # Now group hip rafters with their capping pieces into assemblies
            group_final_assemblies(model)
            
            model.commit_operation
            puts "Softened edges on #{softened_count} hip rafter groups"
        rescue => e
            model.abort_operation
            puts "Error softening hip rafters: #{e.message}"
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Copy geometry from source group to destination group
        # ------------------------------------------------------------
        def copy_group_geometry(source_group, dest_group)
            source_ents = source_group.entities
            dest_ents = dest_group.entities
            
            # Map to track copied vertices
            vertex_map = {}
            
            # First pass: copy all edges (but not smooth/soft attributes yet)
            source_ents.grep(Sketchup::Edge).each do |edge|
                start_pos = edge.start.position
                end_pos = edge.end.position
                new_edge = dest_ents.add_line(start_pos, end_pos)
                
                # Map vertices for face creation
                vertex_map[edge.start] = new_edge.start
                vertex_map[edge.end] = new_edge.end
            end
            
            # Second pass: recreate faces with correct orientation
            source_ents.grep(Sketchup::Face).each do |face|
                # Get face vertices in order
                vertices = face.outer_loop.vertices
                points = vertices.map(&:position)
                
                # Try to create face
                begin
                    new_face = dest_ents.add_face(points)
                    if new_face
                        # Check if we need to reverse the face
                        # Compare the normal directions
                        source_normal = face.normal
                        new_normal = new_face.normal
                        
                        # If normals point in opposite directions, reverse the new face
                        if source_normal.dot(new_normal) < 0
                            new_face.reverse!
                        end
                        
                        # Copy materials
                        new_face.material = face.material if face.material
                        new_face.back_material = face.back_material if face.back_material
                    end
                rescue
                    # Face might already exist from edges
                end
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Group final assemblies after moving to model root
        # ------------------------------------------------------------
        def group_final_assemblies(model)
            model.start_operation('Group Hip Assemblies', true)
            
            final_assemblies = []
            
            # Find all hip rafters and their matching capping pieces
            hip_rafters = {}
            capping_pieces = {}
            
            model.entities.grep(Sketchup::Group).each do |group|
                if match = group.name.match(/\AHipRafter-(\d+)\z/)
                    hip_rafters[match[1].to_i] = group
                elsif match = group.name.match(/\ACappingPiece-(\d+)\z/)
                    capping_pieces[match[1].to_i] = group
                end
            end
            
            # Group them together
            hip_rafters.each do |num, hip_group|
                capping_group = capping_pieces[num]
                next unless hip_group && hip_group.valid? && capping_group && capping_group.valid?
                
                # Create container group at model root
                container = model.entities.add_group
                container.name = format("RoofLanternElement__3dObject__HipRafter-%02d", num)
                
                # Move both groups into container
                container.entities.add_group(hip_group)
                container.entities.add_group(capping_group)
                
                # Apply tag
                tag_name = "97__ValeRoofLantern__3dHipRafters"
                layer = model.layers[tag_name]
                container.layer = layer if layer
                
                final_assemblies << container
            end
            
            model.commit_operation
            puts "Created #{final_assemblies.length} hip rafter assemblies"
        rescue => e
            model.abort_operation
            puts "Error creating assemblies: #{e.message}"
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------

    end
end

# -----------------------------------------------------------------------------
# REGION | Menu Integration and Auto-execution
# -----------------------------------------------------------------------------

# Menu hook
unless defined?($vale_hip_rafter_menu_added) && $vale_hip_rafter_menu_added
    UI.menu('Extensions').add_item('Vale: Generate Hip Rafters From Hypotenuse Datum Lines') { ValeDesignSuite::Create3dStandardHipRafterObject.run }
    $vale_hip_rafter_menu_added = true
end

# Auto-run for console paste
ValeDesignSuite::Create3dStandardHipRafterObject.run

# endregion -------------------------------------------------------------------