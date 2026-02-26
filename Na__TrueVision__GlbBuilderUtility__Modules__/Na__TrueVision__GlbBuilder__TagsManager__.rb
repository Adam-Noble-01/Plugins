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
# - Loads the standardised tags index from Na__TrueVision__GlbBuilder__TagsIndex__.json
# - Parses the JSON and constructs SketchUp tags (layers) in the active model
# - Checks for tag existence before attempting creation to avoid duplicates
# - Wraps creation in a single SketchUp operation for clean undo support
#
# =============================================================================

require 'json'                                                                    # <-- JSON parsing for tags index file

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Tags Manager - Standardised Tag Creation
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Path to Tags Index JSON File
        # ------------------------------------------------------------
        def self.Na__TagsManager__TagsIndexPath
            File.join(NA_PLUGIN_ROOT, 'Na__TrueVision__GlbBuilder__TagsIndex__.json')  # <-- Path relative to plugin root constant
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Load and Parse Tags Index JSON
        # ------------------------------------------------------------
        def self.Na__TagsManager__LoadTagsIndex
            index_path = self.Na__TagsManager__TagsIndexPath                          # Resolve path to tags index

            unless File.exist?(index_path)
                puts "✗ Tags index file not found at: #{index_path}"
                return nil
            end

            begin
                raw_json = File.read(index_path, encoding: 'UTF-8')                   # <-- Read raw JSON text
                parsed   = JSON.parse(raw_json)                                       # <-- Parse into Ruby hash
                tags     = parsed['tags']                                              # <-- Extract tags array
                puts "✓ Tags index loaded: #{tags.length} tags found"
                tags
            rescue JSON::ParserError => e
                puts "✗ Failed to parse tags index JSON: #{e.message}"
                nil
            rescue => e
                puts "✗ Error loading tags index: #{e.message}"
                nil
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
                        skipped_tags << tag_name                                      # Record as skipped
                        puts "  [SKIP] Tag already exists: #{tag_name}"
                    else
                        begin
                            model.layers.add(tag_name)                                # <-- Create new tag (layer) in model
                            created_tags << tag_name                                  # Record as created
                            puts "  [OK]   Tag created: #{tag_name}"
                        rescue => e
                            error_tags << tag_name                                    # Record as failed
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
