# ==================================================================================================
# SketchUp 2026 | Vale Roof Lantern | Rafter Generation From Datum Hypotenuse Lines
# --------------------------------------------------------------------------------------------------
# IMPORTANT: JSON paths use Windows Long Path API prefix to bypass 260-character limit
# REVISION: Updated JSON path to use Windows Long Path API prefix (\\?\) for path length > 260 chars
# --------------------------------------------------------------------------------------------------
# USER ACTION:
#   - Select one or more "RoofAngleTriangle__StandardRafter-XX" groups (any nesting level).
#   - Run: Noble::Create3dStandardRafterObject.run
#
# WHAT SCRIPT DOES:
#   - Recursively traverses all selected groups (and nested groups).
#   - Finds groups named like:
#        "SR01__3dDatumLine__Hypotenuse"
#        "SR02__3dDatumLine__Hypotenuse"
#        "SRnn__3dDatumLine__Hypotenuse"
#        "SRContinued__3dDatumLine__Hypotenuse"
#   - Each such group contains a single edge: this is the hypotenuse datum line.
#   - Loads the standard JSON profile (with fallback path).
#   - Places profile at START of edge, aligns +Z to edge direction, extrudes full length using
#     Face#followme, then smooth/softens at 20°.
#   - Creates output geometry in the SAME parent entities as the hypotenuse group.
#
# --------------------------------------------------------------------------------------------------
# PROFILE LIBRARY JSON PATHS:
#   PRIMARY :
#     D:\02_CoreLib__SketchUp\01_-_Core-Lib_-_SU-Components\60-Series__ProfilesLibrary__ValeProfilesLib\PFL001__RoofLanter__TypicalRafters__GlazeBarCapsAndMouldings__SketchUpToJsonData.json
#   FALLBACK:
#     Tools_RoofLanternConfigurator/00__FallbackProfilesLibrary/PFL001__RoofLanter__TypicalRafters__GlazeBarCapsAndMouldings__SketchUpToJsonData.json
#     (relative from plugin root: ValeDesignSuite::PLUGIN_ROOT)
# ==================================================================================================

require 'sketchup.rb'
require 'json'

