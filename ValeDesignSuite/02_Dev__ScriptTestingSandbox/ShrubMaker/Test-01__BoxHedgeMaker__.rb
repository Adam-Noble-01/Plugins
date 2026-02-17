# SketchUp Whitecard Shrub Generator
# Copy and paste this entire block into the Ruby Console
# Click in the model to generate shrubs.

require 'sketchup.rb'

module WhitecardVegetation
  class ShrubGenTool
    
    def initialize
      @cursor_id = 0 # Standard cursor
    end

    def activate
      puts "Whitecard Shrub Tool Activated: Click to place shrubs."
      Sketchup.status_text = "Click to place a random whitecard shrub."
    end

    def onLButtonUp(flags, x, y, view)
      # Create an input point to detect where the user clicked in 3D space
      ip = Sketchup::InputPoint.new
      ip.pick(view, x, y)
      
      if ip.valid?
        # Generate the shrub at the clicked point
        generate_shrub(ip.position)
      end
    end

    def generate_shrub(center_pt)
      model = Sketchup.active_model
      
      # Start an undo operation so one Ctrl+Z removes the whole shrub
      model.start_operation('Generate Shrub', true)
      
      # --- Constraints ---
      # Dimensions in mm
      min_w, max_w = 400.mm, 800.mm
      min_h, max_h = 600.mm, 1000.mm
      
      # Vertex Jitter (The "Bushy" look)
      jitter_min = 10.mm
      jitter_max = 30.mm
      
      # Calculate random bounds for this specific instance
      width = min_w + rand * (max_w - min_w)
      depth = min_w + rand * (max_w - min_w) # Random depth separate from width
      height = min_h + rand * (max_h - min_h)
      
      # Create a new group for the shrub
      group = model.active_entities.add_group
      entities = group.entities
      
      # --- 1. Create Grid Points (The "Split Shape") ---
      # We create a virtual 3x3x4 grid. This creates enough segments to look organic
      # but keeps the polygon count low (Optimized for Whitecard).
      segs_x = 2 # 2 segments = 3 points wide
      segs_y = 2
      segs_z = 3 
      
      points_grid = []
      
      (0..segs_x).each do |i|
        points_grid[i] = []
        (0..segs_y).each do |j|
          points_grid[i][j] = []
          (0..segs_z).each do |k|
             # Calculate the nominal grid position
             nx = (i.to_f / segs_x) * width - (width / 2.0)
             ny = (j.to_f / segs_y) * depth - (depth / 2.0)
             nz = (k.to_f / segs_z) * height
             
             nominal_pt = Geom::Point3d.new(center_pt.x + nx, center_pt.y + ny, center_pt.z + nz)
             
             # --- 2. Randomly Move Vertexes ---
             # Generate a random vector direction
             vx = rand - 0.5
             vy = rand - 0.5
             vz = rand - 0.5
             vec = Geom::Vector3d.new(vx, vy, vz)
             
             # Avoid zero length vector error
             if vec.length == 0
               vec = Geom::Vector3d.new(0, 0, 1)
             end
             
             # Normalize and apply random magnitude between 10mm and 30mm
             vec.normalize!
             displacement = jitter_min + rand * (jitter_max - jitter_min)
             vec.length = displacement
             
             # Apply jitter to point
             points_grid[i][j][k] = nominal_pt + vec
          end
        end
      end
      
      # --- 3. Generate Mesh Faces ---
      # We use PolygonMesh for speed and optimization
      mesh = Geom::PolygonMesh.new
      
      # Helper to add a quad face (made of 2 triangles)
      # Order points CCW for correct normal orientation
      def self.add_quad_to_mesh(mesh, p1, p2, p3, p4)
        mesh.add_polygon(p1, p2, p3)
        mesh.add_polygon(p1, p3, p4)
      end

      # Stitch the Hull (Outer skin only)
      
      # Front (y=0) & Back (y=max)
      (0...segs_x).each do |i|
        (0...segs_z).each do |k|
          # Front
          p1, p2 = points_grid[i][0][k], points_grid[i+1][0][k]
          p3, p4 = points_grid[i+1][0][k+1], points_grid[i][0][k+1]
          add_quad_to_mesh(mesh, p1, p2, p3, p4) # 1-2-3-4
          
          # Back
          p1b, p2b = points_grid[i+1][segs_y][k], points_grid[i][segs_y][k]
          p3b, p4b = points_grid[i][segs_y][k+1], points_grid[i+1][segs_y][k+1]
          add_quad_to_mesh(mesh, p1b, p2b, p3b, p4b)
        end
      end
      
      # Left (x=0) & Right (x=max)
      (0...segs_y).each do |j|
        (0...segs_z).each do |k|
          # Left
          p1, p2 = points_grid[0][j+1][k], points_grid[0][j][k]
          p3, p4 = points_grid[0][j][k+1], points_grid[0][j+1][k+1]
          add_quad_to_mesh(mesh, p1, p2, p3, p4)
          
          # Right
          p1r, p2r = points_grid[segs_x][j][k], points_grid[segs_x][j+1][k]
          p3r, p4r = points_grid[segs_x][j+1][k+1], points_grid[segs_x][j][k+1]
          add_quad_to_mesh(mesh, p1r, p2r, p3r, p4r)
        end
      end
      
      # Top (z=max) & Bottom (z=0)
      (0...segs_x).each do |i|
        (0...segs_y).each do |j|
          # Bottom
          p1, p2 = points_grid[i][j+1][0], points_grid[i+1][j+1][0]
          p3, p4 = points_grid[i+1][j][0], points_grid[i][j][0]
          add_quad_to_mesh(mesh, p1, p2, p3, p4)

          # Top
          p1t, p2t = points_grid[i][j][segs_z], points_grid[i+1][j][segs_z]
          p3t, p4t = points_grid[i+1][j+1][segs_z], points_grid[i][j+1][segs_z]
          add_quad_to_mesh(mesh, p1t, p2t, p3t, p4t)
        end
      end
      
      # Create geometry from mesh
      entities.fill_from_mesh(mesh, true, 0)
      
      # --- 4. Optimization & Style ---
      # Soften and Smooth edges for that organic "Whitecard" look
      entities.grep(Sketchup::Edge).each do |e|
        e.soft = true
        e.smooth = true
      end
      
      model.commit_operation
    end
  end

  # Activate the tool immediately
  Sketchup.active_model.select_tool(ShrubGenTool.new)
end