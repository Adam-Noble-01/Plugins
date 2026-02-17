# =============================================================================
# SKETCHUP RUBY | WHITECARD VEGETATION GENERATOR
# =============================================================================
# Version: 7.0
# Author: Adam Noble
#
# Pipeline:
#   1. GENERATE  - Rounded sphere topology with jitter
#   2. DECIMATE  - Poke faces for extra detail (leafy look)
#   3. MERGE     - Collapse close vertices to median point (abstract/whitecard)
#   4. ORIENT    - Fix face normals (ensure no back-faces)
# =============================================================================

require 'sketchup.rb'

# -----------------------------------------------------------------------------
# REGION | Whitecard Vegetation Module
# -----------------------------------------------------------------------------
module WhitecardVegetation
  
  class ShrubGenTool
    
    # -------------------------------------------------------------------------
    # REGION | Configuration
    # -------------------------------------------------------------------------
    
    DEFAULT_CONFIG = {
      # Dimensions (mm)
      :width_min             => 400.mm,   # <-- Minimum shrub width
      :width_max             => 800.mm,   # <-- Maximum shrub width
      :height_min            => 600.mm,   # <-- Minimum shrub height
      :height_max            => 1000.mm,  # <-- Maximum shrub height

      # Phase 1: Base Shape
      :base_jitter           => 25.mm,    # <-- Base geometry randomness
      :density_radial        => 12,       # <-- Segments around circumference
      :density_vertical      => 8,        # <-- Number of vertical rings

      # Phase 2: Detail Pass (Poking)
      :detail_pass_enabled   => true,     # <-- Enable face subdivision
      :detail_jitter         => 20.mm,    # <-- Randomness of poked spikes

      # Phase 3: Vertex Merging (Simplification)
      :merge_distance        => 60.mm     # <-- Vertices closer than this snap to median (approx 2 inches)
    }
    
    # endregion ---------------------------------------------------------------
    
    
    # -------------------------------------------------------------------------
    # REGION | Tool Lifecycle
    # -------------------------------------------------------------------------
    
    # FUNCTION | Constructor
    # -------------------------------------------------------------------------
    def initialize
      @settings       = DEFAULT_CONFIG.dup                  # <-- Configuration settings
      @ip             = Sketchup::InputPoint.new            # <-- Input point for snapping
      @cursor_pos     = nil                                 # <-- Current cursor position
      @crosshair_size = 300.mm                              # <-- Crosshair arm length
      @dialog         = nil                                 # <-- Parameter dialog window
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Tool activation handler
    # -------------------------------------------------------------------------
    def activate
      puts "Whitecard Shrub Tool v7 Activated."
      dist_mm = @settings[:merge_distance].to_mm.round(1)
      Sketchup.status_text = "Click to place shrub. (Merge Distance: #{dist_mm}mm)"
      
      # Auto-open parameter dialog
      show_parameter_dialog
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Mouse click handler
    # -------------------------------------------------------------------------
    def onLButtonUp(flags, x, y, view)
      @ip.pick(view, x, y)
      
      if @ip.valid?
        generate_shrub(@ip.position)
      end
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Tool resume handler
    # -------------------------------------------------------------------------
    def resume(view)
      view.invalidate                                       # <-- Refresh view to redraw cursor
    end
    # -------------------------------------------------------------------------
    
    # endregion ---------------------------------------------------------------
    
    
    # -------------------------------------------------------------------------
    # REGION | Visual Feedback & Cursor
    # -------------------------------------------------------------------------
    
    # FUNCTION | Track cursor position with snapping
    # -------------------------------------------------------------------------
    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)                                  # <-- Update input point with snapping
      @cursor_pos = @ip.position                            # <-- Store cursor position
      view.invalidate                                       # <-- Refresh view to redraw cursor
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Render green 3D crosshair cursor at mouse position
    # -------------------------------------------------------------------------
    # Draws a 6-armed crosshair (±X, ±Y, ±Z) in green color.
    # Indicates the bottom center point where the shrub will be inserted.
    # -------------------------------------------------------------------------
    def draw(view)
      return unless @cursor_pos                             # <-- Exit if no cursor position yet
      
      # Draw input point (shows vertex/edge snapping indicator)
      @ip.draw(view)                                        # <-- Draw standard InputPoint indicator
      
      # Draw custom green crosshair cursor
      cx   = @cursor_pos.x                                  # <-- Get cursor X coordinate
      cy   = @cursor_pos.y                                  # <-- Get cursor Y coordinate
      cz   = @cursor_pos.z                                  # <-- Get cursor Z coordinate
      size = @crosshair_size                                # <-- Get crosshair size
      
      # Define crosshair line endpoints (world-aligned)
      x_pos = Geom::Point3d.new(cx + size, cy, cz)          # <-- Positive X direction
      x_neg = Geom::Point3d.new(cx - size, cy, cz)          # <-- Negative X direction
      y_pos = Geom::Point3d.new(cx, cy + size, cz)          # <-- Positive Y direction
      y_neg = Geom::Point3d.new(cx, cy - size, cz)          # <-- Negative Y direction
      z_pos = Geom::Point3d.new(cx, cy, cz + size)          # <-- Positive Z direction
      z_neg = Geom::Point3d.new(cx, cy, cz - size)          # <-- Negative Z direction
      
      # Set drawing style
      view.line_stipple    = ""                             # <-- Solid line
      view.line_width      = 2                              # <-- Line width 2 pixels
      view.drawing_color   = Sketchup::Color.new(0, 255, 0) # <-- Green color
      
      # Draw 3D crosshair lines (X, Y, Z axes)
      view.draw_line(@cursor_pos, x_pos)                    # <-- Draw +X arm
      view.draw_line(@cursor_pos, x_neg)                    # <-- Draw -X arm
      view.draw_line(@cursor_pos, y_pos)                    # <-- Draw +Y arm
      view.draw_line(@cursor_pos, y_neg)                    # <-- Draw -Y arm
      view.draw_line(@cursor_pos, z_pos)                    # <-- Draw +Z arm
      view.draw_line(@cursor_pos, z_neg)                    # <-- Draw -Z arm
    end
    # -------------------------------------------------------------------------
    
    # endregion ---------------------------------------------------------------
    
    
    # -------------------------------------------------------------------------
    # REGION | HTML Dialog Interface
    # -------------------------------------------------------------------------
    
    # FUNCTION | Create and show parameter dialog
    # -------------------------------------------------------------------------
    # Opens an interactive HTML dialog with dual-range sliders for controlling
    # shrub width and height parameters. Dialog remains open while using tool.
    # -------------------------------------------------------------------------
    def show_parameter_dialog
      return if @dialog && @dialog.visible?                 # <-- Don't create duplicate dialog
      
      @dialog = UI::HtmlDialog.new(
        :dialog_title    => "Shrub Generator Parameters",
        :preferences_key => "ShrubGenerator_Params",
        :scrollable      => false,
        :resizable       => true,
        :width           => 420,
        :height          => 900,
        :left            => 200,
        :top             => 200,
        :style           => UI::HtmlDialog::STYLE_DIALOG
      )
      
      html_content = create_dialog_html                     # <-- Generate HTML content
      @dialog.set_html(html_content)                        # <-- Set dialog HTML content
      
      setup_dialog_callbacks                                # <-- Register callbacks
      @dialog.show                                          # <-- Show the dialog
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Generate HTML content for dialog
    # -------------------------------------------------------------------------
    # Returns complete HTML string with custom dual-range sliders.
    # Pure CSS/JavaScript implementation, no external dependencies.
    # -------------------------------------------------------------------------
    def create_dialog_html
      # Get current parameter values in mm
      width_min  = @settings[:width_min].to_mm.round
      width_max  = @settings[:width_max].to_mm.round
      height_min = @settings[:height_min].to_mm.round
      height_max = @settings[:height_max].to_mm.round
      
      # Calculate complexity (1-10 scale from density_radial 6-24)
      complexity = ((@settings[:density_radial] - 6) / 2.0 + 1).clamp(1, 10).round
      
      # Get randomness (base_jitter in mm)
      randomness = @settings[:base_jitter].to_mm.round
      
      # Get merge distance (in mm)
      merge_dist = @settings[:merge_distance].to_mm.round
      
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            
            body {
              font-family: 'Segoe UI', Arial, sans-serif;
              padding: 25px;
              background: #f8f9fa;
              color: #333;
            }
            
            h2 {
              font-size: 18px;
              font-weight: 600;
              margin-bottom: 25px;
              color: #2c3e50;
              border-bottom: 2px solid #4CAF50;
              padding-bottom: 10px;
            }
            
            .slider-container {
              margin-bottom: 35px;
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            
            .slider-label {
              font-size: 14px;
              font-weight: 600;
              margin-bottom: 15px;
              color: #34495e;
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }
            
            .dual-range-wrapper {
              position: relative;
              height: 40px;
              margin: 20px 0;
            }
            
            .range-track {
              position: absolute;
              width: 100%;
              height: 8px;
              background: #ecf0f1;
              border-radius: 4px;
              top: 16px;
            }
            
            .range-fill {
              position: absolute;
              height: 8px;
              background: #4CAF50;
              border-radius: 4px;
              top: 16px;
            }
            
            .range-input {
              position: absolute;
              width: 100%;
              pointer-events: none;
              -webkit-appearance: none;
              appearance: none;
              background: transparent;
              outline: none;
            }
            
            .range-input::-webkit-slider-thumb {
              -webkit-appearance: none;
              appearance: none;
              width: 20px;
              height: 20px;
              border-radius: 50%;
              background: white;
              border: 3px solid #4CAF50;
              cursor: pointer;
              pointer-events: all;
              box-shadow: 0 2px 4px rgba(0,0,0,0.2);
            }
            
            .range-input::-webkit-slider-thumb:hover {
              background: #e8f5e9;
              transform: scale(1.1);
            }
            
            .range-input::-moz-range-thumb {
              width: 20px;
              height: 20px;
              border-radius: 50%;
              background: white;
              border: 3px solid #4CAF50;
              cursor: pointer;
              pointer-events: all;
              box-shadow: 0 2px 4px rgba(0,0,0,0.2);
            }
            
            .range-input::-moz-range-thumb:hover {
              background: #e8f5e9;
              transform: scale(1.1);
            }
            
            .slider-values {
              display: flex;
              justify-content: space-between;
              margin-top: 15px;
              font-size: 13px;
              color: #7f8c8d;
            }
            
            .slider-values strong {
              color: #2c3e50;
              font-weight: 600;
              font-size: 15px;
            }
            
            .single-range-wrapper {
              position: relative;
              height: 40px;
              margin: 20px 0;
            }
            
            .range-fill-single {
              position: absolute;
              height: 8px;
              background: #4CAF50;
              border-radius: 4px;
              top: 16px;
              left: 0;
            }
            
            .range-input-single {
              position: absolute;
              width: 100%;
              -webkit-appearance: none;
              appearance: none;
              background: transparent;
              outline: none;
            }
            
            .range-input-single::-webkit-slider-thumb {
              -webkit-appearance: none;
              appearance: none;
              width: 20px;
              height: 20px;
              border-radius: 50%;
              background: white;
              border: 3px solid #4CAF50;
              cursor: pointer;
              box-shadow: 0 2px 4px rgba(0,0,0,0.2);
            }
            
            .range-input-single::-webkit-slider-thumb:hover {
              background: #e8f5e9;
              transform: scale(1.1);
            }
            
            .range-input-single::-moz-range-thumb {
              width: 20px;
              height: 20px;
              border-radius: 50%;
              background: white;
              border: 3px solid #4CAF50;
              cursor: pointer;
              box-shadow: 0 2px 4px rgba(0,0,0,0.2);
            }
            
            .range-input-single::-moz-range-thumb:hover {
              background: #e8f5e9;
              transform: scale(1.1);
            }
            
            .slider-value-center {
              text-align: center;
              margin-top: 15px;
              font-size: 13px;
              color: #7f8c8d;
            }
            
            .info-text {
              font-size: 12px;
              color: #95a5a6;
              text-align: center;
              margin-top: 20px;
              font-style: italic;
            }
          </style>
        </head>
        <body>
          <h2>Shrub Generator Parameters</h2>
          
          <div class="slider-container">
            <div class="slider-label">Width Range (mm)</div>
            <div class="dual-range-wrapper">
              <div class="range-track"></div>
              <div class="range-fill" id="width-fill"></div>
              <input type="range" min="200" max="2000" step="50" value="#{width_min}" 
                     class="range-input" id="width-min-input">
              <input type="range" min="200" max="2000" step="50" value="#{width_max}" 
                     class="range-input" id="width-max-input">
            </div>
            <div class="slider-values">
              <span>Min: <strong id="width-min-display">#{width_min}</strong> mm</span>
              <span>Max: <strong id="width-max-display">#{width_max}</strong> mm</span>
            </div>
          </div>
          
          <div class="slider-container">
            <div class="slider-label">Height Range (mm)</div>
            <div class="dual-range-wrapper">
              <div class="range-track"></div>
              <div class="range-fill" id="height-fill"></div>
              <input type="range" min="300" max="3000" step="50" value="#{height_min}" 
                     class="range-input" id="height-min-input">
              <input type="range" min="300" max="3000" step="50" value="#{height_max}" 
                     class="range-input" id="height-max-input">
            </div>
            <div class="slider-values">
              <span>Min: <strong id="height-min-display">#{height_min}</strong> mm</span>
              <span>Max: <strong id="height-max-display">#{height_max}</strong> mm</span>
            </div>
          </div>
          
          <div class="slider-container">
            <div class="slider-label">Complexity (Vertex Count)</div>
            <div class="single-range-wrapper">
              <div class="range-track"></div>
              <div class="range-fill-single" id="complexity-fill"></div>
              <input type="range" min="1" max="10" step="1" value="#{complexity}" 
                     class="range-input-single" id="complexity-input">
            </div>
            <div class="slider-value-center">
              <span>Level: <strong id="complexity-display">#{complexity}</strong> / 10</span>
            </div>
          </div>
          
          <div class="slider-container">
            <div class="slider-label">Randomness (Jitter Amount)</div>
            <div class="single-range-wrapper">
              <div class="range-track"></div>
              <div class="range-fill-single" id="randomness-fill"></div>
              <input type="range" min="0" max="50" step="5" value="#{randomness}" 
                     class="range-input-single" id="randomness-input">
            </div>
            <div class="slider-value-center">
              <span>Amount: <strong id="randomness-display">#{randomness}</strong> mm</span>
            </div>
          </div>
          
          <div class="slider-container">
            <div class="slider-label">Merge Distance (Simplification)</div>
            <div class="single-range-wrapper">
              <div class="range-track"></div>
              <div class="range-fill-single" id="merge-fill"></div>
              <input type="range" min="0" max="150" step="5" value="#{merge_dist}" 
                     class="range-input-single" id="merge-input">
            </div>
            <div class="slider-value-center">
              <span>Distance: <strong id="merge-display">#{merge_dist}</strong> mm</span>
            </div>
          </div>
          
          <div class="info-text">
            Parameters update in real-time. Close dialog when done.
          </div>
          
          <script>
            // Dual Range Slider Implementation
            function initDualRangeSlider(minId, maxId, fillId, minDisplayId, maxDisplayId) {
              const minInput = document.getElementById(minId);
              const maxInput = document.getElementById(maxId);
              const fill = document.getElementById(fillId);
              const minDisplay = document.getElementById(minDisplayId);
              const maxDisplay = document.getElementById(maxDisplayId);
              
              const min = parseInt(minInput.min);
              const max = parseInt(minInput.max);
              
              function updateFill() {
                const minVal = parseInt(minInput.value);
                const maxVal = parseInt(maxInput.value);
                
                // Prevent crossing
                if (minVal > maxVal - parseInt(minInput.step)) {
                  minInput.value = maxVal - parseInt(minInput.step);
                }
                if (maxVal < minVal + parseInt(minInput.step)) {
                  maxInput.value = minVal + parseInt(minInput.step);
                }
                
                const minValFinal = parseInt(minInput.value);
                const maxValFinal = parseInt(maxInput.value);
                
                // Update visual fill
                const percentMin = ((minValFinal - min) / (max - min)) * 100;
                const percentMax = ((maxValFinal - min) / (max - min)) * 100;
                
                fill.style.left = percentMin + '%';
                fill.style.width = (percentMax - percentMin) + '%';
                
                // Update displays
                minDisplay.textContent = minValFinal;
                maxDisplay.textContent = maxValFinal;
                
                sendParamsToRuby();
              }
              
              minInput.addEventListener('input', updateFill);
              maxInput.addEventListener('input', updateFill);
              
              // Initialize
              updateFill();
            }
            
            // Initialize dual-range sliders
            initDualRangeSlider('width-min-input', 'width-max-input', 'width-fill', 
                                'width-min-display', 'width-max-display');
            initDualRangeSlider('height-min-input', 'height-max-input', 'height-fill', 
                                'height-min-display', 'height-max-display');
            
            // Single Range Slider Implementation
            function initSingleRangeSlider(inputId, fillId, displayId, min, max) {
              const input = document.getElementById(inputId);
              const fill = document.getElementById(fillId);
              const display = document.getElementById(displayId);
              
              function updateSlider() {
                const value = parseInt(input.value);
                const percent = ((value - min) / (max - min)) * 100;
                fill.style.width = percent + '%';
                display.textContent = value;
                sendParamsToRuby();
              }
              
              input.addEventListener('input', updateSlider);
              updateSlider();
            }
            
            // Initialize single-range sliders
            initSingleRangeSlider('complexity-input', 'complexity-fill', 'complexity-display', 1, 10);
            initSingleRangeSlider('randomness-input', 'randomness-fill', 'randomness-display', 0, 50);
            initSingleRangeSlider('merge-input', 'merge-fill', 'merge-display', 0, 150);
            
            // Send parameters to Ruby
            function sendParamsToRuby() {
              const widthMin = parseInt(document.getElementById('width-min-input').value);
              const widthMax = parseInt(document.getElementById('width-max-input').value);
              const heightMin = parseInt(document.getElementById('height-min-input').value);
              const heightMax = parseInt(document.getElementById('height-max-input').value);
              const complexity = parseInt(document.getElementById('complexity-input').value);
              const randomness = parseInt(document.getElementById('randomness-input').value);
              const mergeDist = parseInt(document.getElementById('merge-input').value);
              
              sketchup.updateParams({
                widthMin: widthMin,
                widthMax: widthMax,
                heightMin: heightMin,
                heightMax: heightMax,
                complexity: complexity,
                randomness: randomness,
                mergeDist: mergeDist
              });
            }
            
            // Notify Ruby that dialog is ready
            sketchup.dialogReady();
          </script>
        </body>
        </html>
      HTML
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Setup Ruby callbacks for JavaScript communication
    # -------------------------------------------------------------------------
    # Registers callbacks that JavaScript can invoke to communicate with Ruby.
    # Updates @settings hash when slider values change.
    # -------------------------------------------------------------------------
    def setup_dialog_callbacks
      @dialog.add_action_callback("updateParams") do |action_context, params|
        # Update width and height ranges
        @settings[:width_min]  = params["widthMin"].to_f.mm
        @settings[:width_max]  = params["widthMax"].to_f.mm
        @settings[:height_min] = params["heightMin"].to_f.mm
        @settings[:height_max] = params["heightMax"].to_f.mm
        
        # Update complexity (scale 1-10 controls density)
        complexity = params["complexity"].to_i
        @settings[:density_radial]   = 6 + (complexity - 1) * 2          # <-- 6 to 24 segments
        @settings[:density_vertical] = (4 + (complexity - 1) * 1.33).round  # <-- 4 to 16 rings
        
        # Update randomness (controls jitter for both stages)
        randomness = params["randomness"].to_f
        @settings[:base_jitter]   = randomness.mm                        # <-- Base geometry jitter
        @settings[:detail_jitter] = (randomness * 0.8).mm                # <-- Detail jitter (80% of base)
        
        # Update merge distance (simplification threshold)
        merge_dist = params["mergeDist"].to_f
        @settings[:merge_distance] = merge_dist.mm                       # <-- Merge distance threshold
        
        # Log updated parameters
        puts "Shrub parameters updated:"
        puts "  Width:       #{params["widthMin"].to_i} - #{params["widthMax"].to_i} mm"
        puts "  Height:      #{params["heightMin"].to_i} - #{params["heightMax"].to_i} mm"
        puts "  Complexity:  #{complexity} (radial: #{@settings[:density_radial]}, vertical: #{@settings[:density_vertical]})"
        puts "  Randomness:  #{randomness.to_i}mm (base: #{randomness.to_i}mm, detail: #{(randomness * 0.8).to_i}mm)"
        puts "  Merge Dist:  #{merge_dist.to_i}mm"
      end
      
      @dialog.add_action_callback("dialogReady") do |action_context|
        puts "Parameter dialog ready."
      end
    end
    # -------------------------------------------------------------------------
    
    # endregion ---------------------------------------------------------------
    
    
    # -------------------------------------------------------------------------
    # REGION | Geometry Helpers
    # -------------------------------------------------------------------------
    
    # FUNCTION | Subdivide quad face by poking center with jitter
    # -------------------------------------------------------------------------
    # Creates 4 triangles from a quad by adding a jittered center vertex.
    # Produces leafy, organic detail. Normals are fixed later.
    # -------------------------------------------------------------------------
    def add_poked_quad(mesh, p1, p2, p3, p4, jitter_max)
      pt1 = mesh.point_at(p1)
      pt2 = mesh.point_at(p2)
      pt3 = mesh.point_at(p3)
      pt4 = mesh.point_at(p4)
      
      # Calculate center
      cx = (pt1.x + pt2.x + pt3.x + pt4.x) / 4.0
      cy = (pt1.y + pt2.y + pt3.y + pt4.y) / 4.0
      cz = (pt1.z + pt2.z + pt3.z + pt4.z) / 4.0
      
      # Apply jitter
      jx = (rand - 0.5) * jitter_max * 2
      jy = (rand - 0.5) * jitter_max * 2
      jz = (rand - 0.5) * jitter_max * 2
      
      center_pt  = Geom::Point3d.new(cx + jx, cy + jy, cz + jz)
      center_idx = mesh.add_point(center_pt)
      
      # Add triangles (normals fixed later)
      mesh.add_polygon(p1, p2, center_idx)
      mesh.add_polygon(p2, p3, center_idx)
      mesh.add_polygon(p3, p4, center_idx)
      mesh.add_polygon(p4, p1, center_idx)
    end
    # -------------------------------------------------------------------------
    
    # FUNCTION | Merge vertices within threshold distance to median point
    # -------------------------------------------------------------------------
    # Greedy clustering algorithm:
    #   1. Iterate all vertices
    #   2. Find neighbors within threshold
    #   3. Calculate centroid (median)
    #   4. Move all to centroid
    #   5. Erase zero-length edges
    # -------------------------------------------------------------------------
    def merge_close_vertices(entities, threshold)
      verts     = entities.grep(Sketchup::Vertex)
      processed = {}  # <-- Track already-merged vertices
      
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
          # Calculate centroid (median point)
          cx = 0.0
          cy = 0.0
          cz = 0.0
          
          cluster.each do |v| 
            cx += v.position.x
            cy += v.position.y
            cz += v.position.z
          end
          
          centroid = Geom::Point3d.new(cx / cluster.size, cy / cluster.size, cz / cluster.size)
          
          # Move all vertices in cluster to centroid
          cluster.each do |v|
            vec = v.position.vector_to(centroid)
            entities.transform_entities(Geom::Transformation.translation(vec), v)
            processed[v] = true
          end
        end
      end
      
      # Cleanup: Erase zero-length edges created by vertex merging
      tiny_tolerance = 0.001.mm
      entities.grep(Sketchup::Edge).each do |e|
        if e.valid? && e.length < tiny_tolerance
          e.erase! 
        end
      end
    end
    # -------------------------------------------------------------------------
    
    # endregion ---------------------------------------------------------------
    
    
    # -------------------------------------------------------------------------
    # REGION | Main Generation Pipeline
    # -------------------------------------------------------------------------
    
    # FUNCTION | Generate complete shrub at specified position
    # -------------------------------------------------------------------------
    # 4-Phase pipeline:
    #   Phase 1: Generate sphere topology with base jitter
    #   Phase 2: Subdivide faces (detail pass) if enabled
    #   Phase 3: Merge close vertices for whitecard look
    #   Phase 4: Fix normals and apply final styling
    # -------------------------------------------------------------------------
    def generate_shrub(center_pt)
      model = Sketchup.active_model
      model.start_operation('Generate Shrub', true)
      
      # Read configuration
      s_min_w         = @settings[:width_min]           # <-- Width range
      s_max_w         = @settings[:width_max]
      s_min_h         = @settings[:height_min]          # <-- Height range
      s_max_h         = @settings[:height_max]
      s_base_jitter   = @settings[:base_jitter]         # <-- Base randomness
      s_detail_jitter = @settings[:detail_jitter]       # <-- Detail randomness
      s_merge_dist    = @settings[:merge_distance]      # <-- Merge threshold
      
      num_seg         = @settings[:density_radial]      # <-- Circumference segments
      num_rings       = @settings[:density_vertical]    # <-- Vertical rings

      # Randomize dimensions
      actual_w = s_min_w + rand * (s_max_w - s_min_w)
      actual_d = actual_w * (0.8 + rand * 0.4) 
      actual_h = s_min_h + rand * (s_max_h - s_min_h)
      
      # Initialize geometry containers
      group        = model.active_entities.add_group
      entities     = group.entities
      mesh         = Geom::PolygonMesh.new
      ring_indices = []

      # -----------------------------------------------------------------------
      # PHASE 1 | Generate Points (Sphere Topology)
      # -----------------------------------------------------------------------

      # South Pole
      bottom_pt  = Geom::Point3d.new(center_pt.x, center_pt.y, center_pt.z + (rand * 10.mm))
      bottom_idx = mesh.add_point(bottom_pt)

      # Middle Rings
      (1...num_rings).each do |i|
        current_ring_indices = []
        phi = (Math::PI * i) / num_rings.to_f
        
        (0...num_seg).each do |j|
          theta = (2 * Math::PI * j) / num_seg.to_f
          
          # Spherical coordinates
          x = Math.sin(phi) * Math.cos(theta)
          y = Math.sin(phi) * Math.sin(theta)
          z = Math.cos(phi) 
          
          # Scale to ellipsoid
          px = x * (actual_w / 2.0)
          py = y * (actual_d / 2.0)
          pz = ((z * -1) + 1) / 2.0 * actual_h 
          
          # Apply base jitter
          jx = (rand - 0.5) * s_base_jitter * 2
          jy = (rand - 0.5) * s_base_jitter * 2
          jz = (rand - 0.5) * s_base_jitter * 2
          
          pt = Geom::Point3d.new(center_pt.x + px + jx, center_pt.y + py + jy, center_pt.z + pz + jz)
          current_ring_indices << mesh.add_point(pt)
        end
        
        ring_indices << current_ring_indices
      end

      # North Pole
      top_pt  = Geom::Point3d.new(center_pt.x, center_pt.y, center_pt.z + actual_h + ((rand - 0.5) * s_base_jitter))
      top_idx = mesh.add_point(top_pt)

      # -----------------------------------------------------------------------
      # PHASE 2 | Connect Faces (With Optional Detail Pass)
      # -----------------------------------------------------------------------

      # Bottom Cap
      first_ring = ring_indices[0]
      (0...num_seg).each do |j|
        next_j = (j + 1) % num_seg
        mesh.add_polygon(bottom_idx, first_ring[next_j], first_ring[j])
      end

      # Middle Body (Poked Quads or Simple Quads)
      (0...ring_indices.length - 1).each do |i|
        current_ring = ring_indices[i]
        next_ring    = ring_indices[i + 1]
        
        (0...num_seg).each do |j|
          next_j = (j + 1) % num_seg
          
          p1 = current_ring[j]
          p2 = current_ring[next_j]
          p3 = next_ring[next_j]
          p4 = next_ring[j]
          
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
      
      # -----------------------------------------------------------------------
      # PHASE 3 | Merge Close Vertices (Simplification)
      # -----------------------------------------------------------------------
      # Runs AFTER poking to simplify the added detail
      # -----------------------------------------------------------------------
      
      if s_merge_dist > 0
        merge_close_vertices(entities, s_merge_dist)
      end

      # -----------------------------------------------------------------------
      # PHASE 4 | Orientation & Styling
      # -----------------------------------------------------------------------
      
      # Fix normals (raycast style - ensure outward facing)
      centroid = group.bounds.center
      entities.grep(Sketchup::Face).each do |face|
        vector_out = face.bounds.center - centroid
        
        if vector_out.dot(face.normal) < 0
          face.reverse!
        end
        
        # Soften edges for smooth appearance
        face.edges.each do |e| 
          e.soft   = true
          e.smooth = true
        end
      end

      # Random rotation around Z axis
      tr = Geom::Transformation.rotation(center_pt, Geom::Vector3d.new(0, 0, 1), rand * 360.degrees)
      group.transform!(tr)

      model.commit_operation
    end
    # -------------------------------------------------------------------------
    
    # endregion ---------------------------------------------------------------
    
  end
  
  
  # ---------------------------------------------------------------------------
  # REGION | Public Entry Point
  # ---------------------------------------------------------------------------
  
  # FUNCTION | Show Parameter Dialog (Hotkey Entry Point)
  # -------------------------------------------------------------------------
  # Bind this method in Preferences → Shortcuts to a custom hotkey
  # Method name: WhitecardVegetation.show_shrub_parameters
  # -------------------------------------------------------------------------
  def self.show_shrub_parameters
    model = Sketchup.active_model                           # <-- Get active model
    return unless model                                     # <-- Exit if no active model
    
    tool = model.tools.active_tool                          # <-- Get active tool
    
    if tool.is_a?(ShrubGenTool)
      tool.show_parameter_dialog                            # <-- Open parameter dialog
    else
      UI.messagebox("Activate Shrub Tool first")            # <-- Show warning
    end
  end
  # -------------------------------------------------------------------------
  
  # endregion -----------------------------------------------------------------
  
  
  # ---------------------------------------------------------------------------
  # REGION | Menu Registration and Startup Wiring
  # ---------------------------------------------------------------------------
  
  # FUNCTION | Install Menu and Commands
  # -------------------------------------------------------------------------
  def self.install_menu_and_commands
    return if @menu_installed                               # <-- Exit if already installed
    
    # Create UI command for shrub tool activation
    cmd = UI::Command.new('NA_ShrubGenerator') do           # <-- Create command with ID
      Sketchup.active_model.select_tool(ShrubGenTool.new)  # <-- Activate the tool
    end
    cmd.tooltip = "Whitecard Shrub Generator"               # <-- Set tooltip
    cmd.status_bar_text = "Activate whitecard vegetation generator tool"  # <-- Set status bar text
    cmd.menu_text = "Na__ShrubMaker__Main"                  # <-- Set menu text for hotkey search
    
    # Add to Plugins menu
    UI.menu('Plugins').add_item(cmd)                        # <-- Add to Plugins menu
    
    @menu_installed = true                                  # <-- Mark as installed
  end
  # -------------------------------------------------------------------------
  
  # FUNCTION | Activate for Model
  # -------------------------------------------------------------------------
  def self.activate_for_model(model)
    install_menu_and_commands                               # <-- Install menu and commands
  end
  # -------------------------------------------------------------------------
  
  # endregion -----------------------------------------------------------------
  
# endregion -------------------------------------------------------------------
end

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
  WhitecardVegetation.activate_for_model(Sketchup.active_model)  # <-- Activate menu registration
  file_loaded(__FILE__)                                           # <-- Mark file as loaded
end