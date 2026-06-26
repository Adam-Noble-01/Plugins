# -----------------------------------------------------------------------------
# Tools_DrawBitmapAlongFaceEdges.rb
# Creates unique textures with black perimeter lines on selected faces
# Author: Vale Design Suite
# Ruby API: 2025
# -----------------------------------------------------------------------------

require 'sketchup.rb'

module ValeDesignSuite
module DrawBitmapAlongFaceEdges

    # -----------------------------------------------------------------------------
    # REGION | Configuration
    # -----------------------------------------------------------------------------
    
    MAX_FACES_ALLOWED = 100                                              # <-- Prevent hangs/crashes
    DEBUG_MODE        = true                                             # <-- Speeds up processing by skipping debug prints
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Main Entry Point
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Main entry point - Apply border textures to selected faces
    # ------------------------------------------------------------------------
    def self.apply_border_textures
        model = Sketchup.active_model
        selection = model.selection
        
        # Get selected faces
        faces = selection.grep(Sketchup::Face)
        
        if faces.empty?
            UI.messagebox("Please select one or more faces.")
            return
        end
        
        # Check face count limit
        if faces.length > MAX_FACES_ALLOWED
            result = UI.messagebox(
                "You have selected #{faces.length} faces. For performance reasons, this tool is limited to #{MAX_FACES_ALLOWED} faces at a time.\n\n" +
                "Only the first #{MAX_FACES_ALLOWED} faces will be processed.\n\n" +
                "Continue?",
                MB_OKCANCEL
            )
            return if result == IDCANCEL
            faces = faces.take(MAX_FACES_ALLOWED)
        end
        
        # Prompt for border thickness in millimeters
        prompts = ["Border Thickness (mm):"]
        defaults = ["10"]
        input = UI.inputbox(prompts, defaults, "Border Texture Settings")
        
        return unless input
        
        border_thickness_mm = input[0].to_f
        
        if border_thickness_mm <= 0
            UI.messagebox("Border thickness must be greater than 0.")
            return
        end
        
        # Process each face one at a time
        model.start_operation('Apply Border Textures', true)
        
        success_count = 0
        
        faces.each_with_index do |face, index|
            puts "Processing face #{index + 1} of #{faces.length}..." if DEBUG_MODE
            
            begin
                create_and_apply_border_texture(face, border_thickness_mm, index)
                success_count += 1
            rescue => e
                if DEBUG_MODE
                    puts "Error processing face #{index + 1}: #{e.message}"
                    puts e.backtrace.join("\n")
                end
            end
        end
        
        model.commit_operation
        
        UI.messagebox("Successfully applied border textures to #{success_count} of #{faces.length} face(s).")
    end
    # ------------------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Face Processing
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Create and apply border texture to a single face
    # ------------------------------------------------------------------------
    def self.create_and_apply_border_texture(face, border_thickness_mm, face_index)
        # Extract face coordinates and calculate proper dimensions
        face_data = extract_face_coordinates(face)
        
        return unless face_data
        
        # Convert dimensions to pixels (using 72 DPI)
        pixels_per_inch = 72
        tex_width = [(face_data[:width] * pixels_per_inch).to_i, 64].max
        tex_height = [(face_data[:height] * pixels_per_inch).to_i, 64].max
        
        # Convert border from mm to base pixels
        mm_per_inch = 25.4
        border_px_base = (border_thickness_mm / mm_per_inch * pixels_per_inch)
        
        # Ensure reasonable texture size and track scale factor
        max_size = 2048
        scale = 1.0
        if tex_width > max_size || tex_height > max_size
            scale = [tex_width.to_f / max_size, tex_height.to_f / max_size].max
            tex_width = (tex_width / scale).to_i
            tex_height = (tex_height / scale).to_i
        end
        
        # Scale border thickness proportionally with texture
        border_px_scaled = [border_px_base / scale, 1.0].max         # <-- Min 1 pixel
        
        if DEBUG_MODE
            puts "  Face dimensions: #{(face_data[:width] * 25.4).round(1)}mm x #{(face_data[:height] * 25.4).round(1)}mm"
            puts "  Texture size: #{tex_width} x #{tex_height} px (scale: #{scale.round(2)}x)"
            puts "  Border: #{border_thickness_mm}mm → #{border_px_scaled.round(1)} px"
        end
        
        # Create the bitmap with actual edge geometry
        image_path = create_border_bitmap(tex_width, tex_height, border_px_scaled, face_index, face_data)
        
        # Create material and apply to face with proper UV mapping
        apply_texture_to_face(face, image_path, face_data)
        
        # Clean up temporary file
        File.delete(image_path) if File.exist?(image_path)
    end
    # ------------------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Geometry Extraction
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Extract face coordinates and calculate dimensions
    # ------------------------------------------------------------------------
    def self.extract_face_coordinates(face)
        # Get the outer loop vertices
        vertices = face.outer_loop.vertices
        points = vertices.map(&:position)
        
        return nil if points.length < 3
        
        # Create a transformation to flatten the face to 2D
        # Get face normal and arbitrary axes
        normal = face.normal
        
        # Create local coordinate system
        # Pick a vertex as origin
        origin = points[0]
        
        # Find longest edge to establish primary axis direction
        # This works for both regular and irregular faces
        longest_edge = nil
        longest_length = 0
        
        vertices.each_with_index do |v, i|
            next_v = vertices[(i + 1) % vertices.length]
            edge_vector = next_v.position - v.position
            edge_length = edge_vector.length
            
            if edge_length > longest_length
                longest_length = edge_length
                longest_edge = edge_vector
            end
        end
        
        # Use longest edge direction as X axis
        x_axis = longest_edge
        x_axis.normalize!
        
        # Y axis is perpendicular to both X and normal
        y_axis = normal.cross(x_axis)
        y_axis.normalize!
        
        # Transform all points to 2D local coordinates
        points_2d = points.map do |pt|
            vec = pt - origin
            x = vec.dot(x_axis)
            y = vec.dot(y_axis)
            [x, y]
        end
        
        # Find bounds in 2D
        min_x = points_2d.map { |p| p[0] }.min
        max_x = points_2d.map { |p| p[0] }.max
        min_y = points_2d.map { |p| p[1] }.min
        max_y = points_2d.map { |p| p[1] }.max
        
        width = max_x - min_x
        height = max_y - min_y
        
        {
            origin: origin,
            x_axis: x_axis,
            y_axis: y_axis,
            width: width,
            height: height,
            min_x: min_x,
            min_y: min_y,
            max_x: max_x,
            max_y: max_y,
            points_2d: points_2d                                         # <-- Face vertices in 2D
        }
    end
    # ------------------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Bitmap Generation
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Create a white bitmap with black border along actual face edges
    # ------------------------------------------------------------------------
    def self.create_border_bitmap(width, height, border_thickness, face_index, face_data)
        # Create temporary file path
        temp_dir = Sketchup.temp_dir
        timestamp = Time.now.to_i
        image_path = File.join(temp_dir, "border_texture_#{timestamp}_#{face_index}.png")
        
        # Transform 2D points to pixel coordinates
        points_2d = face_data[:points_2d]
        min_x = face_data[:min_x]
        min_y = face_data[:min_y]
        face_width = face_data[:width]
        face_height = face_data[:height]
        
        # Convert face coordinates to pixel coordinates
        # Note: Flip X-axis to correct UV mapping orientation
        pixel_points = points_2d.map do |pt|
            px = (width - ((pt[0] - min_x) / face_width * width)).round   # <-- Flip X (left-right)
            py = ((pt[1] - min_y) / face_height * height).round
            [px, py]
        end
        
        # Create white background with black border along edges
        pixels = []
        
        height.times do |y|
            row = []
            width.times do |x|
                # Check if pixel is near any edge
                in_border = is_pixel_near_edge?(x, y, pixel_points, border_thickness)
                
                if in_border
                    row << 0   # Red                                   # <-- Black border
                    row << 0   # Green
                    row << 0   # Blue
                    row << 255 # Alpha
                else
                    row << 255 # Red                                   # <-- White background
                    row << 255 # Green
                    row << 255 # Blue
                    row << 255 # Alpha
                end
            end
            pixels.concat(row)
        end
        
        # Create ImageRep and write to file
        begin
            image_rep = Sketchup::ImageRep.new
            image_rep.set_data(width, height, 32, 0, pixels.pack('C*'))
            image_rep.save_file(image_path)
        rescue => e
            puts "Error creating bitmap: #{e.message}" if DEBUG_MODE
            return nil
        end
        
        image_path
    end
    # ------------------------------------------------------------------------
    
    # FUNCTION | Check if pixel is near any face edge
    # ------------------------------------------------------------------------
    def self.is_pixel_near_edge?(px, py, pixel_points, thickness)
        # Check distance to each edge
        pixel_points.each_with_index do |pt, i|
            next_pt = pixel_points[(i + 1) % pixel_points.length]
            
            # Calculate distance from pixel to line segment
            dist = distance_to_line_segment(px, py, pt[0], pt[1], next_pt[0], next_pt[1])
            
            return true if dist <= thickness
        end
        
        false
    end
    # ------------------------------------------------------------------------
    
    # FUNCTION | Calculate distance from point to line segment
    # ------------------------------------------------------------------------
    def self.distance_to_line_segment(px, py, x1, y1, x2, y2)
        # Vector from line start to point
        dx = x2 - x1
        dy = y2 - y1
        
        # Handle zero-length segment
        if dx == 0 && dy == 0
            return Math.sqrt((px - x1)**2 + (py - y1)**2)
        end
        
        # Parameter t for projection onto line
        t = ((px - x1) * dx + (py - y1) * dy).to_f / (dx * dx + dy * dy)
        
        # Clamp t to [0, 1] to stay on segment
        t = [[t, 0].max, 1].min
        
        # Find closest point on segment
        closest_x = x1 + t * dx
        closest_y = y1 + t * dy
        
        # Return distance
        Math.sqrt((px - closest_x)**2 + (py - closest_y)**2)
    end
    # ------------------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Texture Application
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Apply texture to face with proper UV mapping
    # ------------------------------------------------------------------------
    def self.apply_texture_to_face(face, image_path, face_data)
        return unless image_path && File.exist?(image_path)
        
        model = Sketchup.active_model
        materials = model.materials
        
        # Create unique material name
        timestamp = Time.now.to_i
        material_name = "BorderTexture_#{timestamp}_#{rand(10000)}"
        
        # Create or get material
        material = materials.add(material_name)
        material.texture = image_path
        
        # Set texture size to match face dimensions
        material.texture.size = [face_data[:width], face_data[:height]]
        
        # Apply material to face
        face.material = material
        
        # Position texture using proper UV coordinates (rotated 90 degrees)
        # Define three points to position the texture
        # Rotate mapping by swapping axes
        # Point 1: Origin (bottom-left of texture bounds)
        # Point 2: Origin + Y direction (maps to texture width)
        # Point 3: Origin + X direction (maps to texture height)
        
        origin = face_data[:origin]
        x_axis = face_data[:x_axis]
        y_axis = face_data[:y_axis]
        width = face_data[:width]
        height = face_data[:height]
        min_x = face_data[:min_x]
        min_y = face_data[:min_y]
        
        # Calculate actual texture position points in 3D space
        # Rotated 90 degrees: Y-axis maps to texture width, X-axis to height
        pt1 = origin.offset(x_axis, min_x).offset(y_axis, min_y)
        pt2 = origin.offset(x_axis, min_x).offset(y_axis, min_y + height)
        pt3 = origin.offset(x_axis, min_x + width).offset(y_axis, min_y)
        
        # Position the texture
        face.position_material(material, [pt1, pt2, pt3], true)
    end
    # ------------------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Menu Integration
    # -----------------------------------------------------------------------------

    # FUNCTION | Create menu item
    # ------------------------------------------------------------------------
    def self.create_menu
        unless @menu_added
            menu = UI.menu('Plugins')
            menu.add_item('Apply Border Textures to Faces') {
                self.apply_border_textures
            }
            @menu_added = true
        end
    end
    # ------------------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------

end # module DrawBitmapAlongFaceEdges
end # module ValeDesignSuite


# -----------------------------------------------------------------------------
# INITIALIZATION
# -----------------------------------------------------------------------------
if defined?(Sketchup)
    ValeDesignSuite::DrawBitmapAlongFaceEdges.create_menu
    puts "ValeDesignSuite::DrawBitmapAlongFaceEdges loaded successfully." if ValeDesignSuite::DrawBitmapAlongFaceEdges::DEBUG_MODE
end
