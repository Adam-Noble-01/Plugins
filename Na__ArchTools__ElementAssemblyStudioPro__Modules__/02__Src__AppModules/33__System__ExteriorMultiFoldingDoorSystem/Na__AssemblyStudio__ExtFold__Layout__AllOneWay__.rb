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
# - Slave MVE distance scales linearly: the k-th slave from the master
#   travels k * panel_w_mm toward the jamb (track-side approximation;
#   the TrueVision animation refines the actual cascade arc in Phase 6).
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
        panel_count       = config_hash["bifold_door_panel_count"].to_i
        opening_w_mm      = config_hash["bifold_door_opening_width_mm"].to_f
        opening_h_mm      = config_hash["bifold_door_opening_height_mm"].to_f
        floor_clearance   = config_hash["bifold_door_floor_clearance_mm"].to_f
        open_side_raw     = (config_hash["bifold_door_open_side"] || "Right").to_s

        return [] if panel_count < 2 || opening_w_mm <= 0.0 || opening_h_mm <= 0.0

        panel_w_mm        = GeometryHelpers.na_compute_panel_width_mm(opening_w_mm, panel_count)
        panel_h_mm        = GeometryHelpers.na_compute_panel_height_mm(opening_h_mm, floor_clearance)

        return [] if panel_w_mm <= 0.0 || panel_h_mm <= 0.0

        cascade_left = (open_side_raw.downcase == "left")
        cascade_left ? na_build_left_cascade(panel_count, panel_w_mm, panel_h_mm) :
                       na_build_right_cascade(panel_count, panel_w_mm, panel_h_mm)
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
    def self.na_build_left_cascade(panel_count, panel_w_mm, panel_h_mm)
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
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    -1 * slave_pos * panel_w_mm,                                  # <-- Negative track displacement toward LEFT jamb
                    is_leading,
                    :right                                                        # <-- Handle on right edge of leading slave
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
    def self.na_build_right_cascade(panel_count, panel_w_mm, panel_h_mm)
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
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,
                    'X',
                    +1 * slave_pos * panel_w_mm,                                  # <-- Positive track displacement toward RIGHT jamb
                    is_leading,
                    :left                                                         # <-- Handle on left edge of leading slave
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
    def self.na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, jamb_side)
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
            :has_handle      => false,
            :handle_side     => (jamb_side == :left ? :right : :left)
        }
    end
    private_class_method :na_build_master_descriptor
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build a Slave-Panel Descriptor (ROT + MVE)
    # ------------------------------------------------------------
    def self.na_build_slave_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, hinge_x_mm, mve_axis, mve_distance_mm, has_handle, handle_side)
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
