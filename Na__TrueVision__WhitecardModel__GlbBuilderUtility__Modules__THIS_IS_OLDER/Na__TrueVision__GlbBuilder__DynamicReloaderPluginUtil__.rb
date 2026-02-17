module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Dynamic Reloader Utility
    # -----------------------------------------------------------------------------

        # FUNCTION | Register / Re-register Extensions Menu Entry
        # ---------------------------------------------------------------
        # Core implementation lives here so both the top-level loader and the
        # in-session dynamic reload helper can call it safely.
        def self.Na__DynamicReloader__RegisterMenu
            begin
                if @menu_registered
                    puts "TrueVision3D GLB Builder menu already registered; skipping."
                    return
                end

                extensions_menu = UI.menu("Extensions")                                   # Get Extensions menu
                truevision_submenu = extensions_menu.add_submenu("Na__TrueVision3D")    # Create/get TrueVision3D submenu

                # Add separator if menu has items (best effort)
                begin
                    truevision_submenu.add_separator
                rescue
                    # Ignore if separator fails
                end

                # Add TrueVision GLB Builder menu item
                truevision_submenu.add_item("Na__TrueVision3D__GlbBuilderUtility") {
                    TrueVision3D::GlbBuilderUtility.Na__PublicApi__StartExport
                }

                @menu_registered = true
                puts "✓ TrueVision3D GLB Builder Utility menu registered via Na__DynamicReloader__RegisterMenu"
            rescue => e
                puts "✗ Error registering TrueVision3D GLB Builder Utility menu: #{e.message}"
                puts e.backtrace.first(5).join("\n")
            end
        end
        # ---------------------------------------------------------------


        # FUNCTION | Reload All Scripts for Rapid Development
        # ------------------------------------------------------------
        # Reloads all .rb files in the module directory and re-runs the loader
        # and menu registration. This enables rapid iteration and testing
        # during development without restarting SketchUp.
        def self.Na__DynamicReloader__ReloadAllScripts
            puts "\n" + "=" * 60
            puts "TRUEVISION3D GLB BUILDER - RELOADING SCRIPTS"
            puts "=" * 60
            
            reload_count = 0
            error_count = 0
            
            # Get all .rb files in the module directory
            rb_files = Dir.glob(File.join(NA_PLUGIN_ROOT, "*.rb"))
            
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
            
            puts "-" * 60
            puts "Reload complete: #{reload_count} files loaded, #{error_count} errors"
            puts "=" * 60 + "\n"

            # Also attempt to reload the top-level loader script (one level up in Plugins folder)
            begin
                loader_path = File.join(File.dirname(NA_PLUGIN_ROOT), 'Na__TrueVision__GlbBuilderUtility__Loader.rb')
                if File.exist?(loader_path)
                    load loader_path
                    puts "  [OK] Loaded loader: #{File.basename(loader_path)}"
                else
                    puts "  [WARN] Loader script not found at: #{loader_path}"
                end
            rescue => e
                puts "  [ERROR] Failed to reload loader script: #{e.message}"
            end
            
            # Ensure the Extensions menu entry is registered using the shared helper
            begin
                self.Na__DynamicReloader__RegisterMenu
            rescue => e
                puts "  [ERROR] Failed to (re)register TrueVision3D GLB Builder menu: #{e.message}"
            end
            
            # Refresh UI
            UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)
            
            # Reopen dialog if it was visible
            if @export_dialog && @export_dialog.visible?
                @export_dialog.close
                self.Na__UserInterface__ShowExportDialog
            end
            
            # Show success message
            UI.messagebox("Scripts reloaded: #{reload_count} files, #{error_count} errors") if reload_count > 0
        end
        # ---------------------------------------------------------------


        # FUNCTION | Backwards-compatible wrappers (3-stage naming)
        # ---------------------------------------------------------------
        # Keep existing public entry points but delegate to the new
        # Na__DynamicReloader__* implementations.

        def self.Na__PublicApi__RegisterMenu
            self.Na__DynamicReloader__RegisterMenu
        end

        def self.Na__DevTools__ReloadScripts
            self.Na__DynamicReloader__ReloadAllScripts
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
