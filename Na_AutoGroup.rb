# =============================================================================
# VALEDESIGNSUITE - AUTO GROUP SOLID ISLANDS
# =============================================================================
#
# FILE       : NaTools_Tools_AutoGroupSolidIslands.rb
# NAMESPACE  : NaTools::Tools
# MODULE     : AutoGroupSolidIslands
# AUTHOR     : Adam Noble - Vale Garden Houses
# PURPOSE    : Detects and groups disconnected solid islands of geometry from
#              the current SketchUp selection. Provides warnings if any group
#              is not a valid manifold solid.
# CREATED    : 28-May-2025
#
# DESCRIPTION:
# - Automatically detects all discrete geometry islands (connected face/edge sets)
#   in the active selection.
# - Each island is grouped into its own SketchUp Group.
# - If any group is not a valid manifold solid, it will be listed in a warning.
# - Intended for workflow automation where multiple ungrouped solids must be
#   processed efficiently.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 28-May-2025 - Version 1.0.0
# - Initial implementation of auto-grouping for disconnected solid islands.
# - Added validation using Group#manifold? to flag non-solids.
# 28-May-2025 - Version 1.1.0
# - Added SketchUp Extension Menu item to allow hotkey binding via UI.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Main Tool Functionality - Auto Group Solid Islands
# -----------------------------------------------------------------------------

module NaTools
	module Tools
		module AutoGroupSolidIslands

			# FUNCTION | Run Auto Grouping and Solid Validation
			# ------------------------------------------------------------
			def self.run
				model     = Sketchup.active_model                         # <-- Access current model
				selection = model.selection                              # <-- Get current selection
				ents      = model.active_entities                         # <-- Active editing context

				if selection.empty?
					UI.messagebox("Please select geometry to process.")
					return
				end

				geom = selection.grep(Sketchup::Edge) + selection.grep(Sketchup::Face)
				if geom.empty?
					UI.messagebox("Selection contains no raw geometry (edges/faces).")
					return
				end

				# Detect disconnected islands
				islands = []
				remaining = geom.uniq

				until remaining.empty?
					seed      = remaining.first
					connected = seed.all_connected
					islands << connected
					remaining -= connected
				end

				model.start_operation("Auto Group Solids", true)

				grouped     = []
				non_solids  = []

				islands.each do |cluster|
					group = ents.add_group(cluster)
					grouped << group

					is_solid = false
					begin
						is_solid = group.manifold?                        # <-- Newer API method for solid validation
					rescue
						is_solid = false
					end

					non_solids << group unless is_solid
				end

				model.commit_operation

				if non_solids.any?
					UI.messagebox("\u26A0 Some groups are NOT valid solids:\n\n" + non_solids.map(&:entityID).join("\n"))
				end
			end
			# ---------------------------------------------------------------

		end # module AutoGroupSolidIslands
	end # module Tools
end # module NaTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Extension Menu and Keybinding Integration
# -----------------------------------------------------------------------------

unless file_loaded?(__FILE__)
	UI.menu("Extensions").add_item("NA | Auto Group Utility") {
		NaTools::Tools::AutoGroupSolidIslands.run               # <-- Binds command to Plugins menu
	}
	file_loaded(__FILE__)
end

# endregion -------------------------------------------------------------------
