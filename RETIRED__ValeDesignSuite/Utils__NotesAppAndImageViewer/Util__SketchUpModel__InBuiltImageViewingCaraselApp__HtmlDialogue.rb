# =============================================================================
# VALEDESIGNSUITE - IMAGE CAROUSEL VIEWER
# =============================================================================
#
# FILE       : Util__SketchUpModel__InBuiltImageViewingCaraselApp__HtmlDialogue.rb
# NAMESPACE  : ValeDesignSuite::Utils
# MODULE     : ImageCarousel
# AUTHOR     : Adam Noble - Vale Garden Houses
# TYPE       : SketchUp 2026 Plugin Utility
# PURPOSE    : In-built image carousel viewer for browsing project images
# CREATED    : 2025
#
# DESCRIPTION:
# - This module provides an image carousel viewer that allows browsing images
#   from a selected folder within SketchUp
# - Features include zoom, pan, rotate, fullscreen, and keyboard shortcuts
# - Images are displayed in a thumbnail sidebar with a main canvas viewer
# - Supports common image formats: PNG, JPG, JPEG, GIF, BMP, WEBP, TIF, TIFF, HEIC, HEIF
# - Adapted from Noble Architecture Image Carousel 2026
#
# USAGE NOTES:
# - Access via: ValeDesignSuite::Utils::ImageCarousel.start
# - Can be launched directly from Ruby Console
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 2025 - Version 1.0.0 - INITIAL CREATION
# - Created Image Carousel module adapted from Noble Architecture Toolbox
# - Styled with Vale Design Suite conventions
# - Integrated into ValeDesignSuite Utils namespace
#
# =============================================================================

module ValeDesignSuite
    module Utils
        module ImageCarousel
            extend self


# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Dialog Configuration and Image Extensions
    # ------------------------------------------------------------
    unless const_defined?(:DIALOG_ID)
        DIALOG_ID              =   'vale_design_suite_image_carousel'              # <-- Preferences key for dialog settings
    end
    
    unless const_defined?(:IMAGE_EXTS)
        IMAGE_EXTS              =   %w[.png .jpg .jpeg .gif .bmp .webp .tif .tiff .heic .heif]  # <-- Supported image file extensions
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Dialog Initialization and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Show Image Carousel Dialog
    # ------------------------------------------------------------
    def show_carousel
        if @dlg && @dlg.visible?                                                # <-- Check if dialog exists and is visible
            @dlg.bring_to_front                                                 # <-- Bring existing dialog to front
        else
            @dlg = create_dialog                                                # <-- Create new dialog instance
            setup_action_callbacks                                              # <-- Configure Ruby-JS bridge callbacks
            @dlg.show                                                           # <-- Display dialog
            @dlg.bring_to_front                                                 # <-- Bring to front
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Start Image Carousel Dialog (Legacy Method)
    # ------------------------------------------------------------
    def start
        show_carousel                                                           # <-- Delegate to show_carousel method
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create HTML Dialog Instance
    # ------------------------------------------------------------
    def create_dialog
        UI::HtmlDialog.new(
            dialog_title:    'Project Image Carousel',
            preferences_key: DIALOG_ID,
            style:           UI::HtmlDialog::STYLE_DIALOG,
            width:           1200,
            height:          800,
            min_width:       900,
            min_height:      600,
            resizable:       true,
            scrollable:      false
        )
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Setup Action Callbacks for Ruby-JS Communication
    # ------------------------------------------------------------
    def setup_action_callbacks
        return if @callbacks_set                                                # <-- Prevent duplicate callback registration
        
        @dlg.set_html(html_source)                                             # <-- Set HTML content

        @dlg.add_action_callback('choose_folder') do |_ctx, _param|
            handle_folder_selection                                             # <-- Handle folder selection callback
        end

        @dlg.add_action_callback('open_in_os') do |_ctx, path|
            open_in_os(path)                                                    # <-- Handle reveal in OS callback
        end

        @dlg.add_action_callback('copy_path') do |_ctx, path|
            copy_path_to_clipboard(path)                                        # <-- Handle copy path callback
        end
        
        @callbacks_set = true                                                   # <-- Mark callbacks as set
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Handle Folder Selection Dialog
    # ------------------------------------------------------------
    def handle_folder_selection
        default_dir = Sketchup.read_default(DIALOG_ID, 'last_dir', Dir.home)   # <-- Get last used directory
        folder      = UI.select_directory(title: 'Select image folder', directory: default_dir)  # <-- Show folder picker
        
        if folder
            Sketchup.write_default(DIALOG_ID, 'last_dir', folder)               # <-- Save selected directory
            paths = collect_images(folder)                                      # <-- Collect image paths
            urlish = paths.map { |p| Sketchup.platform == :platform_win ? p.tr('\\\\', '/') : p }  # <-- Convert to forward slashes for URLs
            @dlg.execute_script("window.SKP_onFolderChosen(#{urlish.to_json});")  # <-- Send paths to JavaScript
        else
            @dlg.execute_script('window.SKP_onFolderChosen(null);')             # <-- Send null if cancelled
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | File System Operations
# -----------------------------------------------------------------------------

    # FUNCTION | Collect Image Files from Directory
    # ------------------------------------------------------------
    def collect_images(root)
        Dir.glob(File.join(root, '**', '*'))
            .select { |f| File.file?(f) && IMAGE_EXTS.include?(File.extname(f).downcase) }  # <-- Filter image files only
            .sort_by { |p| p.downcase }                                         # <-- Sort case-insensitively
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open File in Operating System File Manager
    # ------------------------------------------------------------
    def open_in_os(path)
        return unless path && !path.empty?                                     # <-- Validate path exists
        
        native_path = path                                                      # <-- Initialize native path
        if Sketchup.platform == :platform_win
            native_path = native_path.tr('/', '\\')                            # <-- Convert to Windows path format
            if File.exist?(native_path)
                system('explorer', '/select,', native_path)                    # <-- Reveal in Windows Explorer
            else
                UI.messagebox('File not found: ' + native_path)                # <-- Show error if file missing
            end
        else
            if File.exist?(native_path)
                system('open', '-R', native_path)                              # <-- Reveal in macOS Finder
            else
                UI.messagebox('File not found: ' + native_path)                # <-- Show error if file missing
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Copy File Path to Clipboard
    # ------------------------------------------------------------
    def copy_path_to_clipboard(path)
        return unless path && !path.empty?                                     # <-- Validate path exists
        
        native = Sketchup.platform == :platform_win ? path.tr('/', '\\') : path  # <-- Convert to native path format
        begin
            UI.copy_text_to_clipboard(native)                                  # <-- Copy to clipboard
        rescue => e
            UI.messagebox("Copy failed: #{e.message}")                         # <-- Show error if copy fails
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | HTML Content Generation
# -----------------------------------------------------------------------------

    # FUNCTION | Generate HTML Source for Dialog
    # ------------------------------------------------------------
    def html_source
        logo_image_path = File.join(ValeDesignSuite::BRAND_ASSETS, 'ValeHeaderImage_ValeLogo_HorizontalFormat.png')  # <-- Logo path using plugin constant
        logo_image_url = "file:///" + File.expand_path(logo_image_path).gsub(File::SEPARATOR, '/')                    # <-- Convert to absolute file URL with forward slashes
        
        <<-HTML
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta http-equiv="X-UA-Compatible" content="IE=edge" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Vale Design Suite | Image Carousel</title>
          <style>
            @font-face {
                font-family   : 'Open Sans Regular';
                src           : url('https://www.noble-architecture.com/assets/AD04_-_LIBR_-_Common_-_Front-Files/AD04_01_-_Standard-Font_-_Open-Sans-Regular.ttf') format('truetype');
                font-weight   : normal;
                font-style    : normal;
                font-display  : swap;
            }
            @font-face {
                font-family   : 'Open Sans Semibold';
                src           : url('https://www.noble-architecture.com/assets/AD04_-_LIBR_-_Common_-_Front-Files/AD04_02_-_Standard-Font_-_Open-Sans-SemiBold.ttf') format('truetype');
                font-weight   : 600;
                font-style    : normal;
                font-display  : swap;
            }
            :root {
                --FontCol_ValeTitleTextColour      : #172b3a;
                --FontCol_ValeTitleHeadingColour    : #172b3a;
                --FontCol_ValeStandardTextColour   : #1e1e1e;
                --FontCol_ValeDisabledTextColour   : #999999;
                --FontType_ValeStandardText         : 'Open Sans Regular', sans-serif;
                --FontType_ValeTitleHeading02       : 'Open Sans Semibold', sans-serif;
                --ValeBackgroundColor              : #f0f0f0;
                --ValeContentBackground            : #ffffff;
                --ValeBorderColor                  : #dddddd;
                --ValePrimaryButtonBg              : #006600;
                --ValePrimaryButtonHoverBg         : #008800;
                --ValePrimaryButtonText            : #ffffff;
                --ValeSecondaryButtonBg            : #172b3a;
                --ValeSecondaryButtonHoverBg       : #2a4a63;
                --ValeSecondaryButtonText          : #ffffff;
                --ValeHighlightColor               : #006600;
            }
            * { box-sizing: border-box; }
            html, body { 
                height:100%; 
                margin:0; 
                background:var(--ValeBackgroundColor); 
                color:var(--FontCol_ValeStandardTextColour); 
                font-family:var(--FontType_ValeStandardText);
                font-size:14px;
                line-height:1.4;
            }
            .app { height:100%; display:flex; flex-direction:column; }
            .header-bar {
                display:flex;
                align-items:center;
                justify-content:center;
                padding:10px 15px;
                margin:0;
                flex-shrink:0;
                background-color:var(--ValeContentBackground);
                border-bottom:1px solid var(--ValeBorderColor);
                position:relative;
            }
            .header-bar__logo-image {
                position:absolute;
                left:15px;
                top:50%;
                transform:translateY(-50%);
                height:35px;
            }
            .header-bar__title {
                margin:0;
                font-size:1.25rem;
                color:var(--FontCol_ValeTitleTextColour);
                font-family:var(--FontType_ValeTitleHeading02);
            }
            .toolbar { 
                display:flex; 
                gap:8px; 
                align-items:center; 
                padding:8px 10px; 
                background:var(--ValeContentBackground); 
                border-bottom:1px solid var(--ValeBorderColor); 
            }
            .toolbar .title { 
                font-weight:600; 
                margin-right:auto; 
                color:var(--FontCol_ValeTitleHeadingColour);
                font-family:var(--FontType_ValeTitleHeading02);
            }
            button { 
                appearance:none; 
                border:1px solid var(--ValeBorderColor); 
                background:var(--ValeSecondaryButtonBg); 
                color:var(--ValeSecondaryButtonText); 
                padding:6px 10px; 
                border-radius:4px; 
                cursor:pointer;
                font-family:var(--FontType_ValeStandardText);
                font-size:0.9rem;
                transition:background-color 0.2s ease;
            }
            button:hover { 
                background:var(--ValeSecondaryButtonHoverBg); 
            }
            button.primary {
                background:var(--ValePrimaryButtonBg);
                color:var(--ValePrimaryButtonText);
            }
            button.primary:hover {
                background:var(--ValePrimaryButtonHoverBg);
            }
            button[disabled] { opacity:.5; cursor:not-allowed; }
            .icon { width:16px; height:16px; vertical-align:-3px; }
            .main { flex:1; display:flex; min-height:0; }
            .thumbs { 
                width:220px; 
                max-width:40%; 
                overflow:auto; 
                border-right:1px solid var(--ValeBorderColor); 
                background:var(--ValeContentBackground); 
                padding:8px; 
            }
            .thumb { 
                position:relative; 
                margin:0 0 8px; 
                border:1px solid var(--ValeBorderColor); 
                background:var(--ValeContentBackground); 
                border-radius:4px; 
                padding:6px; 
                cursor:pointer;
                transition:border-color 0.2s ease;
            }
            .thumb:hover {
                border-color:var(--ValeHighlightColor);
            }
            .thumb img { display:block; width:100%; border-radius:4px; }
            .thumb .cap { 
                margin-top:6px; 
                color:var(--FontCol_ValeStandardTextColour); 
                font-size:12px; 
                white-space:nowrap; 
                overflow:hidden; 
                text-overflow:ellipsis;
                font-family:var(--FontType_ValeStandardText);
            }
            .thumb.active { 
                outline:2px solid var(--ValeHighlightColor);
                border-color:var(--ValeHighlightColor);
            }
            .viewer { position:relative; flex:1; min-width:0; display:flex; flex-direction:column; }
            .canvas-wrap { 
                position:relative; 
                flex:1; 
                min-height:0; 
                background:#e8e8e8;
            }
            canvas { position:absolute; inset:0; width:100%; height:100%; }
            .status { 
                display:flex; 
                gap:16px; 
                align-items:center; 
                padding:8px 10px; 
                color:var(--FontCol_ValeStandardTextColour); 
                border-top:1px solid var(--ValeBorderColor); 
                background:var(--ValeContentBackground);
                font-family:var(--FontType_ValeStandardText);
                font-size:0.9rem;
            }
            .spacer { flex:1; }
            .kbd { 
                font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; 
                background:var(--ValeContentBackground); 
                border:1px solid var(--ValeBorderColor); 
                padding:2px 6px; 
                border-radius:4px; 
                color:var(--FontCol_ValeStandardTextColour); 
            }
            .controls { display:flex; gap:6px; }
            .hidden { display:none; }
          </style>
        </head>
        <body>
          <div class="app">
            <div class="header-bar">
              <img src="#{logo_image_url}" alt="Vale Garden Houses Logo" class="header-bar__logo-image">
              <h1 class="header-bar__title">Vale Design Suite : Image Carousel</h1>
            </div>
            <div class="toolbar">
              <div class="title">Image Viewer</div>
              <button id="btnChoose" class="primary">Select Folder</button>
              <div class="spacer"></div>
              <div class="controls">
                <button id="btnPrev" title="Previous (←)">⟨</button>
                <button id="btnNext" title="Next (→)">⟩</button>
                <button id="btnPlay" title="Play/Pause (Space)">▶</button>
                <button id="btnFit" title="Fit (0)">Fit</button>
                <button id="btnFill" title="Fill">Fill</button>
                <button id="btn100" title="Actual Size (1)">100%</button>
                <button id="btnZoomIn" title="Zoom In (+)">＋</button>
                <button id="btnZoomOut" title="Zoom Out (−)">−</button>
                <button id="btnRotateL" title="Rotate Left (R)">⟲</button>
                <button id="btnRotateR" title="Rotate Right (Shift+R)">⟳</button>
                <button id="btnFull" title="Fullscreen (F)">⛶</button>
              </div>
            </div>
            <div class="main">
              <div class="thumbs" id="thumbs"></div>
              <div class="viewer">
                <div class="canvas-wrap">
                  <canvas id="canvas"></canvas>
                </div>
                <div class="status" id="status">
                  <div id="metaLeft">No folder selected</div>
                  <div class="spacer"></div>
                  <button id="btnReveal" title="Reveal in OS">Reveal</button>
                  <button id="btnCopy" title="Copy path">Copy Path</button>
                </div>
              </div>
            </div>
          </div>

          <script>
            // -----------------------------------------------------------------------------
            // REGION | JavaScript Module Variables and Initialization
            // -----------------------------------------------------------------------------

            const $ = sel => document.querySelector(sel);
            const thumbsEl = $('#thumbs');
            const canvas = $('#canvas');
            const ctx = canvas.getContext('2d');
            const metaLeft = $('#metaLeft');
            const isWin = navigator.platform.toLowerCase().includes('win');

            let images = [];                                                    // <-- Array of absolute image paths with forward slashes
            let index = -1;                                                    // <-- Current image index
            let playTimer = null;                                              // <-- Auto-play timer reference

            const viewer = {
              img: new Image(),
              imgW: 0,
              imgH: 0,
              zoom: 1,
              baseZoom: 1,
              rotation: 0,
              offX: 0,
              offY: 0,
              isPanning: false,
              startX: 0,
              startY: 0,
            };

            // endregion ----------------------------------------------------


            // -----------------------------------------------------------------------------
            // REGION | Canvas Rendering Functions
            // -----------------------------------------------------------------------------

            // FUNCTION | Resize Canvas to Match Container Dimensions
            // ------------------------------------------------------------
            function resizeCanvas() {
              const rect = canvas.getBoundingClientRect();
              const ratio = window.devicePixelRatio || 1;
              canvas.width = Math.max(1, Math.floor(rect.width * ratio));
              canvas.height = Math.max(1, Math.floor(rect.height * ratio));
              ctx.setTransform(1,0,0,1,0,0);
              draw();
            }
            // ---------------------------------------------------------------

            // FUNCTION | Convert File Path to File URL
            // ------------------------------------------------------------
            function pathToFileURL(p) {
              const prefix = isWin ? 'file:///' : 'file://';
              return encodeURI(prefix + p);
            }
            // ---------------------------------------------------------------

            // FUNCTION | Load Image at Specified Index
            // ------------------------------------------------------------
            function loadImageAt(i) {
              if (i < 0 || i >= images.length) return;                        // <-- Validate index range
              index = i;
              const path = images[index];
              viewer.img = new Image();
              viewer.img.onload = () => {
                viewer.imgW = viewer.img.naturalWidth;                        // <-- Store image width
                viewer.imgH = viewer.img.naturalHeight;                       // <-- Store image height
                fit();                                                        // <-- Fit image to canvas
                updateStatus();                                               // <-- Update status bar
                highlightThumb();                                             // <-- Highlight thumbnail
              };
              viewer.img.onerror = () => {
                metaLeft.textContent = 'Failed to load image (format may be unsupported)';
              };
              viewer.img.src = pathToFileURL(path);
            }
            // ---------------------------------------------------------------

            // FUNCTION | Draw Image on Canvas with Transformations
            // ------------------------------------------------------------
            function draw() {
              const w = canvas.width, h = canvas.height;
              ctx.clearRect(0,0,w,h);
              if (!viewer.img || !viewer.img.complete) return;                // <-- Exit if image not loaded
              ctx.save();
              ctx.translate(w/2 + viewer.offX, h/2 + viewer.offY);             // <-- Translate to center with offset
              ctx.rotate(viewer.rotation);                                    // <-- Apply rotation
              ctx.scale(viewer.zoom, viewer.zoom);                            // <-- Apply zoom scale
              ctx.drawImage(viewer.img, -viewer.imgW/2, -viewer.imgH/2);     // <-- Draw image centered
              ctx.restore();
            }
            // ---------------------------------------------------------------

            // endregion ----------------------------------------------------


            // -----------------------------------------------------------------------------
            // REGION | Image View Control Functions
            // -----------------------------------------------------------------------------

            // FUNCTION | Fit Image to Canvas Viewport
            // ------------------------------------------------------------
            function fit() {
              if (!viewer.imgW || !viewer.imgH) return;                       // <-- Exit if dimensions not set
              const w = canvas.width, h = canvas.height;
              const s = Math.min(w / viewer.imgW, h / viewer.imgH);           // <-- Calculate fit scale
              viewer.baseZoom = s;                                            // <-- Set base zoom level
              viewer.zoom = s;                                                // <-- Set current zoom
              viewer.rotation = 0;                                            // <-- Reset rotation
              viewer.offX = 0;                                                // <-- Reset X offset
              viewer.offY = 0;                                                // <-- Reset Y offset
              draw();
            }
            // ---------------------------------------------------------------

            // FUNCTION | Fill Canvas with Image (Crop to Fit)
            // ------------------------------------------------------------
            function fill() {
              if (!viewer.imgW || !viewer.imgH) return;                       // <-- Exit if dimensions not set
              const w = canvas.width, h = canvas.height;
              const s = Math.max(w / viewer.imgW, h / viewer.imgH);          // <-- Calculate fill scale
              viewer.zoom = s;                                                // <-- Set zoom to fill
              viewer.baseZoom = Math.min(w / viewer.imgW, h / viewer.imgH);   // <-- Set base zoom for reference
              viewer.rotation = 0;                                            // <-- Reset rotation
              viewer.offX = 0;                                                // <-- Reset X offset
              viewer.offY = 0;                                                // <-- Reset Y offset
              draw();
            }
            // ---------------------------------------------------------------

            // FUNCTION | Set Image to Actual Size (100% Zoom)
            // ------------------------------------------------------------
            function actual() { 
              viewer.zoom = 1;                                                // <-- Set zoom to 1:1
              draw(); 
            }
            // ---------------------------------------------------------------

            // FUNCTION | Rotate Image Left (90 degrees counter-clockwise)
            // ------------------------------------------------------------
            function rotateLeft() { 
              viewer.rotation -= Math.PI/2;                                    // <-- Decrease rotation by 90 degrees
              draw(); 
            }
            // ---------------------------------------------------------------

            // FUNCTION | Rotate Image Right (90 degrees clockwise)
            // ------------------------------------------------------------
            function rotateRight() { 
              viewer.rotation += Math.PI/2;                                   // <-- Increase rotation by 90 degrees
              draw(); 
            }
            // ---------------------------------------------------------------

            // FUNCTION | Zoom at Specific Point with Factor
            // ------------------------------------------------------------
            function zoomAt(cx, cy, factor) {
              const w = canvas.width, h = canvas.height;
              const x = cx - (w/2 + viewer.offX);                             // <-- Calculate relative X position
              const y = cy - (h/2 + viewer.offY);                             // <-- Calculate relative Y position
              const cos = Math.cos(-viewer.rotation), sin = Math.sin(-viewer.rotation);  // <-- Pre-calculate rotation values
              const ix = (x * cos - y * sin) / viewer.zoom;                  // <-- Calculate image-space X
              const iy = (x * sin + y * cos) / viewer.zoom;                  // <-- Calculate image-space Y
              viewer.zoom = Math.max(0.05, Math.min(40, viewer.zoom * factor));  // <-- Apply zoom factor with limits
              const nx = ix * viewer.zoom;                                    // <-- Calculate new image-space X
              const ny = iy * viewer.zoom;                                    // <-- Calculate new image-space Y
              const dx = (nx - (x * cos - y * sin));                         // <-- Calculate X offset delta
              const dy = (ny - (x * sin + y * cos));                         // <-- Calculate Y offset delta
              viewer.offX -= dx;                                              // <-- Update X offset
              viewer.offY -= dy;                                              // <-- Update Y offset
              draw();
            }
            // ---------------------------------------------------------------

            // endregion ----------------------------------------------------


            // -----------------------------------------------------------------------------
            // REGION | Canvas Event Handlers
            // -----------------------------------------------------------------------------

            canvas.addEventListener('wheel', e => {
              e.preventDefault();
              const factor = e.deltaY < 0 ? 1.1 : 0.9;                       // <-- Determine zoom direction
              zoomAt(e.offsetX * (window.devicePixelRatio||1), e.offsetY * (window.devicePixelRatio||1), factor);  // <-- Zoom at cursor position
            }, { passive:false });

            canvas.addEventListener('mousedown', e => {
              viewer.isPanning = true;                                        // <-- Enable panning mode
              viewer.startX = e.clientX;                                      // <-- Store start X position
              viewer.startY = e.clientY;                                      // <-- Store start Y position
            });

            window.addEventListener('mousemove', e => {
              if (!viewer.isPanning) return;                                  // <-- Exit if not panning
              viewer.offX += (e.clientX - viewer.startX) * (window.devicePixelRatio||1);  // <-- Update X offset
              viewer.offY += (e.clientY - viewer.startY) * (window.devicePixelRatio||1);  // <-- Update Y offset
              viewer.startX = e.clientX;                                      // <-- Update start X
              viewer.startY = e.clientY;                                      // <-- Update start Y
              draw();
            });

            window.addEventListener('mouseup', () => viewer.isPanning = false);  // <-- Disable panning on mouse up

            // endregion ----------------------------------------------------


            // -----------------------------------------------------------------------------
            // REGION | Thumbnail Management Functions
            // -----------------------------------------------------------------------------

            // FUNCTION | Render Thumbnail Sidebar
            // ------------------------------------------------------------
            function renderThumbs() {
              thumbsEl.innerHTML = '';
              images.forEach((p, i) => {
                const d = document.createElement('div');
                d.className = 'thumb';
                const im = document.createElement('img');
                im.loading = 'lazy';                                          // <-- Enable lazy loading
                im.src = pathToFileURL(p);
                im.onerror = () => d.classList.add('hidden');                 // <-- Hide thumbnails that fail to load
                const cap = document.createElement('div');
                cap.className = 'cap';
                cap.textContent = p.split('/').pop();                         // <-- Display filename
                d.appendChild(im); 
                d.appendChild(cap);
                d.addEventListener('click', () => loadImageAt(i));            // <-- Load image on click
                thumbsEl.appendChild(d);
              });
              highlightThumb();
            }
            // ---------------------------------------------------------------

            // FUNCTION | Highlight Active Thumbnail
            // ------------------------------------------------------------
            function highlightThumb() {
              const all = thumbsEl.querySelectorAll('.thumb');
              all.forEach((el, i) => el.classList.toggle('active', i === index));  // <-- Toggle active class
              const active = all[index];
              if (active) active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });  // <-- Scroll to active thumbnail
            }
            // ---------------------------------------------------------------

            // endregion ----------------------------------------------------


            // -----------------------------------------------------------------------------
            // REGION | Status and Navigation Functions
            // -----------------------------------------------------------------------------

            // FUNCTION | Update Status Bar Information
            // ------------------------------------------------------------
            function updateStatus() {
              if (index < 0) { 
                metaLeft.textContent = 'No folder selected'; 
                return; 
              }
              const name = images[index].split('/').pop();                    // <-- Get filename
              const z = Math.round((viewer.zoom) * 100);                      // <-- Calculate zoom percentage
              const dims = `${viewer.imgW}×${viewer.imgH}`;                   // <-- Format dimensions
              metaLeft.textContent = `${index+1}/${images.length}  •  ${name}  •  ${dims}  •  ${z}%`;  // <-- Update status text
            }
            // ---------------------------------------------------------------

            // FUNCTION | Navigate to Next Image
            // ------------------------------------------------------------
            function next() { 
              if (!images.length) return;                                      // <-- Exit if no images
              loadImageAt((index+1) % images.length);                         // <-- Load next image with wrap-around
            }
            // ---------------------------------------------------------------

            // FUNCTION | Navigate to Previous Image
            // ------------------------------------------------------------
            function prev() { 
              if (!images.length) return;                                      // <-- Exit if no images
              loadImageAt((index-1+images.length) % images.length);            // <-- Load previous image with wrap-around
            }
            // ---------------------------------------------------------------

            // FUNCTION | Toggle Auto-Play Slideshow
            // ------------------------------------------------------------
            function togglePlay() {
              if (playTimer) { 
                clearInterval(playTimer);                                      // <-- Stop auto-play
                playTimer = null; 
                $('#btnPlay').textContent = '▶';                              // <-- Update button icon
              }
              else { 
                playTimer = setInterval(next, 3000);                           // <-- Start auto-play (3 second interval)
                $('#btnPlay').textContent = '⏸';                             // <-- Update button icon
              }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Toggle Fullscreen Mode
            // ------------------------------------------------------------
            function goFullscreen() {
              const root = document.documentElement;
              if (!document.fullscreenElement) 
                root.requestFullscreen?.();                                    // <-- Enter fullscreen
              else 
                document.exitFullscreen?.();                                   // <-- Exit fullscreen
            }
            // ---------------------------------------------------------------

            // endregion ----------------------------------------------------


            // -----------------------------------------------------------------------------
            // REGION | UI Event Handlers and Initialization
            // -----------------------------------------------------------------------------

            // UI hooks — avoid optional chaining for older CEF builds
            $('#btnChoose').addEventListener('click', () => { 
              if (window.sketchup && window.sketchup.choose_folder) 
                window.sketchup.choose_folder();                                // <-- Trigger folder selection
            });
            $('#btnPrev').addEventListener('click', prev);
            $('#btnNext').addEventListener('click', next);
            $('#btnPlay').addEventListener('click', togglePlay);
            $('#btnFit').addEventListener('click', fit);
            $('#btnFill').addEventListener('click', fill);
            $('#btn100').addEventListener('click', actual);
            $('#btnZoomIn').addEventListener('click', () => zoomAt(canvas.width/2, canvas.height/2, 1.2));  // <-- Zoom in at center
            $('#btnZoomOut').addEventListener('click', () => zoomAt(canvas.width/2, canvas.height/2, 1/1.2));  // <-- Zoom out at center
            $('#btnRotateL').addEventListener('click', rotateLeft);
            $('#btnRotateR').addEventListener('click', rotateRight);
            $('#btnFull').addEventListener('click', goFullscreen);
            $('#btnReveal').addEventListener('click', () => { 
              const p = images[index]; 
              if (p && window.sketchup && window.sketchup.open_in_os) 
                window.sketchup.open_in_os(p);                                  // <-- Reveal file in OS
            });
            $('#btnCopy').addEventListener('click', () => { 
              const p = images[index]; 
              if (p && window.sketchup && window.sketchup.copy_path) 
                window.sketchup.copy_path(p);                                   // <-- Copy path to clipboard
            });

            window.addEventListener('resize', resizeCanvas);                   // <-- Handle window resize
            resizeCanvas();                                                    // <-- Initial canvas resize

            // Keyboard shortcuts
            window.addEventListener('keydown', (e) => {
              if (e.target && ['INPUT','TEXTAREA'].includes(e.target.tagName)) return;  // <-- Ignore input fields
              if (e.key === 'ArrowRight') next();                              // <-- Next image
              else if (e.key === 'ArrowLeft') prev();                         // <-- Previous image
              else if (e.key === ' ') { e.preventDefault(); togglePlay(); }   // <-- Toggle play/pause
              else if (e.key === '0') fit();                                  // <-- Fit to viewport
              else if (e.key === '1') actual();                               // <-- Actual size
              else if (e.key.toLowerCase() === 'r' && !e.shiftKey) rotateLeft();  // <-- Rotate left
              else if (e.key.toLowerCase() === 'r' && e.shiftKey) rotateRight();   // <-- Rotate right
              else if (e.key.toLowerCase() === 'f') goFullscreen();            // <-- Toggle fullscreen
              else if (e.key === '+' || e.key === '=') zoomAt(canvas.width/2, canvas.height/2, 1.1);  // <-- Zoom in
              else if (e.key === '-' ) zoomAt(canvas.width/2, canvas.height/2, 1/1.1);  // <-- Zoom out
            });

            // Ruby -> JS data in
            window.SKP_onFolderChosen = function(list) {
              if (!list || !list.length) { 
                images = []; 
                thumbsEl.innerHTML = ''; 
                index = -1; 
                metaLeft.textContent = 'No folder selected'; 
                ctx.clearRect(0,0,canvas.width,canvas.height); 
                return; 
              }
              images = list;                                                   // <-- Store image paths
              renderThumbs();                                                  // <-- Render thumbnails
              loadImageAt(0);                                                  // <-- Load first image
            };

            // endregion ----------------------------------------------------
          </script>
        </body>
        </html>
        HTML
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
