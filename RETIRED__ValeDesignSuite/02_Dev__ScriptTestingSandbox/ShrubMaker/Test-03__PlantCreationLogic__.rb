# ==============================================================================
# SKETCHUP RUBY: WHITECARD VEGETATION GENERATOR (v7 - Final Complete)
# ==============================================================================
# 1. GENERATE: Rounded Sphere Topology.
# 2. DECIMATE: Poke faces for extra detail (Leafy look).
# 3. MERGE:    Collapse close vertices to a median point (Abstract/Whitecard look).
# 4. ORIENT:   Fix face normals (Ensure no back-faces).
# ==============================================================================

require 'sketchup.rb'

module WhitecardVegetation
  class ShrubGenTool
    
    # ==========================================================================
    # --- 1. CONFIGURATION ---
    # ==========================================================================
    
    DEFAULT_CONFIG = {
      # --- Dimensions (mm) ---
      :width_min        => 400.mm,
      :width_max        => 800.mm,
      :height_min       => 600.mm,
      :height_max       => 1000.mm,

      # --- Phase 1: Base Shape ---
      :base_jitter      => 25.mm, 
      :density_radial   => 12, 
      :density_vertical => 8, 

      # --- Phase 2: Detail Pass (Poking) ---
      :detail_pass_enabled => true, 
      :detail_jitter       => 20.mm, # Randomness of the poked spikes

      # --- Phase 3: Vertex Merging (Simplification) ---
      # Vertices closer than this distance will be snapped to a single median point.
      # Default: 50mm (Approx 2 inches).
      :merge_distance      => 50.mm 
    }

    # ==========================================================================
    # --- 2. TOOL SETUP ---
    # ==========================================================================

    def initialize
      @settings = DEFAULT_CONFIG.dup
    end

    def activate
      puts "Whitecard Shrub Tool v7 Activated."
      dist_mm = @settings[:merge_distance].to_mm.round(1)
      Sketchup.status_text = "Click to place. (Merge Distance: #{dist_mm}mm)"
    end

    def onLButtonUp(flags, x, y, view)
      ip = Sketchup::InputPoint.new
      ip.pick(view, x, y)
      if ip.valid?
        generate_shrub(ip.position)
      end
    end

    # ==========================================================================
    # --- 3. HELPER METHODS ---
    # ==========================================================================
    
    def add_poked_quad(mesh, p1, p2, p3, p4, jitter_max)
      pt1, pt2 = mesh.point_at(p1), mesh.point_at(p2)
      pt3, pt4 = mesh.point_at(p3), mesh.point_at(p4)
      
      # Calc Center
      cx = (pt1.x + pt2.x + pt3.x + pt4.x) / 4.0
      cy = (pt1.y + pt2.y + pt3.y + pt4.y) / 4.0
      cz = (pt1.z + pt2.z + pt3.z + pt4.z) / 4.0
      
      # Apply Jitter
      jx = (rand - 0.5) * jitter_max * 2
      jy = (rand - 0.5) * jitter_max * 2
      jz = (rand - 0.5) * jitter_max * 2
      
      center_pt = Geom::Point3d.new(cx + jx, cy + jy, cz + jz)
      center_idx = mesh.add_point(center_pt)
      
      # Add Triangles (Blindly, normals fixed later)
      mesh.add_polygon(p1, p2, center_idx)
      mesh.add_polygon(p2, p3, center_idx)
      mesh.add_polygon(p3, p4, center_idx)
      mesh.add_polygon(p4, p1, center_idx)
    end

    def merge_close_vertices(entities, threshold)
      # Greedy Clustering Algorithm
      # 1. Iterate all vertices.
      # 2. Find neighbors within threshold.
      # 3. Calculate Centroid (Median).
      # 4. Move them all to Centroid.
      
      verts = entities.grep(Sketchup::Vertex)
      processed = {} # Keep track of verts we have already moved/merged
      
      # Suspend UI for speed during this calculation
      
      verts.each do |v1|
        next if processed[v1] || !v1.valid?
        
        # Find cluster
        cluster = [v1]
        verts.each do |v2|
          next if v1 == v2 || processed[v2] || !v2.valid?
          if v1.position.distance(v2.position) <= threshold
            cluster << v2
          end
        end
        
        # If we found neighbors to merge
        if cluster.length > 1
          # Calculate Centroid (Median Point)
          cx, cy, cz = 0.0, 0.0, 0.0
          cluster.each do |v| 
            cx += v.position.x
            cy += v.position.y
            cz += v.position.z
          end
          centroid = Geom::Point3d.new(cx/cluster.size, cy/cluster.size, cz/cluster.size)
          
          # Move all vertices in cluster to this centroid
          cluster.each do |v|
            vec = v.position.vector_to(centroid)
            # transform_entities is the fastest way to move a vertex
            entities.transform_entities(Geom::Transformation.translation(vec), v)
            processed[v] = true
          end
        end
      end
      
      # Cleanup: Moving vertices together creates zero-length edges.
      # We must erase them to truly "merge" the geometry.
      tiny_tolerance = 0.001.mm
      entities.grep(Sketchup::Edge).each do |e|
        if e.valid? && e.length < tiny_tolerance
          e.erase! 
        end
      end
    end

    # ==========================================================================
    # --- 4. MAIN GENERATION ---
    # ==========================================================================

    def generate_shrub(center_pt)
      model = Sketchup.active_model
      model.start_operation('Generate Shrub', true)
      
      # Read Config
      s_min_w, s_max_w = @settings[:width_min], @settings[:width_max]
      s_min_h, s_max_h = @settings[:height_min], @settings[:height_max]
      s_base_jitter    = @settings[:base_jitter]
      s_detail_jitter  = @settings[:detail_jitter]
      s_merge_dist     = @settings[:merge_distance]
      
      num_seg   = @settings[:density_radial]
      num_rings = @settings[:density_vertical]

      # Dimensions
      actual_w = s_min_w + rand * (s_max_w - s_min_w)
      actual_d = actual_w * (0.8 + rand * 0.4) 
      actual_h = s_min_h + rand * (s_max_h - s_min_h)
      
      group = model.active_entities.add_group
      entities = group.entities
      mesh = Geom::PolygonMesh.new
      ring_indices = []

      # --- PHASE 1: GENERATE POINTS (Sphere) ---

      # South Pole
      bottom_pt = Geom::Point3d.new(center_pt.x, center_pt.y, center_pt.z + (rand * 10.mm))
      bottom_idx = mesh.add_point(bottom_pt)

      # Middle Rings
      (1...num_rings).each do |i|
        current_ring_indices = []
        phi = (Math::PI * i) / num_rings.to_f
        
        (0...num_seg).each do |j|
          theta = (2 * Math::PI * j) / num_seg.to_f
          x = Math.sin(phi) * Math.cos(theta)
          y = Math.sin(phi) * Math.sin(theta)
          z = Math.cos(phi) 
          
          px = x * (actual_w / 2.0)
          py = y * (actual_d / 2.0)
          pz = ((z * -1) + 1) / 2.0 * actual_h 
          
          jx = (rand - 0.5) * s_base_jitter * 2
          jy = (rand - 0.5) * s_base_jitter * 2
          jz = (rand - 0.5) * s_base_jitter * 2
          
          pt = Geom::Point3d.new(center_pt.x + px + jx, center_pt.y + py + jy, center_pt.z + pz + jz)
          current_ring_indices << mesh.add_point(pt)
        end
        ring_indices << current_ring_indices
      end

      # North Pole
      top_pt = Geom::Point3d.new(center_pt.x, center_pt.y, center_pt.z + actual_h + ((rand-0.5)*s_base_jitter))
      top_idx = mesh.add_point(top_pt)

      # --- PHASE 2: POKE FACES (Decimation/Detail) ---

      # Bottom Cap
      first_ring = ring_indices[0]
      (0...num_seg).each do |j|
        next_j = (j + 1) % num_seg
        mesh.add_polygon(bottom_idx, first_ring[next_j], first_ring[j])
      end

      # Middle Body (Poked Quads)
      (0...ring_indices.length - 1).each do |i|
        current_ring = ring_indices[i]
        next_ring = ring_indices[i+1]
        (0...num_seg).each do |j|
          next_j = (j + 1) % num_seg
          p1, p2 = current_ring[j], current_ring[next_j]
          p3, p4 = next_ring[next_j], next_ring[j]
          
          if @settings[:detail_pass_enabled]
            add_poked_quad(mesh, p1, p2, p3, p4, s_detail_jitter)
          else
            mesh.add_polygon(p1, p2, p3, p4)
          end
        end
      end

      # Top Cap
      last_ring = ring_indices.last
      (0...num_seg).each do |j|
        next_j = (j + 1) % num_seg
        mesh.add_polygon(top_idx, last_ring[j], last_ring[next_j])
      end
      
      entities.fill_from_mesh(mesh, true, 0)
      
      # --- PHASE 3: MERGE CLOSE VERTICES ---
      # This runs AFTER poking to simplify the added details
      if s_merge_dist > 0
        merge_close_vertices(entities, s_merge_dist)
      end

      # --- PHASE 4: ORIENTATION & STYLE ---
      # Fix Normals (Ray cast style)
      centroid = group.bounds.center
      entities.grep(Sketchup::Face).each do |face|
        # If normal points inward (towards center), flip it
        vector_out = face.bounds.center - centroid
        if vector_out.dot(face.normal) < 0
          face.reverse!
        end
        
        # Soften edges
        face.edges.each do |e| 
          e.soft = true
          e.smooth = true
        end
      end

      # Rotate
      tr = Geom::Transformation.rotation(center_pt, Geom::Vector3d.new(0,0,1), rand * 360.degrees)
      group.transform!(tr)

      model.commit_operation
    end
  end

  Sketchup.active_model.select_tool(ShrubGenTool.new)
end
