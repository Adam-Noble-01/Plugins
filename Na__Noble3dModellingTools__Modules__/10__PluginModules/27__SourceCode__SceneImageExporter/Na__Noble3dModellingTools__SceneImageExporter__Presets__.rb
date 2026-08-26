# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE IMAGE EXPORTER - PRESETS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneImageExporter__Presets__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneImageExporter__Presets
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Single source of truth for export presets, size steps, aspect
#              ratios, render overrides, and the default settings hash.
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Every preset, size step, aspect ratio and render override lives in this file
# and is pushed to the dialog JavaScript as data. The UI builds its dropdowns
# from that payload, so adding a preset here is the only edit required.
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com):
#   Sketchup::View#write_image(options_hash) accepts:
#     :filename     - String   - output path, extension selects the encoder
#     :width        - Integer  - pixels, maximum 16000
#     :height       - Integer  - pixels, maximum 16000
#     :antialias    - Boolean  - default false (this tool always sends true)
#     :compression  - Float    - 0.0 to 1.0, JPEG quality only
#     :transparent  - Boolean  - PNG alpha, SketchUp 8.0+
#     :scale_factor - Float    - SketchUp 2019.2+, scales viewport dependent
#                                elements: LINE WIDTHS, text heights, arrow
#                                heads and stipple patterns. This is the real
#                                "line thickness" control for image exports.
#     :source       - Symbol   - :image (offscreen, any size) or :framebuffer
#
#   Sketchup::RenderingOptions keys used by the override system:
#     DrawSilhouettes / SilhouetteWidth   - profile edges and their weight
#     ExtendLines / LineExtension         - edge overshoot and its length
#     DisplayText / DisplayDims           - screen text and dimension entities
#     DisplaySectionPlanes                - section plane markers
#     DisplayWatermarks                   - style watermarks
#     DisplaySketchAxes                   - the red/green/blue model axes
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneImageExporter__Presets

# -----------------------------------------------------------------------------
# REGION | Hard Limits
# -----------------------------------------------------------------------------

        NA_MAX_PIXELS          = 16000                                              # <-- Documented write_image ceiling
        NA_MIN_PIXELS          = 64
        NA_MIN_SCALE_FACTOR    = 0.1
        NA_MAX_SCALE_FACTOR    = 10.0
        NA_SCHEMA_VERSION      = '1.0.0'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Image Height Steps
