# =============================================================================
# NA DATALIB - LOCAL FALLBACK
# =============================================================================
#
# FILE       : Na__DataLib__LocalFallback__.rb
# NAMESPACE  : Na__DataLib__LocalFallback
# MODULE     : Na__DataLib__LocalFallback
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Last-resort loader from local plugins folder with user notification
# CREATED    : 15-Mar-2026
#
# DESCRIPTION:
# - Reads JSON data files from the local Na__Common__DataLib__CoreSuEntityStandards
#   folder when the web URL fetch and temp cache have both failed.
# - Prints a console warning for every fallback load.
# - Shows a one-time UI notification per SketchUp session so the user knows
#   that local files are being used because web data could not be retrieved.
# - Returns the parsed Ruby Hash on success, nil if the local file is missing.
#
# =============================================================================

require 'json'

require_relative 'Na__DataLib__UrlGenerator__'

module Na__DataLib__LocalFallback

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

    # MODULE VARIABLES | Session Notification Flag
    # ------------------------------------------------------------
    @na_fallback_notified = false
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Load Data from Local File with User Notification
    # ------------------------------------------------------------
    def self.Na__Fallback__LoadLocal(file_key)
        filename = Na__DataLib__UrlGenerator.Na__Url__FileNameForKey(file_key)
        unless filename
            puts "    [Na__DataLib__Fallback] Unknown file_key: #{file_key.inspect}"
            return nil
        end

        local_path = File.join(File.dirname(__FILE__), filename)

        unless File.exist?(local_path)
            puts "    [Na__DataLib__Fallback] Local file not found: #{local_path}"
            return nil
        end

        begin
            raw    = File.read(local_path, encoding: 'UTF-8')
            parsed = JSON.parse(raw)

            puts "    [Na__DataLib__Fallback] WARNING: Using local fallback for :#{file_key} - web data unavailable"

            Na__Fallback__NotifyUserOnce

            parsed

        rescue => e
            puts "    [Na__DataLib__Fallback] Failed to parse local file for :#{file_key}: #{e.message}"
            nil
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | User Notification
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Show One-Time Fallback Notification
    # ---------------------------------------------------------------
    def self.Na__Fallback__NotifyUserOnce
        return if @na_fallback_notified

        @na_fallback_notified = true

        puts "    [Na__DataLib__Fallback] ============================================"
        puts "    [Na__DataLib__Fallback] NOTICE: Web data files could not be retrieved."
        puts "    [Na__DataLib__Fallback] Using local plugin folder copies instead."
        puts "    [Na__DataLib__Fallback] Data may not reflect the latest updates."
        puts "    [Na__DataLib__Fallback] ============================================"

        UI.messagebox(
            "Noble Architecture Data Library\n\n" \
            "Web data files could not be retrieved.\n" \
            "Using local copies from the plugins folder.\n\n" \
            "Data may not reflect the latest updates.\n" \
            "Check your internet connection and restart SketchUp to retry.",
            MB_OK
        )
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Reset Notification Flag (for testing)
    # ---------------------------------------------------------------
    def self.Na__Fallback__ResetNotification
        @na_fallback_notified = false
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DataLib__LocalFallback

# =============================================================================
# END OF FILE
# =============================================================================
