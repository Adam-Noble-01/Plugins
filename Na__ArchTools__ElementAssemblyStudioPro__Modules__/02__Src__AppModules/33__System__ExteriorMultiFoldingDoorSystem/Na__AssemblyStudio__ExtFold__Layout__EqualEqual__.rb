# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD LAYOUT: EQUAL-EQUAL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__Layout__EqualEqual__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__Layout__EqualEqual
# AUTHOR     : Noble Architecture
# PURPOSE    : Layout algorithm for the "Equal-Equal" bifold mode where
#              the panel set is split open to BOTH sides of the opening.
#              For an even panel count, half cascade left and half
#              cascade right. For an odd panel count, the centre panel
#              is fixed (no ROT, no MVE) and the surrounding pairs split
#              in equal halves.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - The leftmost and rightmost panels are jamb-hinged "masters" that
#   swing -90 deg outward; their MOD name uses NA_MOD_NAME_FORMAT_ROT_ONLY.
# - All other panels are slaves: they fold 180 deg about their joint
#   hinge with the adjacent panel AND translate along the head track
#   toward the corresponding jamb (left half: -X track displacement;
#   right half: +X track displacement). Their MOD name uses
#   NA_MOD_NAME_FORMAT_ROT_MVE.
# - Handles are placed on the two "leading" slaves closest to the centre
#   of the opening (the ones whose handles meet when the door is closed).
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
module Na__Layout__EqualEqual

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Generate Panel Descriptors for the Equal-Equal Layout
    # ------------------------------------------------------------
    # @param config_hash [Hash] Bifold configuration (snake_case keys)
    # @return [Array<Hash>] Panel descriptors consumed by AssemblyComposer
    def self.na_generate_panel_descriptors(config_hash)
        panel_count       = config_hash["bifold_door_panel_count"].to_i
        opening_w_mm      = config_hash["bifold_door_opening_width_mm"].to_f
        opening_h_mm      = config_hash["bifold_door_opening_height_mm"].to_f
        floor_clearance   = config_hash["bifold_door_floor_clearance_mm"].to_f

        return [] if panel_count < 2 || opening_w_mm <= 0.0 || opening_h_mm <= 0.0

        panel_w_mm        = GeometryHelpers.na_compute_panel_width_mm(opening_w_mm, panel_count)
        panel_h_mm        = GeometryHelpers.na_compute_panel_height_mm(opening_h_mm, floor_clearance)

        return [] if panel_w_mm <= 0.0 || panel_h_mm <= 0.0

        if panel_count.even?
            na_build_descriptors_even_split(panel_count, panel_w_mm, panel_h_mm)
        else
            na_build_descriptors_odd_split(panel_count, panel_w_mm, panel_h_mm)
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Even Split
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors for Even-Count Equal-Equal
    # ------------------------------------------------------------
    # Half the panels cascade to the left jamb, half to the right.
    # Panel 1 hinges on the LEFT JAMB (master, ROT -90, no MVE).
    # Panel N hinges on the RIGHT JAMB (master, ROT -90, no MVE).
    # Panels in between are slaves that fold 180 + slide toward their
    # corresponding jamb.
    def self.na_build_descriptors_even_split(panel_count, panel_w_mm, panel_h_mm)
        descriptors = []
        half_count  = panel_count / 2

        descriptors.concat(na_build_left_half_descriptors(half_count, panel_w_mm, panel_h_mm, 1))

        right_start_index = half_count + 1
        descriptors.concat(na_build_right_half_descriptors(half_count, panel_w_mm, panel_h_mm, right_start_index, panel_count))

        descriptors
    end
    private_class_method :na_build_descriptors_even_split
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors for Odd-Count Equal-Equal
    # ------------------------------------------------------------
    # Centre panel is fixed (master, no rotation, no translation).
    # Surrounding pairs split equally to both sides.
    def self.na_build_descriptors_odd_split(panel_count, panel_w_mm, panel_h_mm)
        descriptors  = []
        side_count   = (panel_count - 1) / 2

        descriptors.concat(na_build_left_half_descriptors(side_count, panel_w_mm, panel_h_mm, 1))

        centre_index = side_count + 1
        descriptors << na_build_centre_fixed_descriptor(centre_index, panel_w_mm, panel_h_mm)

        right_start_index = side_count + 2
        descriptors.concat(na_build_right_half_descriptors(side_count, panel_w_mm, panel_h_mm, right_start_index, panel_count))

        descriptors
    end
    private_class_method :na_build_descriptors_odd_split
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Per-Half Cascade
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors for the Left-Cascading Half
    # ------------------------------------------------------------
    # Indices run 1..half_count (1-based, left-most is the master).
    # Each successive panel folds back toward the LEFT jamb.
    def self.na_build_left_half_descriptors(half_count, panel_w_mm, panel_h_mm, start_index)
        list = []
        (0...half_count).each do |i|
            panel_index   = start_index + i
            origin_x_mm   = i * panel_w_mm
            slave_position = i

            list << if i == 0
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, 0.0, :left)
            else
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    origin_x_mm,                                         # <-- Hinge on LEFT edge (joint with previous)
                    'X',
                    -1 * slave_position * panel_w_mm,                    # <-- Negative track displacement toward left jamb
                    (slave_position == half_count - 1)                   # <-- Handle on the leading slave
                )
            end
        end
        list
    end
    private_class_method :na_build_left_half_descriptors
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Descriptors for the Right-Cascading Half
    # ------------------------------------------------------------
    # Indices run start_index..panel_count_total (right-most is master).
    # Each successive panel folds toward the RIGHT jamb.
    def self.na_build_right_half_descriptors(half_count, panel_w_mm, panel_h_mm, start_index, panel_count_total)
        list = []
        (0...half_count).each do |i|
            panel_index    = start_index + i
            origin_x_mm    = (start_index - 1 + i) * panel_w_mm
            slave_position = half_count - 1 - i

            list << if i == half_count - 1
                jamb_hinge_x = origin_x_mm + panel_w_mm
                na_build_master_descriptor(panel_index, origin_x_mm, panel_w_mm, panel_h_mm, jamb_hinge_x, :right)
            else
                hinge_x_mm = origin_x_mm + panel_w_mm
                na_build_slave_descriptor(
                    panel_index,
                    origin_x_mm,
                    panel_w_mm,
                    panel_h_mm,
                    hinge_x_mm,                                          # <-- Hinge on RIGHT edge (joint with next)
                    'X',
                    +1 * slave_position * panel_w_mm,                    # <-- Positive track displacement toward right jamb
                    (i == 0)                                             # <-- Handle on the leading slave (closest to centre)
                )
            end
        end
        list
    end
    private_class_method :na_build_right_half_descriptors
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

    # HELPER FUNCTION | Build a Centre-Fixed Descriptor (Odd Panel Count)
    # ------------------------------------------------------------
    def self.na_build_centre_fixed_descriptor(panel_index, panel_w_mm, panel_h_mm)
        origin_x_mm = (panel_index - 1) * panel_w_mm
        {
            :index           => panel_index,
            :width_mm        => panel_w_mm,
            :height_mm       => panel_h_mm,
            :origin_x_mm     => origin_x_mm,
            :hinge_x_mm      => origin_x_mm + panel_w_mm / 2.0,
            :hinge_y_mm      => 0.0,
            :rot_degrees     => 0,
            :mve_axis        => nil,
            :mve_distance_mm => 0,
            :role            => :standalone,
            :has_handle      => false,
            :handle_side     => :right
        }
    end
    private_class_method :na_build_centre_fixed_descriptor
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__Layout__EqualEqual
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
