# encoding: UTF-8
# idk_overlay_entity.rb

# ENTITIES OVERLAY EXTENSION
# --------------------------------------------------------------------
# DESCRIPTION:
# Displays entity info in configurable 2D/3D overlays, including tag name,
# instance and definition names, volume, area, length, and component descriptions.
# Labels support zoom-aware fading, customizable font size and color, optional
# tag color swatches, and user-defined overlay position. Overlay contents are
# fully configurable with toggles for each info type and real-time visual updates.
# --------------------------------------------------------------------
# CHANGELOG
# --------------------------------------------------------------------
# 1.0.0 - 2025-07-16
# • Initial release.
# • Displays entity info as 2D or 3D labels.
# • Toggle options for label overlay, leader lines, zoom-aware fading, and entity info detail.
# • Sliders to adjust label angle (0–360°) and label offset distance (inches).
# • Responsive HTML dialog using Bootstrap + Modus with dark mode support.
# --------------------------------------------------------------------
# 1.0.1 - 2025-07-17
# • Fixed zoom fading logic to properly interpolate between fade start and end distances.
# • Restored 3D label font color support (was overridden by fade color).
# • Added tag color swatches in both 2D and 3D label views.
# • Improved leader line rendering and color reset behavior.
# • UI sliders now adjust fade start and end distances in real time.
# --------------------------------------------------------------------
# 1.1.5 - 2025-07-18
# • Added toggles to control display of instance name, definition name, and volume.
# • Added support for wrapping long component descriptions.
# • New toggle to show or hide component description.
# • New toggle to show or hide the "Tag:" label (independent of swatch).
# • All toggle states are persisted using localStorage and synced with the overlay.
# --------------------------------------------------------------------
# 1.1.6 - 2025-09-09
# • Added arc, curve, circle, polygon support.
# --------------------------------------------------------------------
# 1.1.7 - 2025-09-09
# • Edit Component Description modal added.
# --------------------------------------------------------------------
# 1.1.8 - 2025-09-10
# • Volume, area, length, radius, segments completed.
# --------------------------------------------------------------------
# 2.0.0 - 2025-09-14
# • Updated — UI and overlay features redesigned for clarity and flexibility.
# • Added measurement toggles: Area, Length, Radius, and Segments.
# • Integrated Edit Component Description modal (with undo support).
# • Reworked dark mode toggle.
# • Removed unused Settings modal for a cleaner interface.
# • Leader offset slider now uses inches; fade distances use feet.
# • Improved persistence of all toggle/slider states via localStorage and Ruby sync.
# • Notifications system added for user feedback (warnings, info, errors).
# --------------------------------------------------------------------
# 2.0.0 - 2025-09-15
# • Show background added.
# --------------------------------------------------------------------

module IDKProgramming
  module OverlayEntity

    VERSION = '2.0.1'

    EXTENSION_NAME = 'Overlay Entity Info'
    LOADER_PATH = 'idk_overlay_entity/overlay_entity_loader'
    CREATOR = 'IDK Programming' 
    COPYRIGHT = '©2025 by IDK Programming. All rights reserved.' 
    DESCRIPTION = 'An overlay extension that displays Entity Info in 2D onscreen, as 3D labels, or both.'

    extension = SketchupExtension.new(EXTENSION_NAME, LOADER_PATH)
    extension.version = VERSION
    extension.creator = CREATOR
    extension.copyright = COPYRIGHT
    extension.description = DESCRIPTION
    
    Sketchup.register_extension(extension, true)

  end 
end

# • DESCRIPTION (short):
# • Display entity information directly in your model with configurable 2D and 3D overlays.
# • Show tags, names, descriptions, and measurements with customizable colors, font size,
# • and position. Includes zoom-aware fading, dark mode support, and quick toggles for
# • each info type.