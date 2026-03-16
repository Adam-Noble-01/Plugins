# =============================================================================
# NA EDGE UTIL - PAINT DEEP NESTED EDGES - REFRESH PLUGIN DATA
# =============================================================================
#
# FILE       : Na__EdgeUtil__PaintDeepNestedEdges__RefreshPluginData__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges
# MODULE     : Na__RefreshPluginData
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Force-refresh web data cache and reload plugin Ruby files
# CREATED    : 16-Mar-2026
#
# DESCRIPTION:
# - Provides two independent refresh operations triggered from the Settings tab.
# - Region 1 busts the Na__DataLib cache and re-fetches JSON from GitHub URL,
#   bypassing the 30-minute TTL so fresh data is loaded immediately.
# - Region 2 reloads all .rb files in the plugin module folder plus the
#   top-level loader script, enabling in-session hot-reloading without
#   restarting SketchUp.
# - Both operations return a result hash consumed by the dialog callback
#   to display feedback in the Settings tab status element.
#
# =============================================================================

module Na__EdgeUtil__PaintDeepNestedEdges
    module Na__RefreshPluginData

# -----------------------------------------------------------------------------
# REGION | Web Data Re-Fetch - Force Bypass Cache and Reload from URL
# -----------------------------------------------------------------------------

        # FUNCTION | Clear In-Memory State and Force Re-Fetch Web Data
        # ------------------------------------------------------------
        def self.Na__Refresh__FetchWebData
            puts "\n" + "=" * 60
            puts "NA EDGE UTIL - REFRESHING WEB DATA"
            puts "=" * 60

            na_clear_mte_state                                                    # <-- Clear cached in-memory data

            edge_materials_result = na_force_reload_file_key(:edge_materials)    # <-- Force re-fetch edge materials
            tags_result           = na_force_reload_file_key(:tags)              # <-- Force re-fetch tags

            puts "-" * 60
            puts "Web data re-fetch complete"
            puts "=" * 60 + "\n"

            return {
                edge_materials: edge_materials_result,
                tags:           tags_result
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Clear In-Memory MTE State on Main Module
        # ---------------------------------------------------------------
        def self.na_clear_mte_state
            Na__EdgeUtil__PaintDeepNestedEdges.instance_variable_set(:@na_mte_data,     nil) # <-- Reset MTE raw data
            Na__EdgeUtil__PaintDeepNestedEdges.instance_variable_set(:@na_mte_colours,  nil) # <-- Reset flattened colours
            Na__EdgeUtil__PaintDeepNestedEdges.instance_variable_set(:@na_mte_swatches, nil) # <-- Reset swatch array
            Na__EdgeUtil__PaintDeepNestedEdges.instance_variable_set(:@na_mte_meta,     nil) # <-- Reset meta block
            puts "  [RefreshPluginData] In-memory MTE state cleared"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Force Reload a Single DataLib File Key from URL
        # ---------------------------------------------------------------
        def self.na_force_reload_file_key(file_key)
            begin
                Na__DataLib__CacheData.Na__Cache__LoadData(file_key, true)        # <-- force_reload: true bypasses TTL
                source = Na__DataLib__CacheData.Na__Cache__LastSource(file_key)
                puts "  [RefreshPluginData] :#{file_key} -> #{source}"
                return source
            rescue => e
                puts "  [RefreshPluginData] ERROR re-fetching :#{file_key}: #{e.message}"
                return :failed
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plugin Files Reload - Hot Reload Ruby Scripts in Session
# -----------------------------------------------------------------------------

        # FUNCTION | Reload All Plugin Ruby Files for In-Session Hot Reload
        # ------------------------------------------------------------
        def self.Na__Refresh__ReloadRubyFiles
            puts "\n" + "=" * 60
            puts "NA EDGE UTIL - RELOADING RUBY FILES"
            puts "=" * 60

            reload_count = 0
            error_count  = 0

            rb_files = Dir.glob(File.join(NA_PLUGIN_ROOT, "*.rb"))               # <-- Collect all .rb files in module folder

            rb_files.each do |file|
                begin
                    load file
                    puts "  [OK] Loaded: #{File.basename(file)}"
                    reload_count += 1
                rescue => e
                    puts "  [ERROR] #{File.basename(file)}: #{e.message}"
                    error_count += 1
                end
            end

            na_reload_top_level_loader                                            # <-- Also reload the top-level loader

            puts "-" * 60
            puts "Ruby reload complete: #{reload_count} files loaded, #{error_count} errors"
            puts "=" * 60 + "\n"

            return { reload_count: reload_count, error_count: error_count }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Reload Top-Level Loader Script from Plugins Root
        # ---------------------------------------------------------------
        def self.na_reload_top_level_loader
            loader_path = File.join(
                File.dirname(NA_PLUGIN_ROOT),
                'Na__EdgeUtil__PaintDeepNestedEdges__Loader__.rb'
            )

            if File.exist?(loader_path)
                begin
                    load loader_path
                    puts "  [OK] Loaded loader: #{File.basename(loader_path)}"
                rescue => e
                    puts "  [ERROR] Failed to reload loader: #{e.message}"
                end
            else
                puts "  [WARN] Loader script not found at: #{loader_path}"
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end  # module Na__RefreshPluginData
end  # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
