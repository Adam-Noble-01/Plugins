# To Scale Ortho Texture Maker
# =============================================================================
# Module : 34__SourceCode__ToScaleOrthoTextureMaker
# Plugin : Na Noble3d Modelling Tools
# Tab    : Misc Utils > Ortho Reference Planes

## Overview

Captures the active parallel-projection viewport as a flat textured plane that
matches the view, then can export that texture as a PNG whose filename carries
the true-scale millimetre size.

Group prefix `Na__Ortho__` and attribute dictionary `Na__Ortho__Capture` are
unchanged, so groups captured by the standalone plugin still export.

Parent entry: main devlog **Version 0.9.5** (24-Sep-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================

## Version 3.0.0 - 24-Sep-2026 - Ported into Noble 3D Tools

- Moved out of the standalone `Na__ToScaleOrthoTextureMaker` plugin.
- Menu and hotkey registration now come from the Noble command registry.
- Capture, plane, material, and export responsibilities stay in separate files.
- Dialog styling follows the Noble light theme.
