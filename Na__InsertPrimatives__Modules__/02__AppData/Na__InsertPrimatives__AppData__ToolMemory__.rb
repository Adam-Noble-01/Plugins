# =============================================================================
# NA INSERT PRIMATIVES - TOOL MEMORY (MODEL DICTIONARY)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppData__ToolMemory__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Remember each modifier tool's last successful value in the model
# CREATED    : 2026
#
# DESCRIPTION:
# - Native Push/Pull repeats its last distance on a double-click. For that to
#   work across a tool switch, a plugin reload and a reopened file, the value
#   has to live somewhere that travels with the model — its own attribute
#   dictionary, one key per modifier tool.
# - Values are stored in MILLIMETRES so the dictionary reads sensibly in an
#   attribute inspector, and converted to internal inches on the way back in.
#
# WRITE INSIDE THE OPERATION THAT EARNED IT:
# - Setting a model attribute is itself an undoable change. Written on its own
#   it would add a second undo step after every push, and a user's Ctrl+Z
#   would then have to be pressed twice. So Na__ToolMemory__Write is only ever
#   called between start_operation and commit_operation, where the write
#   merges into the placement it records. Undo the push and the memory of it
#   goes too, which is the right answer.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Dictionary Keys
    # -----------------------------------------------------------------------------

    NA_TOOL_MEMORY_DICTIONARY    = 'Na__InsertPrimatives__ToolMemory'.freeze
    NA_TOOL_MEMORY_PUSH_PULL_KEY = 'Na__DeepPushPull__LastDistanceMm'.freeze     # <-- Signed: negative is INTO the material
    NA_TOOL_MEMORY_CHAMFER_KEY   = 'Na__DeepChamfer__LastSetbackMm'.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Read and Write
    # -----------------------------------------------------------------------------

    # FUNCTION | Read a Remembered Value as Internal Inches, or nil
    # ------------------------------------------------------------
    def self.Na__ToolMemory__Read(model, key)
        return nil unless model && key

        stored = model.get_attribute(NA_TOOL_MEMORY_DICTIONARY, key, nil)
        return nil if stored.nil?

        value_mm = stored.to_f
        return nil if value_mm.abs < 0.0001                                   # <-- A zero is no memory at all

        value_mm / NA_DRAWN_INCH_TO_MM
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Write a Value (Internal Inches) as Millimetres
    # Call ONLY inside an open operation — see the header.
    # ------------------------------------------------------------
    def self.Na__ToolMemory__Write(model, key, value)
        return false unless model && key

        value_mm = (value.to_f * NA_DRAWN_INCH_TO_MM).round(3)
        model.set_attribute(NA_TOOL_MEMORY_DICTIONARY, key, value_mm)
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA TOOL MEMORY: could not write #{key} — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
