# =============================================================================
# NA INSERT PRIMATIVES - KEYBOARD HANDLERS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__KeyboardHandlers__.rb
# NAMESPACE  : Na__InsertPrimatives::KeyboardHandlers
# AUTHOR     : Noble Architecture
# PURPOSE    : Mixin module for all keyboard and VCB interactions in PrimitiveCubeTool
# CREATED    : 2026
#
# DESCRIPTION:
# - Included into PrimitiveCubeTool via `include Na__InsertPrimatives::KeyboardHandlers`
# - Methods have full access to the host class's instance variables when mixed in
# - Covers: rotation key cycle, VCB enable/parse, status bar hint text
#
# KEY BINDING NOTES:
# - Rotation uses Tab (key code 9 = VK_TAB = 0x09).
#   The SketchUp Ruby API does not export a VK_TAB constant.
#
# - onKeyDown is used with a @key_tab_held guard to suppress the Windows
#   double-fire regression SKEXT-3890 (introduced 23.1.340, unresolved as of 2026).
#   Pattern: act only when the key transitions from up → down; onKeyUp resets the flag.
#
# - onKeyUp alone caused Tab to require a double-press: SketchUp's focus management
#   consumes the onKeyUp event on alternating presses for certain keys (documented
#   for Alt key in the same bug report; Tab exhibits the same behaviour).
#
# - Tab does not send characters to the VCB, making it safe when enableVCB? = true.
#
# ROTATION CYCLE (each Tab press advances one step):
#   0°  →  90°  →  180°  →  270°  →  0°  (wraps)
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    module KeyboardHandlers

        # KEY BINDING CONSTANTS
        # ------------------------------------------------------------
        NA_ROTATION_KEY   = 9   # Tab key (VK_TAB = 0x09) — no VK_TAB constant in SketchUp Ruby API
        NA_ROTATION_STEPS = [0, 90, 180, 270].freeze
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Key Handlers
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | Advance rotation by 90° on Tab press (first press only)
        # @key_tab_held prevents acting on SKEXT-3890 double-fire or typematic repeats.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == NA_ROTATION_KEY && !@key_tab_held
                @key_tab_held   = true
                @rotation_step  = (@rotation_step.to_i + 1) % 4
                na_key__update_status_text()
                view.invalidate
            end
            false
        end
        # ---------------------------------------------------------------

        # ON KEY UP | Reset key-held flag when Tab is released
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            @key_tab_held = false if key == NA_ROTATION_KEY
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | VCB (Value Control Box) Handling
        # -----------------------------------------------------------------------------

        # FUNCTION | Enable VCB Input
        # ------------------------------------------------------------
        def enableVCB?
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle User Text Input in VCB
        # ------------------------------------------------------------
        def onUserText(text, view)
            begin
                dims = Na__InsertPrimatives.Na__VcbInput__ParseDimensions(text)

                x_val, y_val, z_val = dims

                if x_val > 0 && y_val > 0 && z_val > 0
                    @cube_size_x = x_val
                    @cube_size_y = y_val
                    @cube_size_z = z_val

                    Na__InsertPrimatives.Na__VcbInput__UpdateDisplay(@cube_size_x, @cube_size_y, @cube_size_z)

                    if @last_cube_group && @last_cube_group.valid? && @last_corner_position
                        Na__Primitive__RegenerateCube(@last_cube_group, @last_corner_position)

                        x_mm = @cube_size_x.to_mm.round
                        y_mm = @cube_size_y.to_mm.round
                        z_mm = @cube_size_z.to_mm.round
                        Sketchup::set_status_text("Cube regenerated: #{x_mm}mm x #{y_mm}mm x #{z_mm}mm", SB_PROMPT)
                    else
                        x_mm = @cube_size_x.to_mm.round
                        y_mm = @cube_size_y.to_mm.round
                        z_mm = @cube_size_z.to_mm.round
                        Sketchup::set_status_text("Dimensions set: #{x_mm}mm x #{y_mm}mm x #{z_mm}mm", SB_PROMPT)
                    end

                    view.invalidate
                else
                    UI.beep
                    Sketchup::set_status_text("Dimensions must be positive", SB_PROMPT)
                end
            rescue ArgumentError => e
                UI.beep
                Sketchup::set_status_text("Invalid input: #{e.message}", SB_PROMPT)
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Bar Helpers
        # -----------------------------------------------------------------------------

        # FUNCTION | Update Status Bar to Reflect Current Rotation Step
        # Called from activate, resume, onKeyDown.
        # ------------------------------------------------------------
        def na_key__update_status_text
            step    = @rotation_step.to_i
            degrees = NA_ROTATION_STEPS[step]
            Sketchup::set_status_text("Click to place | Rotation: #{degrees}° [TAB to rotate]", SB_PROMPT)
        end
        private :na_key__update_status_text
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End KeyboardHandlers module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF KEYBOARD HANDLERS MODULE
# =============================================================================
