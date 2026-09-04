# =============================================================================
# NA INSERT PRIMATIVES - APPCONFIG LOADER
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppData__ConfigLoader__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Load and write the global plugin config JSON; gate diagnostic console output
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__InsertPrimatives

    @na_app_config = nil

    NA_CONFIG_ROOT_KEY          = 'Na__InsertPrimatives__AppConfig'.freeze
    NA_DEV_MODE_SECTION_KEY     = 'Na__DevMode__Config'.freeze
    NA_DEV_MODE_ENABLED_KEY     = 'Na__DevMode__Enabled'.freeze

    # -----------------------------------------------------------------------------
    # REGION | Config Load
    # -----------------------------------------------------------------------------

    # FUNCTION | Absolute Path to the Global AppConfig JSON
    # ------------------------------------------------------------
    def self.Na__Config__FilePath
        File.join(__dir__, 'Na__InsertPrimatives__AppConfig__Main.json')
    end
    # ---------------------------------------------------------------


    # FUNCTION | Empty AppConfig Document Body
    # ------------------------------------------------------------
    def self.Na__Config__EmptyBody
        {
            NA_DEV_MODE_SECTION_KEY => {
                NA_DEV_MODE_ENABLED_KEY => false
            }
        }
    end
    # ---------------------------------------------------------------


    # FUNCTION | Normalise Disk JSON into the Cached AppConfig Body
    # Accepts the current Na__InsertPrimatives__AppConfig root, and the older
    # appConfig / camelCase shape so a leftover file still reads.
    # ------------------------------------------------------------
    def self.Na__Config__Normalize(parsed)
        body = Na__InsertPrimatives.Na__Config__EmptyBody
        return body unless parsed.is_a?(Hash)

        root = parsed[NA_CONFIG_ROOT_KEY]
        root = parsed['appConfig'] unless root.is_a?(Hash)
        root = parsed unless root.is_a?(Hash)

        section = root[NA_DEV_MODE_SECTION_KEY]
        section = {} unless section.is_a?(Hash)

        enabled = section[NA_DEV_MODE_ENABLED_KEY]
        enabled = root['devMode'] if enabled.nil?

        body[NA_DEV_MODE_SECTION_KEY][NA_DEV_MODE_ENABLED_KEY] = (enabled == true)
        body
    end
    # ---------------------------------------------------------------


    # FUNCTION | Load and Cache AppConfig
    # ------------------------------------------------------------
    def self.Na__Config__Load
        return @na_app_config if @na_app_config.is_a?(Hash)

        path = Na__InsertPrimatives.Na__Config__FilePath
        unless File.exist?(path)
            @na_app_config = Na__InsertPrimatives.Na__Config__EmptyBody
            return @na_app_config
        end

        parsed = JSON.parse(File.read(path, encoding: 'UTF-8'))
        @na_app_config = Na__InsertPrimatives.Na__Config__Normalize(parsed)
        @na_app_config
    rescue StandardError
        @na_app_config = Na__InsertPrimatives.Na__Config__EmptyBody
        @na_app_config
    end
    # ---------------------------------------------------------------


    # FUNCTION | Drop the Cached Config so the Next Read Hits Disk
    # ------------------------------------------------------------
    def self.Na__Config__Reload
        @na_app_config = nil
        Na__InsertPrimatives.Na__Config__Load
    end
    # ---------------------------------------------------------------


    # FUNCTION | Write the Cached AppConfig Back to Disk
    # ------------------------------------------------------------
    def self.Na__Config__Write
        body = Na__InsertPrimatives.Na__Config__Load
        document = { NA_CONFIG_ROOT_KEY => body }
        json_text = JSON.pretty_generate(document, { :indent => '    ' })
        File.write(
            Na__InsertPrimatives.Na__Config__FilePath,
            json_text + "\n",
            encoding: 'UTF-8'
        )
        true
    rescue StandardError => error
        UI.messagebox("Na Insert Primatives could not write AppConfig:\n\n#{error.message}")
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Dev Mode
    # -----------------------------------------------------------------------------

    # FUNCTION | Is Diagnostic Console Output Enabled?
    # ------------------------------------------------------------
    def self.Na__Config__DevMode?
        config = Na__InsertPrimatives.Na__Config__Load
        section = config[NA_DEV_MODE_SECTION_KEY]
        return false unless section.is_a?(Hash)

        section[NA_DEV_MODE_ENABLED_KEY] == true
    end
    # ---------------------------------------------------------------


    # FUNCTION | Persist Dev Mode and Refresh the In-Memory Cache
    # ------------------------------------------------------------
    def self.Na__Config__SetDevMode(enabled)
        config = Na__InsertPrimatives.Na__Config__Load
        config[NA_DEV_MODE_SECTION_KEY] ||= {}
        config[NA_DEV_MODE_SECTION_KEY][NA_DEV_MODE_ENABLED_KEY] = (enabled == true)
        @na_app_config = config

        return false unless Na__InsertPrimatives.Na__Config__Write

        state = enabled ? 'ON' : 'OFF'
        Sketchup.set_status_text("Na Insert Primatives Dev Mode #{state}", SB_PROMPT)
        Kernel.puts("Na Insert Primatives Dev Mode #{state}") if enabled
        true
    end
    # ---------------------------------------------------------------


    # FUNCTION | Menu Toggle for Dev Mode
    # ------------------------------------------------------------
    def self.Na__Config__ToggleDevMode
        Na__InsertPrimatives.Na__Config__SetDevMode(!Na__InsertPrimatives.Na__Config__DevMode?)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Diagnostic Console
    # -----------------------------------------------------------------------------

    # FUNCTION | Write to the Ruby Console Only When Dev Mode Is On
    # ------------------------------------------------------------
    def self.Na__Debug__Puts(*args)
        return unless Na__InsertPrimatives.Na__Config__DevMode?

        Kernel.puts(*args)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
