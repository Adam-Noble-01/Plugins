# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - COMPONENT NAME SUFFIX (SHARED NAMING HELPER)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ComponentNameSuffix__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__GeometryHelpers
# MODULE     : Na__ComponentNameSuffix
# AUTHOR     : Noble Architecture
# PURPOSE    : Single authority for the OPTIONAL, user-authored tail that is
#              appended to a product's SketchUp instance / definition name.
# CREATED    : 28-Aug-2026
#
# THE CONTRACT THIS FILE PROTECTS
# - Every product this app emits is named `<base_prefix><component_name>`:
#
#       AWN019__Window__            + GroundFloor__BayWindow
#       ADR004__ExteriorDoubleDoor__ + GroundFloor__Orangery
#
# - The `base_prefix` half (`<ID>__<TypeTag>__`) is a FIXED, machine-read
#   contract. TrueVision, ValeVision and every downstream scanner resolve a
#   product by matching the head of the name, so nothing in this module is
#   ever allowed to alter, reorder or shorten it. This module only ever
#   composes what comes AFTER it.
# - The suffix is therefore free text for humans (Outliner grouping), and is
#   deliberately excluded from every parser contract.
#
# WHY THE NAME IS THE SOURCE OF TRUTH
# - The live `definition.name` is what the user actually sees in the Outliner,
#   so it - not a mirrored dictionary key - is read back to populate the
#   dialog field. That makes the round-trip self-healing: a component renamed
#   by hand in SketchUp reports its real suffix, and models saved before this
#   feature existed migrate with no conversion step.
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__GeometryHelpers
module Na__ComponentNameSuffix


    # -----------------------------------------------------------------------------
    # REGION | Module Constants
    # -----------------------------------------------------------------------------

    # SENTINEL | Preserve Whatever Suffix the Instance Already Carries
    # ------------------------------------------------------------
    # Passed as the `component_name` argument by every rebuild path that
    # is not itself changing the name. Without it an Update / Live Update
    # would silently reset a named component back to its bare prefix.
    NA_KEEP                   = :keep

    NA_MAX_SUFFIX_LENGTH      = 96                                                      # <-- Keeps the Outliner readable; SketchUp itself has no practical limit

    # Characters SketchUp, Windows paths and the DXF / glTF exporters all
    # dislike. Stripped rather than substituted so nothing invents content.
    NA_ILLEGAL_CHARACTERS     = /[\x00-\x1F\/\\\[\]:*?"<>|]/.freeze

    # SketchUp appends "#1", "#2", ... when a definition name collides.
    # That is SketchUp's bookkeeping, not a user-authored suffix.
    NA_DEDUPE_SUFFIX_REGEX    = /\A#\d+\z/.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Sanitising
    # -----------------------------------------------------------------------------

    # FUNCTION | Clean One User-Typed Suffix Into a Safe Name Tail
    # ------------------------------------------------------------
    # @param raw         [Object]      Anything the dialog sent (usually String or nil)
    # @param base_prefix [String, nil] The fixed head, used only to strip a
    #                                  pasted duplicate of itself
    # @return            [String]      "" when nothing usable remains
    def self.na_sanitise(raw, base_prefix = nil)
        return "" if raw.nil?

        text = raw.to_s.gsub(NA_ILLEGAL_CHARACTERS, "")
        text = text.gsub(/\s+/, " ").strip

        # Paste-guard | "AWN019__Window__Lounge" typed into the field must
        # not become "AWN019__Window__AWN019__Window__Lounge".
        if base_prefix.is_a?(String) && !base_prefix.empty?
            while text.start_with?(base_prefix)
                text = text[base_prefix.length..-1].to_s.strip
            end
        end

        text = text.sub(/\A_+/, "")                                                     # <-- base_prefix already ends in "__"
        text = text[0, NA_MAX_SUFFIX_LENGTH].to_s.strip if text.length > NA_MAX_SUFFIX_LENGTH
        return "" if text.match?(NA_DEDUPE_SUFFIX_REGEX)                                # <-- SketchUp's own "#1" collision marker

        text
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reading the Current Suffix Back Off a Component
    # -----------------------------------------------------------------------------

    # FUNCTION | Split the Suffix Off a Full Name
    # ------------------------------------------------------------
    # Returns "" when the name does not carry the expected head, which
    # is the safe answer - a foreign name must never be reinterpreted.
    def self.na_extract(full_name, base_prefix)
        return "" unless full_name.is_a?(String) && base_prefix.is_a?(String)
        return "" unless full_name.start_with?(base_prefix)

        tail = full_name[base_prefix.length..-1].to_s
        return "" if tail.match?(NA_DEDUPE_SUFFIX_REGEX)

        tail
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read the Suffix an Instance Is Currently Wearing
    # ------------------------------------------------------------
    # Prefers the definition name (the Outliner label) and falls back to
    # the instance name when the two have drifted apart.
    def self.na_current_suffix(instance, base_prefix)
        return "" unless na_named_instance?(instance)

        from_definition = na_extract(instance.definition.name.to_s, base_prefix)
        return from_definition unless from_definition.empty?

        na_extract(instance.name.to_s, base_prefix)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve the Suffix a Rename Should Actually Write
    # ------------------------------------------------------------
    # NA_KEEP preserves what is already there; anything else is treated
    # as user input and sanitised.
    def self.na_resolve(instance, base_prefix, requested)
        return na_current_suffix(instance, base_prefix) if requested == NA_KEEP
        na_sanitise(requested, base_prefix)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Applying a Name
    # -----------------------------------------------------------------------------

    # FUNCTION | Compose a Full Component Name From Its Two Halves
    # ------------------------------------------------------------
    def self.na_compose(base_prefix, requested)
        "#{base_prefix}#{na_sanitise(requested, base_prefix)}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Write the Composed Name Onto an Instance + Its Definition
    # ------------------------------------------------------------
    # Assignments are skipped when the name is already correct so the
    # Live Update path can call this on every rebuild for free.
    #
    # @return [String, nil] The full name now on the component, or nil
    def self.na_apply(instance, base_prefix, requested = NA_KEEP)
        return nil unless na_named_instance?(instance)
        return nil unless base_prefix.is_a?(String) && !base_prefix.empty?

        full_name = "#{base_prefix}#{na_resolve(instance, base_prefix, requested)}"

        instance.name            = full_name unless instance.name            == full_name
        instance.definition.name = full_name unless instance.definition.name == full_name

        full_name
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Internal Guards
    # -----------------------------------------------------------------------------

    # SUB FUNCTION | Is This a Live Component Instance We Can Rename?
    # ------------------------------------------------------------
    def self.na_named_instance?(instance)
        instance.is_a?(Sketchup::ComponentInstance) &&
            instance.valid? &&
            instance.definition &&
            instance.definition.valid?
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


end # module Na__ComponentNameSuffix
end # module Na__GeometryHelpers
end # module Na__AssemblyStudio


# =============================================================================
# END OF FILE
# =============================================================================
