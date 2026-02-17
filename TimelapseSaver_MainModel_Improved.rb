# =============================================================================
# TIMELAPSE AUTO-SAVE - 3D WORK MODEL SCRIPT
# =============================================================================
#
# FILE       : TimelapseSaver_MainModel_Improved.rb
# MODULE     : ValeDesignSuite::TimelapseSaver
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Auto-saves your work for timelapse recording
# CREATED    : 2025
#
# USAGE:
# - Run this in your main work model (Model A - 3D Work Model)
# - Saves automatically every 10 seconds
# - Detects active tools and postpones saves to avoid interruptions
# - Camera model (Model B) monitors these saves to capture frames
#
# =============================================================================

require 'sketchup.rb'

module ValeDesignSuite
  module TimelapseSaver

    # MODULE CONSTANTS | Configuration Settings
    # ------------------------------------------------------------
    SAVE_INTERVAL           =   10.0                                             # <-- Seconds between saves
    TOOL_CHECK_DELAY        =   1.0                                              # <-- Delay to recheck if tool active
    MAX_POSTPONE_TIME       =   30.0                                             # <-- Max time to postpone a save
    FADE_DURATION           =   2.0                                              # <-- Status message fade time
    ENABLE_TOOL_CHECK       =   true                                             # <-- Enable/disable tool checking
    # ------------------------------------------------------------

    @@timer                 =   nil                                              # <-- Timer reference
    @@save_count            =   0                                                # <-- Save counter for status
    @@save_pending          =   false                                            # <-- Save waiting for tool completion
    @@postpone_start        =   nil                                              # <-- When postponement started
    @@last_save_time        =   Time.now                                         # <-- Track save timing
    @@status_timer          =   nil                                              # <-- Status bar update timer
    @@tool_observer         =   nil                                              # <-- Tool state observer
    
    # -----------------------------------------------------------------------------
    # REGION | Tool Detection Functions
    # -----------------------------------------------------------------------------

        # FUNCTION | Check if Any Tool is Active
        # ------------------------------------------------------------
        def self.tool_active?
            model = Sketchup.active_model
            tools = model.tools
            
            # Check if we're not in select tool (default)
            # The active_tool_id returns 0 for select tool, non-zero for other tools
            active_tool = tools.active_tool_id
            
            # Return true if any tool is active (not select tool)
            # 21022 is select tool ID, 0 is also select tool
            return (active_tool != 0 && active_tool != 21022)
        end
        # ------------------------------------------------------------

        # CLASS | Tool State Observer
        # ------------------------------------------------------------
        class ToolStateObserver < Sketchup::ToolsObserver
            def onActiveToolChanged(tools, tool_name, tool_id)
                # When tool changes, check if we have pending saves
                if !ValeDesignSuite::TimelapseSaver.tool_active? && ValeDesignSuite::TimelapseSaver.save_pending?
                    ValeDesignSuite::TimelapseSaver.process_pending_save
                end
            end
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Status Feedback Functions
    # -----------------------------------------------------------------------------

        # FUNCTION | Update Status Bar with Fade Effect
        # ------------------------------------------------------------
        def self.update_status(message, fade = true)
            Sketchup.status_text = message                                       # <-- Set status text
            
            # Cancel existing fade timer
            if @@status_timer
                UI.stop_timer(@@status_timer)
                @@status_timer = nil
            end
            
            # Start fade timer if requested
            if fade
                @@status_timer = UI.start_timer(FADE_DURATION, false) {
                    Sketchup.status_text = ""                                    # <-- Clear after fade
                    @@status_timer = nil
                }
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Show Save Progress Indicator
        # ------------------------------------------------------------
        def self.show_save_feedback
            # Subtle visual feedback during save
            update_status("📸 Timelapse frame #{@@save_count + 1} saved", true)
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Save Management Functions
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check if Save is Pending
        # ------------------------------------------------------------
        def self.save_pending?
            @@save_pending                                                       # <-- Return pending state
        end
        # ------------------------------------------------------------

        # FUNCTION | Process Pending Save
        # ------------------------------------------------------------
        def self.process_pending_save
            return unless @@save_pending                                         # <-- Exit if no pending save
            
            @@save_pending = false                                               # <-- Clear pending flag
            @@postpone_start = nil                                               # <-- Clear postpone timer
            
            save_model                                                           # <-- Execute the save
        end
        # ------------------------------------------------------------

        # FUNCTION | Smart Save with Tool Detection
        # ------------------------------------------------------------
        def self.smart_save
            puts "[TimelapseSaver] Timer triggered - checking for save..."
            
            # Check if tool detection is enabled and tool is active
            if ENABLE_TOOL_CHECK && tool_active?
                unless @@save_pending
                    @@save_pending = true                                        # <-- Mark save as pending
                    @@postpone_start = Time.now                                  # <-- Start postpone timer
                    update_status("⏸ Timelapse save postponed (tool active)", false)
                end
                
                # Check if we've been postponing too long
                if @@postpone_start && (Time.now - @@postpone_start) > MAX_POSTPONE_TIME
                    # Force save after max postpone time
                    update_status("⚠️ Forcing timelapse save (max postpone reached)", true)
                    @@save_pending = false
                    @@postpone_start = nil
                    save_model
                else
                    # Recheck soon
                    UI.start_timer(TOOL_CHECK_DELAY, false) { smart_save }      # <-- Retry after delay
                end
            else
                # Tool not active, safe to save
                puts "[TimelapseSaver] No tool active - proceeding with save"
                if @@save_pending
                    process_pending_save                                         # <-- Process pending save
                else
                    save_model                                                   # <-- Normal save
                end
            end
        end
        # ------------------------------------------------------------

        # SUB FUNCTION | Save the Model with Minimal Impact
        # ------------------------------------------------------------
        def self.save_model
            model = Sketchup.active_model
            return unless model.path && !model.path.empty?                      # <-- Skip if no path
            
            begin
                # Track timing for performance monitoring
                start_time = Time.now
                
                # Perform save
                puts "[TimelapseSaver] Saving model..."
                success = model.save                                             # <-- Save the model
                puts "[TimelapseSaver] Save result: #{success}"
                
                # Update counters and timing
                save_duration = Time.now - start_time
                @@save_count += 1                                                # <-- Increment counter
                @@last_save_time = Time.now                                      # <-- Update last save time
                
                # Show feedback
                show_save_feedback                                               # <-- Visual feedback
                puts "[TimelapseSaver] Save #{@@save_count} completed in #{save_duration.round(3)}s"
                
                # Performance warning if save took too long
                if save_duration > 1.0
                    puts "[TimelapseSaver] WARNING: Save took #{save_duration.round(2)}s"
                end
                
                # Subtle console update every 6 saves
                if @@save_count % 6 == 0
                    puts "[TimelapseSaver] #{@@save_count} frames | Avg interval: #{average_interval}s"
                end
                
            rescue => e
                puts "[TimelapseSaver] ERROR: #{e.message}"
                update_status("❌ Timelapse save failed: #{e.message}", true)
                stop                                                             # <-- Stop on error
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Calculate Average Save Interval
        # ------------------------------------------------------------
        def self.average_interval
            return SAVE_INTERVAL if @@save_count < 2
            total_time = Time.now - @start_time
            (total_time / @@save_count).round(1)
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Timer Control Functions
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check if Timer is Running
        # ------------------------------------------------------------
        def self.running?
            !@@timer.nil?                                                        # <-- Return true if timer exists
        end
        # ------------------------------------------------------------

        # FUNCTION | Start Auto-Save Timer with Smart Detection
        # ------------------------------------------------------------
        def self.start
            return if running?                                                   # <-- Exit if already running
            
            model = Sketchup.active_model
            unless model.path && !model.path.empty?
                UI.messagebox("Please save your model first before starting timelapse.")
                return
            end
            
            # Initialize tracking
            @@save_count = 0                                                     # <-- Reset counter
            @@save_pending = false                                               # <-- Clear pending flag
            @start_time = Time.now                                               # <-- Track start time
            
            # Set up tool observer if enabled
            if ENABLE_TOOL_CHECK
                @@tool_observer = ToolStateObserver.new
                model.tools.add_observer(@@tool_observer)                        # <-- Watch for tool changes
            end
            
            # Start timer with smart save
            @@timer = UI.start_timer(SAVE_INTERVAL, true) { smart_save }        # <-- Start timer
            
            puts "\n[TimelapseSaver] Started - saving every #{SAVE_INTERVAL}s"
            puts "[TimelapseSaver] Model: #{File.basename(model.path)}"
            puts "[TimelapseSaver] Tool detection: #{ENABLE_TOOL_CHECK ? 'ENABLED' : 'DISABLED'}"
            
            update_status("🎬 Timelapse started - Smart save enabled", true)
            
            UI.messagebox(
                "Timelapse Auto-Save Started! (Model A)\n\n" +
                "This is your 3D Work Model\n" +
                "✓ Auto-saves every #{SAVE_INTERVAL} seconds\n" +
                (ENABLE_TOOL_CHECK ? "✓ Tool detection enabled\n" : "✗ Tool detection disabled (saves always happen)\n") +
                "✓ Status updates in bottom bar\n\n" +
                "To record timelapse:\n" +
                "1. Open another SketchUp instance\n" +
                "2. Run 'Timelapse Camera Model (Model B)'\n" +
                "3. Select this file to monitor"
            )
        end
        # ------------------------------------------------------------

        # FUNCTION | Stop Auto-Save Timer
        # ------------------------------------------------------------
        def self.stop
            return unless running?                                               # <-- Exit if not running
            
            UI.stop_timer(@@timer)                                               # <-- Stop the timer
            @@timer = nil                                                        # <-- Clear timer reference
            
            # Remove tool observer if it exists
            if @@tool_observer && ENABLE_TOOL_CHECK
                begin
                    Sketchup.active_model.tools.remove_observer(@@tool_observer)
                rescue => e
                    puts "[TimelapseSaver] Error removing observer: #{e.message}"
                end
                @@tool_observer = nil
            end
            
            # Clear status timer
            if @@status_timer
                UI.stop_timer(@@status_timer)
                @@status_timer = nil
            end
            
            duration = Time.now - @start_time rescue 0
            mins = (duration / 60).floor
            secs = (duration % 60).floor
            
            puts "\n[TimelapseSaver] Stopped after #{@@save_count} saves"
            puts "[TimelapseSaver] Total time: #{mins}m #{secs}s"
            
            update_status("🛑 Timelapse stopped - #{@@save_count} frames captured", true)
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Progressive Saving Research
    # -----------------------------------------------------------------------------

        # NOTE: SketchUp Ruby API Limitations
        # ------------------------------------------------------------
        # The SketchUp Ruby API (as of 2025) does not provide:
        # 1. Incremental/differential save functionality
        # 2. Access to undo/redo stack for custom serialization
        # 3. Direct access to model change deltas
        # 4. Streaming save capabilities
        #
        # The model.save method always performs a complete save.
        # 
        # Potential workarounds (not implemented):
        # - Track entity changes manually (complex, error-prone)
        # - Use external diff tools on .skp files (requires unpacking)
        # - Implement custom serialization (loses SketchUp features)
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Menu Integration
    # -----------------------------------------------------------------------------

        unless file_loaded?(__FILE__)
            # Create menu command
            cmd = UI::Command.new('Timelapse Auto-Save (Model A)') { 
                ValeDesignSuite::TimelapseSaver.running? ? ValeDesignSuite::TimelapseSaver.stop : ValeDesignSuite::TimelapseSaver.start 
            }
            cmd.set_validation_proc { 
                ValeDesignSuite::TimelapseSaver.running? ? MF_CHECKED : MF_UNCHECKED 
            }
            cmd.tooltip = "Auto-save your 3D work model for timelapse recording"
            cmd.status_bar_text = "Start/stop timelapse auto-save (Model A - Work Model)"
            
            UI.menu('Extensions').add_item(cmd)
            
            # Stop cleanly on quit
            Sketchup.add_observer(
                Class.new(Sketchup::AppObserver) {
                    def onQuit
                        ValeDesignSuite::TimelapseSaver.stop
                    end
                }.new
            )
            
            file_loaded(__FILE__)
        end

    # endregion -------------------------------------------------------------------

  end # TimelapseSaver
end # ValeDesignSuite