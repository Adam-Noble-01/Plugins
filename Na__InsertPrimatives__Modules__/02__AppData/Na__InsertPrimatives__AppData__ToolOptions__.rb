# =============================================================================
# NA INSERT PRIMATIVES - TOOL OPTIONS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppData__ToolOptions__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Per-tool toggleable options, persisted, and the data the popup submenu renders from
# CREATED    : 2026
#
# DESCRIPTION:
# - The right-click popup lists every tool in the plugin, and a tool with three
#   or four options of its own would either bloat that list for everybody or
#   need a second dialog nobody would find. So options are declared HERE,
#   against the mode key of the tool that owns them, and the popup renders them
#   as an indented block under the ACTIVE tool's button only. A tool that is
#   not running contributes nothing to the menu's height.
# - Adding an option to any tool is one entry in NA_TOOL_OPTIONS. Nothing in
#   the popup, the callbacks or the tools needs to learn about it: the menu
#   builds itself from this table and the toggle callback is generic.
# - State persists through Sketchup.write_default, in the same registry section
#   as the snap grid and the segment count, so an option survives a restart the
#   way every other drawn-tool preference does.
#
# OPTION FIELDS:
#   :id       Stable string the popup and the callbacks pass around
#   :mode     Filled in automatically from the table key
#   :key      Registry key under NA_DRAWN_SETTINGS_SECTION
#   :label    Short caption; the popup appends On / Off
#   :default  Value when nothing has been stored yet
#   :summary  One line for the console banner and the status bar
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Option Declarations
    # -----------------------------------------------------------------------------

    NA_TOOL_OPTIONS = {

        :drawn_volume => [
            {
                :id      => 'volume_subtract',
                :key     => 'VolumeSubtractEnabled',
                :label   => 'Subtraction',
                :default => false,
                :summary => 'Cut the drawn box out of a solid instead of placing it'
            },
            {
                :id      => 'volume_transparent',
                :key     => 'VolumeTransparentEnabled',
                :label   => 'Transparent',
                :default => false,
                :summary => 'Paint the new group container with MAT011 ModelingUtility Transparent'
            }
        ]

    }.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Declaration Lookup
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Option Declared Against a Tool's Mode Key
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Definitions(mode_key)
        return [] unless mode_key

        NA_TOOL_OPTIONS[mode_key.to_sym] || []
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Declaration Behind an Option Id, Whichever Tool Owns It
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Find(option_id)
        wanted = option_id.to_s
        return nil if wanted.empty?

        NA_TOOL_OPTIONS.each do |mode_key, options|
            found = options.find { |option| option[:id] == wanted }
            return found.merge(:mode => mode_key) if found
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Persisted State
    # -----------------------------------------------------------------------------

    # FUNCTION | In-Memory Cache of Every Option Read This Session
    # Sketchup.read_default is a native call and the tools ask for these on every
    # commit, so the answer is held once rather than fetched per shape.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Cache
        @na_tool_option_cache ||= {}
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Option Switched On?
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Enabled?(option_id)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return false unless definition

        cache = Na__InsertPrimatives.Na__ToolOptions__Cache
        key   = definition[:id]
        return cache[key] if cache.key?(key)

        stored     = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, definition[:key], definition[:default])
        cache[key] = (stored == true || stored == 'true' || stored == 1)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Switch an Option On or Off
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Set(option_id, enabled)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return false unless definition

        state = (enabled ? true : false)
        Na__InsertPrimatives.Na__ToolOptions__Cache[definition[:id]] = state
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, definition[:key], state)
        state
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Flip an Option and Hand Back Its New State
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Toggle(option_id)
        Na__InsertPrimatives.Na__ToolOptions__Set(
            option_id,
            !Na__InsertPrimatives.Na__ToolOptions__Enabled?(option_id)
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Display
    # -----------------------------------------------------------------------------

    # FUNCTION | The Caption a Toggle Button Carries
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Caption(definition, enabled)
        "#{definition[:label]}: #{enabled ? 'On' : 'Off'}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Caption for an Option Id Alone
    # ------------------------------------------------------------
    def self.Na__ToolOptions__CaptionFor(option_id)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return '' unless definition

        Na__InsertPrimatives.Na__ToolOptions__Caption(
            definition,
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(option_id)
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Everything the Popup Needs to Draw One Tool's Submenu
    # Returns [] for a tool with no options, which is what keeps the menu short.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Describe(mode_key)
        Na__InsertPrimatives.Na__ToolOptions__Definitions(mode_key).map do |definition|
            enabled = Na__InsertPrimatives.Na__ToolOptions__Enabled?(definition[:id])

            {
                :id      => definition[:id],
                :label   => definition[:label],
                :caption => Na__InsertPrimatives.Na__ToolOptions__Caption(definition, enabled),
                :enabled => enabled,
                :summary => definition[:summary].to_s
            }
        end
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Short Status Fragment Naming the Options a Tool Has Switched On
    # ------------------------------------------------------------
    def self.Na__ToolOptions__ActiveSummary(mode_key)
        active = Na__InsertPrimatives.Na__ToolOptions__Definitions(mode_key).select do |definition|
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(definition[:id])
        end

        return '' if active.empty?

        " | #{active.map { |definition| definition[:label].upcase }.join('+')}"
    rescue StandardError
        ''
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF TOOL OPTIONS
# =============================================================================
