# =============================================================================
# NA NOBLE3D MODELLING TOOLS - AGENT OUTLINER - LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__AgentOutliner__Loader__.rb
# NAMESPACE  : Na__Noble3dModellingTools (host) / Na__AgentOutliner (module)
# PURPOSE    : Entry point required by Na__Noble3dModellingTools__ModuleLoaders__Main__.rb
# CREATED    : 10-Nov-2026
#
# NOTES:
# This loader wires the self-contained Agent Outliner into Noble 3D Tools. The
# module keeps its own Na__AgentOutliner namespace (as Component Editor Tools
# keeps Na__ComponentEditorTools), opens its own HtmlDialog from the Entity
# Utils tab, the Extensions menu or a shortcut, and is what the Na SketchUp MCP
# tools agent_outliner and agent_outliner_edit call (06__McpOperations).
#
# @delegate: 01__AppCore/Na__AgentOutliner__AppCore__Main__.rb
#
# =============================================================================

require_relative '01__AppCore/Na__AgentOutliner__AppCore__Main__'

# =============================================================================
# END OF FILE
# =============================================================================
