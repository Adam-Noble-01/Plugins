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
#   :kind     :toggle (the default when absent), :cycle or :action
#   :key      Registry key under NA_DRAWN_SETTINGS_SECTION (not for :action)
#   :label    Short caption; the popup appends On / Off, or the value's caption
#   :default  Value when nothing has been stored yet
#   :values   :cycle only — the stored strings, in the order a click steps through
#   :captions :cycle only — what each stored value reads as on the button
#   :summary  One line for the console banner and the status bar
#   :status   false keeps a toggle out of the status line's list of options
#             that are on (2D Orbit Lock: on by default, so naming it would
#             add the same words to every line)
#
# THREE KINDS, ONE BUTTON (5.2.0):
#   :toggle   On / Off, green when on. Everything before Deep Scale.
#   :cycle    Steps through :values on each click, like the Snap Grid button,
#             and stays white: a choice between values is not "on".
#   :action   Does something once and stores nothing (Clear Stretch Planes).
#             The tool that owns it does the work in its own
#             Na__DrawnMode__ToggleToolOption override.
#
# DECLARED OPTIONS:
#   Pitched Roof, Hipped Roof   Fascia & Soffit (default ON, shared by both)
#   Plane (click to place)      Face (default ON, shared with the Drawn Plane)
#   Drawn Plane                 Face (default ON), Transparent (default OFF),
#                               2D Orbit Lock (default ON, shared with Volume)
#   Drawn Volume                Subtraction, Transparent (default OFF),
#                               2D Orbit Lock (default ON, shared with Plane)
#   Pipework                    End Caps (default ON), Erase Path,
#                               Internal Diameter (default OFF), Bar on
#                               Selection (default ON)
#   Deep Push/Pull              Joint Surfaces (default ON; SHIFT+TAB)
#   Deep Project                Object Target (default OFF; SHIFT+TAB)
#   Deep Scale                  Handles, Stretch Planes, About Centre,
#                               Dimensions, Dimension Size, Dimension Offset,
#                               Clear Stretch Planes
#   Deep Vertex Move            Visible Only (default OFF), Vertex Size (default
#                               Medium); in 2D views only: Depth Limit (default
#                               Off), Depth Plane
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Option Declarations
    # -----------------------------------------------------------------------------

    # One option shared by both roof tools: declared once and listed under
    # each, so switching Fascia & Soffit off in the Pitched Roof's submenu
    # switches it off for the Hipped Roof too. Find returns the first owner,
    # and the state is keyed by :id, so the two can never disagree.
    NA_TOOL_OPTION_ROOF_FASCIA_SOFFIT = {
        :id      => 'roof_fascia_soffit',
        :key     => 'RoofFasciaSoffitEnabled',
        :label   => 'Fascia & Soffit',
        :default => true,
        :summary => 'Set out the wall line, pull up the fascia, drag out the soffit, then pitch the roof on top'
    }.freeze

    # Face is shared the same way by the click-to-place Plane and the Drawn
    # Plane: one declaration listed under both, on the registry key the old
    # general "Plane Faces" button used, so the two can never disagree about
    # it. DrawnSettings reads and writes it through this table for that reason.
    NA_TOOL_OPTION_PLANE_FACES = {
        :id      => 'plane_faces',
        :key     => 'DrawnPlaneFacesEnabled',
        :label   => 'Face',
        :default => true,
        :summary => 'Build the plane as a face; off leaves the four edges only'
    }.freeze

    # The camera guard both drawing tools share (Camera__ParallelDrawingGuard__,
    # 5.2.12, and its AltGr filter, 5.2.13): one declaration listed under each,
    # so switching it off in one tool's submenu switches it off in the other.
    # On by default, which is why it is kept off the status line; switched
    # off, SketchUp 2027's Ctrl+Alt orbit and pan are back as SketchUp ships them.
    NA_TOOL_OPTION_ORBIT_LOCK = {
        :id      => 'drawn_orbit_lock',
        :key     => 'DrawnOrbitLockEnabled',
        :label   => '2D Orbit Lock',
        :default => true,
        :status  => false,
        :summary => 'In a parallel (2D) view, AltGr / Ctrl+Alt cannot orbit or pan the camera (SketchUp 2027 touchpad gestures); the middle mouse, the Pan tool and the wheel work as ever'
    }.freeze

    NA_TOOL_OPTIONS = {

        :drawn_pitched_roof => [NA_TOOL_OPTION_ROOF_FASCIA_SOFFIT],
        :drawn_hipped_roof  => [NA_TOOL_OPTION_ROOF_FASCIA_SOFFIT],

        :plane       => [NA_TOOL_OPTION_PLANE_FACES],

        :drawn_plane => [
            NA_TOOL_OPTION_PLANE_FACES,
            {
                :id      => 'plane_transparent',
                :key     => 'PlaneTransparentEnabled',
                :label   => 'Transparent',
                :default => false,
                :summary => 'Paint the new group container with MAT011 ModelingUtility Transparent'
            },
            NA_TOOL_OPTION_ORBIT_LOCK
        ],

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
            },
            NA_TOOL_OPTION_ORBIT_LOCK
        ],

        # Read by the Pipework tool when it builds. A resize keeps each pipe's
        # own caps, which it stores with its route.
        :drawn_pipe => [
            {
                :id      => 'pipe_end_caps',
                :key     => 'PipeEndCapsEnabled',
                :label   => 'End Caps',
                :default => true,
                :summary => 'Close the ends of new pipes; off leaves open tubes, for ends hidden in walls'
            },
            {
                :id      => 'pipe_erase_path',
                :key     => 'PipeErasePathEnabled',
                :label   => 'Erase Path',
                :default => false,
                :summary => 'After piping a selection, erase its loose route edges (never an edge bounding a face)'
            },
            {
                :id      => 'pipe_internal_diameter',
                :key     => 'PipeInternalDiameterEnabled',
                :label   => 'Internal Diameter',
                :default => false,
                :summary => 'True pipes with a bore: type it as the 4th value (80,110,24s,70) or 70i; 5w types a wall'
            },
            {
                :id      => 'pipe_auto_bar',
                :key     => 'PipeAutoBarEnabled',
                :label   => 'Bar on Selection',
                :default => true,
                :summary => 'Show the Pipework bar, top left, whenever pipes are selected with the Select tool, or a pipe path is out to edit'
            }
        ],

        # Deep Push/Pull's one switch (5.2.14), also on SHIFT+TAB and a
        # Shortcuts command. On by default, which is why it is kept off the
        # status line (the TAB hint says it instead); off, every face is
        # pushed on its own, as before. The id is NA_JOINT_OPTION, spelt out
        # because the push/pull files load after this table.
        :drawn_push_pull => [
            {
                :id      => 'push_joint_surfaces',
                :key     => 'PushPullJointSurfacesEnabled',
                :label   => 'Joint Surfaces',
                :default => true,
                :status  => false,
                :summary => 'A face on a smoothed surface pushes the whole surface as one, every face along its own normal, ' \
                            'the corners mitred; preselected faces that touch push together (SHIFT+TAB)'
            }
        ],

        # Deep Project's one switch, also on SHIFT+TAB: the same option, so the
        # key and the menu button can never disagree about which mode is on.
        :drawn_project => [
            {
                :id      => 'project_hit_object',
                :key     => 'ProjectObjectTargetEnabled',
                :label   => 'Object Target',
                :default => false,
                :summary => 'Stop where the face first touches the group or component under the cursor, instead of landing on the plane of the face'
            }
        ],

        # Deep Scale's settings are all here so the popup, the on-screen
        # handle bar and the keys read and write ONE copy of each. The bar is
        # one click away while scaling; the popup is where the two dimension
        # settings live, because nobody changes a text size mid-drag.
        :drawn_scale => [
            {
                :id       => 'scale_handles',
                :kind     => :cycle,
                :key      => 'ScaleHandleSet',
                :label    => 'Handles',
                :values   => %w[all faces corners x y z].freeze,
                :captions => {
                    'all'     => 'All',
                    'faces'   => 'Faces (XYZ)',
                    'corners' => 'Corners',
                    'x'       => 'X only',
                    'y'       => 'Y only',
                    'z'       => 'Z only'
                }.freeze,
                :default  => 'all',
                :summary  => 'Which scale grips are shown — one side much thinner than the others is no longer a guess'
            },
            {
                :id      => 'scale_planes',
                :key     => 'ScaleStretchPlanesEnabled',
                :label   => 'Stretch Planes',
                :default => false,
                :summary => 'Grips stretch the object at its cut planes, so frames and details keep their size'
            },
            {
                :id      => 'scale_about_centre',
                :key     => 'ScaleAboutCentreEnabled',
                :label   => 'About Centre',
                :default => false,
                :summary => 'Grips scale both sides at once, about the middle of the object (TAB)'
            },
            {
                :id      => 'scale_dimensions',
                :key     => 'ScaleDimensionsEnabled',
                :label   => 'Dimensions',
                :default => true,
                :summary => 'Show the object size on three edges; click one and type to resize'
            },
            {
                :id       => 'scale_dim_size',
                :kind     => :cycle,
                :key      => 'ScaleDimensionTextSize',
                :label    => 'Dimension Size',
                :values   => %w[11 13 16 20].freeze,
                :captions => { '11' => 'Small', '13' => 'Medium', '16' => 'Large', '20' => 'Extra Large' }.freeze,
                :default  => '13',
                :summary  => 'Text size of the scale dimensions'
            },
            {
                :id       => 'scale_dim_offset',
                :kind     => :cycle,
                :key      => 'ScaleDimensionOffsetPx',
                :label    => 'Dimension Offset',
                :values   => %w[12 24 40 64].freeze,
                :captions => { '12' => '12 px', '24' => '24 px', '40' => '40 px', '64' => '64 px' }.freeze,
                :default  => '24',
                :summary  => 'How far the dimensions stand off the object, on screen'
            },
            {
                :id      => 'scale_clear_planes',
                :kind    => :action,
                :label   => 'Clear Stretch Planes',
                :summary => 'Remove every stretch plane saved with the object being scaled'
            }
        ],

        # Deep Vertex Move: what a box or a click may take. The two depth
        # options are listed only while the camera is in parallel projection
        # (the tool filters them out of its own submenu otherwise), and the
        # plane button's caption is the tool's, naming the plane in force.
        :drawn_vertex_move => [
            {
                :id      => 'vertex_visible_only',
                :key     => 'VertexMoveVisibleOnly',
                :label   => 'Visible Only',
                :default => false,
                :summary => 'A box or a click takes only the vertices the camera can see; ones behind a face are left'
            },
            {
                :id       => 'vertex_dot_size',
                :kind     => :cycle,
                :key      => 'VertexMoveDotSize',
                :label    => 'Vertex Size',
                :values   => %w[small medium large].freeze,
                :captions => { 'small' => 'Small', 'medium' => 'Medium', 'large' => 'Large' }.freeze,
                :default  => 'medium',
                :summary  => 'The base size of the vertex squares; zooming scales it gently either side'
            },
            {
                :id       => 'vertex_depth_limit',
                :kind     => :cycle,
                :key      => 'VertexMoveDepthLimitMm',
                :label    => 'Depth Limit',
                :values   => %w[off 100 150 225 300 450 600 1000].freeze,
                :captions => {
                    'off'  => 'Off',
                    '100'  => '100 mm',
                    '150'  => '150 mm',
                    '225'  => '225 mm',
                    '300'  => '300 mm',
                    '450'  => '450 mm',
                    '600'  => '600 mm',
                    '1000' => '1000 mm'
                }.freeze,
                :default  => 'off',
                :summary  => 'In a 2D view, a box takes only the vertices within this depth behind the first visible plane (or the picked one)'
            },
            {
                :id      => 'vertex_depth_plane',
                :kind    => :action,
                :label   => 'Depth Plane',
                :summary => 'Pick the face the depth is measured from, or clear it to use each box\'s first visible plane'
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

    # FUNCTION | Which of the Three Kinds an Option Is
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Kind(definition)
        return :toggle unless definition

        kind = definition[:kind]
        [:cycle, :action].include?(kind) ? kind : :toggle
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Option Switched On?
    # A cycle or an action is never "on": only a toggle can be green.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Enabled?(option_id)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return false unless definition
        return false unless Na__InsertPrimatives.Na__ToolOptions__Kind(definition) == :toggle

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
        return false unless Na__InsertPrimatives.Na__ToolOptions__Kind(definition) == :toggle

        state = (enabled ? true : false)
        Na__InsertPrimatives.Na__ToolOptions__Cache[definition[:id]] = state
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, definition[:key], state)
        state
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Stored Value of a Cycle Option (a Toggle Answers true / false)
    # A stored value that is no longer one of :values — a value retired from
    # the list, a registry edited by hand — reads as the default rather than
    # as something the buttons cannot show.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Value(option_id)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return nil unless definition

        case Na__InsertPrimatives.Na__ToolOptions__Kind(definition)
        when :toggle then return Na__InsertPrimatives.Na__ToolOptions__Enabled?(option_id)
        when :action then return nil
        end

        cache = Na__InsertPrimatives.Na__ToolOptions__Cache
        key   = definition[:id]
        return cache[key] if cache.key?(key)

        stored     = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, definition[:key], definition[:default]).to_s
        cache[key] = definition[:values].include?(stored) ? stored : definition[:default]
    rescue StandardError
        definition ? definition[:default] : nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Store One of a Cycle Option's Values; Returns the Value Kept
    # ------------------------------------------------------------
    def self.Na__ToolOptions__SetValue(option_id, value)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return nil unless definition
        return Na__InsertPrimatives.Na__ToolOptions__Set(option_id, value) if Na__InsertPrimatives.Na__ToolOptions__Kind(definition) == :toggle
        return nil unless Na__InsertPrimatives.Na__ToolOptions__Kind(definition) == :cycle

        wanted = value.to_s
        return Na__InsertPrimatives.Na__ToolOptions__Value(option_id) unless definition[:values].include?(wanted)

        Na__InsertPrimatives.Na__ToolOptions__Cache[definition[:id]] = wanted
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, definition[:key], wanted)
        wanted
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Flip a Toggle, Step a Cycle; Hand Back the New State
    # An action has no state to change and answers nil — its tool does the work.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Toggle(option_id)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return false unless definition

        case Na__InsertPrimatives.Na__ToolOptions__Kind(definition)
        when :action
            nil
        when :cycle
            values  = definition[:values]
            current = values.index(Na__InsertPrimatives.Na__ToolOptions__Value(option_id)) || -1
            Na__InsertPrimatives.Na__ToolOptions__SetValue(option_id, values[(current + 1) % values.length])
        else
            Na__InsertPrimatives.Na__ToolOptions__Set(
                option_id,
                !Na__InsertPrimatives.Na__ToolOptions__Enabled?(option_id)
            )
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Display
    # -----------------------------------------------------------------------------

    # FUNCTION | The Caption a Button Carries
    # state is the toggle's true / false, or the cycle's stored value.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Caption(definition, state)
        case Na__InsertPrimatives.Na__ToolOptions__Kind(definition)
        when :action
            definition[:label].to_s
        when :cycle
            captions = definition[:captions] || {}
            "#{definition[:label]}: #{captions[state.to_s] || state}"
        else
            "#{definition[:label]}: #{state ? 'On' : 'Off'}"
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Caption for an Option Id Alone
    # ------------------------------------------------------------
    def self.Na__ToolOptions__CaptionFor(option_id)
        definition = Na__InsertPrimatives.Na__ToolOptions__Find(option_id)
        return '' unless definition

        Na__InsertPrimatives.Na__ToolOptions__Caption(
            definition,
            Na__InsertPrimatives.Na__ToolOptions__Value(option_id)
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Everything the Popup Needs to Draw One Tool's Submenu
    # Returns [] for a tool with no options, which is what keeps the menu short.
    # ------------------------------------------------------------
    def self.Na__ToolOptions__Describe(mode_key)
        Na__InsertPrimatives.Na__ToolOptions__Definitions(mode_key).map do |definition|
            enabled = Na__InsertPrimatives.Na__ToolOptions__Enabled?(definition[:id])
            value   = Na__InsertPrimatives.Na__ToolOptions__Value(definition[:id])

            {
                :id      => definition[:id],
                :kind    => Na__InsertPrimatives.Na__ToolOptions__Kind(definition),
                :label   => definition[:label],
                :caption => Na__InsertPrimatives.Na__ToolOptions__Caption(definition, value),
                :enabled => enabled,
                :summary => definition[:summary].to_s
            }
        end
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Short Status Fragment Naming the Options a Tool Has Switched On
    # Toggles only: Deep Scale says its own cycles in its own status line.
    # A toggle declared :status => false is never named (2D Orbit Lock).
    # ------------------------------------------------------------
    def self.Na__ToolOptions__ActiveSummary(mode_key)
        active = Na__InsertPrimatives.Na__ToolOptions__Definitions(mode_key).select do |definition|
            Na__InsertPrimatives.Na__ToolOptions__Kind(definition) == :toggle &&
                definition[:status] != false &&
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
