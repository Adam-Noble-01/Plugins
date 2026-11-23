# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - DEFAULTS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__Defaults__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__Defaults
# AUTHOR     : Noble Architecture
# PURPOSE    : Every constant the Assembly Run Studio shares: ARN ids,
#              dictionary keys, the configuration keys, the kinds of span,
#              column and corner, and the default configuration of each mode.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# THE WORDS (Adam, 16-Nov-2026)
# - Run        : one master component holding a path and everything set out
#                along it: a conservatory's framework, a row of door sets, an
#                L-shaped kitchen, a wall of wardrobes.
# - Leg        : one straight stretch of the path, corner to corner.
# - Span       : a place on a leg that holds a panel: a window, a door set, a
#                bifold, a cabinet.
# - Panel type : the element a span holds, by code (A, B, C ...). Every span
#                of type A is an instance of ONE element definition, so
#                changing one type A changes them all.
# - Column     : what stands between spans: a fused mullion, an infill block,
#                a library column, or a gap.
# - Corner     : what stands where two legs meet.
#
# THE TWO MODES
# - Frames     : windows and exterior doors (casement, sash, single, double,
#                bifold, sliding). The path is the FRAMEWORK FACE, the outside
#                face of the frames; the outside is on the RIGHT of the path.
# - Cabinets   : fitted units (base, drawers, wall, tall, wardrobe). The path
#                is the WALL LINE; the room is on the RIGHT of the path.
#   In both, a span's element stands with its own X along the leg, so the
#   element frames the Windows and Cabinetry tabs already use apply unchanged.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__Defaults

