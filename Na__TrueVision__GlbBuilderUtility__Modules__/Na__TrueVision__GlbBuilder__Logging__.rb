# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - LOGGING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__Logging__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Logging (Buffered TXT Log + Conditional Console Output)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Replaces per-call Ruby Console puts with a session-scoped
#              buffered log that writes to a TXT file beside the GLB outputs.
#              Console output is gated by a config flag (default OFF) to
#              eliminate the major export speed penalty from Sketchup::Console.
# CREATED    : 25-May-2026
#
# DESCRIPTION:
# - Na__Log__OpenSession  : Opens a timestamped TXT file in the export folder,
#                           writes a session header. Config flags are read from
#                           Na__ExportConfig__Logging* helpers on Main__.rb.
# - Na__Log__Puts         : Appends to the TXT file (when TextFileEnabled).
#                           Echoes to Ruby Console only when ConsoleVerbose.
#                           No-ops cleanly before a session is open.
# - Na__Log__Warn         : Always writes to both TXT and Ruby Console.
#                           Use for WARNING / ERROR lines that must stay visible.
# - Na__Log__CloseSession : Flushes and closes the file, writes a footer with
#                           wall-time. Returns the resolved log path string.
#
# DEPENDENCIES:
# - Na__TrueVision__GlbBuilder__Main__.rb must be loaded first so the
#   Na__ExportConfig__Logging* helper methods are available.
#
# DEVELOPMENT LOG:
# 25-May-2026 - Version 1.0.0
# - Initial implementation as part of v2.3.0 logging overhaul.
#
# =============================================================================

require 'fileutils'

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        # MODULE VARIABLES | Active Session State
        # ------------------------------------------------------------
        @na_log_file            = nil                                         # <-- Open File handle (nil = no session)
        @na_log_file_path       = nil                                         # <-- Resolved path of the current log file
        @na_log_session_start   = nil                                         # <-- Time.now at OpenSession
        @na_log_console_verbose = false                                       # <-- Cached console-verbose flag for session
        @na_log_text_enabled    = true                                        # <-- Cached text-file-enabled flag for session
        # ------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Session Lifecycle
    # -------------------------------------------------------------------------

        # FUNCTION | Open Log Session
        # ---------------------------------------------------------------
        # Resolves the configured filename pattern (expands %TIMESTAMP%),
        # opens the file in the export folder for write, caches config flags
        # for this session, and writes a header banner.
        #
        # Silently no-ops if TextFileEnabled is false.
        #
        # @param export_dir [String] The directory the GLBs will be written to.
        # ---------------------------------------------------------------
        def self.Na__Log__OpenSession(export_dir)
            @na_log_console_verbose = self.Na__ExportConfig__LoggingConsoleVerbose
            @na_log_text_enabled    = self.Na__ExportConfig__LoggingTextFileEnabled

            if @na_log_text_enabled
                begin
                    timestamp   = Time.now.strftime("%Y-%m-%d_%H%M%S")
                    pattern     = self.Na__ExportConfig__LoggingTextFileNamePattern
                    filename    = pattern.gsub("%TIMESTAMP%", timestamp)
                    @na_log_file_path = File.join(export_dir, filename)

                    FileUtils.mkdir_p(export_dir) unless Dir.exist?(export_dir)
                    @na_log_file = File.open(@na_log_file_path, "w:UTF-8")

                    model_name = Sketchup.active_model ? (Sketchup.active_model.path.empty? ? "Unsaved Model" : File.basename(Sketchup.active_model.path)) : "Unknown Model"

                    @na_log_file.puts "==============================================================================="
                    @na_log_file.puts " TrueVision3D GLB Builder - Export Log"
                    @na_log_file.puts "==============================================================================="
                    @na_log_file.puts " Model      : #{model_name}"
                    @na_log_file.puts " Export dir : #{export_dir}"
                    @na_log_file.puts " Timestamp  : #{timestamp}"
                    @na_log_file.puts " Console    : #{@na_log_console_verbose ? 'verbose (ON)' : 'suppressed (OFF)'}"
                    @na_log_file.puts "-------------------------------------------------------------------------------"
                    @na_log_file.flush
                rescue => e
                    puts "[Na__Log] WARNING: Could not open log file: #{e.message}"
                    @na_log_file      = nil
                    @na_log_file_path = nil
                end
            end

            @na_log_session_start = Time.now
        end
        # ---------------------------------------------------------------

        # FUNCTION | Close Log Session
        # ---------------------------------------------------------------
        # Writes a footer (elapsed time), flushes and closes the file.
        # Returns the resolved log file path, or nil if no session was open.
        # Safe to call even when no session is open (no-op).
        # ---------------------------------------------------------------
        def self.Na__Log__CloseSession
            resolved_path = @na_log_file_path

            if @na_log_file
                begin
                    elapsed_s = @na_log_session_start ? (Time.now - @na_log_session_start).round(2) : "?"
                    @na_log_file.puts "-------------------------------------------------------------------------------"
                    @na_log_file.puts " Export complete. Elapsed: #{elapsed_s}s"
                    @na_log_file.puts "==============================================================================="
                    @na_log_file.flush
                    @na_log_file.close
                rescue => e
                    puts "[Na__Log] WARNING: Error closing log file: #{e.message}"
                ensure
                    @na_log_file = nil
                end
            end

            @na_log_file_path     = nil
            @na_log_session_start = nil

            resolved_path
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------



    # -------------------------------------------------------------------------
    # REGION | Message Writers
    # -------------------------------------------------------------------------

        # FUNCTION | Write a Standard Log Message
        # ---------------------------------------------------------------
        # Appends to the open TXT log when TextFileEnabled.
        # Echoes to Ruby Console only when ConsoleVerbose is true.
        # No-ops cleanly before Na__Log__OpenSession is called.
        #
        # @param message [String] The message to record.
        # ---------------------------------------------------------------
        def self.Na__Log__Puts(message)
            @na_log_file.puts(message) if @na_log_file
            puts message if @na_log_console_verbose
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write a Warning or Error Message (Always Visible)
        # ---------------------------------------------------------------
        # Writes to BOTH the TXT log AND the Ruby Console unconditionally.
        # Use for lines that must remain visible regardless of ConsoleVerbose.
        # Safe to call before a session is open (console only in that case).
        #
        # @param message [String] The warning or error message.
        # ---------------------------------------------------------------
        def self.Na__Log__Warn(message)
            @na_log_file.puts(message) if @na_log_file
            puts message
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
