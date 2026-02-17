# -----------------------------------------------------------------------------
# REGION | Architectural Hatches & Detailing Tool
# -----------------------------------------------------------------------------
# Generates CAD-style vector hatching on selected faces.
# Creates distinct groups for hatches with specific scale settings.
# Uses a modular definition structure for hatch patterns (JSON-like).
# -----------------------------------------------------------------------------

module Na__ArchitecturalHatches

    # -----------------------------------------------------------------------------
    # REGION | Hatch Definitions (JSON-like Structure)
    # -----------------------------------------------------------------------------
    # This hash acts as the library for all vector hatch patterns.
    # It stores 2D vertex coordinates and edge connectivity.
    # New patterns can be added here without changing the logic code.
    # -----------------------------------------------------------------------------
    HATCH_LIBRARY = {
        :concrete => {
            :name => "Standard Concrete",
            # Unit size reference for 1:1 scaling (in meters for calculation)
            :base_unit_size => 0.20, 
            # Probability of an element appearing in a grid cell (0.0 - 1.0)
            :density_factor => 0.7,
            # The graphical elements that make up the hatch
            :elements => [
                # ELEMENT 1: Standard Triangle (Aggregate)
                {
                    :type => "edges",
                    :vertices => [ [0.0, 0.0], [0.05, 0.08], [0.10, 0.0] ],
                    :closed => true,
                    :weight => 3 # Higher weight = more frequent in randomization
                },
                # ELEMENT 2: Small Triangle (Small Aggregate)
                {
                    :type => "edges",
                    :vertices => [ [0.0, 0.0], [0.03, 0.05], [0.06, 0.0] ],
                    :closed => true,
                    :weight => 2
                },
                # ELEMENT 3: Irregular Speck (Line)
                {
                    :type => "edges",
                    :vertices => [ [0.0, 0.0], [0.02, 0.02] ],
                    :closed => false,
                    :weight => 4
                },
                # ELEMENT 4: Dot/Point (Small Line)
                {
                    :type => "edges",
                    :vertices => [ [0.0, 0.0], [0.01, 0.0] ],
                    :closed => false,
                    :weight => 5
                }
            ]
        }
    }

    # -----------------------------------------------------------------------------
    # REGION | Core Hatch Generator Logic
    # -----------------------------------------------------------------------------
    
    class HatchGenerator
        
        # INITIALIZE
        # ------------------------------------------------------------
        def initialize(face, pattern_key, scale_mode)
            @face = face
            @pattern = HATCH_LIBRARY[pattern_key]
            @scale_mode = scale_mode # :scale_1_50 or :scale_1_5
            
            # Define Scale Factors based on user spec
            # 1:50 is the "Base". 1:5 is 0.1x the size of 1:50.
            case @scale_mode
            when :scale_1_50
                @scale_factor = 1.0
                @layer_name = "01_30__1:50_Hatches"
            when :scale_1_5
                @scale_factor = 0.1
                @layer_name = "01_30__1:5_Hatches"
            end
        end

        # EXECUTE | Main Generation Method
        # ------------------------------------------------------------
        def execute
            return unless @pattern
            
            model = Sketchup.active_model
            model.start_operation("Create Concrete Hatch #{@scale_mode}", true)

            # 1. Create/Get Layer (Tag)
            ensure_layer(model, @layer_name)

            # 2. Create Container Group
            # We create it in the same context as the face
            entities = @face.parent.entities
            hatch_group = entities.add_group
            hatch_group.name = "Hatch_#{@pattern[:name]}_#{@scale_mode}"
            hatch_group.layer = @layer_name
            
            # 3. Calculate Coordinate System
            # Create a 2D plane coordinate system based on the face
            center = @face.bounds.center
            normal = @face.normal
            
            # Arbitrary X/Y axes on the face plane
            tangent = (normal.parallel?(Z_AXIS)) ? X_AXIS : Z_AXIS * normal
            xaxis = tangent.normalize
            yaxis = (normal * xaxis).normalize
            
            # 4. Generate Hatch Geometry
            populate_hatch(hatch_group, center, xaxis, yaxis)

            model.commit_operation
        end

        # POPULATE HATCH | scattering algorithm
        # ------------------------------------------------------------
        def populate_hatch(group, origin, xaxis, yaxis)
            bounds = @face.bounds
            
            # Physical size of the grid cell based on pattern base size and chosen scale
            grid_size = @pattern[:base_unit_size] * @scale_factor * 25.4 # Convert roughly if needed, assuming base_unit is relative (~200mm visually)
            # Adjust grid size to be reasonable for model units (inches internal)
            # Let's assume base_unit_size 0.20 means 200mm in a 1:50 world.
            # In Sketchup Internal Units (inches): 
            cell_size = 5.inch * @scale_factor # Base cell size approx 5 inches scaled
            
            # Define coverage area (simple bbox iteration)
            min_pt = bounds.min
            max_pt = bounds.max
            
            # We iterate a grid over the bounds
            # For each cell, we check if center is on face, then place a random element
            
            # Get transformation to face plane for check
            # We will generate points in 3D and check them
            
            width = bounds.width
            height = bounds.depth # or height depending on orientation
            # Fallback to diagonal for iteration limit
            diag = bounds.diagonal
            
            # Simple iteration vectors aligned to world for the loop, 
            # but we project to face plane
            
            # Better approach: Iterate 2D local grid on the face plane
            # Project face vertices to 2D to find bounds in local 2D space
            inv_trans = Geom::Transformation.axes(origin, xaxis, yaxis, @face.normal).inverse
            
            local_points = @face.vertices.map { |v| v.position.transform(inv_trans) }
            min_x = local_points.map(&:x).min
            max_x = local_points.map(&:x).max
            min_y = local_points.map(&:y).min
            max_y = local_points.map(&:y).max
            
            # Z offset for overlay (prevent z-fighting)
            z_offset = 1.mm 

            x_curr = min_x
            while x_curr < max_x
                y_curr = min_y
                while y_curr < max_y
                    
                    # Randomized Jitter within the cell for "seamless" look
                    offset_x = (rand - 0.5) * (cell_size * 0.5)
                    offset_y = (rand - 0.5) * (cell_size * 0.5)
                    
                    local_pt = Geom::Point3d.new(x_curr + offset_x, y_curr + offset_y, 0)
                    
                    # Transform back to 3D world to check if inside face
                    world_trans = Geom::Transformation.axes(origin, xaxis, yaxis, @face.normal)
                    world_pt = local_pt.transform(world_trans)
                    
                    # Check if point is on the face
                    result = @face.classify_point(world_pt)
                    
                    # Sketchup::Face::PointInside = 1, PointOnVertex = 2, PointOnEdge = 4
                    if [1, 2, 4].include?(result)
                        # Decide whether to place an element here (Density)
                        if rand < @pattern[:density_factor]
                            add_random_element(group.entities, world_pt, xaxis, yaxis)
                        end
                    end
                    
                    y_curr += cell_size
                end
                x_curr += cell_size
            end
        end

        # ADD RANDOM ELEMENT | Pick from JSON and draw
        # ------------------------------------------------------------
        def add_random_element(entities, position, xaxis, yaxis)
            # Select element based on weight
            element = pick_weighted_element(@pattern[:elements])
            return unless element

            # Setup local transformation for the element
            # Random rotation (0 to 360 degrees)
            rotation_angle = rand * 360.degrees
            
            # Create vectors for vertices
            pts = []
            
            element[:vertices].each do |v_data|
                # v_data is [x, y] from JSON
                # Scale it
                vx = v_data[0] * 10.inch * @scale_factor # Multiplier to make coordinates useful
                vy = v_data[1] * 10.inch * @scale_factor
                
                # Rotate 2D
                rx = vx * Math.cos(rotation_angle) - vy * Math.sin(rotation_angle)
                ry = vx * Math.sin(rotation_angle) + vy * Math.cos(rotation_angle)
                
                # Map to 3D axes at position
                # position + (xaxis * rx) + (yaxis * ry)
                vec = (xaxis.clone.length = rx) + (yaxis.clone.length = ry)
                # Note: Setting length of vector directly, assuming normalized axes
                
                # Combine
                final_pt = position.offset(xaxis, rx).offset(yaxis, ry)
                
                # Apply slight Z lift
                final_pt = final_pt.offset(@face.normal, 0.5.mm)
                
                pts << final_pt
            end
            
            # Draw edges
            if pts.length > 1
                if element[:closed]
                    entities.add_edges(pts << pts.first) # Loop back to start
                else
                    entities.add_edges(pts)
                end
            end
        end

        # HELPER | Weighted Random Picker
        # ------------------------------------------------------------
        def pick_weighted_element(elements)
            total_weight = elements.inject(0) { |sum, el| sum + (el[:weight] || 1) }
            target = rand * total_weight
            
            current = 0
            elements.each do |el|
                current += (el[:weight] || 1)
                return el if current >= target
            end
            elements.first
        end

        # HELPER | Ensure Tag/Layer Exists
        # ------------------------------------------------------------
        def ensure_layer(model, layer_name)
            layers = model.layers
            layer = layers[layer_name]
            unless layer
                layer = layers.add(layer_name)
            end
            layer
        end

    end # End Class

    # -----------------------------------------------------------------------------
    # REGION | Selection Validator & Entry
    # -----------------------------------------------------------------------------
    
    def self.generate_concrete_1_50
        run_hatch(:concrete, :scale_1_50)
    end
    
    def self.generate_concrete_1_5
        run_hatch(:concrete, :scale_1_5)
    end

    def self.run_hatch(pattern_key, scale_mode)
        model = Sketchup.active_model
        sel = model.selection
        
        # Validation
        if sel.empty? || !sel.first.is_a?(Sketchup::Face)
            UI.messagebox("Please select a Face first.")
            return
        end
        
        face = sel.first
        
        # Instantiate and Run
        generator = HatchGenerator.new(face, pattern_key, scale_mode)
        generator.execute
    end

    # -----------------------------------------------------------------------------
    # REGION | Menu Registration
    # -----------------------------------------------------------------------------
    
    unless file_loaded?(__FILE__)
        
        # Main Submenu
        menu = UI.menu('Plugins').add_submenu('Architectural Hatches')
        
        # Command: 1:50
        cmd1 = UI::Command.new("Apply Concrete Hatch (1:50)") {
            Na__ArchitecturalHatches.generate_concrete_1_50
        }
        cmd1.tooltip = "Creates a 1:50 scale concrete hatch group on selected face"
        cmd1.status_bar_text = "Apply 1:50 Concrete Hatch"
        menu.add_item(cmd1)
        
        # Command: 1:5
        cmd2 = UI::Command.new("Apply Concrete Hatch (1:5)") {
            Na__ArchitecturalHatches.generate_concrete_1_5
        }
        cmd2.tooltip = "Creates a 1:5 scale (0.1x size) concrete hatch group on selected face"
        cmd2.status_bar_text = "Apply 1:5 Concrete Hatch"
        menu.add_item(cmd2)
        
        file_loaded(__FILE__)
    end

end # End Module