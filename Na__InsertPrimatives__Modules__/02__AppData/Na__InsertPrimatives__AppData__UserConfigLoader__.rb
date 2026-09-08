# =============================================================================
# NA INSERT PRIMATIVES - USERCONFIG LOADER
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppData__UserConfigLoader__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Load and write the per-user config JSON (menu placement and sizing)
# CREATED    : 2026
#
# DESCRIPTION:
# - AppConfig (Na__InsertPrimatives__AppConfig__Main.json) carries the plugin's
#   own switches, such as Dev Mode. This file owns the OTHER document — what
#   this user has arranged to suit their own hands: where the right-click menu
#   sits, how big they made it. Two files because the two change for two
#   different reasons, and a window position has no business in a diff of the
#   plugin's settings.
# - Keys follow the three-stage Na__Domain__Name style all the way down, and
#   every read is answered over the defaults below, so a hand-edited or
#   half-written file never hands back nil where a number was expected.
# - Unknown keys found on disk are carried through a write untouched, so a
#   newer build's settings survive being opened by an older one.
#
# =============================================================================

require 'json'

module Na__InsertPrimatives

    @na_user_config = nil

    NA_USER_CONFIG_ROOT_KEY  = 'Na__InsertPrimatives__UserConfig'.freeze
    NA_USER_CONFIG_FILE_NAME = 'Na__InsertPrimatives__UserConfig__Main.json'.freeze

    # -----------------------------------------------------------------------------
    # REGION | Defaults
    # -----------------------------------------------------------------------------

    # FUNCTION | The Complete Default UserConfig Body
    # A fresh Hash on every call, so a caller mutating the cache can never
    # mutate the defaults underneath it.
    # ------------------------------------------------------------
    def self.Na__UserConfig__Defaults
        {
            'Na__RightClickMenu__Config' => {
                'Na__RightClickMenu__AnchorMode' => 'anchored',
                'Na__RightClickMenu__Position'   => {
                    'Na__Position__X' => nil,
                    'Na__Position__Y' => nil
                },
                'Na__RightClickMenu__Size'       => {
                    'Na__Size__Width'  => 216,
                    'Na__Size__Height' => nil
                }
            }
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Lay a Disk Document Over the Defaults, Nested Hash by Nested Hash
    # ------------------------------------------------------------
    def self.Na__UserConfig__DeepMerge(base, overlay)
        return base unless overlay.is_a?(Hash)

        merged = {}

        base.each do |key, value|
            incoming = overlay[key]

            merged[key] =
                if value.is_a?(Hash) && incoming.is_a?(Hash)
                    Na__InsertPrimatives.Na__UserConfig__DeepMerge(value, incoming)
                elsif overlay.key?(key)
                    incoming
                else
                    value
                end
        end

        overlay.each do |key, value|
            merged[key] = value unless merged.key?(key)                       # <-- Keys this build does not know survive the round trip
        end

        merged
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Config Load and Write
    # -----------------------------------------------------------------------------

    # FUNCTION | Absolute Path to the UserConfig JSON
    # ------------------------------------------------------------
    def self.Na__UserConfig__FilePath
        File.join(__dir__, NA_USER_CONFIG_FILE_NAME)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Load and Cache UserConfig, Merged Over the Defaults
    # ------------------------------------------------------------
    def self.Na__UserConfig__Load
        return @na_user_config if @na_user_config.is_a?(Hash)

        defaults = Na__InsertPrimatives.Na__UserConfig__Defaults
        path     = Na__InsertPrimatives.Na__UserConfig__FilePath

        unless File.exist?(path)
            @na_user_config = defaults
            return @na_user_config
        end

        parsed = JSON.parse(File.read(path, encoding: 'UTF-8'))
        body   = parsed.is_a?(Hash) ? parsed[NA_USER_CONFIG_ROOT_KEY] : nil

        @na_user_config = Na__InsertPrimatives.Na__UserConfig__DeepMerge(defaults, body)
        @na_user_config
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA USERCONFIG: could not read #{NA_USER_CONFIG_FILE_NAME} — #{error.message}"
        @na_user_config = Na__InsertPrimatives.Na__UserConfig__Defaults
        @na_user_config
    end
    # ---------------------------------------------------------------


    # FUNCTION | Drop the Cached Config so the Next Read Hits Disk
    # ------------------------------------------------------------
    def self.Na__UserConfig__Reload
        @na_user_config = nil
        Na__InsertPrimatives.Na__UserConfig__Load
    end
    # ---------------------------------------------------------------


    # FUNCTION | Write the Cached UserConfig Back to Disk
    # A failure here is reported to the console rather than in a message box:
    # this file is written on every popup close, and a locked file must not
    # interrupt the user's modelling with a dialog each time.
    # ------------------------------------------------------------
    def self.Na__UserConfig__Write
        body      = Na__InsertPrimatives.Na__UserConfig__Load
        document  = { NA_USER_CONFIG_ROOT_KEY => body }
        json_text = JSON.pretty_generate(document, { :indent => '    ' })

        File.write(
            Na__InsertPrimatives.Na__UserConfig__FilePath,
            json_text + "\n",
            encoding: 'UTF-8'
        )
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA USERCONFIG: could not write #{NA_USER_CONFIG_FILE_NAME} — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Nested Access
    # -----------------------------------------------------------------------------

    # FUNCTION | Read a Nested Value by Key Path
    # Na__UserConfig__Get('Na__RightClickMenu__Config', 'Na__RightClickMenu__AnchorMode')
    # Returns nil for any path the document does not carry.
    # ------------------------------------------------------------
    def self.Na__UserConfig__Get(*keys)
        node = Na__InsertPrimatives.Na__UserConfig__Load

        keys.each do |key|
            return nil unless node.is_a?(Hash)
            node = node[key]
        end

        node
    end
    # ---------------------------------------------------------------


    # FUNCTION | Set a Nested Value by Key Path, Creating the Path, and Write
    # ------------------------------------------------------------
    def self.Na__UserConfig__Set(value, *keys)
        return false if keys.empty?

        node = Na__InsertPrimatives.Na__UserConfig__Load

        keys[0..-2].each do |key|
            node[key] = {} unless node[key].is_a?(Hash)
            node = node[key]
        end

        node[keys[-1]] = value
        Na__InsertPrimatives.Na__UserConfig__Write
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
