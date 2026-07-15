# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC SECTION PLANE CAPTURE
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__SectionPlaneCapture__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__SectionPlaneCapture
# PURPOSE    : Capture the active SketchUp section plane(s) for each IMG## scene
#              so ValeVision3D can auto-create matching live cross sections
# CREATED    : 15-Jul-2026
#
# DESCRIPTION:
# - Uses the SketchUp 2026+ Sketchup::Page#active_section_planes API to read
#   which section plane(s) a scene activates WITHOUT switching pages.
# - Only pages that store the section-plane property (use_section_planes?)
#   contribute data — scenes that do not manage sections emit nothing, so
#   ValeVision leaves its own per-scene section bindings untouched for them.
# - Only MODEL-LEVEL section planes are captured (world coordinates). Planes
#   nested inside groups/components are skipped with a console note; their
#   local-to-world transform chain is deliberately out of scope for v1.
# - Plane maths: get_plane returns [a, b, c, d] (inches) for
#   Ax + By + Cz + D = 0. SketchUp keeps geometry IN FRONT of the plane (the
#   normal side) — the same sign convention as three.js clipping planes, so
#   ValeVision consumes normal + position directly:
#       normal      = (a, b, c) / |(a, b, c)|          (unit, Z-up)
#       position_mm = (-d / |(a, b, c)|) * 25.4        (along the normal)
#   The Z-up -> Y-up axis swap is handled by the ValeVision3D web app,
#   exactly as it is for the camera vectors in this data block.
# - Degrades safely: pre-2026 SketchUp (no active_section_planes) and any
#   per-scene error both return nil, never aborting the camera capture.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 15-Jul-2026 - Version 1.0.0
# - Initial implementation (per-scene SketchUp section plane capture).
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__SectionPlaneCapture

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        INCHES_TO_MM = 25.4  # <-- SketchUp internal unit is inches

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Active Section Planes For One Scene Page
        # ------------------------------------------------------------
        # Returns an Array of section plane hashes (usually one — SketchUp
        # allows a single active plane per entities context), or nil when the
        # scene has no captured section state. nil means "this scene does not
        # manage sections" and MUST stay nil (not []) so ValeVision leaves its
        # own bindings untouched for the scene.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__CaptureSectionPlanesForScene(page)
            return nil unless page.respond_to?(:active_section_planes)       # <-- SketchUp 2026+ API only
            return nil unless page.use_section_planes?                       # <-- Scene does not store section-plane state

            active_planes = page.active_section_planes
            return nil if active_planes.nil? || active_planes.empty?

            captured = []
            active_planes.each do |section|
                next unless section.is_a?(Sketchup::SectionPlane)

                unless section.parent.is_a?(Sketchup::Model)
                    puts "[Na__ValeVisionCloudSync] Nested section plane skipped on scene '#{page.name}' (group/component sections unsupported)"
                    next
                end

                entry = na_convert_section_plane(section)
                captured << entry if entry
            end

            captured.empty? ? nil : captured
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plane Conversion
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Convert One SectionPlane to the ValeVision Data Hash
        # ---------------------------------------------------------------
        def self.na_convert_section_plane(section)
            plane = section.get_plane                                        # <-- [a, b, c, d] plane coefficients (inches)
            return nil unless plane.is_a?(Array) && plane.length >= 4

            a, b, c, d = plane[0].to_f, plane[1].to_f, plane[2].to_f, plane[3].to_f
            length     = Math.sqrt((a * a) + (b * b) + (c * c))
            return nil if length < 1e-9                                      # <-- Degenerate plane: skip defensively

            section_name = section.respond_to?(:name) ? section.name.to_s : ''

            {
                'name'        => section_name,
                'coordinate_system' => 'SketchUp_Z_up',                      # <-- Web app performs the Y-up swap (matches camera block)
                'normal'      => {
                    'x' => (a / length).round(6),
                    'y' => (b / length).round(6),
                    'z' => (c / length).round(6)
                },
                'position_mm' => ((-d / length) * INCHES_TO_MM).round(2),    # <-- Plane position along its normal
                'keep_side'   => 'front'                                     # <-- SketchUp keeps geometry on the normal side
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__SectionPlaneCapture
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
