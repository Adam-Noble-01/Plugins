# -----------------------------------------------------------------------------
# SketchUp Plugin | To-Scale Orthographic Texture Maker
# -----------------------------------------------------------------------------
# Projects 3D geometry onto a plane as a perfectly scaled orthographic texture
# Uses scene camera angle to render object, then maps result to target plane
#
# USAGE: Pre-select 1 Group/Component (source) AND 1 Face (target), then run
#
# Version 3.1.0 - 01-Feb-2026
#  - Pre-selection approach (select both entities before running)
#  - Scene picker for camera angle
#  - Based on proven OrthoProjector v3 code
# -----------------------------------------------------------------------------

require 'sketchup.rb'

module Na_ToScaleOrthoTextureMaker
    extend self

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

    TEMP_IMAGE_PREFIX = "na_ortho_texture" unless defined?(TEMP_IMAGE_PREFIX)
    BASE_RESOLUTION = 2048 unless defined?(BASE_RESOLUTION)
    IMAGE_COMPRESSION = 0.9 unless defined?(IMAGE_COMPRESSION)

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Main Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Run Ortho Texture Maker
    # ------------------------------------------------------------
    def self.Na__ToScaleOrthoTextureMaker__Run
        model = Sketchup.active_model
        return unless model

        sel = model.selection
        view = model.active_view

        # -----------------------------------------------------------------
        # VALIDATION - Check pre-selection
        # -----------------------------------------------------------------
        
        # Find face in selection (direct face or single-face group)
        face = sel.grep(Sketchup::Face).first
        
        # If no direct face, check for group containing single face
        unless face
            groups_in_sel = sel.grep(Sketchup::Group) + sel.grep(Sketchup::ComponentInstance)
            groups_in_sel.each do |g|
                faces = collect_faces_from_container(g)
                if faces.length == 1
                    face = faces.first
                    break
                end
            end
        end

        # Find source group/component (exclude face container if it's a group)
        target = nil
        (sel.grep(Sketchup::Group) + sel.grep(Sketchup::ComponentInstance)).each do |entity|
            # Skip if this is the face container
            faces_in_entity = collect_faces_from_container(entity)
            next if faces_in_entity.length == 1 && faces_in_entity.first == face
            target = entity
            break
        end

        # Validate we have both
        unless face && target
            UI.messagebox(
                "Invalid Selection!\n\n" \
                "Please pre-select:\n" \
                "  • 1 Group or Component (source to project)\n" \
                "  • 1 Face (target plane)\n\n" \
                "Then run this command again."
            )
            return
        end

        # -----------------------------------------------------------------
        # SCENE SELECTION
        # -----------------------------------------------------------------
        pages = model.pages
        selected_page = nil

        if pages && pages.count > 0
            page_names = pages.map { |p| p.name }
            page_names.unshift("Current View")

            result = UI.inputbox(
                ["Select Scene for camera angle:"],
                [page_names[0]],
                [page_names.join("|")],
                "Camera View"
            )

            return unless result                                             # <-- User cancelled

            selected_name = result[0]
            if selected_name != "Current View"
                selected_page = pages.find { |p| p.name == selected_name }
            end
        end

        # Apply scene camera if selected (direct copy, no transition)
        if selected_page
            view.camera = selected_page.camera
            view.refresh
        end

        # -----------------------------------------------------------------
        # RUN PROJECTION
        # -----------------------------------------------------------------
        run_ortho_projection(model, view, target, face)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------

    # FUNCTION | Collect Faces from Container (handles nested groups/components)
    # ------------------------------------------------------------
    def self.collect_faces_from_container(container)
        faces = []

        entities = if container.respond_to?(:definition)
            container.definition.entities
        else
            container.entities
        end

        entities.each do |entity|
            if entity.is_a?(Sketchup::Face)
                faces << entity
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                faces.concat(collect_faces_from_container(entity))
            end
        end

        faces
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Projection Execution (OrthoProjector v3)
    # -----------------------------------------------------------------------------

    # FUNCTION | Run Ortho Projection
    # ------------------------------------------------------------
    def self.run_ortho_projection(model, view, target, face)
        model.start_operation('Ortho Projection', true)

        begin
            # ------------------------------------------------------------------
            # GEOMETRY ANALYSIS
            # ------------------------------------------------------------------
            plane_trans = Geom::Transformation.new(
                face.bounds.center,
                face.normal
            ).inverse

            corners = []
            (0..7).each { |i| corners << target.bounds.corner(i) }
            local_corners = corners.map { |c| c.transform(plane_trans) }

            min_x = local_corners.map(&:x).min
            max_x = local_corners.map(&:x).max
            min_y = local_corners.map(&:y).min
            max_y = local_corners.map(&:y).max

            obj_width = max_x - min_x
            obj_height = max_y - min_y

            local_center = Geom::Point3d.new(
                (min_x + max_x) / 2.0,
                (min_y + max_y) / 2.0,
                0
            )
            world_center = local_center.transform(plane_trans.inverse)

            # ------------------------------------------------------------------
            # CAMERA SETUP
            # ------------------------------------------------------------------
            current_cam = view.camera
            new_cam = Sketchup::Camera.new

            new_cam.set(current_cam.eye, world_center, current_cam.up)
            new_cam.perspective = false

            # ------------------------------------------------------------------
            # ASPECT RATIO & ZOOM
            # ------------------------------------------------------------------
            vp_ar = view.vpwidth.to_f / view.vpheight.to_f
            obj_ar = obj_width / obj_height

            if vp_ar > obj_ar
                new_cam.height = obj_height
                capture_height = obj_height
                capture_width = obj_height * vp_ar
            else
                new_cam.height = obj_width / vp_ar
                capture_height = obj_width / vp_ar
                capture_width = obj_width
            end

            view.camera = new_cam
            view.refresh

            # ------------------------------------------------------------------
            # RASTERIZATION
            # ------------------------------------------------------------------
            entities_to_hide = model.active_entities.to_a - [target]
            vis_states = entities_to_hide.map { |e| e.hidden? rescue true }
            entities_to_hide.each { |e| e.hidden = true rescue nil }

            temp_path = File.join(
                ENV['TMP'] || ENV['TEMP'],
                "#{TEMP_IMAGE_PREFIX}_#{Time.now.to_i}.png"
            )

            view.write_image(
                filename: temp_path,
                width: BASE_RESOLUTION,
                height: (BASE_RESOLUTION / vp_ar).to_i,
                antialias: true,
                transparent: true,
                compression: IMAGE_COMPRESSION
            )

            # Restore visibility & camera
            entities_to_hide.each_with_index { |e, i| e.hidden = vis_states[i] rescue nil }
            view.camera = current_cam

            # ------------------------------------------------------------------
            # GEOMETRY GENERATION - Use TARGET FACE orientation
            # ------------------------------------------------------------------
            vec_z = face.normal                                  # <-- Use face normal!
            
            # Calculate orthogonal X/Y vectors in the face's plane
            if vec_z.parallel?(Z_AXIS)
                # Face is horizontal - align with world X/Y
                vec_x = X_AXIS.clone
                vec_y = Y_AXIS.clone
                vec_y = vec_y.reverse if vec_z.z < 0             # <-- Flip if facing down
            else
                # Face is angled - derive from world Z
                vec_x = Z_AXIS * vec_z
                vec_x.normalize!
                vec_y = vec_z * vec_x
                vec_y.normalize!
            end

            half_w = capture_width / 2.0
            half_h = capture_height / 2.0

            pt1 = world_center.offset(vec_x, -half_w).offset(vec_y, -half_h)
            pt2 = world_center.offset(vec_x, half_w).offset(vec_y, -half_h)
            pt3 = world_center.offset(vec_x, half_w).offset(vec_y, half_h)
            pt4 = world_center.offset(vec_x, -half_w).offset(vec_y, half_h)

            group = model.active_entities.add_group
            new_face = group.entities.add_face(pt1, pt2, pt3, pt4)

            mat = model.materials.add("NA_OrthoProjected_#{Time.now.to_i}")
            mat.texture = temp_path
            new_face.material = mat

            uvs = [pt1, [0, 0], pt2, [1, 0], pt3, [1, 1], pt4, [0, 1]]
            new_face.position_material(mat, uvs, true)

            new_face.edges.each { |e| e.hidden = true }

            model.commit_operation

            UI.messagebox("Ortho texture projection complete!")

        rescue => error
            model.abort_operation
            UI.messagebox("Error during projection:\n#{error.message}")
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Menu Registration
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed

        cmd = UI::Command.new('NA_ToScaleOrthoTextureMaker') do
            Na_ToScaleOrthoTextureMaker.Na__ToScaleOrthoTextureMaker__Run
        end
        cmd.tooltip = "Project geometry as scaled ortho texture (pre-select Group + Face first)"
        cmd.status_bar_text = "Pre-select 1 Group and 1 Face, then run"
        cmd.menu_text = "Na__ToScaleOrthoTextureMaker"

        extensions_menu = UI.menu('Extensions')
        extensions_menu.add_item(cmd)

        @menu_installed = true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    Na_ToScaleOrthoTextureMaker.activate_for_model(Sketchup.active_model)
    file_loaded(__FILE__)
end
