# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD LAYOUT: MASTER + SLAVES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__Layout__MasterSlaves__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__Layout__MasterSlaves
# AUTHOR     : Noble Architecture
# PURPOSE    : Layout algorithm for the "Master + Slaves" bifold mode
#              where ONE leaf swings 90 deg as a single door (the master),
#              and the remaining N-1 leaves cascade in the OPPOSITE
#              direction as a one-way bifold stack.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - `bifold_door_master_side` chooses which jamb the master is hinged to:
#     * "Left"  -> master is panel 1 (left jamb), slaves cascade toward
#                  the RIGHT jamb (panel N is the slave-side jamb master).
#     * "Right" -> master is panel N (right jamb), slaves cascade toward
#                  the LEFT jamb (panel 1 is the slave-side jamb master).
# - The LONE MASTER (walk-through leaf) swings outward to perpendicular
#   about its jamb hinge - it is hinge-direction-aware so a right-jamb
#   lone master uses +90 deg (not -90 deg) and a left-jamb lone master
#   uses -90 deg. Handle is on the master's leading edge.
# - The SLAVE-SIDE JAMB MASTER (cascade master) anchors the slave
#   accordion at the OPPOSITE jamb. Slaves rotate to perpendicular and
#   translate by k * (panel_w - panel_t - gap) toward that jamb, so they
#   stack at panel_t + gap from the previous panel (a true accordion
#   stack, not a flat deck of cards).
# - This pattern is common in domestic patio bifolds where the master
#   leaf operates daily as a "walk-through" door while the slaves are
#   only opened occasionally.
#
# COORDINATE SYSTEM (ADR-local):
# - Origin       = bottom-front-left corner of the structural opening.
# - X+           = along the wall (left -> right across opening).
# - Y+           = through the wall depth (front face at Y=0).
# - Z+           = upwards.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 1.7.2
# - Right-jamb lone master now swings OUTWARD (+90 deg) instead of into
#   the room (-90 deg). Slave cascade now uses the accordion helpers so
#   slaves rotate to perpendicular instead of 180 deg and translate by
#   k * (panel_w - panel_t - gap). Pre-V1.7.2 the slaves all collapsed
#   onto the cascade master's hinge, and a right-jamb lone master swung
#   into the room.
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
module Na__Layout__MasterSlaves

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Generate Panel Descriptors for the Master + Slaves Layout
    # ------------------------------------------------------------
    # @param config_hash [Hash] Bifold configuration (snake_case keys)
    # @return [Array<Hash>] Panel descriptors consumed by AssemblyComposer
    def self.na_generate_panel_descriptors(config_hash)
        panel_count     = config_hash["bifold_door_panel_count"].to_i
        master_side_raw = (config_hash["bifold_door_master_side"] || "Right").to_s

        return [] if panel_count < 2

        dims = GeometryHelpers.na_resolve_door_opening_dimensions(config_hash)
        return [] if dims[:inner_w_mm] <= 0.0 || dims[:inner_h_mm] <= 0.0

        panel_w_mm = GeometryHelpers.na_compute_panel_width_mm(dims[:inner_w_mm], panel_count)
        panel_h_mm = dims[:inner_h_mm]
        return [] if panel_w_mm <= 0.0 || panel_h_mm <= 0.0

        panel_t_mm = GeometryHelpers.na_resolve_panel_thickness_mm(config_hash)            # <-- Accordion-stack offset depends on panel thickness

        master_left = (master_side_raw.downcase == "left")
        master_left ? na_build_master_left(panel_count, panel_w_mm, panel_h_mm, panel_t_mm) :
                      na_build_master_right(panel_count, panel_w_mm, panel_h_mm, panel_t_mm)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Master Position Variants
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors When the Master Is on the LEFT Jamb
    # ------------------------------------------------------------
    # Panel 1 = lone master (left jamb, walk-through leaf).
    # Panels 2..N-1 = slaves that cascade toward the RIGHT jamb.
    # Panel N = slave-side cascade master (right jamb anchor).
    def self.na_build_master_left(panel_count, panel_w_mm, panel_h_mm, panel_t_mm)
        list = []
        (0...panel_count).each do |i|
            panel_index = i + 1
            origin_x_mm = i * panel_w_mm

            list << if i == 0
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, 0.0, :left, true)
            elsif i == panel_count - 1
                jamb_hinge_x = origin_x_mm + panel_w_mm
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, jamb_hinge_x, :right, false)
            else
                slave_pos  = panel_count - 1 - i                                                                       # <-- Counts back from right-jamb cascade master
                hinge_x_mm = origin_x_mm + panel_w_mm
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
                    false,                                                        # <-- Handle stays on lone master leaf
                    rot_deg
                )
            end
        end
        list
    end
    private_class_method :na_build_master_left
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors When the Master Is on the RIGHT Jamb
    # ------------------------------------------------------------
    # Panel N = lone master (right jamb, walk-through leaf).
    # Panels 2..N-1 = slaves that cascade toward the LEFT jamb.
    # Panel 1 = slave-side cascade master (left jamb anchor).
    def self.na_build_master_right(panel_count, panel_w_mm, panel_h_mm, panel_t_mm)
        list = []
        (0...panel_count).each do |i|
            panel_index = i + 1
            origin_x_mm = i * panel_w_mm

            list << if i == panel_count - 1
                jamb_hinge_x = origin_x_mm + panel_w_mm
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, jamb_hinge_x, :right, true)
            elsif i == 0
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, 0.0, :left, false)
            else
                slave_pos  = i                                                                                         # <-- Counts up from left-jamb cascade master
                hinge_x_mm = origin_x_mm
                rot_deg = GeometryHelpers.na_compute_panel_rot_degrees(slave_pos, :left)                               # <-- ~ -90 deg with alternating tilt
                mve_mm  = GeometryHelpers.na_compute_slave_mve_distance_mm(slave_pos, :left, panel_w_mm, panel_t_mm)   # <-- Negative offset toward LEFT jamb
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    mve_mm,
                    false,                                                        # <-- Handle stays on lone master leaf
                    rot_deg
                )
            end
        end
        list
    end
    private_class_method :na_build_master_right
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Panel Descriptor Builders
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build a Master-Panel Descriptor (Jamb-Hinged, ROT Only)
    # ------------------------------------------------------------
    # Routes the rotation through the accordion helper so the right-jamb
    # master swings OUTWARD (+90 deg) and the left-jamb master swings
    # OUTWARD (-90 deg), each with the small termination tilt. Used for
    # both the lone walk-through master AND the slave-side cascade
    # master at the opposite jamb.
    def self.na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, jamb_side, has_handle)
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
            :has_handle      => has_handle,
            :handle_side     => (jamb_side == :left ? :right : :left)
        }
    end
    private_class_method :na_build_master_descriptor
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build a Slave-Panel Descriptor (ROT + MVE)
    # ------------------------------------------------------------
    # Caller computes rot_degrees + mve_distance_mm via the shared
    # accordion helpers so V1.7.2 panels stack neatly at perpendicular.
    def self.na_build_slave_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, mve_axis, mve_distance_mm, has_handle, rot_degrees)
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
            :handle_side     => (mve_distance_mm < 0 ? :right : :left)
        }
    end
    private_class_method :na_build_slave_descriptor
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__Layout__MasterSlaves
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
