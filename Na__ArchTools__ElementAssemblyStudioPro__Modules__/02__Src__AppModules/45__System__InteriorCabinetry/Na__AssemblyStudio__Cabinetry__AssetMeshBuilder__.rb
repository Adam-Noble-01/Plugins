# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - ASSET MESH BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__AssetMeshBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__AssetMeshBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Turns the Na__Asset__Mesh3D block of a leg or handle asset into
#              a ComponentDefinition, once per asset (and per leg height), and
#              hands it back for placing as instances.
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - Same mesh contract as the door handles (Na__HandleBuilder3D): vertices by
#   VertexId in mm, faces by OuterLoop_VertexIds, edges by start / end vertex
#   with IsSoft / IsSmooth / IsHidden / CastsShadows, matched to SketchUp's
#   merged edges by position.
# - Definitions are material neutral; the finish goes on each instance.
# - LEG STRETCH: a leg asset names a stretch zone in Z
#   (Na__CabinetPlacement__StretchZoneMin_mm..Max_mm, inside its threaded
#   column). For a plinth height other than the nominal, points above the
#   zone move by the difference and points inside it scale, so the foot,
#   adjuster, sleeve and plate keep their real sizes. Below the asset's
#   MinHeight the zone is closed and the whole leg is scaled to fit.
# - A definition carries a signature of its mesh and height, so an edited
#   asset file rebuilds it rather than reusing a stale copy.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'digest'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__Cabinetry__AssetLibrary__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__AssetMeshBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers
        AssetLibrary    = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetLibrary

        NA_SIGNATURE_DICT = "Na__Cabinetry__AssetMeshBuilder".freeze
        NA_SIGNATURE_KEY  = "Na__MeshSignature".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_definition_cache = {}                                              # <-- definition name -> ComponentDefinition
        @na_signature_cache  = {}                                              # <-- "name|asset object id" -> signature (saves re-hashing a mesh per build)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | The Definition for a Handle Asset
        # ------------------------------------------------------------
        # @return [Sketchup::ComponentDefinition, nil]
        def self.na_handle_definition(asset_key)
            asset = AssetLibrary.na_load(:handles, asset_key)
            return nil unless asset
            na_definition_for("Na__Cabinetry__Handle__#{asset_key}", asset, nil)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Definition for a Leg Asset at a Given Height (mm)
        # ------------------------------------------------------------
        # @return [Sketchup::ComponentDefinition, nil]
        def self.na_leg_definition(asset_key, height_mm)
            asset = AssetLibrary.na_load(:legs, asset_key)
            return nil unless asset
            height = height_mm.to_f.round(1)
            na_definition_for("Na__Cabinetry__Leg__#{asset_key}__h#{format('%g', height)}", asset, height)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget Cached Definitions (Developer Reload, New Model)
        # ------------------------------------------------------------
        def self.na_clear_cache
            @na_definition_cache = {}
            @na_signature_cache  = {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stretch One Z Value to a New Leg Height (Pure, mm)
        # ------------------------------------------------------------
        # @param z        [Float] vertex Z in the asset (mm)
        # @param asset    [Hash]  leg asset (reads the Na__CabinetPlacement__ zone)
        # @param height   [Float] wanted leg height (mm)
        # @return [Float] new Z (mm)
        def self.na_stretch_z(z, asset, height)
            nominal = AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__NominalHeight_mm", 0).to_f
            zone_lo = AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__StretchZoneMin_mm", 0).to_f
            zone_hi = AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__StretchZoneMax_mm", 0).to_f
            return z if nominal <= 0 || zone_hi <= zone_lo || height.nil?

            zone      = zone_hi - zone_lo
            delta     = height - nominal
            new_zone  = zone + delta
            if new_zone <= 0                                                   # <-- Shorter than the zone allows: close it, scale the rest
                fixed = nominal - zone
                closed = z <= zone_lo ? z : (z >= zone_hi ? z - zone : zone_lo)
                return closed * (height / fixed)
            end
            return z if z <= zone_lo
            return z + delta if z >= zone_hi
            zone_lo + (z - zone_lo) * (new_zone / zone)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definition Builder
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Get or Build a Definition From an Asset Mesh
        # ------------------------------------------------------------
        def self.na_definition_for(name, asset, height)
            mesh = asset["Na__Asset__Mesh3D"]
            unless na_valid_mesh?(mesh)
                DebugTools.na_debug_warn("Cabinetry asset '#{name}' has no usable Na__Asset__Mesh3D")
                return nil
            end

            model = Sketchup.active_model
            return nil unless model
            memo_key  = "#{name}|#{asset.object_id}"
            signature = (@na_signature_cache[memo_key] ||= Digest::SHA256.hexdigest("v1|#{height}|#{JSON.generate(mesh)}"))

            cached = @na_definition_cache[name]
            return cached if cached && cached.valid? && na_signature(cached) == signature

            definition = model.definitions[name]
            if definition && definition.valid? && na_signature(definition) == signature && !definition.entities.grep(Sketchup::Face).empty?
                @na_definition_cache[name] = definition
                return definition
            end

            definition ||= model.definitions.add(name)
            definition.entities.clear!
            built = na_build_mesh(definition.entities, mesh, asset, height)
            if built.zero?
                DebugTools.na_debug_warn("Cabinetry asset '#{name}' built no faces")
                return nil
            end
            definition.set_attribute(NA_SIGNATURE_DICT, NA_SIGNATURE_KEY, signature)
            @na_definition_cache[name] = definition
            DebugTools.na_debug_geometry("Built cabinetry asset definition '#{name}' (#{built} faces)")
            definition
        end
        private_class_method :na_definition_for
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add the Mesh Faces, Then Apply the Edge Flags
        # ------------------------------------------------------------
        def self.na_build_mesh(entities, mesh, asset, height)
            points = {}
            mesh["Na__Geometry__Vertices"].each do |record|
                z = record["PosZ_mm"].to_f
                z = na_stretch_z(z, asset, height) if height
                points[record["VertexId"]] = GeometryHelpers.na_point(record["PosX_mm"].to_f, record["PosY_mm"].to_f, z)
            end

            built = 0
            mesh["Na__Geometry__Faces"].each do |record|
                loop_points = (record["OuterLoop_VertexIds"] || []).map { |id| points[id] }.compact
                next if loop_points.length < 3
                begin
                    face = entities.add_face(loop_points)
                    built += 1 if face && face.valid?
                rescue ArgumentError
                    next                                                       # <-- Degenerate after stretching (collapsed zone); skip it
                end
            end
            na_apply_edge_flags(entities, mesh, points)
            built
        end
        private_class_method :na_build_mesh
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Soft / Smooth / Hidden Flags Onto the Merged Edges
        # ------------------------------------------------------------
        def self.na_apply_edge_flags(entities, mesh, points)
            flags = {}
            (mesh["Na__Geometry__Edges"] || []).each do |record|
                a = points[record["StartVertex"]]
                b = points[record["EndVertex"]]
                next unless a && b
                flags[na_edge_key(a, b)] = record
            end
            return if flags.empty?

            entities.grep(Sketchup::Edge).each do |edge|
                record = flags[na_edge_key(edge.start.position, edge.end.position)]
                next unless record
                edge.soft   = record["IsSoft"] == true
                edge.smooth = record["IsSmooth"] == true
                edge.hidden = true if record["IsHidden"] == true
                edge.casts_shadows = (record["CastsShadows"] != false) if edge.respond_to?(:casts_shadows=)
            end
        end
        private_class_method :na_apply_edge_flags
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Position Key for an Unordered Edge (6 dp, inches)
        # ------------------------------------------------------------
        def self.na_edge_key(a, b)
            [a, b].map { |pt| format("%.6f|%.6f|%.6f", pt.x.to_f, pt.y.to_f, pt.z.to_f) }.sort.join("||")
        end
        private_class_method :na_edge_key
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Mesh Block Have Vertices and Faces
        # ------------------------------------------------------------
        def self.na_valid_mesh?(mesh)
            mesh.is_a?(Hash) &&
                mesh["Na__Geometry__Vertices"].is_a?(Array) && !mesh["Na__Geometry__Vertices"].empty? &&
                mesh["Na__Geometry__Faces"].is_a?(Array) && !mesh["Na__Geometry__Faces"].empty?
        end
        private_class_method :na_valid_mesh?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Signature Stored on a Definition
        # ------------------------------------------------------------
        def self.na_signature(definition)
            definition.get_attribute(NA_SIGNATURE_DICT, NA_SIGNATURE_KEY, "").to_s
        end
        private_class_method :na_signature
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__AssetMeshBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
