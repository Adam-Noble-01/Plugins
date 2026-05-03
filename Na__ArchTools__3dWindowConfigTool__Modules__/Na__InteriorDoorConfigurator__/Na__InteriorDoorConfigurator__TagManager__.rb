# =============================================================================
# NA INTERIOR DOOR CONFIGURATOR - TAG MANAGER
# =============================================================================
#
# FILE       : Na__InteriorDoorConfigurator__TagManager__.rb
# NAMESPACE  : Na__InteriorDoorConfigurator
# MODULE     : Na__TagManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Resolves and creates SketchUp tags (layers) for door entities
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Pulls tag standards from the shared Na__DataLib (Na__DataLib__CoreIndex__Tags__.json).
# - Resolves the canonical SketchUp tag name for the role (e.g. door swings, door closed,
#   door open, proposed doors container) and creates it in the active model on demand.
# - Provides a hardcoded fallback when the DataLib is unreachable so the tool never breaks.
# - Roles map to the following DataLib tags (with hardcoded fallbacks):
#     * door_swing      -> 02__Linetype__DoorSwings
#     * door_closed     -> Na__Door__Closed              (door-tool specific)
#     * door_open       -> Na__Door__Open                (door-tool specific)
#     * door_panel      -> Na__DoorPanel                 (door-tool specific)
#     * door_lining     -> Na__DoorLining                (door-tool specific)
#     * architrave      -> Na__Architrave               (door-tool specific)
#     * door_handle     -> Na__DoorHandle                (door-tool specific)
#     * proposed_doors  -> 25__ProposedBuilding__Doors  (TrueVision GLB segmentation)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
# - Three-stage role keys are kept as plain symbols for terse internal lookup.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InteriorDoorConfigurator__DebugTools__'

