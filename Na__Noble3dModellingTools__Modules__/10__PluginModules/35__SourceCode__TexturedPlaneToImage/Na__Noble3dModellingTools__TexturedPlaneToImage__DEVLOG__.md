# Textured Plane to Image
# =============================================================================
# Module : 35__SourceCode__TexturedPlaneToImage
# Plugin : Na Noble3d Modelling Tools
# Tab    : Misc Utils > Ortho Reference Planes

## Overview

Replaces a positioned, textured rectangular face with a SketchUp Image of the
same width, height, and orientation. Images stay visible in wireframe. The
face is the size and position reference, so the image does not need a separate
scale step.

Parent entry: main devlog **Version 0.9.6** (24-Sep-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================

## Version 1.0.0 - 24-Sep-2026 - Initial Build

- Selects faces directly, or the faces inside a selected group or component.
- Requires a four-sided rectangle with a textured front or back material.
- Writes the texture region shown on the face, including a cropped or tiled mapping.
- Places the Image in the same entities collection, on the same tag, then erases the face.
- One undo restores the face.
