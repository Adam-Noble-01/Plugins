# ==============================================================================
# SKETCHUP RUBY: WHITECARD VEGETATION GENERATOR (FINAL)
# ==============================================================================
# Usage: Copy/Paste into Ruby Console -> Press Enter -> Click in model.
# ==============================================================================

require 'sketchup.rb'

module WhitecardVegetation
  class ShrubGenTool
    
    # ==========================================================================
    # --- 1. CONFIGURATION HEADER ---
    # Adjust these constants to change the default behavior of the brush.
    # These are designed to be easily mapped to a UI InputBox later.
    # ==========================================================================
    
    DEFAULT_CONFIG = {
      # --- Size Constraints (mm) ---
      :width_min        => 400.mm,
      :width_max        => 800.mm,
      :height_min       => 600.mm,
      :height_max       => 1000.mm,

      # --- Style / Noise ---
      # How much random movement to apply to vertices (The "Bushy" look)
      :jitter_amount    => 25.mm, 

      # --- Vertex Density (Resolution) ---
      # Higher numbers = smoother bushes but heavier models.
      # Radial: Segments around the equator (12 is Low Poly, 24 is Smooth)
      :density_radial   => 24, 
      # Vertical: Rings from bottom to top (8 is Low Poly, 16 is Smooth)
      :density_vertical => 16   
    }

    # ==========================================================================
    # --- 2. TOOL INITIALIZATION ---
    # ==========================================================================

    def initialize
      # Load configuration into an instance variable (Mutable for future UI)
      @settings = DEFAULT_CONFIG.dup
      @cursor_id = 0 
    end

    def activate
      puts "Whitecard Shrub Tool Activated."
      puts "Current Settings: #{@settings}"
      Sketchup.status_text = "Click to place a shrub. (Radial: #{@settings[:density_radial]}, Rings: #{@settings[:density_vertical]})"
    end

    def onLButtonUp(flags, x, y, view)
      ip = Sketchup::InputPoint.new
      ip.pick(view, x, y)
      
      if ip.valid?
        generate_shrub(ip.position)
      end
    end

    # ==========================================================================
    # --- 3. GENERATION LOGIC ---
    # ==========================================================================

    def generate_shrub(center_pt)
      model = Sketchup.active_model
      model.start_operation('Generate Shrub', true)
      
      # 1. READ CONFIG VARIABLES
      s_min_w = @settings[:width_min]
      s_max_w = @settings[:width_max]
      s_min_h = @settings[:height_min]
      s_max_h = @settings[:height_max]
      s_jitter = @settings[:jitter_amount]
      
      num_seg   = @settings[:density_radial]
      num_rings = @settings[:density_vertical]

      # 2. CALCULATE INSTANCE RANDOMNESS
      # Width
      actual_w = s_min_w + rand * (s_max_w - s_min_w)
      # Depth (Relative to width, keeps it generally round but varied)
      actual_d = actual_w * (0.8 + rand * 0.4) 
      # Height
      actual_h = s_min_h + rand * (s_max_h - s_min_h)
      
      # 3. SETUP MESH
      group = model.active_entities.add_group
      entities = group.entities
      mesh = Geom::PolygonMesh.new
      
      # Array to store vertex INDICES (integers), not point objects
      ring_indices = []

      # 4. GENERATE GEOMETRY (MANIFOLD / WATERTIGHT LOGIC)

      # --- A. South Pole (Bottom) ---
      # Single merged vertex to close the hole
      bottom_jitter = (rand * (s_jitter * 0.3)) # Very slight Z movement
      bottom_pt = Geom::Point3d.new(center_pt.x, center_pt.y, center_pt.z + bottom_jitter)
      bottom_idx = mesh.add_point(bottom_pt)

      # --- B. Middle Rings ---
      (1...num_rings).each do |i|
        current_ring_indices = []
        
        # Calculate latitude (Phi)
        phi = (Math::PI * i) / num_rings.to_f
        
        (0...num_seg).each do |j|
          # Calculate longitude (Theta)
          theta = (2 * Math::PI * j) / num_seg.to_f
          
          # Spherical Coordinates
          x = Math.sin(phi) * Math.cos(theta)
          y = Math.sin(phi) * Math.sin(theta)
          z = Math.cos(phi) 
          
          # Scale to dimensions
          # Z Mapping: -1..1 (Cos) -> 0..Height
          px = x * (actual_w / 2.0)
          py = y * (actual_d / 2.0)
          pz = ((z * -1) + 1) / 2.0 * actual_h 
          
          # Apply Organic Jitter (XYZ)
          jx = (rand - 0.5) * s_jitter * 2
          jy = (rand - 0.5) * s_jitter * 2
          jz = (rand - 0.5) * s_jitter * 2
          
          pt = Geom::Point3d.new(
            center_pt.x + px + jx, 
            center_pt.y + py + jy, 
            center_pt.z + pz + jz
          )
          
          # Add to mesh
          idx = mesh.add_point(pt)
          current_ring_indices << idx
        end
        ring_indices << current_ring_indices
      end

      # --- C. North Pole (Top) ---
      # Single merged vertex
      top_jitter = (rand - 0.5) * s_jitter
      top_pt = Geom::Point3d.new(center_pt.x, center_pt.y, center_pt.z + actual_h + top_jitter)
      top_idx = mesh.add_point(top_pt)

      # 5. STITCH FACES

      # Bottom Fan (South Pole -> Ring 1)
      first_ring = ring_indices[0]
      (0...num_seg).each do |j|
        next_j = (j + 1) % num_seg
        mesh.add_polygon(bottom_idx, first_ring[next_j], first_ring[j])
      end

      # Middle Body (Quads)
      (0...ring_indices.length - 1).each do |i|
        current_ring = ring_indices[i]
        next_ring = ring_indices[i+1]
        (0...num_seg).each do |j|
          next_j = (j + 1) % num_seg
          p1 = current_ring[j]
          p2 = current_ring[next_j]
          p3 = next_ring[next_j]
          p4 = next_ring[j]
          mesh.add_polygon(p1, p2, p3)
          mesh.add_polygon(p1, p3, p4)
        end
      end

      # Top Fan (Last Ring -> North Pole)
      last_ring = ring_indices.last
      (0...num_seg).each do |j|
        next_j = (j + 1) % num_seg
        mesh.add_polygon(top_idx, last_ring[j], last_ring[next_j])
      end
      
      # 6. FINALIZE & STYLE
      entities.fill_from_mesh(mesh, true, 0)
      
      # Soften/Smooth Edges
      entities.grep(Sketchup::Edge).each do |e|
        e.soft = true
        e.smooth = true
      end
      
      # Random Rotation (Z-Axis)
      tr = Geom::Transformation.rotation(center_pt, Geom::Vector3d.new(0,0,1), rand * 360.degrees)
      group.transform!(tr)

      model.commit_operation
    end
  end

  # Select the tool immediately
  Sketchup.active_model.select_tool(ShrubGenTool.new)
end