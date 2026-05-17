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
# - The master operates exactly like an ExteriorSingleDoor: ROT -90 about
#   its jamb hinge, no MVE. Handle is placed on the master's leading
#   edge (opposite the hinge).
# - Slave panels behave like an All-One-Way cascade towards the
#   opposite jamb. The slave-side jamb panel becomes a secondary master
#   (ROT -90, no MVE). All other slaves use ROT 180 + MVE.
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
        panel_count       = config_hash["bifold_door_panel_count"].to_i
        opening_w_mm      = config_hash["bifold_door_opening_width_mm"].to_f
        opening_h_mm      = config_hash["bifold_door_opening_height_mm"].to_f
        floor_clearance   = config_hash["bifold_door_floor_clearance_mm"].to_f
        master_side_raw   = (config_hash["bifold_door_master_side"] || "Right").to_s

        return [] if panel_count < 2 || opening_w_mm <= 0.0 || opening_h_mm <= 0.0

        panel_w_mm        = GeometryHelpers.na_compute_panel_width_mm(opening_w_mm, panel_count)
        panel_h_mm        = GeometryHelpers.na_compute_panel_height_mm(opening_h_mm, floor_clearance)

        return [] if panel_w_mm <= 0.0 || panel_h_mm <= 0.0

        master_left = (master_side_raw.downcase == "left")
        master_left ? na_build_master_left(panel_count, panel_w_mm, panel_h_mm) :
                      na_build_master_right(panel_count, panel_w_mm, panel_h_mm)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Master Position Variants
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors When the Master Is on the LEFT Jamb
    # ------------------------------------------------------------
    # Panel 1 = master (left jamb). Slaves 2..N cascade toward the
    # RIGHT jamb (panel N is the slave-side jamb master).
    def self.na_build_master_left(panel_count, panel_w_mm, panel_h_mm)
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
                slave_pos  = panel_count - 1 - i
                hinge_x_mm = origin_x_mm + panel_w_mm
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    +1 * slave_pos * panel_w_mm,
                    false                                                         # <-- Handle stays on master leaf
                )
            end
        end
        list
    end
    private_class_method :na_build_master_left
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors When the Master Is on the RIGHT Jamb
    # ------------------------------------------------------------
    # Panel N = master (right jamb). Slaves 1..N-1 cascade toward the
    # LEFT jamb (panel 1 is the slave-side jamb master).
    def self.na_build_master_right(panel_count, panel_w_mm, panel_h_mm)
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
                slave_pos  = i
                hinge_x_mm = origin_x_mm
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    -1 * slave_pos * panel_w_mm,
                    false                                                         # <-- Handle stays on master leaf
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
    def self.na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, jamb_side, has_handle)
        {
            :index           => panel_index,
            :width_mm        => panel_w_mm,
            :height_mm       => panel_h_mm,
            :origin_x_mm     => origin_x_mm,
            :hinge_x_mm      => hinge_x_mm,
            :hinge_y_mm      => 0.0,
            :rot_degrees     => -90,
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
    def self.na_build_slave_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, mve_axis, mve_distance_mm, has_handle)
        {
            :index           => panel_index,
            :width_mm        => panel_w_mm,
            :height_mm       => panel_h_mm,
            :origin_x_mm     => origin_x_mm,
            :hinge_x_mm      => hinge_x_mm,
            :hinge_y_mm      => 0.0,
            :rot_degrees     => 180,
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
