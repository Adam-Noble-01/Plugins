# =============================================================================
# NA EDGE UTIL - PAINT DEEP NESTED EDGES - APPLY LINE THICKNESS TAGS
# =============================================================================
#
# FILE       : Na__EdgeUtil__PaintDeepNestedEdges__ApplyLineThicknessTags__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__ApplyLineThicknessTags
# MODULE     : Na__ApplyLineThicknessTags
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Assign Layout linework thickness tags to edges based on MTE colour
# CREATED    : 15-Mar-2026
#
# DESCRIPTION:
# - Loads the Tags JSON from Na__DataLib to get the 03__LayoutDrawingLineworkTags__
#   section which maps each greyscale MTE edge colour to a Layout line thickness tag.
# - Builds a lookup hash: { MTE colour name => tag name }.
# - Traverses every edge in the entire model (deep nested).
# - For each edge with a greyscale MTE material, assigns edge.layer to the
#   corresponding 03__LineworkStyle__ tag.
# - Ensures all required tags exist in the model before assignment.
# - Wraps all changes in a single SketchUp operation for clean undo.
#
# =============================================================================

require 'sketchup.rb'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Line Thickness Tag Assignment Module
# -----------------------------------------------------------------------------

    module Na__ApplyLineThicknessTags

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        @na_colour_to_tag_lookup = nil                                        # <-- { MTE colour ID => tag name }
        @na_tag_entries          = nil                                        # <-- Array of { colour_id, tag_name, description } for UI
        @na_protected_tag_names  = nil                                        # <-- Hash of tag names that block Advanced-mode override

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Data Loading
    # -------------------------------------------------------------------------

        # FUNCTION | Load and Build the MTE Colour to Tag Lookup
        # ------------------------------------------------------------
        def self.Na__LineTags__LoadLookup
            return @na_colour_to_tag_lookup if @na_colour_to_tag_lookup

            tags_data = Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
            unless tags_data
                puts "    [LineTags] WARNING: Tags data unavailable"
                @na_colour_to_tag_lookup = {}
                @na_tag_entries          = []
                return @na_colour_to_tag_lookup
            end

            tags_library = tags_data["Na__DataLib__CoreIndex__Tags"]
            linework_section = tags_library && tags_library["03__LayoutDrawingLineworkTags__"]

            unless linework_section.is_a?(Hash)
                puts "    [LineTags] WARNING: 03__LayoutDrawingLineworkTags__ section not found"
                @na_colour_to_tag_lookup = {}
                @na_tag_entries          = []
                return @na_colour_to_tag_lookup
            end

            lookup  = {}
            entries = []

            linework_section.each do |_key, entry|
                next unless entry.is_a?(Hash)
                next unless entry["Layout__EdgeColourID"] && entry["Tag__SketchUpName"]

                colour_id = entry["Layout__EdgeColourID"]
                tag_name  = entry["Tag__SketchUpName"]
                lookup[colour_id] = tag_name
                entries << { colour_id: colour_id, tag_name: tag_name, description: entry["Tag__Description"] || "" }
            end

            @na_colour_to_tag_lookup = lookup
            @na_tag_entries          = entries
            puts "    [LineTags] Loaded #{lookup.size} MTE colour -> tag mappings"
            lookup
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return the Colour-to-Tag Lookup Hash
        # ---------------------------------------------------------------
        def self.Na__LineTags__Lookup
            self.Na__LineTags__LoadLookup unless @na_colour_to_tag_lookup
            @na_colour_to_tag_lookup || {}
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Tag Entry Array for UI Display
        # ---------------------------------------------------------------
        def self.Na__LineTags__TagEntries
            self.Na__LineTags__LoadLookup unless @na_tag_entries
            @na_tag_entries || []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load and Cache the Set of Protected Tag Names
        # ------------------------------------------------------------
        # Reads ExportExclusions.AdvancedSwapOffTagNames from Tags JSON as the
        # fast path. Falls back to iterating all tag entries for the per-tag
        # EdgePainting__AdvancedSwapOff field if the curated list is absent.
        # Returns a Hash keyed by tag name for O(1) membership checks.
        def self.Na__LineTags__LoadProtectedTagNames
            return @na_protected_tag_names if @na_protected_tag_names

            tags_data = Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
            unless tags_data
                puts "    [LineTags] WARNING: Tags data unavailable for protected tag names"
                @na_protected_tag_names = {}
                return @na_protected_tag_names
            end

            protected_names = {}

            export_exclusions = tags_data["ExportExclusions"]
            curated_list      = export_exclusions && export_exclusions["AdvancedSwapOffTagNames"]

            if curated_list.is_a?(Array) && !curated_list.empty?
                curated_list.each { |name| protected_names[name] = true }    # <-- Use curated fast-path list
                puts "    [LineTags] Loaded #{protected_names.size} protected tag(s) from AdvancedSwapOffTagNames"
            else
                tags_library = tags_data["Na__DataLib__CoreIndex__Tags"] || {}
                tags_library.each_value do |section|
                    next unless section.is_a?(Hash)
                    section.each_value do |entry|
                        next unless entry.is_a?(Hash)
                        next unless entry["EdgePainting__AdvancedSwapOff"] == true
                        next unless entry["Tag__SketchUpName"].is_a?(String)

                        protected_names[entry["Tag__SketchUpName"]] = true   # <-- Fallback: iterate per-tag flags
                    end
                end
                puts "    [LineTags] Loaded #{protected_names.size} protected tag(s) via per-tag fallback scan"
            end

            @na_protected_tag_names = protected_names
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Cached Protected Tag Names Hash
        # ---------------------------------------------------------------
        def self.Na__LineTags__ProtectedTagNames
            self.Na__LineTags__LoadProtectedTagNames unless @na_protected_tag_names
            @na_protected_tag_names || {}
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tag Ensurance
    # -------------------------------------------------------------------------

        # HELPER FUNCTION | Ensure All Required Linework Tags Exist in Model
        # ---------------------------------------------------------------
        def self.Na__LineTags__EnsureTagsExist(model)
            lookup       = self.Na__LineTags__Lookup
            created_tags = []

            lookup.each_value do |tag_name|
                existing = model.layers.any? { |l| l.name == tag_name }
                unless existing
                    model.layers.add(tag_name)
                    created_tags << tag_name
                    puts "    [LineTags] Created tag: #{tag_name}"
                end
            end

            created_tags
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Model Traversal and Tag Application
    # -------------------------------------------------------------------------

        # HELPER FUNCTION | Collect ALL Edges in Entire Model (Deep Nested)
        # ---------------------------------------------------------------
        def self.Na__LineTags__CollectAllModelEdges(model)
            edges = []
            model.active_entities.each do |entity|
                Na__EdgeUtil__PaintDeepNestedEdges.na_collect_edges(entity, edges)
            end
            edges
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply Line Thickness Tags to All Greyscale MTE Edges
        # ------------------------------------------------------------
        def self.Na__LineTags__ApplyToModel
            model = Sketchup.active_model
            unless model
                return { applied: 0, skipped: 0, tags_created: 0, total_edges: 0, errors: ["No active model"] }
            end

            lookup = self.Na__LineTags__Lookup
            if lookup.empty?
                return { applied: 0, skipped: 0, tags_created: 0, total_edges: 0, errors: ["No colour-to-tag mappings loaded"] }
            end

            model.start_operation("Apply Line Thickness Tags", true)

            begin
                created_tags    = self.Na__LineTags__EnsureTagsExist(model)
                edges           = self.Na__LineTags__CollectAllModelEdges(model)
                protected_names = self.Na__LineTags__ProtectedTagNames            # <-- Load protected tag set
                applied         = 0
                skipped         = 0
                preserved       = 0                                               # <-- Edges on protected tags — left untouched
                errors          = []

                untagged_layer = model.layers["Layer0"] || model.layers["Untagged"]
                untagged_count = 0

                edges.each do |edge|
                    if protected_names.key?(edge.layer.name)                      # <-- Skip if already on a protected tag
                        preserved += 1
                        next
                    end

                    mat_name = edge.material ? edge.material.display_name : nil
                    tag_name = mat_name ? lookup[mat_name] : nil

                    begin
                        if tag_name
                            target_layer = model.layers[tag_name]
                            if target_layer
                                edge.layer = target_layer
                                applied += 1
                            else
                                edge.layer = untagged_layer if untagged_layer
                                untagged_count += 1
                            end
                        else
                            edge.layer = untagged_layer if untagged_layer
                            untagged_count += 1
                        end
                    rescue => e
                        skipped += 1
                        errors << "#{mat_name || 'no material'}: #{e.message}" if errors.length < 10
                    end
                end

                model.commit_operation

                summary = {
                    applied:      applied,
                    untagged:     untagged_count,
                    preserved:    preserved,
                    skipped:      skipped,
                    tags_created: created_tags.length,
                    total_edges:  edges.length,
                    errors:       errors
                }

                puts "    [LineTags] Complete: #{applied} tagged, #{untagged_count} moved to Untagged, #{preserved} preserved, #{skipped} skipped, #{created_tags.length} tags created (#{edges.length} total)"
                summary

            rescue => e
                model.abort_operation
                puts "    [LineTags] ERROR: #{e.message}"
                { applied: 0, skipped: 0, tags_created: 0, total_edges: 0, errors: [e.message] }
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    end # module Na__ApplyLineThicknessTags

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