module Na__InteriorDoorConfigurator
    module Na__TagManager

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__InteriorDoorConfigurator::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Role -> Hardcoded Fallback Tag Name
        # ------------------------------------------------------------
        # These are used when the DataLib is unreachable. Where a DataLib
        # entry exists with a different name, na_resolve_tag_name will
        # prefer the DataLib entry over these defaults.
        NA_ROLE_FALLBACKS = {
            :door_swing      => "02__Linetype__DoorSwings".freeze,        # <-- DataLib default tag for 2D door swings
            :door_closed     => "Na__Door__Closed".freeze,                # <-- Closed-state assembly visibility tag
            :door_open       => "Na__Door__Open".freeze,                  # <-- Open-state assembly visibility tag
            :door_panel      => "Na__DoorPanel".freeze,                   # <-- Door panel solid tag
            :door_lining     => "Na__DoorLining".freeze,                  # <-- Door lining sections tag
            :architrave      => "Na__Architrave".freeze,                  # <-- Architrave Follow Me solid tag
            :door_handle     => "Na__DoorHandle".freeze,                  # <-- Door handle 3D tag
            :proposed_doors  => "25__ProposedBuilding__Doors".freeze      # <-- TrueVision GLB segmentation container tag
        }.freeze
        # ---------------------------------------------------------------

        # CONSTANTS | Default Tag Colors (RGB)
        # ------------------------------------------------------------
        # Applied only when the tag is created fresh by this module.
        NA_ROLE_DEFAULT_COLORS = {
            :door_swing      => [180, 180, 180],                          # <-- Light grey for swing arcs
            :door_closed     => [120, 160, 200],                          # <-- Soft blue for closed-state group
            :door_open       => [200, 160, 120],                          # <-- Soft orange for open-state group
            :door_panel      => [165, 130,  90],                          # <-- Warm timber brown
            :door_lining     => [200, 180, 150],                          # <-- Lighter timber tone
            :architrave      => [180, 150, 110],                          # <-- Mid timber tone
            :door_handle     => [200, 175,  90],                          # <-- Brass-like yellow
            :proposed_doors  => [120, 160, 200]                           # <-- Matches door_closed for consistency
        }.freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_resolved_names_cache  = {}                                    # <-- Memoized role -> tag name lookups

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Resolve and Create Tags
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve the SketchUp Tag Name for a Role
        # ------------------------------------------------------------
        # Looks up the role in the shared DataLib first, then falls back
        # to the hardcoded NA_ROLE_FALLBACKS map. The result is memoized.
        #
        # @param role [Symbol] The role key (e.g. :door_swing, :door_closed)
        # @return [String] The SketchUp tag (layer) name to use
        def self.na_resolve_tag_name(role)
            return NA_ROLE_FALLBACKS[role] unless NA_ROLE_FALLBACKS.key?(role)

            cached = @na_resolved_names_cache[role]
            return cached if cached

            datalib_name = na_resolve_from_datalib(role)
            resolved     = datalib_name || NA_ROLE_FALLBACKS[role]

            @na_resolved_names_cache[role] = resolved
            DebugTools.na_debug_tag("Resolved role :#{role} -> '#{resolved}' (#{datalib_name ? 'DataLib' : 'fallback'})")
            resolved
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get or Create a SketchUp Tag for a Role
        # ------------------------------------------------------------
        # Returns the existing tag if present, otherwise creates a new
        # tag with the resolved name and a default colour for the role.
        #
        # @param role [Symbol] The role key
        # @return [Sketchup::Layer, nil] The tag, or nil if no active model
        def self.na_get_or_create_tag(role)
            model = Sketchup.active_model
            return nil unless model

            tag_name = na_resolve_tag_name(role)
            existing = model.layers[tag_name]
            return existing if existing

            new_tag      = model.layers.add(tag_name)
            color_rgb    = NA_ROLE_DEFAULT_COLORS[role]
            new_tag.color = Sketchup::Color.new(*color_rgb) if color_rgb && new_tag.respond_to?(:color=)
            DebugTools.na_debug_tag("Created tag '#{tag_name}' for role :#{role}")
            new_tag
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply a Role Tag to an Entity
        # ------------------------------------------------------------
        # Helper that resolves -> creates -> assigns in one call.
        #
        # @param entity [Sketchup::Drawingelement] The entity to tag
        # @param role [Symbol] The role key
        # @return [Boolean] True on success
        def self.na_apply_tag_to_entity(entity, role)
            return false unless entity && entity.respond_to?(:layer=)

            tag = na_get_or_create_tag(role)
            return false unless tag

            entity.layer = tag
            true
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - DataLib Lookup
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve a Role's Tag Name from the Shared DataLib
        # ------------------------------------------------------------
        # Reads Na__DataLib__CoreIndex__Tags__ via Na__DataLib__CacheData
        # and walks the nested structure looking for the canonical
        # SketchUp name. Returns nil if the DataLib is unavailable or the
        # role has no DataLib mapping.
        #
        # @param role [Symbol] The role key
        # @return [String, nil] The DataLib SketchUp name, or nil
        def self.na_resolve_from_datalib(role)
            return nil unless defined?(Na__DataLib__CacheData)

            data = na_load_tags_data
            return nil unless data.is_a?(Hash)

            datalib_keys = na_role_to_datalib_keys(role)
            return nil if datalib_keys.empty?

            tags_root = data["Na__DataLib__CoreIndex__Tags"]
            return nil unless tags_root.is_a?(Hash)

            datalib_keys.each do |key|
                found_name = na_find_tag_in_datalib(tags_root, key)
                return found_name if found_name
            end

            nil
        end
        private_class_method :na_resolve_from_datalib
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Load Tags Data Hash via Cache (with Rescue)
        # ------------------------------------------------------------
        def self.na_load_tags_data
            return nil unless defined?(Na__DataLib__CacheData)

            begin
                Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
            rescue => e
                DebugTools.na_debug_warn("DataLib :tags load failed: #{e.message}")
                nil
            end
        end
        private_class_method :na_load_tags_data
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Map a Role to Candidate DataLib Tag Keys
        # ------------------------------------------------------------
        # Some roles map to known tags in the DataLib (e.g. door_swing
        # -> 02__Linetype__DoorSwings). Others are tool-specific and
        # have no DataLib counterpart yet, so they return [].
        def self.na_role_to_datalib_keys(role)
            case role
            when :door_swing      then ["02__Linetype__DoorSwings"]
            when :proposed_doors  then ["25__ProposedBuilding__Doors"]
            else                       []
            end
        end
        private_class_method :na_role_to_datalib_keys
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Recursively Find a Tag's SketchUpName by Key
        # ------------------------------------------------------------
        def self.na_find_tag_in_datalib(node, target_key)
            return nil unless node.is_a?(Hash)

            node.each do |key, value|
                if key == target_key && value.is_a?(Hash) && value["Tag__SketchUpName"]
                    return value["Tag__SketchUpName"]
                end

                found = na_find_tag_in_datalib(value, target_key) if value.is_a?(Hash)
                return found if found
            end

            nil
        end
        private_class_method :na_find_tag_in_datalib
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__TagManager
end # module Na__InteriorDoorConfigurator

# =============================================================================
# END OF FILE
# =============================================================================
