# =============================================================================
# NA NOBLE3D MODELLING TOOLS - COMPONENT EDITOR TOOLS - LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ComponentEditorTools__Loader__.rb
# NAMESPACE  : Na__Noble3dModellingTools (host) / Na__ComponentEditorTools (module)
# PURPOSE    : Entry point required by Na__Noble3dModellingTools__ModuleLoaders__Main__.rb
# CREATED    : 2026
#
# NOTES:
# This loader wires the self-contained Component Editor Tools module into the
# Noble 3D Modelling Tools plugin. The module retains its own Na__ComponentEditorTools
# namespace and opens as an independent HtmlDialog launched from the Entity Utils tab.
#
# @delegate: 01__AppCore/Na__ComponentEditorTools__AppCore__Main__.rb
#
# =============================================================================

require_relative '01__AppCore/Na__ComponentEditorTools__AppCore__Main__'

# =============================================================================
# END OF FILE
# =============================================================================
