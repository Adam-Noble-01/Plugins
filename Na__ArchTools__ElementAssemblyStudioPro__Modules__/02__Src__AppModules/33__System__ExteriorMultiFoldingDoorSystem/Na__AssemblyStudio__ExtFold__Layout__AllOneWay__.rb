# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD LAYOUT: ALL-ONE-WAY
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__Layout__AllOneWay__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__Layout__AllOneWay
# AUTHOR     : Noble Architecture
# PURPOSE    : Layout algorithm for the "All-One-Way" bifold mode where
#              every panel cascades to a single jamb (Left or Right).
#              The jamb-side panel is the master (jamb-hinged, no MVE);
#              every other panel folds 180 about its predecessor's
#              joint hinge AND translates along the head track toward
#              the cascade jamb by an amount proportional to its
#              distance from the master.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - `bifold_door_open_side` chooses the cascade jamb:
#     * "Left"  -> master is panel 1 (left jamb).
#     * "Right" -> master is panel N (right jamb).
# - The master swings outward to perpendicular about its jamb hinge.
# - Slaves rotate to perpendicular (matching the master's outward sign)
#   AND translate along the head track by k * (panel_w - panel_t - gap)
#   toward the cascade jamb so successive slaves stack at panel_t + gap
#   from the previous panel - a true accordion stack, not a flat deck.
# - Adjacent panels alternate the small termination tilt so the open
#   state reads as a zigzag concertina.
# - Handle goes on the LEADING slave (the one farthest from the master),
#   matching real-world bifold installations where the leading edge
#   carries the operator handle.
#
# COORDINATE SYSTEM (ADR-local):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 1.7.2
# - Right-cascade master now swings OUTWARD (+90 deg) instead of into
#   the room (-90 deg). Slaves now rotate to perpendicular instead of
#   180 deg and translate by k * (panel_w - panel_t - gap) so they
#   accordion-stack at the cascade jamb. Pre-V1.7.2 they all collapsed
#   onto the master's hinge in the same world position.
#
# 17-May-2026 - Version 0.2.0
# - Phase-3a implementation: emits panel descriptors for AssemblyComposer.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (returned []).
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__AssemblyStudio__ExtFold__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorMultiFoldingDoorSystem
module Na__Layout__AllOneWay

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Generate Panel Descriptors for the All-One-Way Layout
    # ------------------------------------------------------------
    # @param config_hash [Hash] Bifold configuration (snake_case keys)
    # @return [Array<Hash>] Panel descriptors consumed by AssemblyComposer
    def self.na_generate_panel_descriptors(config_hash)
        panel_count   = config_hash["bifold_door_panel_count"].to_i
        open_side_raw = (config_hash["bifold_door_open_side"] || "Right").to_s

        return [] if panel_count < 2

        dims = GeometryHelpers.na_resolve_door_opening_dimensions(config_hash)
        return [] if dims[:inner_w_mm] <= 0.0 || dims[:inner_h_mm] <= 0.0

        panel_w_mm = GeometryHelpers.na_compute_panel_width_mm(dims[:inner_w_mm], panel_count)
        panel_h_mm = dims[:inner_h_mm]
        return [] if panel_w_mm <= 0.0 || panel_h_mm <= 0.0

        panel_t_mm = GeometryHelpers.na_resolve_panel_thickness_mm(config_hash)            # <-- Accordion-stack offset depends on panel thickness

        cascade_left = (open_side_raw.downcase == "left")
        cascade_left ? na_build_left_cascade(panel_count, panel_w_mm, panel_h_mm, panel_t_mm) :
                       na_build_right_cascade(panel_count, panel_w_mm, panel_h_mm, panel_t_mm)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Cascade Direction
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors for Cascade Toward LEFT Jamb
    # ------------------------------------------------------------
    # Master is panel 1 (left jamb-hinged). Slaves 2..N fold and slide
    # back toward the master. The leading slave (rightmost panel)
    # carries the handle.
    def self.na_build_left_cascade(panel_count, panel_w_mm, panel_h_mm, panel_t_mm)
        list = []
        (0...panel_count).each do |i|
            panel_index = i + 1
            origin_x_mm = i * panel_w_mm
            slave_pos   = i

            list << if i == 0
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, 0.0, :left)
            else
                hinge_x_mm = origin_x_mm                                          # <-- Hinge on left edge (joint with previous)
                is_leading = (i == panel_count - 1)
                rot_deg = GeometryHelpers.na_compute_panel_rot_degrees(slave_pos, :left)                              # <-- ~ -90 deg with alternating tilt
                mve_mm  = GeometryHelpers.na_compute_slave_mve_distance_mm(slave_pos, :left, panel_w_mm, panel_t_mm)  # <-- Negative offset toward LEFT jamb
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    mve_mm,
                    is_leading,
                    :right,                                                       # <-- Handle on right edge of leading slave
                    rot_deg
                )
            end
        end
        list
    end
    private_class_method :na_build_left_cascade
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors for Cascade Toward RIGHT Jamb
    # ------------------------------------------------------------
    # Master is panel N (right jamb-hinged). Slaves 1..N-1 fold and
    # slide toward the master. The leading slave (leftmost panel)
    # carries the handle.
    def self.na_build_right_cascade(panel_count, panel_w_mm, panel_h_mm, panel_t_mm)
        list = []
        (0...panel_count).each do |i|
            panel_index = i + 1
            origin_x_mm = i * panel_w_mm
            slave_pos   = panel_count - 1 - i

            list << if i == panel_count - 1
                jamb_hinge_x = origin_x_mm + panel_w_mm
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, jamb_hinge_x, :right)
            else
                hinge_x_mm = origin_x_mm + panel_w_mm                             # <-- Hinge on right edge (joint with next)
                is_leading = (i == 0)
                rot_deg = GeometryHelpers.na_compute_panel_rot_degrees(slave_pos, :right)                              # <-- ~ +90 deg with alternating tilt
                mve_mm  = GeometryHelpers.na_compute_slave_mve_distance_mm(slave_pos, :right, panel_w_mm, panel_t_mm)  # <-- Positive offset toward RIGHT jamb
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    mve_mm,
                    is_leading,
                    :left,                                                        # <-- Handle on left edge of leading slave
                    rot_deg
                )
            end
        end
        list
    end
    private_class_method :na_build_right_cascade
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Panel Descriptor Builders
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build a Master-Panel Descriptor (Jamb-Hinged, ROT Only)
    # ------------------------------------------------------------
    # Routes the rotation through the accordion helper so the right-jamb
    # master swings OUTWARD (+90 deg) and the left-jamb master swings
    # OUTWARD (-90 deg), each with the small termination tilt.
    def self.na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, jamb_side)
        cascade_direction = (jamb_side == :left) ? :left : :right
        rot_deg           = GeometryHelpers.na_compute_panel_rot_degrees(0, cascade_direction)
        {
            :index           => panel_index,
            :width_mm        => panel_w_mm,
            :height_mm       => panel_h_mm,
            :origin_x_mm     => origin_x_mm,
            :hinge_x_mm      => hinge_x_mm,
            :hinge_y_mm      => 0.0,
            :rot_degrees     => rot_deg,
            :mve_axis        => nil,
            :mve_distance_mm => 0,
            :role            => :master,
            :has_handle      => false,
            :handle_side     => (jamb_side == :left ? :right : :left)
        }
    end
    private_class_method :na_build_master_descriptor
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build a Slave-Panel Descriptor (ROT + MVE)
    # ------------------------------------------------------------
    # Caller computes rot_degrees + mve_distance_mm via the shared
    # accordion helpers so V1.7.2 panels stack neatly at perpendicular.
    def self.na_build_slave_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, mve_axis, mve_distance_mm, has_handle, handle_side, rot_degrees)
        {
            :index           => panel_index,
            :width_mm        => panel_w_mm,
            :height_mm       => panel_h_mm,
            :origin_x_mm     => origin_x_mm,
            :hinge_x_mm      => hinge_x_mm,
            :hinge_y_mm      => 0.0,
            :rot_degrees     => rot_degrees.to_i,
            :mve_axis        => mve_axis,
            :mve_distance_mm => mve_distance_mm.to_i,
            :role            => :slave,
            :has_handle      => has_handle,
            :handle_side     => handle_side
        }
    end
    private_class_method :na_build_slave_descriptor
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__Layout__AllOneWay
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