# -----------------------------------------------------------------------------
# REGION | ARN Run Id System
# -----------------------------------------------------------------------------

        NA_RUN_ID_PREFIX            = "ARN".freeze                               # <-- Assembly RuN (AWN windows, ADR doors, ACB cabinets)
        NA_RUN_ID_REGEX_SOURCE      = '^ARN\d{3}$'.freeze
        NA_RUN_ID_FORMAT            = "ARN%03d".freeze
        NA_NAME_TYPE_TAG            = "AssemblyRun".freeze                       # <-- Component name head: ARN001__AssemblyRun__

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dictionary Keys
# -----------------------------------------------------------------------------

        NA_INFO_DICT                = "Na__AssemblyRunConfiguratorInfo".freeze   # <-- On the run's ComponentInstance
        NA_KEY_RUN_ID               = "RunID".freeze
        NA_DEF_DICT_PREFIX          = "Na__AssemblyRunConfigurator_".freeze      # <-- On the run's ComponentDefinition, + id
        NA_KEY_METADATA             = "Na__AssemblyRunMetadata".freeze
        NA_KEY_COMPONENTS           = "Na__AssemblyRunComponents".freeze
        NA_KEY_CONFIGURATION        = "Na__AssemblyRunConfiguration".freeze
        NA_CONFIG_KEY_PREFIX        = "Na__RunConfig__".freeze

        # Sent with a draft by the tab's Create, never stored (V2.7.2). A
        # path measured in the model gives a new run its placement and its
        # path. The tab then holds that path in its draft, where it can be
        # turned inside out or have a leg's length typed. "page" says the
        # draft's path is that measured path as the tab now holds it, so
        # Create takes the placement from the measurement and the path from
        # the draft. Without it the draft describes some other run (one
        # loaded from the model), and the measured path is used as picked.
        NA_KEY_DRAFT_PATH           = "Na__AssemblyRunDraftPath".freeze
        NA_DRAFT_PATH_PAGE          = "page".freeze

        # V2.7.7: Live Mode. The page numbers each live rebuild it asks for
        # under this key at the root of the description it sends; Ruby takes
        # it off (never stored) and answers with the same number, so the page
        # knows whether it changed anything while the run was rebuilding.
        NA_KEY_LIVE_SEQ             = "Na__Run__LiveSeq".freeze
        NA_LIVE_OPERATION           = "Live Update Assembly Run".freeze

        # On every span's element instance inside a run: which run, which
        # panel type, which place. Read by the selection banner ("editing
        # panel type A") and by Make Panel Unique.
        NA_MEMBER_DICT              = "Na__AssemblyRunMemberInfo".freeze
        NA_MEMBER_KEY_RUN_ID        = "RunID".freeze
        NA_MEMBER_KEY_TYPE          = "PanelType".freeze
        NA_MEMBER_KEY_LEG           = "Leg".freeze
        NA_MEMBER_KEY_SPAN          = "Span".freeze

        # SerializerBase contract (AppConfig attributeDictionaries
        # .assemblyRunSystem holds the same values).
        NA_SERIALIZER_CONFIG = {
            :instance_dict_name     => NA_INFO_DICT,
            :instance_id_attribute  => NA_KEY_RUN_ID,
            :definition_dict_prefix => NA_DEF_DICT_PREFIX,
            :metadata_key           => NA_KEY_METADATA,
            :components_key         => NA_KEY_COMPONENTS,
            :configuration_key      => NA_KEY_CONFIGURATION,
            :id_regex               => NA_RUN_ID_REGEX_SOURCE,
            :id_format              => NA_RUN_ID_FORMAT,
            :definition_name_suffix => "__#{NA_NAME_TYPE_TAG}__"
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Modes, Products and the Kinds of Thing on a Run
# -----------------------------------------------------------------------------

        NA_SCHEMA_VERSION           = "1.0.0".freeze

        NA_MODE_FRAMES              = "Frames".freeze
        NA_MODE_CABINETS            = "Cabinets".freeze
        NA_MODES                    = [NA_MODE_FRAMES, NA_MODE_CABINETS].freeze

        # Product keys are the agent seam's (60__System__McpOperations
        # NA_PRODUCTS), so a panel type names its product the same way in
        # the dialog, in a run's saved data and over the MCP.
        NA_MODE_PRODUCTS = {
            NA_MODE_FRAMES   => %w[casement sash single double bifold sliding].freeze,
            NA_MODE_CABINETS => %w[base drawers wall tall wardrobe].freeze
        }.freeze

        NA_MODE_SYSTEMS = {
            NA_MODE_FRAMES   => "window_family".freeze,
            NA_MODE_CABINETS => "cabinet".freeze
        }.freeze

        NA_PRODUCT_LABELS = {
            "casement" => "Casement Window", "sash"     => "Sash Window",
            "single"   => "Single Door",     "double"   => "Double Doors",
            "bifold"   => "Bifold Doors",    "sliding"  => "Sliding Doors",
            "base"     => "Base Unit",       "drawers"  => "Drawer Unit",
            "wall"     => "Wall Unit",       "tall"     => "Tall Unit",
            "wardrobe" => "Wardrobe"
        }.freeze

        # The window products. Their spans can stand on a sill height and
        # carry an internal window board; a door does neither. A panel type
        # changed to any other product loses its sill height: a door on a
        # sill is never what was meant (V2.7.2). Fused, a window is built
        # without any frame of its own: the run builds its head and bottom
        # rail as part of the one framework (V2.7.3).
        NA_WINDOW_PRODUCTS = %w[casement sash].freeze
        NA_SILL_PRODUCTS   = NA_WINDOW_PRODUCTS

        # The cabinet products a run's worktop lies on (V2.7.4). A wall,
        # tall or wardrobe span breaks it; infill blocks and gaps (appliance
        # spaces) carry it unless a gap item says Worktop false (a cooker).
        NA_WORKTOP_PRODUCTS = %w[base drawers].freeze

        # V2.7.6: the floor units a run's ONE kickboard runs along
        # (JoinPlinths), and the tall units its top filler runs over
        # (SoffitHeight_mm). A wall unit, an infill block, a gap, a corner
        # and a free end break them.
        NA_PLINTH_PRODUCTS     = %w[base drawers tall wardrobe].freeze
        NA_TOP_FILLER_PRODUCTS = %w[tall wardrobe].freeze

        NA_ITEM_SPAN                = "Span".freeze
        NA_ITEM_COLUMN              = "Column".freeze

        # What can stand between two spans, or at the end of a run.
        #   None    : nothing. Frames butt jamb to jamb (or share a mullion
        #             when Fuse Framework is on); cabinets butt side to side.
        #   Infill  : a plain block of a set width (a pier, a filler panel).
        #   Vale260 / Vale290 : Adam's standard library columns, inline, on a
        #             backing block of the column's own width (Frames only).
        #   Gap     : a set width left empty (a cooker space, a broken run).
        NA_COLUMN_NONE              = "None".freeze
        NA_COLUMN_INFILL            = "Infill".freeze
        NA_COLUMN_VALE_260          = "Vale260".freeze
        NA_COLUMN_VALE_290          = "Vale290".freeze
        NA_COLUMN_GAP               = "Gap".freeze
        NA_COLUMN_KINDS             = [NA_COLUMN_NONE, NA_COLUMN_INFILL, NA_COLUMN_VALE_260, NA_COLUMN_VALE_290, NA_COLUMN_GAP].freeze
        NA_COLUMN_KINDS_BY_MODE = {
            NA_MODE_FRAMES   => NA_COLUMN_KINDS,
            NA_MODE_CABINETS => [NA_COLUMN_NONE, NA_COLUMN_INFILL, NA_COLUMN_GAP].freeze
        }.freeze

        # What stands where two legs meet.
        #   Post       : a square block filling the corner.
        #   Vale260 / Vale290 : the library corner column on an L-shaped
        #                backing block (Frames, outside corners of 90 degrees).
        #   Open       : nothing: both legs stop short of the corner.
        #   CornerUnit : an L-shaped corner base unit (Cabinets, 90 degrees).
        #   Blind      : the first leg runs into the corner, the second
        #                starts clear of its fronts (Cabinets).
        NA_CORNER_POST              = "Post".freeze
        NA_CORNER_VALE_260          = "Vale260".freeze
        NA_CORNER_VALE_290          = "Vale290".freeze
        NA_CORNER_OPEN              = "Open".freeze
        NA_CORNER_UNIT              = "CornerUnit".freeze
        NA_CORNER_BLIND             = "Blind".freeze
        NA_CORNER_KINDS_BY_MODE = {
            NA_MODE_FRAMES   => [NA_CORNER_POST, NA_CORNER_VALE_260, NA_CORNER_VALE_290, NA_CORNER_OPEN].freeze,
            NA_MODE_CABINETS => [NA_CORNER_UNIT, NA_CORNER_BLIND, NA_CORNER_OPEN].freeze
        }.freeze

        # The posts Fuse Framework adds (never chosen by the user).
        NA_POST_MULLION             = "Mullion".freeze                           # <-- Between two spans
        NA_POST_JAMB                = "Jamb".freeze                              # <-- Where a span meets a column, a corner or the run's end

        # Cabinets: how a leg is filled from one standard width.
        #   End / Start / Both : whole standard units, the remainder as a
        #                        narrower unit at that end (or split in two).
        #   Equal              : every unit the same width, as near the
        #                        standard as the leg divides.
        NA_INFILL_END               = "End".freeze
        NA_INFILL_START             = "Start".freeze
        NA_INFILL_BOTH              = "Both".freeze
        NA_INFILL_EQUAL             = "Equal".freeze
        NA_INFILL_MODES             = [NA_INFILL_END, NA_INFILL_START, NA_INFILL_BOTH, NA_INFILL_EQUAL].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Library Columns (Adam's Vale Standard Columns)
# -----------------------------------------------------------------------------
# Measured from the library files on 16-Nov-2026 (Va__CoreLib__3dAssets,
# 10__Columns). Every one is 2000 tall with its base 0-114 and capital
# 1886.6-2000; the shaft between stretches (every vertex above 1000 moves).
# Inline: origin at the column's left edge seen from outside, on the
# framework face, at its base; the body stands 88.5 proud of that face.
# Corner: origin on the corner of the two framework faces; each leg of the
# column takes Leg_mm of its framework face.

        NA_LIBRARY_COLUMNS = {
            NA_COLUMN_VALE_260 => {
                :label        => "Vale 260 Standard Column",
                :inline_file  => "10_1001__Column__Standard__Inline__w260mm__.skp",
                :corner_file  => "10_1002__Column__Standard__Corner__w260mm__.skp",
                :width_mm     => 260.0,
                :corner_leg_mm=> 165.0,
                :backing_mm   => 95.0,
                :proud_mm     => 88.5
            }.freeze,
            NA_COLUMN_VALE_290 => {
                :label        => "Vale 290 Standard Column",
                :inline_file  => "10_1004__Column__Standard__w290mm__Inline__.skp",
                :corner_file  => "10_1003__Column__Standard__w290mm__Corner__.skp",
                :width_mm     => 290.0,
                :corner_leg_mm=> 195.0,
                :backing_mm   => 95.0,
                :proud_mm     => 88.5
            }.freeze
        }.freeze

        NA_LIBRARY_COLUMN_HEIGHT_MM   = 2000.0
        NA_LIBRARY_COLUMN_STRETCH_Z_MM= 1000.0
        NA_LIBRARY_COLUMN_MIN_MM      = 400.0                                    # <-- Shorter than this the shaft would fold into the base
        NA_LIBRARY_COLUMN_FOLDER      = "AssemblyRun__Columns__".freeze          # <-- Under 04__Data__AssetLibrary (AppConfig assetLibrary.assemblyRun.columns)
        NA_COLUMN_BACKER_TAG          = "00__Util__Linework__ColumnBackers".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Limits (Values Outside These Are Refused, Never Clamped)
# -----------------------------------------------------------------------------

        NA_LIMITS = {
            "Height_mm"            => [300.0, 6000.0],
            "MullionWidth_mm"      => [20.0, 300.0],
            "JambWidth_mm"         => [0.0, 300.0],
            "PostDepth_mm"         => [20.0, 400.0],
            "PostInset_mm"         => [-100.0, 300.0],
            "JointWidth_mm"        => [10.0, 5000.0],
            "EndWidth_mm"          => [10.0, 5000.0],
            "CornerPostSize_mm"    => [20.0, 1000.0],
            "UnitDepth_mm"         => [150.0, 1200.0],
            "FrontAllowance_mm"    => [0.0, 200.0],
            "CornerUnitLeg_mm"     => [600.0, 1500.0],
            "FillerHeight_mm"      => [100.0, 3000.0],
            "StandardWidth_mm"     => [150.0, 1500.0],
            "MinInfillWidth_mm"    => [50.0, 600.0],
            "CillHeight_mm"        => [0.0, 300.0],                              # <-- 0: one line of panels with no cill at all
            "CillProjection_mm"    => [0.0, 300.0],
            "WorktopThickness_mm"  => [10.0, 200.0],
            "WorktopOverhang_mm"   => [0.0, 1500.0],                             # <-- V2.7.5: 1500, a table end on a peninsula (600 was too few for SK02's island)
            "WorktopBackOverhang_mm" => [0.0, 1500.0],                           # <-- SK02's island, KT01: 695 behind the hob run
            "WorktopEndOverhang_mm"  => [0.0, 1500.0],
            "SoffitHeight_mm"        => [0.0, 6000.0]                            # <-- V2.7.6: 0, no top filler
        }.freeze

        # A worktop cut-out (V2.7.5): its outline is kept in the run's own
        # plan, so it moves with the run. Fewer than three points, or a side
        # shorter than this, is refused.
        NA_CUTOUT_MIN_SIDE_MM       = 10.0
        NA_CUTOUT_MAX_COUNT         = 40

        NA_MIN_LEG_MM               = 50.0
        NA_MAX_LEGS                 = 24
        NA_MAX_SPANS_PER_LEG        = 60
        NA_MIN_SPAN_MM              = 100.0
        NA_WIDTH_TOLERANCE_MM       = 0.5                                        # <-- Two spans of one type must agree within this
        NA_SQUARE_TOLERANCE_DEG     = 0.5                                        # <-- A corner within this of 90 degrees is square
        NA_STRAIGHT_TOLERANCE_DEG   = 0.2                                        # <-- A turn smaller than this is no corner

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Default Configuration (Both Modes Share One Shape)
# -----------------------------------------------------------------------------

        NA_DEFAULT_RUN_CONFIGURATION = {
            "Na__RunConfig__SchemaVersion"     => NA_SCHEMA_VERSION,
            "Na__RunConfig__Mode"              => NA_MODE_FRAMES,
            "Na__RunConfig__PathPoints"        => [[0, 0], [3600, 0]],           # <-- mm, the run's own plan; the first leg runs along +X
            "Na__RunConfig__PathClosed"        => false,
            "Na__RunConfig__SideFlipped"       => false,                         # <-- The Flip Inside Out switch (V2.7.2). The flip itself is in the data: the path, legs and corners are stored turned round. Only Na__RunEdits.na_flip_side! sets it
            "Na__RunConfig__Height_mm"         => 2100,                          # <-- Frames: base to the top of the frames
            "Na__RunConfig__FuseFramework"     => false,                         # <-- Frames: the run builds the frame members (heads and bottom rails of its windows, mullions, jambs, blocks, corner posts) as ONE solid; implies JoinCills (V2.7.3)
            "Na__RunConfig__JoinCills"         => true,                          # <-- Frames: one cill and one internal window board along the run, mitred round every corner, in place of each panel's own (V2.7.3)
            "Na__RunConfig__CillHeight_mm"     => 50,                            # <-- The run's cill (the window tab's own cill starts at the same 50 x 50)
            "Na__RunConfig__CillProjection_mm" => 50,                            # <-- How far it stands proud of the framework face
            "Na__RunConfig__MullionWidth_mm"   => 50,
            "Na__RunConfig__JambWidth_mm"      => 50,
            "Na__RunConfig__PostDepth_mm"      => 70,                            # <-- Mullions, jambs and infill blocks (a frame's depth)
            "Na__RunConfig__PostInset_mm"      => 0,                             # <-- Behind the framework face (a frame's wall inset)
            "Na__RunConfig__JointColumn"       => NA_COLUMN_NONE,                # <-- Between two spans that follow each other
            "Na__RunConfig__JointWidth_mm"     => 500,                           # <-- Infill and Gap joints
            "Na__RunConfig__EndColumn"         => NA_COLUMN_NONE,                # <-- At the two free ends of an open run
            "Na__RunConfig__EndWidth_mm"       => 500,
            "Na__RunConfig__CornerColumn"      => NA_CORNER_POST,
            "Na__RunConfig__CornerPostSize_mm" => 100,
            "Na__RunConfig__UnitDepth_mm"      => 560,                           # <-- Cabinets: carcass depth (corners and fillers)
            "Na__RunConfig__FrontAllowance_mm" => 25,                            # <-- Cabinets: fronts and handles in front of the carcass, for a blind corner
            "Na__RunConfig__CornerUnitLeg_mm"  => 900,                           # <-- Cabinets: each arm of an L-shaped corner unit, along its wall
            "Na__RunConfig__FillerHeight_mm"   => 870,                           # <-- Cabinets: infill blocks stand this tall
            "Na__RunConfig__Worktop"           => true,                          # <-- Cabinets: ONE worktop per stretch of base and drawer units, mitred round every corner (V2.7.4)
            "Na__RunConfig__WorktopThickness_mm"    => 40,
            "Na__RunConfig__WorktopOverhang_mm"     => 25,                       # <-- Past the units' fronts
            "Na__RunConfig__WorktopBackOverhang_mm" => 0,                        # <-- Behind the path (the wall line): an island's far side
            "Na__RunConfig__WorktopEndOverhang_mm"  => 0,                        # <-- Past each free end of an open path
            "Na__RunConfig__WorktopMaterialId"      => "",                       # <-- A library material id; empty: the carcass finish of the units under it
            "Na__RunConfig__WorktopCutouts"         => [],                       # <-- V2.7.5: [{ "Label" => "Hob", "Outline_mm" => [[x, y] ...] }] in the run's own plan: holes, or notches where they reach an edge
            "Na__RunConfig__JoinPlinths"            => true,                     # <-- V2.7.6, Cabinets: ONE kickboard per stretch of floor units in place of each unit's own plinth board. A NEW run starts with it on; a run with no stored value (built before 2.7.6) reads it as off
            "Na__RunConfig__SoffitHeight_mm"        => 0,                        # <-- V2.7.6, Cabinets: a top filler in the door plane over tall units up to this soffit; 0 none. Infill blocks beside tall units stand to it
            "Na__RunConfig__Legs"              => [],                            # <-- One entry per leg: { "Items" => [...] } or { "Fill" => {...} }
            "Na__RunConfig__Corners"           => [],                            # <-- Per-corner overrides: { "Column" => "Vale260" }
            "Na__RunConfig__PanelTypes"        => []                             # <-- { "Code", "Product", "Width_mm", "Height_mm", "SillHeight_mm", "ElementId", ... }
        }.freeze

        # What each mode changes from the shared defaults above.
        NA_MODE_DEFAULT_OVERRIDES = {
            NA_MODE_FRAMES   => {}.freeze,
            NA_MODE_CABINETS => {
                "Na__RunConfig__CornerColumn"  => NA_CORNER_UNIT,
                "Na__RunConfig__JointWidth_mm" => 600
            }.freeze
        }.freeze

        NA_DEFAULT_RUN_CONFIG = {
            NA_KEY_METADATA => [
                {
                    "Na__Run__UniqueId"      => nil,
                    "Na__Run__Name"          => "New Assembly Run",
                    "Na__Run__ComponentName" => "",
                    "Na__Run__Description"   => "",
                    "Na__Run__Notes"         => "Created with Element Assembly Studio Pro",
                    "Na__Run__CreatedDate"   => nil,
                    "Na__Run__LastModified"  => nil
                }
            ],
            NA_KEY_COMPONENTS    => [],
            NA_KEY_CONFIGURATION => NA_DEFAULT_RUN_CONFIGURATION
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | A Deep Copy of the Default Root Configuration for a Mode
        # ------------------------------------------------------------
        def self.na_default_config(mode = NA_MODE_FRAMES)
            root = Marshal.load(Marshal.dump(NA_DEFAULT_RUN_CONFIG))
            root[NA_KEY_CONFIGURATION].merge!(Marshal.load(Marshal.dump(NA_MODE_DEFAULT_OVERRIDES[mode] || {})))
            root[NA_KEY_CONFIGURATION]["#{NA_CONFIG_KEY_PREFIX}Mode"] = NA_MODES.include?(mode) ? mode : NA_MODE_FRAMES
            root
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Configuration Key's Full Name ("Mode" or the Full Key)
        # ------------------------------------------------------------
        def self.na_key(short)
            short.to_s.start_with?(NA_CONFIG_KEY_PREFIX) ? short.to_s : "#{NA_CONFIG_KEY_PREFIX}#{short}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name Head of a Run: "ARN001__AssemblyRun__"
        # ------------------------------------------------------------
        def self.na_name_head(run_id)
            "#{run_id}__#{NA_NAME_TYPE_TAG}__"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Panel Type Code After a List of Codes (A, B ... Z, AA)
        # ------------------------------------------------------------
        # @param taken [Array<String>] codes already in use
        # @return [String] the first letter code not taken
        def self.na_next_type_code(taken)
            used = taken.map { |code| code.to_s.upcase }
            code = "A"
            code = code.succ while used.include?(code)
            code
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This a Usable Panel Type Code
        # ------------------------------------------------------------
        # Letters and digits, up to six, starting with a letter: A, B2, DR1.
        def self.na_valid_type_code?(code)
            code.to_s.match?(/\A[A-Z][A-Z0-9]{0,5}\z/)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Defaults
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
