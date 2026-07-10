# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DOOR NAMING CONTRACT (SHARED, READ-ONLY SOURCE OF TRUTH)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__DoorNamingContract__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Single canonical authority for the SketchUp -> TrueVision3D
#              animation naming contract used by every door subsystem
#              (interior, exterior single, exterior bifold, exterior sliding).
#              All format strings, regex patterns and helper formatters live
#              here so both the SketchUp emitters and the TrueVision3D scanner
#              can resolve identical conventions from one place.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - All custom door systems must emit names that match these regex patterns.
# - All custom door systems must allocate ADR ids using NA_ADR_ID_FORMAT.
# - All TrueVision3D animation parsers must accept these regex patterns and
#   tolerate per-system suffix variations (BifoldHingeCentre vs SlidingPanelTrack
#   vs DoorHingeCentre - the suffix is documentation, not contract).
#
# CONTRACT SUMMARY (Phase 4):
#
#   ADR id           : ^ADR\d{3}$            (3-digit zero-padded across all door types)
#   ADR instance     : ADR###__<DoorTypeTag> (e.g. ADR001__BifoldDoor)
#   MOD ROT only     : MOD###__ROT__<deg>-Deg__<PanelTag>
#                      e.g. MOD001__ROT__-90-Deg__DoorPanel
#                           MOD002__ROT__180-Deg__BifoldPanel
#   MOD ROT+MVE      : MOD###__ROT__<deg>-Deg__MVE__<axis><signed-mag>-mm__<PanelTag>
#                      e.g. MOD003__ROT__180-Deg__MVE__X+600-mm__BifoldPanel
#                           MOD004__ROT__180-Deg__MVE__X-600-mm__BifoldPanel
#   MOD MVE only     : MOD###__MVE__<axis><signed-mag>-mm__<PanelTag>
#                      e.g. MOD002__MVE__X+1200-mm__SlidingPanel
#                           MOD003__MVE__X-1200-mm__SlidingPanel
#   MOD FIXED        : MOD###__FIXED__<PanelTag>
#                      e.g. MOD003__FIXED__SlidingPanel
#   ROT helper       : ROT###__RotationPoint__<system-suffix>
#                      e.g. ROT001__RotationPoint__DoorHingeCentre
#                           ROT001__RotationPoint__BifoldHingeCentre
#   MVE helper       : MVE###__MovementPoint__<system-suffix>
#                      e.g. MVE001__MovementPoint__SlidingPanelTrack
#                           MVE001__MovementPoint__BifoldPanelTrack
#
# NEGATIVE-DISTANCE FORMATTING (Phase-4 fix):
# - Use signed integer with explicit sign character so the regex can locate
#   axis vs sign vs magnitude without ambiguity.
# - Use "%+d" (Ruby format) so positive numbers show "+" too:
#     mag = +600 -> "X+600-mm"
#     mag = -600 -> "X-600-mm"
# - This avoids the "X--600-mm" double-hyphen produced by the legacy "%s-%d-mm"
#   format when the layout algorithm passes a negative distance.
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__GeometryHelpers
module Na__DoorNamingContract


    # -----------------------------------------------------------------------------
    # REGION | ADR Id System (door root)
    # -----------------------------------------------------------------------------

    NA_ADR_ID_PREFIX                 = "ADR".freeze
    NA_ADR_ID_FORMAT                 = "ADR%03d".freeze
    NA_ADR_ID_REGEX                  = /^ADR\d{3}$/.freeze
    NA_ADR_ID_EXTRACT_REGEX          = /^ADR(\d{3})$/.freeze
    NA_ADR_SUFFIX_EXTERIOR_DOUBLE    = "__ExteriorDoubleDoor__".freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | MOD Group Naming
    # -----------------------------------------------------------------------------

    # Format strings exposed for self-formatting by external code.
    NA_MOD_NAME_FORMAT_ROT_ONLY      = "MOD%03d__ROT__%s-Deg__%s".freeze        # <-- index, deg, panel_tag
    NA_MOD_NAME_FORMAT_ROT_MVE       = "MOD%03d__ROT__%s-Deg__MVE__%s%+d-mm__%s".freeze  # <-- index, deg, axis_letter, signed_mm, panel_tag
    NA_MOD_NAME_FORMAT_MVE_ONLY      = "MOD%03d__MVE__%s%+d-mm__%s".freeze      # <-- index, axis_letter, signed_mm, panel_tag
    NA_MOD_NAME_FORMAT_FIXED         = "MOD%03d__FIXED__%s".freeze              # <-- index, panel_tag

    # Regex patterns - the canonical TrueVision parser uses these.
    NA_MOD_NAME_REGEX_ROT_ONLY       = /^MOD(\d{3})__ROT__(-?\d+)-Deg__([A-Za-z][A-Za-z0-9]*)$/.freeze
    NA_MOD_NAME_REGEX_ROT_MVE        = /^MOD(\d{3})__ROT__(-?\d+)-Deg__MVE__([XYZ])([+-]\d+)-mm__([A-Za-z][A-Za-z0-9]*)$/.freeze
    NA_MOD_NAME_REGEX_MVE_ONLY       = /^MOD(\d{3})__MVE__([XYZ])([+-]\d+)-mm__([A-Za-z][A-Za-z0-9]*)$/.freeze
    NA_MOD_NAME_REGEX_FIXED          = /^MOD(\d{3})__FIXED__([A-Za-z][A-Za-z0-9]*)$/.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | ROT / MVE Helper Marker Naming
    # -----------------------------------------------------------------------------

    NA_ROT_MARKER_NAME_FORMAT        = "ROT%03d__RotationPoint__%s".freeze      # <-- index, system_suffix
    NA_MVE_MARKER_NAME_FORMAT        = "MVE%03d__MovementPoint__%s".freeze      # <-- index, system_suffix

    NA_ROT_MARKER_NAME_REGEX         = /^ROT(\d{3})__RotationPoint__([A-Za-z][A-Za-z0-9]*)$/.freeze
    NA_MVE_MARKER_NAME_REGEX         = /^MVE(\d{3})__MovementPoint__([A-Za-z][A-Za-z0-9]*)$/.freeze

    # Recognised per-system suffix tokens (documentation only - parser is suffix-agnostic).
    NA_ROT_SUFFIX_INTERIOR_DOOR      = "DoorHingeCentre".freeze
    NA_ROT_SUFFIX_BIFOLD             = "BifoldHingeCentre".freeze
    NA_ROT_SUFFIX_SLIDING            = "SlidingPanelTrack".freeze
    NA_ROT_SUFFIX_EXTERIOR_DOUBLE    = "ExteriorDoubleDoorHingeCentre".freeze
    NA_MVE_SUFFIX_BIFOLD             = "BifoldPanelTrack".freeze
    NA_MVE_SUFFIX_SLIDING            = "SlidingPanelTrack".freeze
    NA_PANEL_TAG_EXTERIOR_DOUBLE     = "ExteriorDoubleDoorPanel".freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Helper Layer & Material Constants
    # -----------------------------------------------------------------------------

    NA_HELPER_TAG_ROLE               = :door_helpers                            # <-- TagManager role symbol
    NA_HELPER_LAYER_FALLBACK         = "02__DoorHelpers__RotationPivots".freeze  # <-- Sketchup tag name fallback
    NA_HELPER_EDGE_COLOUR_ID         = "MTE201__LineColour__Red".freeze          # <-- EdgeColourManager material id

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Formatters - Use These From AssemblyComposers
    # -----------------------------------------------------------------------------

    # FUNCTION | Format an ADR id from a positive integer
    # ------------------------------------------------------------
    # @param  [Integer] number - 1-based door number
    # @return [String]         - "ADR001", "ADR017", etc.
    def self.na_format_adr_id(number)
        format(NA_ADR_ID_FORMAT, number.to_i)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Extract the integer number from an ADR string
    # ------------------------------------------------------------
    # @param  [String] adr_string - any string, validated against NA_ADR_ID_EXTRACT_REGEX
    # @return [Integer, nil]      - parsed number or nil on no match
    def self.na_extract_adr_number(adr_string)
        return nil unless adr_string.is_a?(String)
        match = adr_string.match(NA_ADR_ID_EXTRACT_REGEX)
        match ? match[1].to_i : nil
    end
    # ---------------------------------------------------------------


    # FUNCTION | Format a ROT-only MOD group name
    # ------------------------------------------------------------
    def self.na_format_mod_rot_only(index, rot_degrees, panel_tag)
        format(NA_MOD_NAME_FORMAT_ROT_ONLY, index.to_i, rot_degrees.to_i.to_s, panel_tag.to_s)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Format a ROT+MVE MOD group name (signed distance preserved)
    # ------------------------------------------------------------
    def self.na_format_mod_rot_mve(index, rot_degrees, mve_axis, mve_distance_mm, panel_tag)
        axis_letter = na_normalise_axis_letter(mve_axis)
        format(
            NA_MOD_NAME_FORMAT_ROT_MVE,
            index.to_i,
            rot_degrees.to_i.to_s,
            axis_letter,
            mve_distance_mm.to_i,
            panel_tag.to_s
        )
    end
    # ---------------------------------------------------------------


    # FUNCTION | Format an MVE-only MOD group name (signed distance preserved)
    # ------------------------------------------------------------
    def self.na_format_mod_mve_only(index, mve_axis, mve_distance_mm, panel_tag)
        axis_letter = na_normalise_axis_letter(mve_axis)
        format(
            NA_MOD_NAME_FORMAT_MVE_ONLY,
            index.to_i,
            axis_letter,
            mve_distance_mm.to_i,
            panel_tag.to_s
        )
    end
    # ---------------------------------------------------------------


    # FUNCTION | Format a FIXED MOD group name (no rotation, no translation)
    # ------------------------------------------------------------
    def self.na_format_mod_fixed(index, panel_tag)
        format(NA_MOD_NAME_FORMAT_FIXED, index.to_i, panel_tag.to_s)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Format a ROT marker group name
    # ------------------------------------------------------------
    def self.na_format_rot_marker(index, suffix)
        format(NA_ROT_MARKER_NAME_FORMAT, index.to_i, suffix.to_s)
    end
    # ---------------------------------------------------------------


    # FUNCTION | Format an MVE marker group name
    # ------------------------------------------------------------
    def self.na_format_mve_marker(index, suffix)
        format(NA_MVE_MARKER_NAME_FORMAT, index.to_i, suffix.to_s)
    end
    # ---------------------------------------------------------------


    # SUB FUNCTION | Coerce an axis hint to a single uppercase letter
    # ------------------------------------------------------------
    # Accepts "X", "x", :x, "X+", "X-" - returns "X" / "Y" / "Z".
    # The sign on the axis is dropped because the magnitude carries it.
    def self.na_normalise_axis_letter(axis_hint)
        s = axis_hint.to_s.upcase
        return s[0, 1] if s.length >= 1 && s[0, 1] =~ /[XYZ]/
        "X"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


end # module Na__DoorNamingContract
end # module Na__GeometryHelpers
end # module Na__AssemblyStudio


# =============================================================================
# END OF FILE
# =============================================================================