module ValeDesignSuite
    module Create3dStandardRafterObject
        extend self

        # -----------------------------------------------------------------------------
        # REGION | Constants and Configuration
        # -----------------------------------------------------------------------------
        
        MM_PER_INCH      = 25.4                                          # <-- Unit conversion
        SMOOTH_ANGLE_DEG = 20.0                                          # <-- Smoothing threshold
        
        # Regex filter for hypotenuse datum groups
        HYPOTENUSE_RX = /\A(?:SR\d+|SRContinued)__3dDatumLine__Hypotenuse\z/
        
        # JSON profile paths
        PRIMARY_JSON  = '\\\\?\\D:\\02_CoreLib__SketchUp\\01_CoreLib__Components\\60-Series__ProfilesLibrary__ValeProfilesLib\\PFL700-PFL720__RoofLantern__RoofStructureElements\\PFL701-PFL710__RoofLanternStructure__StandardRafterParts\\PFL701__RoofLantern__TypicalRafters__GlazeBarCapsAndMouldings__SketchUpToJsonData__.json'.freeze
        
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
        
        # FUNCTION | Main entry point for rafter generation
        # ------------------------------------------------------------
        def run
            model = Sketchup.active_model
            return UI.messagebox('No active model.') unless model

            sel = model.selection
            roots = sel.grep(Sketchup::Group) + sel.grep(Sketchup::ComponentInstance)
            if roots.empty?
                UI.messagebox('Select one or more RoofAngleTriangle groups.')
                return
            end

            # Load profile once
            loop_xy_mm = load_profile_loop
            unless loop_xy_mm
                UI.messagebox('Could not load profile JSON (primary or fallback missing).')
                return
            end

            model.start_operation('Vale Lantern Rafters', true)

            prof_def = build_profile_definition_preserving_datum(model, loop_xy_mm)
            unless prof_def
                model.abort_operation
                UI.messagebox('Failed to build profile definition.')
                return
            end

            total_edges = 0
            rafter_groups = []  # Collect groups for post-processing

            # Traverse all roots recursively
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

                    # New group for output
                    out_grp = parent_ents.add_group
                    out_grp.name = "NOBLE_RafterFrom_#{hyp.name}"
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

                    # Store group for post-processing (softening done later)
                    rafter_groups << out_grp
                    total_edges += 1
                end
            end

            # Post-process: Move groups to model root, rename sequentially, and apply tag
            process_rafter_groups(model, rafter_groups, roots)

            model.commit_operation
            
            # Now move the rafter groups to model root in a separate operation
            move_rafters_to_model_root(model)
            
            # Apply softening and smoothing to all rafter groups as final step
            soften_all_rafter_groups(model)
            
            UI.messagebox("Generated rafters on #{total_edges} hypotenuse edge#{total_edges == 1 ? '' : 's'}.")
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
        
        # FUNCTION | Load profile loop from JSON (primary or fallback path)
        # ------------------------------------------------------------
        def load_profile_loop
            path = PRIMARY_JSON if File.exist?(PRIMARY_JSON)
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
        # REGION | Processing Methods - Rafter Group Operations
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Process rafter groups - rename sequentially and apply tag
        # ------------------------------------------------------------
        def process_rafter_groups(model, rafter_groups, root_containers)
            return if rafter_groups.empty?

            # Use layers API (works for all SketchUp versions - "tags" in UI are "layers" in API)
            tag_name = "97__ValeRoofLantern__3dStandardRafters"
            layers = model.layers
            layer = layers[tag_name]
            unless layer
                layer = layers.add(tag_name)
            end

            # Simple approach: Just rename and tag the groups where they are
            # This avoids crashes from complex geometry copying
            rafter_groups.each_with_index do |group, index|
                next unless group && group.valid?

                # Rename sequentially
                group.name = format("RoofLanternElement__3dObject__StandardRafter-%02d", index + 1)
                
                # Apply layer (tag)
                group.layer = layer
            end

            rafter_groups
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Move rafter groups to model root using safer approach
        # ------------------------------------------------------------
        def move_rafters_to_model_root(model)
            model.start_operation('Move Rafters to Model Root', true)
            
            root_entities = model.entities
            moved_count = 0
            
            # Collect all rafter groups with their paths
            rafter_data = []
            collect_rafter_groups(model.entities, [], rafter_data)
            
            # Process each rafter group
            rafter_data.each do |data|
                rafter_group = data[:group]
                parent_chain = data[:parents]
                
                next unless rafter_group.valid?
                next if rafter_group.parent == model  # Already at root
                
                begin
                    # Calculate cumulative transformation
                    transform = Geom::Transformation.new
                    
                    # Build transformation from parent chain
                    parent_chain.each do |parent|
                        transform = transform * parent.transformation
                    end
                    transform = transform * rafter_group.transformation
                    
                    # Create new group at model root with same contents
                    new_group = root_entities.add_group
                    new_group.name = rafter_group.name
                    new_group.layer = rafter_group.layer
                    
                    # Copy geometry using make_unique
                    copy_group_geometry(rafter_group, new_group)
                    
                    # Apply the cumulative transformation
                    new_group.transformation = transform
                    
                    # Remove original group
                    rafter_group.erase! if rafter_group.valid?
                    
                    moved_count += 1
                rescue => e
                    puts "Error moving rafter: #{e.message}"
                end
            end
            
            model.commit_operation
            puts "Moved #{moved_count} rafter groups to model root"
        rescue => e
            model.abort_operation
            UI.messagebox("Error moving rafters: #{e.message}")
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Collect rafter groups with their parent chains
        # ------------------------------------------------------------
        def collect_rafter_groups(entities, parent_chain, results)
            entities.each do |entity|
                if entity.is_a?(Sketchup::Group)
                    # Check if this is a rafter group
                    if entity.name =~ /\ARoofLanternElement__3dObject__StandardRafter-\d+\z/
                        results << { group: entity, parents: parent_chain.dup }
                    end
                    # Recurse into group
                    collect_rafter_groups(entity.entities, parent_chain + [entity], results)
                elsif entity.is_a?(Sketchup::ComponentInstance)
                    # Check if this is a rafter component
                    if entity.name =~ /\ARoofLanternElement__3dObject__StandardRafter-\d+\z/
                        results << { group: entity, parents: parent_chain.dup }
                    end
                    # Recurse into component definition
                    collect_rafter_groups(entity.definition.entities, parent_chain + [entity], results)
                end
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Soften all rafter groups as final step
        # ------------------------------------------------------------
        def soften_all_rafter_groups(model)
            model.start_operation('Soften Rafter Edges', true)
            
            softened_count = 0
            
            # Find all rafter groups at model root
            model.entities.grep(Sketchup::Group).each do |group|
                next unless group.name =~ /\ARoofLanternElement__3dObject__StandardRafter-\d+\z/
                
                # Apply softening to this group
                apply_smooth_and_soften(group, SMOOTH_ANGLE_DEG)
                softened_count += 1
            end
            
            model.commit_operation
            puts "Softened edges on #{softened_count} rafter groups"
        rescue => e
            model.abort_operation
            puts "Error softening rafters: #{e.message}"
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
        
        # endregion -------------------------------------------------------------------

    end
end

# -----------------------------------------------------------------------------
# REGION | Menu Integration and Auto-execution
# -----------------------------------------------------------------------------

# Menu hook
unless defined?($vale_rafter_menu_added) && $vale_rafter_menu_added
    UI.menu('Extensions').add_item('Vale: Generate Rafters From Hypotenuse Datum Lines') { ValeDesignSuite::Create3dStandardRafterObject.run }
    $vale_rafter_menu_added = true
end

# Auto-run for console paste
ValeDesignSuite::Create3dStandardRafterObject.run

# endregion -------------------------------------------------------------------