# -----------------------------------------------------------------------------

        # Heights only. Width is derived from the chosen aspect ratio so that a
        # preset behaves the same on any monitor or viewport shape.
        NA_HEIGHT_STEPS = [
            { 'value' => 1080,  'label' => '1080 px  -  Draft / quick check' },
            { 'value' => 1440,  'label' => '1440 px  -  Screen review' },
            { 'value' => 2048,  'label' => '2048 px  -  Web / email' },
            { 'value' => 2560,  'label' => '2560 px  -  Presentation' },
            { 'value' => 3072,  'label' => '3072 px  -  Large presentation' },
            { 'value' => 4096,  'label' => '4096 px  -  Standard export (default)' },
            { 'value' => 6144,  'label' => '6144 px  -  High detail' },
            { 'value' => 8192,  'label' => '8192 px  -  Very high detail' },
            { 'value' => 12000, 'label' => '12000 px -  Print / poster' },
            { 'value' => 16000, 'label' => '16000 px -  Maximum supported' }
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Aspect Ratios
# -----------------------------------------------------------------------------

        # 'ratio' is width divided by height. A nil ratio means the ratio is
        # resolved at export time (live viewport, or the custom ratio fields).
        NA_ASPECT_MODES = [
            { 'key' => 'viewport',    'label' => 'Match SketchUp viewport (default)', 'ratio' => nil },
            { 'key' => 'ratio_16_9',  'label' => '16 : 9  -  Widescreen',             'ratio' => 16.0 / 9.0 },
            { 'key' => 'ratio_16_10', 'label' => '16 : 10 -  Widescreen tall',        'ratio' => 16.0 / 10.0 },
            { 'key' => 'ratio_3_2',   'label' => '3 : 2   -  Photographic',           'ratio' => 3.0 / 2.0 },
            { 'key' => 'ratio_4_3',   'label' => '4 : 3   -  Classic',                'ratio' => 4.0 / 3.0 },
            { 'key' => 'ratio_1_1',   'label' => '1 : 1   -  Square',                 'ratio' => 1.0 },
            { 'key' => 'ratio_2_1',   'label' => '2 : 1   -  Panoramic',              'ratio' => 2.0 },
            { 'key' => 'a_land',      'label' => 'A-Series landscape (A4 / A3 / A2)', 'ratio' => 297.0 / 210.0 },
            { 'key' => 'a_port',      'label' => 'A-Series portrait (A4 / A3 / A2)',  'ratio' => 210.0 / 297.0 },
            { 'key' => 'custom',      'label' => 'Custom ratio',                      'ratio' => nil }
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Render Override Definitions
# -----------------------------------------------------------------------------

        # Each override is tri-state: 'scene' leaves the scene's own style alone,
        # 'on' and 'off' force the rendering option for the duration of the
        # export only. Values are re-applied after every page activation because
        # activating a scene restores that scene's saved rendering options.
        NA_RENDER_OVERRIDES = [
            {
                'key'        => 'profiles',
                'label'      => 'Profile edges',
                'option_key' => 'DrawSilhouettes',
                'hint'       => 'Heavy outline edges around the silhouette of forms.'
            },
            {
                'key'        => 'edge_extensions',
                'label'      => 'Edge extensions',
                'option_key' => 'ExtendLines',
                'hint'       => 'Sketchy edge overshoot at corners.'
            },
            {
                'key'        => 'screen_text',
                'label'      => 'Screen text',
                'option_key' => 'DisplayText',
                'hint'       => 'Text and leader entities placed in the model.'
            },
            {
                'key'        => 'dimensions',
                'label'      => 'Dimensions',
                'option_key' => 'DisplayDims',
                'hint'       => 'Dimension entities placed in the model.'
            },
            {
                'key'        => 'section_planes',
                'label'      => 'Section plane markers',
                'option_key' => 'DisplaySectionPlanes',
                'hint'       => 'The grey section plane rectangles, not the cut itself.'
            },
            {
                'key'        => 'watermarks',
                'label'      => 'Style watermarks',
                'option_key' => 'DisplayWatermarks',
                'hint'       => 'Watermark images baked into the active style.'
            },
            {
                'key'        => 'model_axes',
                'label'      => 'Model axes',
                'option_key' => 'DisplaySketchAxes',
                'hint'       => 'The red / green / blue drawing axes.'
            }
        ].freeze

        NA_OVERRIDE_STATES = [
            { 'key' => 'scene', 'label' => 'Use scene style' },
            { 'key' => 'on',    'label' => 'Force on' },
            { 'key' => 'off',   'label' => 'Force off' }
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Export Presets
# -----------------------------------------------------------------------------

        # A preset is a bundle of settings applied in one click. Every field it
        # touches stays individually editable afterwards, which flips the active
        # preset to 'custom' in the dialog.
        NA_EXPORT_PRESETS = [
            {
                'key'      => 'standard_4k',
                'label'    => 'Standard 4K PNG (default)',
                'hint'     => '4096 px tall, viewport aspect, slightly weighted lines. The everyday export.',
                'settings' => {
                    'image_height'           => 4096,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 1.5,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'draft_1080',
                'label'    => 'Draft 1080 PNG',
                'hint'     => 'Fast low-resolution pass for checking scene selection and framing.',
                'settings' => {
                    'image_height'           => 1080,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 1.0,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'presentation_2k',
                'label'    => 'Presentation 2K PNG',
                'hint'     => '2048 px tall with true-to-screen line weights. Good for slide decks.',
                'settings' => {
                    'image_height'           => 2048,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 1.0,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'line_heavy_4k',
                'label'    => 'Line Heavy 4K PNG',
                'hint'     => '4096 px tall with 3x line weight. Keeps edges readable when the image is scaled down.',
                'settings' => {
                    'image_height'           => 4096,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 3.0,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'fine_line_4k',
                'label'    => 'Fine Line 4K PNG',
                'hint'     => '4096 px tall with 0.5x line weight. Delicate technical linework.',
                'settings' => {
                    'image_height'           => 4096,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 0.5,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'transparent_4k',
                'label'    => 'Transparent 4K PNG',
                'hint'     => '4096 px tall on a transparent background for compositing over photos or plans.',
                'settings' => {
                    'image_height'           => 4096,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 1.5,
                    'transparent_background' => true,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'print_a3_300dpi',
                'label'    => 'Print A3 landscape @ 300dpi',
                'hint'     => '3508 px tall at A-series landscape ratio (4961 x 3508). Weighted lines for paper.',
                'settings' => {
                    'image_height'           => 3508,
                    'aspect_mode'            => 'a_land',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 2.0,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'print_a4_300dpi',
                'label'    => 'Print A4 landscape @ 300dpi',
                'hint'     => '2480 px tall at A-series landscape ratio (3508 x 2480). Weighted lines for paper.',
                'settings' => {
                    'image_height'           => 2480,
                    'aspect_mode'            => 'a_land',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 1.5,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'web_jpg_2k',
                'label'    => 'Web JPG 2K',
                'hint'     => '2048 px tall JPEG at 92% quality. Small files for web and email.',
                'settings' => {
                    'image_height'           => 2048,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'jpg',
                    'line_scale_factor'      => 1.0,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'maximum_8k',
                'label'    => 'Maximum 8K PNG',
                'hint'     => '8192 px tall with 2.5x line weight. Slow, and produces very large files.',
                'settings' => {
                    'image_height'           => 8192,
                    'aspect_mode'            => 'viewport',
                    'file_format'            => 'png',
                    'line_scale_factor'      => 2.5,
                    'transparent_background' => false,
                    'jpeg_quality'           => 0.92
                }
            },
            {
                'key'      => 'custom',
                'label'    => 'Custom (your own settings)',
                'hint'     => 'Whatever combination is set below. Saved with the model like every other setting.',
                'settings' => {}
            }
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | File Formats, Overwrite Modes, Filename Tokens
# -----------------------------------------------------------------------------

        NA_FILE_FORMATS = [
            { 'key' => 'png', 'label' => 'PNG  -  lossless, supports transparency', 'extension' => 'png' },
            { 'key' => 'jpg', 'label' => 'JPG  -  compressed, smaller files',       'extension' => 'jpg' },
            { 'key' => 'tif', 'label' => 'TIF  -  lossless, print pipelines',       'extension' => 'tif' },
            { 'key' => 'bmp', 'label' => 'BMP  -  uncompressed',                    'extension' => 'bmp' }
        ].freeze

        NA_OVERWRITE_MODES = [
            { 'key' => 'overwrite', 'label' => 'Overwrite existing files' },
            { 'key' => 'skip',      'label' => 'Skip files that already exist' },
            { 'key' => 'unique',    'label' => 'Keep both - add a numbered suffix' }
        ].freeze

        NA_FILENAME_TOKENS = [
            { 'token' => '{{ModelName}}', 'hint' => 'The .skp file name without its extension.' },
            { 'token' => '{{SceneName}}', 'hint' => 'The scene tab name.' },
            { 'token' => '{{Date}}',      'hint' => 'Export date, for example 25-Aug-2026.' },
            { 'token' => '{{Time}}',      'hint' => 'Export time, for example 14-32.' },
            { 'token' => '{{Index}}',     'hint' => 'Two digit position in the export run, 01, 02, 03.' }
        ].freeze

        NA_DEFAULT_FILENAME_PATTERN = '{{ModelName}}__{{SceneName}}__{{Date}}__'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Default Settings
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Factory Default Settings Hash
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__DefaultSettings
            override_defaults = {}
            NA_RENDER_OVERRIDES.each { |entry| override_defaults[entry['key']] = 'scene' }

            {
                'preset_key'             => 'standard_4k',
                'image_height'           => 4096,
                'aspect_mode'            => 'viewport',
                'custom_aspect_width'    => 16,
                'custom_aspect_height'   => 9,
                'file_format'            => 'png',
                'jpeg_quality'           => 0.92,
                'line_scale_factor'      => 1.5,
                'transparent_background' => false,
                'antialias'              => true,                                   # <-- Always on, per tool specification
                'filename_pattern'       => NA_DEFAULT_FILENAME_PATTERN,
                'overwrite_mode'         => 'overwrite',
                'export_folder'          => '',
                'silhouette_width'       => 2,
                'line_extension_amount'  => 4,
                'render_overrides'       => override_defaults
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Look Up One Preset by Key
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__PresetByKey(preset_key)
            NA_EXPORT_PRESETS.find { |entry| entry['key'] == preset_key.to_s }
        end
        # ------------------------------------------------------------

        # FUNCTION | Look Up an Aspect Ratio Definition by Key
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__AspectByKey(aspect_key)
            NA_ASPECT_MODES.find { |entry| entry['key'] == aspect_key.to_s }
        end
        # ------------------------------------------------------------

        # FUNCTION | Resolve the File Extension for a Format Key
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ExtensionForFormat(format_key)
            entry = NA_FILE_FORMATS.find { |candidate| candidate['key'] == format_key.to_s }
            entry ? entry['extension'] : 'png'
        end
        # ------------------------------------------------------------

        # FUNCTION | Bundle Every Choice List for the Dialog Payload
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ChoiceLists
            {
                'schema_version'   => NA_SCHEMA_VERSION,
                'presets'          => NA_EXPORT_PRESETS,
                'height_steps'     => NA_HEIGHT_STEPS,
                'aspect_modes'     => NA_ASPECT_MODES,
                'file_formats'     => NA_FILE_FORMATS,
                'overwrite_modes'  => NA_OVERWRITE_MODES,
                'render_overrides' => NA_RENDER_OVERRIDES,
                'override_states'  => NA_OVERRIDE_STATES,
                'filename_tokens'  => NA_FILENAME_TOKENS,
                'max_pixels'       => NA_MAX_PIXELS,
                'min_pixels'       => NA_MIN_PIXELS,
                'min_scale_factor' => NA_MIN_SCALE_FACTOR,
                'max_scale_factor' => NA_MAX_SCALE_FACTOR
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneImageExporter__Presets
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
