# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - APPLIANCE BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__ApplianceBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__ApplianceBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Places an appliance housing's built-in appliances (an oven, a
#              warming drawer ...) from Adam's component library into the
#              cabinet, in the apertures Na__LayoutResolver gives (V2.7.6).
# CREATED    : 23-Nov-2026
#
# DESCRIPTION:
# - A housing stores each appliance as a library CODE ("17_1001"), never a
#   path, so a model carried to another PC still builds. The definition is
#   found in this order:
#     1. a definition already in the model whose name starts "<code>__"
#        (the library's rule: the component is named exactly like its file);
#     2. the file "<code>__*.skp" under the component library's category
#        folder "NN__*" (NN = the code's first two digits), outside the
#        blocked folders, in the Component Editor Tools' library path, then
#        its fallbacks.
#   An absolute .skp path is also taken as it is.
# - The library items are modelled for a 600 slot with 20 sides: the fascia
#   595 wide at x 2.5, the body 560 wide at x 20 to 580, their origin on the
#   carcass front at the aperture's bottom, +Y into the unit. So they drop
#   into the unit frame with no rotation, fascias flush with 20 doors.
# - A code that cannot be found leaves its aperture empty with a warning;
#   the cabinet still builds.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__ApplianceBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers

        NA_APPLIANCES_GROUP = "Na__Cabinet__Appliances".freeze
        NA_APPLIANCE_NAME   = "Na__Cabinet__%s".freeze                           # <-- Na__Cabinet__Appliance__Upper

        # The Component Editor Tools' own defaults, used when that plugin is
        # not loaded (Na__ComponentEditorTools::Na__UserConfig).
        NA_LIBRARY_PATHS = [
            "D:/06_CoreLib__Web3D/SketchUp__SourceFiles/10__SketchUp__CoreComponentLib",
            "D:/30__Weblib__3dAssets/SketchUp__SourceFiles/10__SketchUp__CoreComponentLib"
        ].freeze
        NA_BLOCKED_FOLDERS  = %w[00__Archive 00__Retired 95__TEMP__Ripdown].freeze
        NA_CODE_REGEX       = /\A(\d{2})_\d{4}\z/

        @na_found_files = {}                                                     # <-- code => path, for this session

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Place Every Appliance the Layout Lists (Nil When None)
        # ------------------------------------------------------------
        # @param layout   [Hash] Na__LayoutResolver.na_resolve output
        # @param entities [Sketchup::Entities] the cabinet definition's
        # @return [Sketchup::Group, nil]
        def self.na_build(layout, entities)
            appliances = Array(layout[:appliances])
            return nil if appliances.empty?

            group = nil
            appliances.each do |appliance|
                definition = na_definition(appliance[:code])
                unless definition
                    layout[:warnings] << "Appliance #{appliance[:code]} is not in the model or the component library, so its aperture is empty."
                    next
                end
                group ||= GeometryHelpers.na_add_group(entities, NA_APPLIANCES_GROUP)
                origin   = GeometryHelpers.na_point(appliance[:x0], appliance[:y], appliance[:z0])
                instance = group.entities.add_instance(definition, Geom::Transformation.new(origin))
                instance.name = format(NA_APPLIANCE_NAME, appliance[:name])
            end
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Definition for a Library Code (or a .skp Path), Nil When Not Found
        # ------------------------------------------------------------
        def self.na_definition(code)
            text  = code.to_s.strip
            return nil if text.empty?
            model = Sketchup.active_model
            return nil unless model

            if text =~ NA_CODE_REGEX
                head  = "#{text}__"
                found = model.definitions.find { |definition| definition.name.start_with?(head) && !definition.group? && !definition.image? }
                return found if found
            end
            path = na_file_for(text)
            return nil unless path
            model.definitions.load(path)
        rescue StandardError => e
            DebugTools.na_debug_warn("Appliance '#{text}' could not be loaded: #{e.message}")
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Library File for a Code, Nil When There Is None
        # ------------------------------------------------------------
        def self.na_file_for(code)
            text = code.to_s.strip
            return (File.file?(text) ? text : nil) if text.downcase.end_with?(".skp")
            match = NA_CODE_REGEX.match(text)
            return nil unless match
            cached = @na_found_files[text]
            return cached if cached && File.file?(cached)

            na_library_roots.each do |root|
                pattern = File.join(root, "*", "#{match[1]}__*", "**", "#{text}__*.skp")
                hit = Dir.glob(pattern).sort.find { |path| (path.split(/[\\\/]/) & NA_BLOCKED_FOLDERS).empty? }
                next unless hit
                @na_found_files[text] = hit
                return hit
            end
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Component Library's Roots, the Configured One First
        # ------------------------------------------------------------
        def self.na_library_roots
            roots = []
            if defined?(::Na__ComponentEditorTools::Na__UserConfig) &&
               ::Na__ComponentEditorTools::Na__UserConfig.respond_to?(:Na__ComponentEditorTools__LibraryPath)
                begin
                    roots << ::Na__ComponentEditorTools::Na__UserConfig.Na__ComponentEditorTools__LibraryPath.to_s
                rescue StandardError => e
                    DebugTools.na_debug_warn("Component library path unreadable: #{e.message}")
                end
            end
            (roots + NA_LIBRARY_PATHS).map(&:strip).reject(&:empty?).uniq.select { |root| Dir.exist?(root) }
        end
        private_class_method :na_library_roots
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ApplianceBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
