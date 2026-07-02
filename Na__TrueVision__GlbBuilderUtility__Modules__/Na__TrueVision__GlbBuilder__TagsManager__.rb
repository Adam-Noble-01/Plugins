# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - TAGS MANAGER MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__TagsManager__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Tags Manager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Centralised tag (layer) creation from the standardised tags index JSON
# CREATED    : 2026
#
# DESCRIPTION:
# - Loads standardised tag definitions from Na__DataLib__CoreIndex__Tags__.json (SSOT)
# - Falls back to Na__TrueVision__GlbBuilder__TagsIndex__.json if DataLib is unavailable
# - Parses tag entries and constructs SketchUp tags (layers) in the active model
# - Checks for tag existence before attempting creation to avoid duplicates
# - Wraps creation in a single SketchUp operation for clean undo support
#
# =============================================================================

require 'json'                                                                    # <-- JSON parsing for tags index file
require_relative '../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Tags Manager - Standardised Tag Creation
    # -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Tag Prefix Ranges Eligible for Standardised Creation
        # ------------------------------------------------------------
        # Matches the curated TagsIndex subset: orbit, environment, building, storey.
        # Excludes utility (02-06), linework thickness (03), bulk furniture/context
        # (30-59, 61-70). Tag 60 (SceneEntourage2D) is a system-managed 2D billboard
        # tag like tag 9 (SiteVegetation2D), so it is carved out for auto-creation
        # even though it sits inside the excluded furniture/context number range.
        # ------------------------------------------------------------
        NA__TAGS_MANAGER__CREATE_PREFIX_RANGES = [
            (1..1),
            (7..9),
            (10..29),
            (60..60),
            (90..93)
        ].freeze
        # ------------------------------------------------------------


        # HELPER FUNCTION | Resolve Path to Tags Index JSON File
        # ------------------------------------------------------------
        def self.Na__TagsManager__TagsIndexPath
            File.join(NA_PLUGIN_ROOT, 'Na__TrueVision__GlbBuilder__TagsIndex__.json')  # <-- Local fallback index
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Check Tag Prefix Against Standardised Create Ranges
        # ---------------------------------------------------------------
        def self.Na__TagsManager__TagEligibleForCreation?(tag_name)
            tag_match = tag_name.match(/^(\d{2})__/)
            return false unless tag_match

            tag_number = tag_match[1].to_i
            NA__TAGS_MANAGER__CREATE_PREFIX_RANGES.any? { |range| range.include?(tag_number) }
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Build Tag List From DataLib Tags JSON
        # ---------------------------------------------------------------
        def self.Na__TagsManager__BuildTagsFromDataLib(tags_data)
            return nil unless tags_data.is_a?(Hash)

            library         = tags_data['Na__DataLib__CoreIndex__Tags']
            tag_entries     = []

            return nil unless library.is_a?(Hash)

            library.each do |_section_key, section|
                next unless section.is_a?(Hash)

                section.each do |entry_key, entry|
                    next unless entry.is_a?(Hash)
                    next if entry_key == 'Tag__Description'

                    tag_name = entry['Tag__SketchUpName']
                    next if tag_name.nil? || tag_name.empty?
                    next unless self.Na__TagsManager__TagEligibleForCreation?(tag_name)

                    # Allow ModelFlag tags (Glb__LineworkHidden or specific ModelFlag name pattern)
                    # even when Glb__FullyExcluded is true — these are user-facing modelling flags
                    is_model_flag   = tag_name.include?('ModelFlag') || entry['Glb__LineworkHidden'] == true
                    is_storey       = entry['Storey__IsContainer'] == true

                    # Skip fully-excluded tags unless they are model-flag or storey containers
                    next if entry['Glb__FullyExcluded'] == true && !is_model_flag && !is_storey

                    tag_entries << {
                        'name'              => tag_name,
                        'description'       => entry['Tag__Description'],
                        'line_style_name'   => entry['Layout__LineStyleName'],
                        'edge_colour_rgb'   => entry['Layout__EdgeColourRGB']
                    }
                end
            end

            tag_entries.sort_by! { |entry| entry['name'] }
            tag_entries
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Load and Parse Local Tags Index JSON Fallback
        # ---------------------------------------------------------------
        def self.Na__TagsManager__LoadLocalTagsIndex
            index_path = self.Na__TagsManager__TagsIndexPath

            unless File.exist?(index_path)
                puts "✗ Tags index file not found at: #{index_path}"
                return nil
            end

            raw_json = File.read(index_path, encoding: 'UTF-8')
            parsed   = JSON.parse(raw_json)
            tags     = parsed['tags']
            puts "✓ Local tags index loaded: #{tags.length} tags found"
            tags
        rescue JSON::ParserError => e
            puts "✗ Failed to parse local tags index JSON: #{e.message}"
            nil
        rescue => e
            puts "✗ Error loading local tags index: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Load Tags From Local DataLib SSOT File
        # ---------------------------------------------------------------
        # Reads the plugins-folder copy directly so tag-creation picks up local
        # edits immediately, without waiting for GitHub fetch or cache expiry.
        # ---------------------------------------------------------------
        def self.Na__TagsManager__LoadLocalDataLibFile
            datalib_path = File.expand_path(
                '../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json',
                __dir__
            )

            return nil unless File.exist?(datalib_path)

            parsed = JSON.parse(File.read(datalib_path, encoding: 'UTF-8'))
            tags   = self.Na__TagsManager__BuildTagsFromDataLib(parsed)

            if tags && !tags.empty?
                puts "✓ Local DataLib tags index loaded: #{tags.length} tags found"
                return tags
            end

            nil
        rescue JSON::ParserError => e
            puts "✗ Failed to parse local DataLib tags JSON: #{e.message}"
            nil
        rescue => e
            puts "✗ Error loading local DataLib tags file: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Load and Parse Tags Index JSON
        # ------------------------------------------------------------
        def self.Na__TagsManager__LoadTagsIndex
            local_datalib_tags = self.Na__TagsManager__LoadLocalDataLibFile
            return local_datalib_tags if local_datalib_tags

            begin
                tags_data = Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
                tags      = self.Na__TagsManager__BuildTagsFromDataLib(tags_data)

                if tags && !tags.empty?
                    puts "✓ DataLib tags index loaded: #{tags.length} tags found"
                    return tags
                end

                puts "  [TagsManager] DataLib tags index empty or unavailable, using local fallback"
            rescue => e
                puts "  [TagsManager] DataLib load failed, using local fallback: #{e.message}"
            end

            self.Na__TagsManager__LoadLocalTagsIndex
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Apply Line Style and Edge Colour to a Tag (Layer)
        # ---------------------------------------------------------------
        # Applies Layout__LineStyleName and Layout__EdgeColourRGB from the
        # tag entry to the newly created SketchUp layer where supported.
        # Guards on respond_to? so older SketchUp versions are safe.
        # ---------------------------------------------------------------
        def self.Na__TagsManager__ApplyTagStyling(layer, tag_entry)
            model = Sketchup.active_model

            line_style_name = tag_entry['line_style_name']
            if line_style_name && !line_style_name.empty?
                begin
                    line_style = model.line_styles[line_style_name]
                    layer.line_style = line_style if line_style && layer.respond_to?(:line_style=)
                rescue => e
                    puts "    [TagsManager] Could not set line style '#{line_style_name}' on '#{layer.name}': #{e.message}"
                end
            end

            edge_colour_rgb = tag_entry['edge_colour_rgb']
            if edge_colour_rgb.is_a?(Array) && edge_colour_rgb.length >= 3
                begin
                    colour = Sketchup::Color.new(edge_colour_rgb[0], edge_colour_rgb[1], edge_colour_rgb[2])
                    layer.color = colour if layer.respond_to?(:color=)
                rescue => e
                    puts "    [TagsManager] Could not set edge colour on '#{layer.name}': #{e.message}"
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Standardised Tags From Index
        # ------------------------------------------------------------
        def self.Na__TagsManager__CreateStandardisedTags
            model = Sketchup.active_model                                             # Get active model

            tags = self.Na__TagsManager__LoadTagsIndex                                # Load tags from JSON index
            if tags.nil? || tags.empty?
                UI.messagebox("Tags index could not be loaded. Check the Ruby Console for details.")
                return
            end

            created_tags  = []                                                        # <-- Tracks newly created tags
            skipped_tags  = []                                                        # <-- Tracks already-existing tags
            error_tags    = []                                                        # <-- Tracks any creation failures

            model.start_operation("Create Standardised Tags", true)                  # <-- Begin undoable operation

            begin
                tags.each do |tag_entry|
                    tag_name = tag_entry['name']                                      # Get tag name from JSON entry

                    # Check existence before creating
                    already_exists = model.layers.any? { |l| l.name == tag_name }    # <-- Check if tag already exists

                    if already_exists
                        skipped_tags << tag_name
                        puts "  [SKIP] Tag already exists: #{tag_name}"
                    else
                        begin
                            new_layer = model.layers.add(tag_name)
                            self.Na__TagsManager__ApplyTagStyling(new_layer, tag_entry)
                            created_tags << tag_name
                            puts "  [OK]   Tag created: #{tag_name}"
                        rescue => e
                            error_tags << tag_name
                            puts "  [ERROR] Failed to create tag '#{tag_name}': #{e.message}"
                        end
                    end
                end

                model.commit_operation                                                # <-- Commit all tag creations as one undo step

            rescue => e
                model.abort_operation                                                 # <-- Roll back on unexpected error
                puts "✗ Tags creation aborted due to error: #{e.message}"
                UI.messagebox("Error creating tags:\n#{e.message}\n\nOperation has been rolled back.")
                return
            end

            # Build summary report
            summary_lines = []
            summary_lines << "Tags Created (#{created_tags.length}):"
            if created_tags.empty?
                summary_lines << "  None"
            else
                created_tags.each { |t| summary_lines << "  + #{t}" }
            end

            summary_lines << ""
            summary_lines << "Already Existed - Skipped (#{skipped_tags.length}):"
            if skipped_tags.empty?
                summary_lines << "  None"
            else
                skipped_tags.each { |t| summary_lines << "  - #{t}" }
            end

            unless error_tags.empty?
                summary_lines << ""
                summary_lines << "Errors (#{error_tags.length}):"
                error_tags.each { |t| summary_lines << "  ! #{t}" }
            end

            puts "\n=== TrueVision3D - Create Standardised Tags - Complete ==="
            puts summary_lines.join("\n")
            puts "==========================================================\n"

            UI.messagebox(summary_lines.join("\n"))                                   # <-- Show summary to user
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
