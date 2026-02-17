# =============================================================================
# TIMELAPSE CAMERA MODEL - MIRROR SCRIPT
# =============================================================================
#
# FILE       : TimelapseObserver_Mirror_Improved.rb
# MODULE     : ValeDesignSuite::TimelapseObserver
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Monitors 3D work model and captures timelapse frames
# CREATED    : 2025
#
# USAGE:
# - Run this in a separate SketchUp instance (Model B - Camera Model)
# - Select your main work model file (Model A) to monitor
# - Captures PNG frames each time the work model is saved
#
# =============================================================================

require 'sketchup.rb'
require 'fileutils'
require 'tempfile'

module ValeDesignSuite
  module TimelapseObserver

    # MODULE CONSTANTS | Configuration Settings
    # ------------------------------------------------------------
    CHECK_INTERVAL          =   10.0                                             # <-- Check every 10 seconds (matches save interval)
    SCENE_NAME              =   'TimelapseVideo__HelperScene'.freeze             # <-- Scene for consistent view
    WIDTH_PX                =   3000                                             # <-- Export width
    HEIGHT_PX               =   2250                                             # <-- Export height
    EXPORT_DIR              =   'D:/11__CoreLib__VideoAsssets/10__TimelapseVideos__RawExports'.tr('\\','/')
    EXTENSION_ID            =   'vale_design_suite.timelapse_observer'.freeze    # <-- Extension ID
    MAX_RETRIES             =   3                                                # <-- Max retry attempts for file load
    RETRY_DELAYS            =   [0.5, 1.0, 2.0].freeze                            # <-- Exponential backoff delays (seconds)
    POST_CHANGE_DELAY       =   2.5                                               # <-- Delay after change detection (seconds)
    FILE_STABILITY_CHECK     =   true                                              # <-- Check if file size is stable before loading
    FILE_STABILITY_DELAY     =   0.5                                               # <-- Delay between stability checks (seconds)
    
    # Names of Tags/Layers to hide during capture
    HIDE_TAG_NAMES          =   [                                                # <-- Tags to hide during export
        '01__ValeCAD',
        '06__Plan__RoofPlan',
        '06__Plan__GroundFloorPlan', 
        '07__Elevation__Front',
        '07__Elevation__Left',
        '07__Elevation__Right',
        '00__Standards',
        '01__GroundGridLines',
        '06__Drawings',
        '05__Mirror'
    ].freeze
    # ------------------------------------------------------------

    # MODULE VARIABLES | State Management
    # ------------------------------------------------------------
    @@timer                 =   nil                                              # <-- Timer reference
    @@source_path           =   nil                                              # <-- Path to main model
    @@last_mtime            =   Time.at(0)                                       # <-- Last modification time
    @@last_size             =   0                                                # <-- Last file size
    @@frame_counter         =   0                                                # <-- Frame number
    @@instance              =   nil                                              # <-- Component instance
    @@scene_page            =   nil                                              # <-- Scene reference
    @@overlay               =   nil                                              # <-- REC indicator
    @@reload_count          =   0                                                # <-- Reload counter
    @@start_time            =   nil                                              # <-- Recording start time
    @@consecutive_failures   =   0                                                # <-- Track consecutive failures
    # ------------------------------------------------------------

    FileUtils.mkdir_p(EXPORT_DIR) unless Dir.exist?(EXPORT_DIR)                 # <-- Ensure export dir exists

    # -----------------------------------------------------------------------------
    # REGION | Core Timer Functions
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check if Timer is Running
        # ------------------------------------------------------------
        def self.running?
            !@@timer.nil?                                                        # <-- Return true if timer exists
        end
        # ------------------------------------------------------------

        # SUB FUNCTION | Timer Callback - Check and Reload
        # ------------------------------------------------------------
        def self.check_and_reload
            puts "[TimelapseObserver] Checking for changes..."
            begin
                load_model_content                                                   # <-- Check and load if changed
            rescue => e
                # Catch ALL exceptions including CFileException to prevent error dialog
                error_msg = e.message.to_s.downcase
                is_file_error = error_msg.include?('cfileexception') || 
                               error_msg.include?('locked') || 
                               error_msg.include?('inaccessible') ||
                               error_msg.include?('file') ||
                               e.class.name.to_s.downcase.include?('file')
                
                if is_file_error
                    puts "[TimelapseObserver] File access error caught in timer callback: #{e.message}"
                    puts "[TimelapseObserver] This is normal when Model A is saving. Will retry on next check."
                else
                    puts "[TimelapseObserver] Unexpected error in timer callback: #{e.message}"
                    puts "[TimelapseObserver] Error type: #{e.class.name}"
                end
                # DO NOT re-raise - this prevents SketchUp error dialog
            end
        end
        # ------------------------------------------------------------
        
        # DEBUG FUNCTION | Force Frame Capture (for testing)
        # ------------------------------------------------------------
        def self.force_capture
            puts "[TimelapseObserver] DEBUG: Forcing frame capture..."
            capture_frame
        end
        # ------------------------------------------------------------
        
        # DEBUG FUNCTION | Force Reload and Capture (for testing)
        # ------------------------------------------------------------
        def self.force_reload
            puts "[TimelapseObserver] DEBUG: Forcing reload and capture..."
            # Force update timestamps
            @@last_mtime = Time.at(0)
            @@last_size = 0
            load_model_content
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Model Loading Functions
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check if File is Accessible (Not Locked)
        # ------------------------------------------------------------
        def self.file_accessible?(filepath)
            return false unless filepath && File.exist?(filepath)                 # <-- Basic check
            
            # Try to open file for reading - if locked, this will fail
            begin
                File.open(filepath, 'r') { |f| f.read(1) }                      # <-- Try to read 1 byte
                return true                                                      # <-- File accessible
            rescue => e
                # File is locked or inaccessible
                return false                                                     # <-- File not accessible
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check if File Size is Stable (Not Being Written)
        # ------------------------------------------------------------
        def self.file_stable?(filepath, check_delay = FILE_STABILITY_DELAY)
            return false unless filepath && File.exist?(filepath)                 # <-- Basic check
            
            begin
                size1 = File.size(filepath)                                      # <-- First size check
                sleep(check_delay)                                                # <-- Wait
                size2 = File.size(filepath)                                      # <-- Second size check
                return size1 == size2                                             # <-- Stable if sizes match
            rescue => e
                return false                                                     # <-- Not stable if error
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Load Model Content and Capture Frame
        # ------------------------------------------------------------
        def self.load_model_content
            return unless @@source_path && File.exist?(@@source_path)            # <-- Check file exists
            
            puts "[TimelapseObserver] === LOADING MODEL CONTENT ==="
            puts "[TimelapseObserver] Source path: #{@@source_path}"
            
            # Get current file info
            current_mtime = File.mtime(@@source_path) rescue nil
            current_size = File.size(@@source_path) rescue 0
            
            puts "[TimelapseObserver] File check:"
            puts "  Last mtime: #{@@last_mtime} | Current: #{current_mtime}"
            puts "  Last size: #{@@last_size} | Current: #{current_size}"
            
            # Check if file has been modified (by time OR size change)
            file_changed = (current_mtime != @@last_mtime) || (current_size != @@last_size)
            
            if !file_changed && @@reload_count > 0
                puts "[TimelapseObserver] No changes detected"
                @@consecutive_failures = 0                                       # <-- Reset failure counter
                return                                                           # <-- Skip if unchanged
            end
            
            puts "[TimelapseObserver] Change detected! Reloading..."
            
            # Post-change delay to allow save operations to complete
            if file_changed && POST_CHANGE_DELAY > 0
                puts "[TimelapseObserver] Waiting #{POST_CHANGE_DELAY}s for save to complete..."
                sleep(POST_CHANGE_DELAY)                                         # <-- Delay before load attempt
            end
            
            # Additional stability check if enabled
            if file_changed && FILE_STABILITY_CHECK
                puts "[TimelapseObserver] Checking file stability..."
                stability_attempts = 0
                max_stability_attempts = 10                                      # <-- Max 5 seconds of checking
                while !file_stable?(@@source_path) && stability_attempts < max_stability_attempts
                    stability_attempts += 1
                    puts "[TimelapseObserver] File still changing, waiting... (attempt #{stability_attempts})"
                    sleep(FILE_STABILITY_DELAY)
                end
                if stability_attempts >= max_stability_attempts
                    puts "[TimelapseObserver] File stability check timeout - proceeding anyway"
                else
                    puts "[TimelapseObserver] File is stable, proceeding with load"
                end
            end
            
            # CRITICAL FIX: Copy file to temp location to avoid lock conflicts
            # This prevents CFileException by never loading the locked original
            temp_file_path = nil
            begin
                # Create a temporary copy of the file
                temp_dir = File.join(ENV['TEMP'] || '/tmp', 'timelapse_temp')
                FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)
                temp_file_path = File.join(temp_dir, "temp_#{Time.now.to_i}_#{File.basename(@@source_path)}")
                
                # Try to copy the file - this will fail if locked
                copy_success = false
                copy_attempts = 0
                max_copy_attempts = 5
                
                while !copy_success && copy_attempts < max_copy_attempts
                    begin
                        puts "[TimelapseObserver] Attempting to copy file (attempt #{copy_attempts + 1})"
                        FileUtils.cp(@@source_path, temp_file_path)
                        copy_success = true
                        puts "[TimelapseObserver] File copied successfully to: #{temp_file_path}"
                    rescue => copy_error
                        copy_attempts += 1
                        if copy_attempts < max_copy_attempts
                            puts "[TimelapseObserver] Copy failed: #{copy_error.message}, retrying..."
                            sleep(0.5)
                        else
                            puts "[TimelapseObserver] Failed to copy file after #{max_copy_attempts} attempts"
                            puts "[TimelapseObserver] File is likely locked by Model A - skipping this cycle"
                            return  # Exit without updating timestamps - will retry next cycle
                        end
                    end
                end
                
                unless copy_success
                    puts "[TimelapseObserver] Unable to copy file - skipping load"
                    return
                end
                
                # Use the temp file for loading instead of the original
                load_path = temp_file_path
                
            rescue => e
                puts "[TimelapseObserver] Error setting up temp file: #{e.message}"
                # Clean up temp file if it exists
                File.delete(temp_file_path) if temp_file_path && File.exist?(temp_file_path)
                return  # Exit without updating timestamps
            end
            
            model = Sketchup.active_model
            model.start_operation('Update Timelapse', true)                      # <-- Start operation
            
            begin
                # Clear existing content
                if @@instance && @@instance.valid?
                    model.entities.erase_entities(@@instance)                    # <-- Remove old instance
                end
                
                # Purge unused definitions periodically
                if @@reload_count % 10 == 0
                    model.definitions.purge_unused                               # <-- Clean up definitions
                end
                
                # Force reload by clearing definition first
                model.definitions.purge_unused                                   # <-- Clear cache
                
                # Force refresh to ensure we get latest content
                # Sometimes SketchUp caches component definitions
                existing_def = model.definitions.find { |d| d.path == @@source_path }
                if existing_def
                    puts "[TimelapseObserver] Found existing definition, removing: #{existing_def.name}"
                    model.definitions.remove(existing_def)
                end
                
                # Load new content from TEMP COPY (not original)
                puts "[TimelapseObserver] Loading from temp file: #{load_path}"
                puts "[TimelapseObserver] Temp file exists: #{File.exist?(load_path)}"
                puts "[TimelapseObserver] Temp file size: #{File.size(load_path)} bytes"
                
                definition = nil
                load_success = false
                
                # Single attempt to load from temp file (no retries needed since it's a copy)
                begin
                    definition = model.definitions.load(load_path)               # <-- Load from TEMP COPY
                    load_success = true
                    puts "[TimelapseObserver] Definition loaded successfully from temp file"
                    puts "[TimelapseObserver] Definition name: #{definition ? definition.name : 'nil'}"
                    puts "[TimelapseObserver] Definition entities count: #{definition ? definition.entities.length : 'N/A'}"
                    puts "[TimelapseObserver] Definition bounds: #{definition ? definition.bounds : 'N/A'}"
                    
                rescue => load_error
                    # This should rarely happen since we're loading from a temp copy
                    puts "[TimelapseObserver] Failed to load temp file: #{load_error.message}"
                    puts "[TimelapseObserver] Error type: #{load_error.class.name}"
                    model.abort_operation                                        # <-- Rollback operation
                    
                    # Clean up temp file
                    File.delete(load_path) if File.exist?(load_path)
                    return                                                        # <-- Exit without updating tracking
                end
                
                # Clean up temp file after successful load
                begin
                    File.delete(load_path) if File.exist?(load_path)
                    puts "[TimelapseObserver] Temp file cleaned up"
                rescue => cleanup_error
                    puts "[TimelapseObserver] Warning: Could not delete temp file: #{cleanup_error.message}"
                end
                
                unless load_success
                    puts "[TimelapseObserver] Load failed - will retry on next check"
                    model.abort_operation                                        # <-- Rollback operation
                    return                                                        # <-- Exit without updating tracking
                end
                
                @@instance = model.entities.add_instance(definition, Geom::Transformation.new)   # <-- Add instance
                puts "[TimelapseObserver] Instance created: #{@@instance ? 'Yes' : 'No'}"
                puts "[TimelapseObserver] Instance bounds: #{@@instance ? @@instance.bounds : 'N/A'}"
                puts "[TimelapseObserver] Model entities count: #{model.entities.length}"
                puts "[TimelapseObserver] Model bounds: #{model.bounds}"
                
                # Update tracking only on successful load
                @@last_mtime = current_mtime                                     # <-- Update timestamp
                @@last_size = current_size                                       # <-- Update size
                @@reload_count += 1                                              # <-- Increment counter
                @@consecutive_failures = 0                                       # <-- Reset failure counter
                
                # Only zoom extents on very first load if model bounds are empty
                if @@reload_count == 1 && model.bounds.diagonal < 1.0
                    puts "[TimelapseObserver] Empty model detected - zooming to fit"
                    model.active_view.zoom_extents                               # <-- Zoom to fit
                end
                
                model.commit_operation                                           # <-- Commit changes
                
                puts "[TimelapseObserver] Model reloaded (#{@@reload_count})"
                
                # Capture frame after successful reload
                capture_frame                                                    # <-- Export image
                
            rescue => e
                # Catch any other unexpected errors
                model.abort_operation                                            # <-- Rollback on error
                
                # Only log non-file errors (file errors already handled above)
                unless e.message.include?('CFileException') || e.message.include?('locked') || e.message.include?('inaccessible')
                    puts "[TimelapseObserver] Unexpected load error: #{e.message}"
                    puts "[TimelapseObserver] Error details: #{e.backtrace.first(3).join("\n")}"
                end
            end
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Frame Capture Functions
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Recursively Hide Entities by Tag
        # ------------------------------------------------------------
        def self.hide_entities_recursive(entities, tag_names, hidden_entities = {})
            entities.each do |entity|
                # Skip if entity doesn't support visibility or layers
                next unless entity.respond_to?(:visible?) && entity.respond_to?(:visible=)
                next unless entity.respond_to?(:layer)
                
                # Check if entity's tag should be hidden
                if tag_names.include?(entity.layer.name)
                    # Store original visibility and hide
                    if entity.visible?
                        hidden_entities[entity] = true                          # <-- Record it was visible
                        entity.visible = false                                  # <-- Hide entity
                    end
                end
                
                # Recurse into groups and component instances
                if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    if entity.definition && entity.definition.entities
                        hide_entities_recursive(entity.definition.entities, tag_names, hidden_entities)
                    end
                end
            end
            
            return hidden_entities
        end
        # ------------------------------------------------------------

        # FUNCTION | Hide Export Tags for Clean Export
        # ------------------------------------------------------------
        def self.hide_export_tags
            model = Sketchup.active_model
            
            # Start operation for clean undo
            model.start_operation('Timelapse Hide Entities', true)
            
            # Recursively hide all entities with specified tags
            hidden_entities = hide_entities_recursive(model.entities, HIDE_TAG_NAMES)
            
            model.commit_operation
            
            puts "[TimelapseObserver] Hidden #{hidden_entities.length} entities for clean export"
            return hidden_entities                                              # <-- Return hidden entities
        end
        # ------------------------------------------------------------

        # FUNCTION | Restore Export Tags Visibility
        # ------------------------------------------------------------
        def self.restore_export_tags(hidden_entities)
            return if hidden_entities.empty?                                    # <-- Exit if no entities
            
            model = Sketchup.active_model
            
            # Restore visibility within operation
            model.start_operation('Timelapse Restore Entities', true)
            
            restored_count = 0
            hidden_entities.each do |entity, was_visible|
                if entity.valid? && was_visible
                    entity.visible = true                                       # <-- Restore visibility
                    restored_count += 1
                end
            end
            
            model.commit_operation
            
            puts "[TimelapseObserver] Restored #{restored_count} entities visibility"
        end
        # ------------------------------------------------------------

        # FUNCTION | Capture Frame
        # ------------------------------------------------------------
        def self.capture_frame
            view = Sketchup.active_model.active_view
            
            # Hide entities with export tags before capture
            hidden_entities = hide_export_tags                                  # <-- Hide entities with tags
            
            begin
                # Force complete redraw for clean capture
                view.invalidate                                                  # <-- Mark for redraw
                view.refresh                                                     # <-- Force redraw
                
                # Generate filename
                timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
                filename = format('frame_%06d_%s.png', @@frame_counter, timestamp)   # <-- Include timestamp
                filepath = File.join(EXPORT_DIR, filename)                       # <-- Full path
                
                # Export with high quality
                view.write_image(
                    filename:    filepath,
                    width:       WIDTH_PX,
                    height:      HEIGHT_PX,
                    antialias:   true,
                    compression: 9,
                    transparent: false
                )
                
                # Update counter
                @@frame_counter += 1                                             # <-- Increment counter
                
                puts "[TimelapseObserver] ✓ Frame #{@@frame_counter} saved: #{filename}"
                puts "[TimelapseObserver] Total frames captured: #{@@frame_counter}"
                
            rescue => e
                puts "[TimelapseObserver] Capture error: #{e.message}"
            ensure
                # Always restore entity visibility regardless of success/failure
                restore_export_tags(hidden_entities)                            # <-- Restore hidden entities
            end
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Overlay Display
    # -----------------------------------------------------------------------------

        # CLASS | Recording Indicator
        # ------------------------------------------------------------
        class RecOverlay < Sketchup::Overlay
            def initialize
                super(ValeDesignSuite::TimelapseObserver::EXTENSION_ID, 'REC')
                @pulse_phase = 0.0                                               # <-- For pulsing effect
            end
            
            def draw(view)
                # Update pulse animation
                @pulse_phase = (@pulse_phase + 0.1) % (2.0 * Math::PI)
                pulse = 0.8 + 0.2 * Math.sin(@pulse_phase)                      # <-- Pulse factor
                
                # Draw REC indicator with pulse
                margin = 15                                                      # <-- Edge margin
                radius = 8 * pulse                                               # <-- Pulsing radius
                
                cx = view.vpwidth - margin - 10                                  # <-- X position
                cy = margin + 10                                                 # <-- Y position
                
                # Draw red circle
                pts = []
                segments = 16                                                    # <-- Circle segments
                (0..segments).each do |i|
                    angle = (i * 2.0 * Math::PI) / segments                      # <-- Angle
                    x = cx + radius * Math.cos(angle)                            # <-- X coordinate
                    y = cy + radius * Math.sin(angle)                            # <-- Y coordinate  
                    pts << Geom::Point3d.new(x, y, 0)                           # <-- Add point
                end
                
                view.drawing_color = [255, 0, 0, (255 * pulse).to_i]            # <-- Pulsing red
                view.draw2d(GL_POLYGON, pts)                                     # <-- Draw filled circle
                
                # Draw REC text
                view.draw_text(
                    Geom::Point3d.new(cx - radius - 35, cy - 6, 0),            # <-- Text position
                    "REC",                                                       # <-- Text
                    {
                        color: [255, 0, 0, 255],                                 # <-- Red text
                        size: 12,                                                # <-- Font size
                        bold: true                                               # <-- Bold font
                    }
                )
                
                # Request redraw for animation
                view.invalidate
            end
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Recording Control Functions
    # -----------------------------------------------------------------------------

        # FUNCTION | Start Observing
        # ------------------------------------------------------------
        def self.start
            return if running?                                                   # <-- Exit if already running
            
            # Select main work model file to observe
            @@source_path = UI.openpanel(
                'Select Model A (3D Work Model) to monitor for timelapse',
                nil,
                'SketchUp Files|*.skp||'
            )
            return unless @@source_path && File.exist?(@@source_path)            # <-- Exit if cancelled
            
            # Clear the mirror model
            model = Sketchup.active_model
            model.entities.clear!                                                # <-- Clear all entities
            model.definitions.purge_unused                                       # <-- Clean definitions
            
            # Set up scene
            @@scene_page = ensure_helper_scene                                   # <-- Create/get scene
            
            # Reset counters
            @@frame_counter = 0                                                  # <-- Reset frame count
            @@reload_count = 0                                                   # <-- Reset reload count
            @@last_mtime = Time.at(0)                                           # <-- Reset timestamp
            @@last_size = 0                                                      # <-- Reset file size
            @@start_time = Time.now                                              # <-- Track start time
            @@consecutive_failures = 0                                           # <-- Reset failure counter
            
            # Initial load
            load_model_content                                                   # <-- Load first time
            
            # Start monitoring timer
            @@timer = UI.start_timer(CHECK_INTERVAL, true) { check_and_reload }  # <-- Start timer
            
            # Create overlay
            create_overlay                                                       # <-- Show REC
            
            puts "\n[TimelapseObserver] Started observing: #{File.basename(@@source_path)}"
            puts "[TimelapseObserver] Checking every #{CHECK_INTERVAL} seconds"
            puts "[TimelapseObserver] Frames saved to: #{EXPORT_DIR}"
            
            UI.messagebox(
                "Timelapse Camera Started! (Model B)\n\n" +
                "Monitoring Model A: #{File.basename(@@source_path)}\n" +
                "Check interval: #{CHECK_INTERVAL}s\n" +
                "Output: #{EXPORT_DIR}\n\n" +
                "This is your camera model - leave it open to record.\n" +
                "Work in Model A - frames capture automatically when you save."
            )
        end
        # ------------------------------------------------------------

        # FUNCTION | Stop Recording
        # ------------------------------------------------------------
        def self.stop
            return unless running?                                               # <-- Exit if not running
            
            UI.stop_timer(@@timer)                                               # <-- Stop timer
            @@timer = nil                                                        # <-- Clear reference
            remove_overlay                                                       # <-- Remove REC
            
            # Calculate duration
            duration = Time.now - @@start_time rescue 0
            mins = (duration / 60).floor
            secs = (duration % 60).floor
            
            puts "\n[TimelapseObserver] === RECORDING COMPLETE ==="
            puts "[TimelapseObserver] Total frames: #{@@frame_counter}"
            puts "[TimelapseObserver] Recording time: #{mins}m #{secs}s"
            puts "[TimelapseObserver] Output folder: #{EXPORT_DIR}"
            puts "[TimelapseObserver] ========================="
            
            # Offer to open output folder
            result = UI.messagebox(
                "Recording Complete!\n\n" +
                "Frames captured: #{@@frame_counter}\n" +
                "Recording time: #{mins}m #{secs}s\n\n" +
                "Open output folder?",
                MB_YESNO
            )
            
            if result == IDYES
                UI.openURL("file:///#{EXPORT_DIR}")                             # <-- Open folder
            end
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Scene Management Functions
    # -----------------------------------------------------------------------------

        # FUNCTION | Create or Get Helper Scene
        # ------------------------------------------------------------
        def self.ensure_helper_scene
            model = Sketchup.active_model
            scene = model.pages[SCENE_NAME]                                      # <-- Check for existing scene
            
            unless scene
                puts "[TimelapseObserver] Creating scene: #{SCENE_NAME}"
                
                # Create scene with current view (don't change camera)
                scene = model.pages.add(SCENE_NAME)                              # <-- Add new scene
                scene.update(0)                                                  # <-- Save current view (0 = all)
                puts "[TimelapseObserver] Scene created with current view"
            end
            
            # Activate the scene like the original did
            model.pages.selected_page = scene                                    # <-- Activate scene
            return scene
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Overlay Management Functions
    # -----------------------------------------------------------------------------

        # FUNCTION | Create Recording Overlay
        # ------------------------------------------------------------
        def self.create_overlay
            return if @@overlay                                                  # <-- Exit if exists
            @@overlay = RecOverlay.new                                           # <-- Create overlay
            Sketchup.active_model.overlays.add(@@overlay)                       # <-- Add to model
        end
        # ------------------------------------------------------------

        # FUNCTION | Remove Recording Overlay
        # ------------------------------------------------------------
        def self.remove_overlay
            return unless @@overlay                                              # <-- Exit if not exists
            Sketchup.active_model.overlays.remove(@@overlay)                     # <-- Remove overlay
            @@overlay = nil                                                      # <-- Clear reference
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Menu Integration
    # -----------------------------------------------------------------------------

        unless file_loaded?(__FILE__)
            # Create menu command
            cmd = UI::Command.new('Timelapse Camera Model (Model B)') { 
                ValeDesignSuite::TimelapseObserver.running? ? ValeDesignSuite::TimelapseObserver.stop : ValeDesignSuite::TimelapseObserver.start 
            }
            cmd.set_validation_proc { 
                ValeDesignSuite::TimelapseObserver.running? ? MF_CHECKED : MF_UNCHECKED 
            }
            cmd.tooltip = "Camera model that monitors your work model for timelapse"
            cmd.status_bar_text = "Start/stop timelapse camera (Model B)"
            
            UI.menu('Extensions').add_item(cmd)
            
            # Clean stop on quit
            Sketchup.add_observer(
                Class.new(Sketchup::AppObserver) {
                    def onQuit
                        ValeDesignSuite::TimelapseObserver.stop
                    end
                }.new
            )
            
            file_loaded(__FILE__)
        end

    # endregion -------------------------------------------------------------------

  end # TimelapseObserver
end # ValeDesignSuite