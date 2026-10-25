# =============================================================================
# NA POINT CLOUD VIEWER - NATIVE ENGINE - BRIDGE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__NativeEngine__Bridge__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__NativeEngine
# PURPOSE    : Loads Na__PointCloudViewer__NativeEngine.dll with Fiddle and
#              wraps its C API (see 01__CppSource/...Api__.h).
#
# WHY FIDDLE, NOT A RUBY C EXTENSION (the decimator's route):
#   - The DLL never touches Ruby objects, so it needs no Ruby headers or import
#     library and is independent of SketchUp's Ruby version.
#   - It can be HOT-SWAPPED: Ruby loads a shadow COPY (so the build can
#     overwrite the original while SketchUp runs) and, when the original is
#     newer, shuts the old copy down, unloads it and loads the new one.
#     A Ruby C extension can never be unloaded.
#
# LIFETIME OF NATIVE OBJECTS:
#   Each native cloud, cleaning context and export job is a Fiddle::Pointer
#   whose free function is its destroy function, so whatever a closed model
#   held is freed by Ruby's GC. Before a hot swap every live export job and
#   cleaning context is destroyed first (each joins its worker thread, so no
#   thread can run in an unloaded DLL), then every cloud; each free function
#   is cleared so GC never calls into the old DLL. Sessions see the generation
#   change and load again.
#
# ABI 5 (v0.8.0): clouds remember which LAS record each point came from and
#   its GPS time, caches are named by the LAS content key, and the cleaning
#   engine (preview context + export job) is exposed.
# ABI 6 (v0.9.1): the LAZ to LAS converter job (napc_laz_convert_*).
# ABI 7 (v0.10.0): several clouds in one frame (napc_render_layers_png): one
#   depth buffer, one shared point budget, each cloud with its own placement,
#   clip box, dot size, opacity and colour.
# ABI 8 (v0.11.0): the Clean tab's Crop and Cut boxes. A cloud's render block
#   grows from 48 to 184 numbers (the boxes and how to show them); a 48-number
#   block still renders, so every caller is padded here. napc_box_count counts
#   what the boxes remove; napc_box_export_start writes a NEW LAS without it.
#
# A BUILD THIS CODE CANNOT USE (v0.11.0): a DLL on disk with another ABI is
#   checked BEFORE the running engine is touched. If the running engine is the
#   right one it keeps running (the newer build waits for Reload Plugin, and is
#   tried once, not every frame); only an engine this code cannot use is let
#   go. Before, a mismatched build unloaded the working engine first and then
#   refused the new one, which stopped every cloud until the plugin reloaded.
#
# =============================================================================

require 'fiddle'
require 'zlib'

module Na__PointCloudViewer
    module Na__NativeEngine

    # -------------------------------------------------------------------------
    # REGION | Constants (must match the C headers)
    # -------------------------------------------------------------------------

        NA_DLL_NAME         = 'Na__PointCloudViewer__NativeEngine.dll'.freeze
        NA_EXPECTED_ABI     = 8
        NA_PARAM_COUNT      = 48                                  # a cloud's render block without boxes (the ABI 7 layout)
        NA_MAX_CUT_BOXES    = 20                                  # Api.h NAPC_MAX_CUT_BOXES
        NA_BOX_BLOCK_COUNT  = 8 + 6 * NA_MAX_CUT_BOXES            # 128: keep flag + box, cut count + boxes
        NA_BOXES_COUNT      = 12 + NA_BOX_BLOCK_COUNT             # 140: local -> model, then the box block
        NA_RENDER_PARAM_COUNT = NA_PARAM_COUNT + 8 + NA_BOX_BLOCK_COUNT   # 184: + view mode, removed colour, tint, share
        NA_STAT_COUNT       = 10
        NA_STAT_KEYS        = %w[pointsTested pointsOnScreen threads clearMs rasterMs resolveMs encodeMs writeMs nativeTotalMs pngBytes].freeze
        NA_LAYER_STAT_KEYS  = %w[demand share tested onScreen].freeze
        NA_MAX_LAYERS       = 16
        NA_LAS_INFO_COUNT   = 22
        NA_JOB_POLL_COUNT   = 27
        NA_CACHE_INFO_COUNT = 18
        NA_TEXT_CAPACITY    = 8192

        # Cleaning (CleanTypes.hpp / Api.h)
        NA_CLEAN_PARAM_KEYS = %w[mm_per_unit noise_enabled iso_ratio iso_min_mm knn_cap_mm link_factor link_min_mm
                                 link_max_mm cluster_min_points cluster_max_mm blowout_remove scatter_ratio
                                 refine_enabled refine_strength max_move_mm cell_mm smooth_radius_mm inlier_band
                                 pass_gap_s pass_disagree_mm doubling_hold sigma_fallback_mm density_enabled voxel_mm
                                 feature_factor].freeze
        NA_CLEAN_REGION_COUNT = 19
        NA_CLEAN_STAT_KEYS  = %w[corePoints kept removedIsolated removedCluster removedBlowout removedDensity moved
                                 candidates doubling heldAmbiguous onSurface feature moveMedianMm moveP95Mm moveMaxMm
                                 gatheredPoints haloMm sigmaMm doublingGapMm gatherMs indexMs noiseMs surfaceMs
                                 refineMs densityMs sectionMs totalMs reusedStages surfaceCount surfaceNote].freeze
        NA_CLEAN_SURFACE_KEYS = %w[kind nx ny nz pointsBefore pointsAfter bandBeforeMm bandAfterMm sigmaBeforeMm
                                   sigmaAfterMm shiftMm moved removed flags share reserved].freeze
        NA_CLEAN_STAT_COUNT = NA_CLEAN_STAT_KEYS.length + 2 * NA_CLEAN_SURFACE_KEYS.length   # 62
        NA_CLEAN_DIFF_COLOURS = 22
        NA_EXPORT_KEYS      = %w[phase done total finished failed cancelled sourcePoints written moved removed heldRange
                                 removedIsolated removedCluster removedBlowout removedDensity doubling candidates
                                 minX minY minZ maxX maxY maxZ bytes keyHi keyLo cleanMs writeMs verifyMs totalMs
                                 tiles maxTilePoints peakWorkMb byReturnMismatch droppedVlrs droppedEvlrs gridMs
                                 removedKeep removedCut].freeze
        NA_EXPORT_POLL_COUNT = NA_EXPORT_KEYS.length   # 39
        NA_PREVIEW_STATES   = { 0 => 'idle', 1 => 'running', 2 => 'done', 3 => 'failed', 4 => 'cancelled' }.freeze

        # LAZ to LAS (Api.h Na__LazPollIndex)
        NA_LAZ_KEYS         = %w[phase done total finished failed cancelled pointCount pointFormat recordLength
                                 versionMajor versionMinor sourceBytes writtenBytes
                                 headerMinX headerMinY headerMinZ headerMaxX headerMaxY headerMaxZ
                                 pointMinX pointMinY pointMinZ pointMaxX pointMaxY pointMaxZ
                                 droppedRecords convertMs checkMs totalMs].freeze
        NA_LAZ_POLL_COUNT   = NA_LAZ_KEYS.length   # 29

        @na_handle       = nil  unless defined?(@na_handle)
        @na_functions    = nil  unless defined?(@na_functions)
        @na_generation   = 0    unless defined?(@na_generation)
        @na_loaded_mtime = nil  unless defined?(@na_loaded_mtime)
        @na_loaded_abi   = nil  unless defined?(@na_loaded_abi)     # nil: loaded by code from before v0.11.0
        @na_refused      = nil  unless defined?(@na_refused)        # [mtime, expected ABI] of a build already refused
        @na_load_error   = nil  unless defined?(@na_load_error)
        @na_live         = ObjectSpace::WeakMap.new unless defined?(@na_live)
        @na_live_contexts = ObjectSpace::WeakMap.new unless defined?(@na_live_contexts)
        @na_live_jobs    = ObjectSpace::WeakMap.new unless defined?(@na_live_jobs)
        @na_live_laz_jobs = ObjectSpace::WeakMap.new unless defined?(@na_live_laz_jobs)
        @na_stats_buffer = nil  unless defined?(@na_stats_buffer)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Load / Hot Swap
    # -------------------------------------------------------------------------

        def self.Na__Native__BinaryPath
            File.join(Na__PointCloudViewer::NA_MODULES_ROOT, '02__Src__NativeEngine', '04__Bin__WindowsSketchUp2026', NA_DLL_NAME)
        end

        def self.Na__Native__Generation
            @na_generation
        end

        # True when an engine this code can use is loaded. Loads on first call
        # and hot-swaps when the binary on disk is newer than the loaded copy.
        # A build on disk with another ABI is refused once (not every frame) and
        # never stops an engine that is the right one.
        def self.Na__Native__EnsureLoaded
            path = self.Na__Native__BinaryPath
            unless File.exist?(path)
                @na_load_error = 'The native engine has not been built yet (02__Src__NativeEngine/03__BuildScripts).'
                return false
            end
            mtime = File.mtime(path)
            usable = @na_handle && @na_loaded_abi == NA_EXPECTED_ABI ? true : false
            return true if usable && @na_loaded_mtime == mtime
            return usable if @na_refused == [mtime, NA_EXPECTED_ABI]
            self.na_load(path, mtime)
        end

        def self.Na__Native__Available?
            self.Na__Native__EnsureLoaded
        rescue StandardError
            false
        end

        # The build on disk is opened and its ABI checked BEFORE the running
        # engine is touched: a build this code cannot use never takes down one
        # it can (it is remembered and not tried again until it changes).
        def self.na_load(path, mtime)
            shadow = self.na_shadow_copy(path, mtime)
            handle = Fiddle::Handle.new(shadow)
            abi_function = Fiddle::Function.new(handle['napc_abi_version'], [], Fiddle::TYPE_INT)
            abi = abi_function.call
            if abi != NA_EXPECTED_ABI
                handle.close
                @na_refused = [mtime, NA_EXPECTED_ABI]
                if @na_handle && @na_loaded_abi == NA_EXPECTED_ABI
                    @na_load_error = "The native engine on disk speaks ABI #{abi}; this plugin expects #{NA_EXPECTED_ABI}. " \
                                     'The engine already running is kept. Reload Plugin once the plugin\'s files match it, or rebuild it.'
                    Na__DebugTools.Na__Debug__Warn(@na_load_error)
                    return true
                end
                self.na_unload if @na_handle      # what runs cannot serve this code either
                @na_load_error = "The native engine binary speaks ABI #{abi}; this plugin expects #{NA_EXPECTED_ABI}. Rebuild it."
                return false
            end
            self.na_unload if @na_handle
            functions = self.na_bind(handle)
            @na_handle       = handle
            @na_functions    = functions
            @na_loaded_mtime = mtime
            @na_loaded_abi   = abi
            @na_refused      = nil
            @na_generation  += 1
            @na_load_error   = nil
            @na_stats_buffer = Fiddle::Pointer.malloc(8 * NA_STAT_COUNT)
            Na__DebugTools.Na__Debug__Info("Native engine loaded (generation #{@na_generation}, #{functions[:threads].call} threads): #{File.basename(shadow)}")
            true
        rescue Fiddle::DLError, StandardError => error
            @na_handle = nil
            @na_functions = nil
            @na_load_error = "The native engine could not be loaded: #{error.message}"
            Na__DebugTools.Na__Debug__Error('Native engine load failed.', error)
            false
        end

        def self.na_bind(handle)
            voidp  = Fiddle::TYPE_VOIDP
            int    = Fiddle::TYPE_INT
            int64  = Fiddle::TYPE_LONG_LONG
            double = Fiddle::TYPE_DOUBLE
            void   = Fiddle::TYPE_VOID
            fn = ->(name, args, ret) { Fiddle::Function.new(handle[name], args, ret) }
            {
                abi:      fn.('napc_abi_version', [], int),
                threads:  fn.('napc_thread_count', [], int),
                error:    fn.('napc_last_error', [], voidp),
                create:   fn.('napc_cloud_create', [voidp, voidp, int64], voidp),
                destroy:  fn.('napc_cloud_destroy', [voidp], void),
                info:     fn.('napc_cloud_info', [voidp, voidp, int], int),
                render:   fn.('napc_render_png', [voidp, voidp, int, voidp, voidp, int], int),
                render_layers: fn.('napc_render_layers_png', [voidp, int, voidp, int, double, voidp, voidp, int, voidp, int], int),
                shutdown: fn.('napc_shutdown', [], void),
                las_header:   fn.('napc_las_read_header', [voidp, voidp, int, voidp, int], int),
                las_key:      fn.('napc_las_content_key', [voidp, voidp, int], int),
                las_import:   fn.('napc_las_import_start', [voidp, voidp, voidp, int], voidp),
                cache_load:   fn.('napc_cache_load_start', [voidp, voidp, int], voidp),
                cache_peek:   fn.('napc_cache_peek', [voidp, voidp, int], int),
                job_poll:     fn.('napc_job_poll', [voidp, voidp, int], int),
                job_error:    fn.('napc_job_error', [voidp, voidp, int], int),
                job_cancel:   fn.('napc_job_cancel', [voidp], void),
                job_take:     fn.('napc_job_take_cloud', [voidp], voidp),
                job_destroy:  fn.('napc_job_destroy', [voidp], void),
                clean_create:         fn.('napc_clean_create', [voidp, double], voidp),
                clean_destroy:        fn.('napc_clean_destroy', [voidp], void),
                clean_request:        fn.('napc_clean_preview_request', [voidp, voidp, int, voidp, int], int64),
                clean_cancel:         fn.('napc_clean_preview_cancel', [voidp], void),
                clean_poll:           fn.('napc_clean_preview_poll', [voidp, voidp, int], int),
                clean_stats:          fn.('napc_clean_preview_stats', [voidp, voidp, int], int),
                clean_error:          fn.('napc_clean_preview_error', [voidp, voidp, int], int),
                clean_cloud:          fn.('napc_clean_preview_cloud', [voidp, int, voidp, int], voidp),
                export_start:         fn.('napc_clean_export_start', [voidp, voidp, voidp, voidp, int, voidp, voidp, voidp], voidp),
                export_poll:          fn.('napc_clean_export_poll', [voidp, voidp, int], int),
                export_error:         fn.('napc_clean_export_error', [voidp, voidp, int], int),
                export_notes:         fn.('napc_clean_export_notes', [voidp, voidp, int], int),
                export_cancel:        fn.('napc_clean_export_cancel', [voidp], void),
                export_destroy:       fn.('napc_clean_export_destroy', [voidp], void),
                box_count:            fn.('napc_box_count', [voidp, voidp, int, voidp, int], int),
                box_export_start:     fn.('napc_box_export_start', [voidp, voidp, voidp, voidp, int, voidp, voidp, voidp], voidp),
                laz_start:            fn.('napc_laz_convert_start', [voidp, voidp], voidp),
                laz_poll:             fn.('napc_laz_convert_poll', [voidp, voidp, int], int),
                laz_error:            fn.('napc_laz_convert_error', [voidp, voidp, int], int),
                laz_notes:            fn.('napc_laz_convert_notes', [voidp, voidp, int], int),
                laz_cancel:           fn.('napc_laz_convert_cancel', [voidp], void),
                laz_destroy:          fn.('napc_laz_convert_destroy', [voidp], void)
            }
        end

        # Every live native object dies with the old DLL: LAZ conversions,
        # export jobs and cleaning contexts first (each joins its own worker),
        # then clouds.
        # Their owners notice the generation change and start again.
        def self.na_unload
            [[@na_live_laz_jobs, :laz_destroy], [@na_live_jobs, :export_destroy], [@na_live_contexts, :clean_destroy],
             [@na_live, :destroy]].each do |live, destroy|
                live.each do |pointer, alive|
                    next unless alive
                    begin
                        pointer.free = nil
                        @na_functions[destroy].call(pointer) if @na_functions
                    rescue StandardError
                        nil
                    end
                end
            end
            @na_live          = ObjectSpace::WeakMap.new
            @na_live_contexts = ObjectSpace::WeakMap.new
            @na_live_jobs     = ObjectSpace::WeakMap.new
            @na_live_laz_jobs = ObjectSpace::WeakMap.new
            @na_functions[:shutdown].call if @na_functions
            @na_handle.close if @na_handle
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('Native engine unload failed.', error)
        ensure
            @na_handle = nil
            @na_functions = nil
            @na_loaded_mtime = nil
            @na_loaded_abi = nil
        end

        # Windows locks a loaded DLL; loading a copy keeps the build output free.
        # The copy is named by a digest of the build's bytes (v0.11.0; it was
        # named by the file's time), so another build can never pass for the
        # copy already loaded, whatever its time says. An update can then keep
        # the old file's time: the code running sees no newer build, and nothing
        # swaps until Reload Plugin brings the code that wants it. (The name
        # stays well inside the 259 characters SketchUp can open.)
        def self.na_shadow_copy(path, _mtime)
            folder = File.join(Na__AssetResolver.Na__Paths__CacheFolder, '00__NativeShadowCopies')
            FileUtils.mkdir_p(folder)
            Dir.glob(File.join(folder, '*.dll')).each { |old| File.delete(old) rescue nil }   # loaded ones stay locked
            digest = format('%08x', Zlib.crc32(File.binread(path)))
            shadow = File.join(folder, "Na__PointCloudViewer__NativeEngine__#{digest}__#{Process.pid}.dll")
            FileUtils.cp(path, shadow) unless File.exist?(shadow)
            shadow
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Clouds
    # -------------------------------------------------------------------------

        # xyz_f32: binary String, count * 3 float32. rgb: binary String, count * 3 bytes.
        # Returns a Fiddle::Pointer owned by the caller (freed by GC) or raises.
        def self.Na__Native__CloudCreate(xyz_f32, rgb, count)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            raw = @na_functions[:create].call(Fiddle::Pointer[xyz_f32], Fiddle::Pointer[rgb], count)
            raise "The native engine could not take the point cloud: #{self.na_last_error}" if raw.null?
            self.na_adopt_cloud(raw)
        end

        # Frees a cloud now instead of waiting for GC (a LAS cloud is ~24 bytes
        # per point of native memory). Safe to call twice.
        def self.Na__Native__CloudRelease(pointer)
            return unless pointer && @na_functions && @na_live[pointer]
            pointer.free = nil
            @na_live[pointer] = false   # WeakMap#delete only exists from Ruby 3.3
            @na_functions[:destroy].call(pointer)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Native cloud release warning: #{error.message}")
        end

        # False once released, or once the DLL it came from was swapped out.
        def self.Na__Native__CloudLive?(pointer)
            pointer && @na_functions && @na_live[pointer] ? true : false
        end

        # { 'count', 'hasRecordIndex', 'hasTime', 'timeBase' } or nil.
        def self.Na__Native__CloudInfo(pointer)
            return nil unless pointer && @na_functions && @na_live[pointer]
            out = Fiddle::Pointer.malloc(8 * 4, self.na_ruby_free)
            return nil if @na_functions[:info].call(pointer, out, 4) < 0
            count, has_index, has_time, time_base = out.to_s(32).unpack('d*')
            { 'count' => count.to_i, 'hasRecordIndex' => has_index.to_i == 1, 'hasTime' => has_time.to_i == 1, 'timeBase' => time_base }
        end

        def self.na_adopt_cloud(raw)
            pointer = Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:destroy])
            @na_live[pointer] = true
            pointer
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | LAS (header, content key, threaded import job)
    # -------------------------------------------------------------------------

        NA_LAS_INFO_KEYS = %w[versionMajor versionMinor pointFormat recordLength pointCount
                              scaleX scaleY scaleZ offsetX offsetY offsetZ minX minY minZ maxX maxY maxZ
                              hasRgb vlrCount hasWkt hasGeoKeys isCompressed].freeze
        NA_JOB_KEYS = %w[phase done total finished failed cancelled readMs colourMs shuffleMs totalMs colourBits
                         originX originY originZ minX minY minZ maxX maxY maxZ pointCount cacheState
                         flags timeBase keyHi keyLo cacheVersion].freeze
        NA_CACHE_INFO_KEYS = %w[pointCount originX originY originZ minX minY minZ maxX maxY maxZ colourBits
                                lasBytes lasMtime version flags keyHi keyLo timeBase].freeze

        def self.Na__Native__LasReadHeader(path)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            info = Fiddle::Pointer.malloc(8 * NA_LAS_INFO_COUNT, self.na_ruby_free)
            text = Fiddle::Pointer.malloc(NA_TEXT_CAPACITY, self.na_ruby_free)
            path_c = self.na_cstr(path)
            code = @na_functions[:las_header].call(Fiddle::Pointer[path_c], info, NA_LAS_INFO_COUNT, text, NA_TEXT_CAPACITY)
            raise self.na_last_error if code < 0
            values = info.to_s(8 * NA_LAS_INFO_COUNT).unpack('d*')
            system_id, software, wkt = text.to_s.force_encoding('UTF-8').scrub('?').split("\t", 3)
            NA_LAS_INFO_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
                            .merge('systemId' => system_id.to_s, 'software' => software.to_s, 'wkt' => wkt.to_s)
        end

        # The LAS file's content key as 16 lowercase hex digits (LasFile.cpp:
        # size, header, VLRs and sampled blocks of the point data). Reads about
        # 2 MB. Raises when the file cannot be read.
        def self.Na__Native__LasContentKey(path)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            out = Fiddle::Pointer.malloc(16, self.na_ruby_free)
            path_c = self.na_cstr(path)
            code = @na_functions[:las_key].call(Fiddle::Pointer[path_c], out, 2)
            raise "The LAS file could not be identified: #{self.na_last_error}" if code < 0
            hi, lo = out.to_s(16).unpack('d*')
            self.Na__Native__KeyHex(hi, lo)
        end

        def self.Na__Native__KeyHex(hi, lo)
            format('%08x%08x', hi.to_i & 0xFFFFFFFF, lo.to_i & 0xFFFFFFFF)
        end

        # [hi, lo] doubles of a 16-hex key ([0, 0] for none).
        def self.Na__Native__KeyParts(key_hex)
            text = key_hex.to_s
            return [0.0, 0.0] unless text.match?(/\A[0-9a-f]{16}\z/)
            [text[0, 8].to_i(16).to_f, text[8, 8].to_i(16).to_f]
        end

        # cache_path: also write the point cache there once the cloud is ready
        # (nil = no cache). las_bytes / las_mtime / key_hex are stored in its header.
        def self.Na__Native__LasImportStart(path, fallback_rgb, cache_path = nil, las_bytes = 0, las_mtime = 0, key_hex = nil)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            params = (fallback_rgb.map(&:to_f) + [las_bytes.to_f, las_mtime.to_f] + self.Na__Native__KeyParts(key_hex)).pack('d*')
            path_c  = self.na_cstr(path)
            cache_c = cache_path ? self.na_cstr(cache_path) : nil
            cache   = cache_c ? Fiddle::Pointer[cache_c] : Fiddle::Pointer.new(0)
            raw = @na_functions[:las_import].call(Fiddle::Pointer[path_c], cache, Fiddle::Pointer[params], 7)
            raise "The LAS import could not start: #{self.na_last_error}" if raw.null?
            Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:job_destroy])
        end

        # Loads a point cache on the engine's worker thread (same job API as an
        # import). key_hex: the content key the cache must record (nil = any).
        def self.Na__Native__CacheLoadStart(cache_path, expect_count, key_hex = nil)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            params = ([expect_count.to_f] + self.Na__Native__KeyParts(key_hex)).pack('d*')
            path_c = self.na_cstr(cache_path)
            raw = @na_functions[:cache_load].call(Fiddle::Pointer[path_c], Fiddle::Pointer[params], 3)
            raise "The point cache could not be opened: #{self.na_last_error}" if raw.null?
            Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:job_destroy])
        end

        # The validated cache header as a Hash (plus 'contentKey'), or nil
        # (missing or not usable).
        def self.Na__Native__CachePeek(cache_path)
            return nil unless File.file?(cache_path)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            out = Fiddle::Pointer.malloc(8 * NA_CACHE_INFO_COUNT, self.na_ruby_free)
            path_c = self.na_cstr(cache_path)
            code = @na_functions[:cache_peek].call(Fiddle::Pointer[path_c], out, NA_CACHE_INFO_COUNT)
            return nil if code < 0
            values = out.to_s(8 * NA_CACHE_INFO_COUNT).unpack('d*')
            info = NA_CACHE_INFO_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
            info.merge('contentKey' => self.na_key_or_nil(info['keyHi'], info['keyLo']))
        end

        def self.Na__Native__JobPoll(job)
            buffer = Fiddle::Pointer.malloc(8 * NA_JOB_POLL_COUNT, self.na_ruby_free)
            @na_functions[:job_poll].call(job, buffer, NA_JOB_POLL_COUNT)
            values = buffer.to_s(8 * NA_JOB_POLL_COUNT).unpack('d*')
            poll = NA_JOB_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
            poll.merge('contentKey' => self.na_key_or_nil(poll['keyHi'], poll['keyLo']))
        end

        def self.Na__Native__JobError(job)
            self.na_read_text(:job_error, job)
        end

        def self.Na__Native__JobCancel(job)
            @na_functions[:job_cancel].call(job) if job && @na_functions
        end

        # The cloud becomes a GC-managed pointer like an uploaded one.
        def self.Na__Native__JobTakeCloud(job)
            raw = @na_functions[:job_take].call(job)
            raw.null? ? nil : self.na_adopt_cloud(raw)
        end

        # Joins the worker now (it exits promptly once cancelled).
        def self.Na__Native__JobDestroy(job)
            return unless job && @na_functions
            job.free = nil
            @na_functions[:job_destroy].call(job)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cleaning: preview context (one per loaded cloud)
    # -------------------------------------------------------------------------

        # cloud_pointer: a live native cloud. The context shares its points, so
        # releasing the cloud later is safe. Freed by GC, or Na__Native__CleanDestroy.
        def self.Na__Native__CleanCreate(cloud_pointer, mm_per_unit)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            raw = @na_functions[:clean_create].call(cloud_pointer, mm_per_unit.to_f)
            raise 'The cleaning engine could not start for this cloud.' if raw.null?
            pointer = Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:clean_destroy])
            @na_live_contexts[pointer] = true
            pointer
        end

        # Cancels and joins its preview worker, then frees it. Safe to call twice.
        def self.Na__Native__CleanDestroy(context)
            return unless context && @na_functions && @na_live_contexts[context]
            context.free = nil
            @na_live_contexts[context] = false
            @na_functions[:clean_destroy].call(context)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Cleaning context release warning: #{error.message}")
        end

        def self.Na__Native__CleanContextLive?(context)
            context && @na_functions && @na_live_contexts[context] ? true : false
        end

        # region: 19 numbers [m (9, row-major), t (3), lo (3), hi (3), frame per unit];
        # params: NA_CLEAN_PARAM_KEYS.length numbers. Returns the request id.
        def self.Na__Native__CleanRequest(context, region, params)
            raise 'The cleaning engine was reloaded; start the preview again.' unless self.Na__Native__CleanContextLive?(context)
            region_packed = region.map(&:to_f).pack('d*')
            params_packed = params.map(&:to_f).pack('d*')
            id = @na_functions[:clean_request].call(context, Fiddle::Pointer[region_packed], NA_CLEAN_REGION_COUNT,
                                                    Fiddle::Pointer[params_packed], NA_CLEAN_PARAM_KEYS.length)
            raise "The preview could not start (code #{id})." if id <= 0
            id
        end

        def self.Na__Native__CleanCancel(context)
            @na_functions[:clean_cancel].call(context) if self.Na__Native__CleanContextLive?(context)
        end

        # { 'state' => 'idle'|'running'|'done'|'failed'|'cancelled', 'finishedId', 'runningId', 'gridReady' }
        def self.Na__Native__CleanPoll(context)
            return { 'state' => 'idle', 'finishedId' => 0, 'runningId' => 0, 'gridReady' => false } unless self.Na__Native__CleanContextLive?(context)
            out = Fiddle::Pointer.malloc(8 * 4, self.na_ruby_free)
            @na_functions[:clean_poll].call(context, out, 4)
            state, finished, running, grid = out.to_s(32).unpack('d*')
            { 'state' => NA_PREVIEW_STATES.fetch(state.to_i, 'idle'), 'finishedId' => finished.to_i,
              'runningId' => running.to_i, 'gridReady' => grid.to_i == 1 }
        end

        # The finished preview's statistics, with 'surfaces' (0 to 2 Hashes).
        def self.Na__Native__CleanStats(context)
            return nil unless self.Na__Native__CleanContextLive?(context)
            out = Fiddle::Pointer.malloc(8 * NA_CLEAN_STAT_COUNT, self.na_ruby_free)
            return nil if @na_functions[:clean_stats].call(context, out, NA_CLEAN_STAT_COUNT) < 0
            values = out.to_s(8 * NA_CLEAN_STAT_COUNT).unpack('d*')
            stats = NA_CLEAN_STAT_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
            base = NA_CLEAN_STAT_KEYS.length
            count = [[stats['surfaceCount'].to_i, 0].max, 2].min
            stats['surfaces'] = (0...count).map do |k|
                offset = base + k * NA_CLEAN_SURFACE_KEYS.length
                NA_CLEAN_SURFACE_KEYS.each_with_index.to_h { |key, index| [key, values[offset + index]] }
            end
            stats
        end

        def self.Na__Native__CleanError(context)
            return '' unless self.Na__Native__CleanContextLive?(context)
            self.na_read_text(:clean_error, context)
        end

        # which: 0 = cleaned points, 1 = differences (colours: 22 numbers, see
        # Api.h). A new native cloud of the finished preview's box, or nil.
        def self.Na__Native__CleanPreviewCloud(context, which, colours)
            return nil unless self.Na__Native__CleanContextLive?(context)
            packed = colours.map(&:to_f).pack('d*')
            raw = @na_functions[:clean_cloud].call(context, which.to_i, Fiddle::Pointer[packed], colours.length)
            raw.null? ? nil : self.na_adopt_cloud(raw)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cleaning: export job (whole cloud -> a NEW LAS)
    # -------------------------------------------------------------------------

        # dest_path nil = clean only (a dry run). origin: the cloud's local
        # origin in source units. Returns a job pointer (freed by GC or
        # Na__Native__ExportDestroy, which also deletes any partial file).
        def self.Na__Native__ExportStart(context, source_path, dest_path, params, origin, provenance_json, software)
            raise 'The cleaning engine is not running for this cloud.' unless self.Na__Native__CleanContextLive?(context)
            source_c = self.na_cstr(source_path)
            dest_c   = dest_path ? self.na_cstr(dest_path) : nil
            prov_c   = self.na_cstr(provenance_json)
            soft_c   = self.na_cstr(software)
            params_packed = params.map(&:to_f).pack('d*')
            origin_packed = origin.map(&:to_f).pack('d*')
            raw = @na_functions[:export_start].call(context, Fiddle::Pointer[source_c],
                                                    dest_c ? Fiddle::Pointer[dest_c] : Fiddle::Pointer.new(0),
                                                    Fiddle::Pointer[params_packed], NA_CLEAN_PARAM_KEYS.length,
                                                    Fiddle::Pointer[origin_packed], Fiddle::Pointer[prov_c], Fiddle::Pointer[soft_c])
            raise 'The export could not start.' if raw.null?
            pointer = Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:export_destroy])
            @na_live_jobs[pointer] = true
            pointer
        end

        def self.Na__Native__ExportPoll(job)
            out = Fiddle::Pointer.malloc(8 * NA_EXPORT_POLL_COUNT, self.na_ruby_free)
            @na_functions[:export_poll].call(job, out, NA_EXPORT_POLL_COUNT)
            values = out.to_s(8 * NA_EXPORT_POLL_COUNT).unpack('d*')
            poll = NA_EXPORT_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
            poll.merge('contentKey' => self.na_key_or_nil(poll['keyHi'], poll['keyLo']))
        end

        def self.Na__Native__ExportError(job)
            self.na_read_text(:export_error, job)
        end

        # Plain-English notes about what the new file differs in (' | ' separated).
        def self.Na__Native__ExportNotes(job)
            self.na_read_text(:export_notes, job)
        end

        def self.Na__Native__ExportCancel(job)
            @na_functions[:export_cancel].call(job) if job && @na_functions && @na_live_jobs[job]
        end

        def self.Na__Native__ExportDestroy(job)
            return unless job && @na_functions && @na_live_jobs[job]
            job.free = nil
            @na_live_jobs[job] = false
            @na_functions[:export_destroy].call(job)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Crop and Cut (BoxFilter.hpp): count, and the export job
    # -------------------------------------------------------------------------

        # transform: the cloud's local -> model (12 numbers); block: the boxes
        # (NA_BOX_BLOCK_COUNT numbers). { 'points', 'outside', 'inside', 'kept' }:
        # exactly what an export with these boxes removes. A few ms per 10 M points.
        def self.Na__Native__BoxCount(cloud_pointer, transform, block)
            raise self.na_unavailable_error unless @na_functions
            raise 'The point cloud is not loaded in the native engine.' unless self.Na__Native__CloudLive?(cloud_pointer)
            packed = self.na_boxes_packed(transform, block)
            out = Fiddle::Pointer.malloc(8 * 4, self.na_ruby_free)
            code = @na_functions[:box_count].call(cloud_pointer, Fiddle::Pointer[packed], NA_BOXES_COUNT, out, 4)
            raise "The points could not be counted: #{self.na_last_error}" if code < 0
            points, outside, inside, kept = out.to_s(32).unpack('d*').map(&:to_i)
            { 'points' => points, 'outside' => outside, 'inside' => inside, 'kept' => kept }
        end

        # A NEW LAS of the cloud without the points the boxes remove (dest_path
        # nil = mark only, for tests). Polled, cancelled and destroyed like a
        # Clean & Export job (Na__Native__ExportPoll and the rest).
        def self.Na__Native__BoxExportStart(cloud_pointer, source_path, dest_path, transform, block, origin, provenance_json, software)
            raise self.na_unavailable_error unless @na_functions
            raise 'The point cloud is not loaded in the native engine.' unless self.Na__Native__CloudLive?(cloud_pointer)
            source_c = self.na_cstr(source_path)
            dest_c   = dest_path ? self.na_cstr(dest_path) : nil
            prov_c   = self.na_cstr(provenance_json)
            soft_c   = self.na_cstr(software)
            packed   = self.na_boxes_packed(transform, block)
            origin_packed = origin.map(&:to_f).pack('d*')
            raw = @na_functions[:box_export_start].call(cloud_pointer, Fiddle::Pointer[source_c],
                                                        dest_c ? Fiddle::Pointer[dest_c] : Fiddle::Pointer.new(0),
                                                        Fiddle::Pointer[packed], NA_BOXES_COUNT, Fiddle::Pointer[origin_packed],
                                                        Fiddle::Pointer[prov_c], Fiddle::Pointer[soft_c])
            raise 'The export could not start (the boxes were not valid, or there are none).' if raw.null?
            pointer = Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:export_destroy])
            @na_live_jobs[pointer] = true
            pointer
        end

        def self.na_boxes_packed(transform, block)
            raise 'The transform must have 12 numbers.' unless transform.length == 12
            raise "The boxes must have #{NA_BOX_BLOCK_COUNT} numbers." unless block.length == NA_BOX_BLOCK_COUNT
            (transform + block).map(&:to_f).pack('d*')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | LAZ to LAS (a NEW uncompressed LAS, checked and published)
    # -------------------------------------------------------------------------

        # Returns a job pointer (freed by GC or Na__Native__LazDestroy, which
        # also deletes any partial file).
        def self.Na__Native__LazStart(source_path, dest_path)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            source_c = self.na_cstr(source_path)
            dest_c   = self.na_cstr(dest_path)
            raw = @na_functions[:laz_start].call(Fiddle::Pointer[source_c], Fiddle::Pointer[dest_c])
            raise "The LAZ conversion could not start: #{self.na_last_error}" if raw.null?
            pointer = Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:laz_destroy])
            @na_live_laz_jobs[pointer] = true
            pointer
        end

        def self.Na__Native__LazPoll(job)
            out = Fiddle::Pointer.malloc(8 * NA_LAZ_POLL_COUNT, self.na_ruby_free)
            @na_functions[:laz_poll].call(job, out, NA_LAZ_POLL_COUNT)
            values = out.to_s(8 * NA_LAZ_POLL_COUNT).unpack('d*')
            NA_LAZ_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
        end

        def self.Na__Native__LazError(job)
            self.na_read_text(:laz_error, job)
        end

        # Plain-English notes about records left out (' | ' separated).
        def self.Na__Native__LazNotes(job)
            self.na_read_text(:laz_notes, job)
        end

        def self.Na__Native__LazCancel(job)
            @na_functions[:laz_cancel].call(job) if job && @na_functions && @na_live_laz_jobs[job]
        end

        def self.Na__Native__LazDestroy(job)
            return unless job && @na_functions && @na_live_laz_jobs[job]
            job.free = nil
            @na_live_laz_jobs[job] = false
            @na_functions[:laz_destroy].call(job)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Render
    # -------------------------------------------------------------------------

        # A cloud's render block as the engine takes it (NA_RENDER_PARAM_COUNT
        # numbers). A 48-number block, as the scene export builds, is padded with
        # zeros: no Crop and Cut boxes.
        def self.Na__Native__FullParams(params)
            return params if params.length == NA_RENDER_PARAM_COUNT
            unless params.length == NA_PARAM_COUNT
                raise "A render block has #{params.length} numbers; #{NA_PARAM_COUNT} or #{NA_RENDER_PARAM_COUNT} were expected."
            end
            params + [0.0] * (NA_RENDER_PARAM_COUNT - NA_PARAM_COUNT)
        end

        # params: NA_PARAM_COUNT or NA_RENDER_PARAM_COUNT numbers. Returns the stats Hash.
        def self.Na__Native__RenderPng(cloud_pointer, params, png_path)
            raise self.na_unavailable_error unless @na_functions
            packed = self.Na__Native__FullParams(params).map(&:to_f).pack('d*')
            path_c = self.na_cstr(png_path)
            code = @na_functions[:render].call(cloud_pointer, Fiddle::Pointer[packed], NA_RENDER_PARAM_COUNT,
                                               Fiddle::Pointer[path_c], @na_stats_buffer, NA_STAT_COUNT)
            raise "Native render failed: #{self.na_last_error}" if code < 0
            values = @na_stats_buffer.to_s(8 * NA_STAT_COUNT).unpack('d*')
            NA_STAT_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
        end

        # Several clouds in ONE image (ABI 7): one depth buffer, so the nearest
        # point wins whichever cloud it belongs to, and total_budget shared
        # between them. pointers: live native clouds; params_list: one Array of
        # NA_PARAM_COUNT or NA_RENDER_PARAM_COUNT numbers per cloud (the first
        # one's camera and image fields describe the frame). Returns the stats
        # Hash plus 'layers' ([{ 'demand', 'share', 'tested', 'onScreen' }] in
        # the same order).
        def self.Na__Native__RenderLayersPng(pointers, params_list, total_budget, png_path)
            raise self.na_unavailable_error unless @na_functions
            count = pointers.length
            raise 'There is no point cloud to draw.' if count.zero?
            raise "At most #{NA_MAX_LAYERS} point clouds can be drawn at once." if count > NA_MAX_LAYERS
            raise 'Each point cloud needs its own render parameters.' unless params_list.length == count
            handles = pointers.map { |pointer| pointer.to_i }.pack('Q*')
            packed  = params_list.map { |params| self.Na__Native__FullParams(params) }.flatten.map(&:to_f).pack('d*')
            path_c  = self.na_cstr(png_path)
            layer_buffer = Fiddle::Pointer.malloc(8 * NA_LAYER_STAT_KEYS.length * count, self.na_ruby_free)
            code = @na_functions[:render_layers].call(Fiddle::Pointer[handles], count, Fiddle::Pointer[packed], NA_RENDER_PARAM_COUNT,
                                                      total_budget.to_f, Fiddle::Pointer[path_c], @na_stats_buffer, NA_STAT_COUNT,
                                                      layer_buffer, NA_LAYER_STAT_KEYS.length * count)
            raise "Native render failed: #{self.na_last_error}" if code < 0
            values = @na_stats_buffer.to_s(8 * NA_STAT_COUNT).unpack('d*')
            stats = NA_STAT_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
            per = layer_buffer.to_s(8 * NA_LAYER_STAT_KEYS.length * count).unpack('d*')
            stats['layers'] = (0...count).map do |layer|
                NA_LAYER_STAT_KEYS.each_with_index.to_h { |key, index| [key, per[layer * NA_LAYER_STAT_KEYS.length + index].to_i] }
            end
            stats
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Status + Helpers
    # -------------------------------------------------------------------------

        def self.Na__Native__Status
            path   = self.Na__Native__BinaryPath
            exists = File.exist?(path)
            disk_mtime = exists ? File.mtime(path) : nil
            {
                'isBuilt'      => exists,
                'isLoaded'     => !@na_handle.nil?,
                'generation'   => @na_generation,
                'threads'      => @na_functions ? @na_functions[:threads].call : nil,
                'binaryTime'   => disk_mtime ? disk_mtime.strftime('%d-%b-%Y %H:%M:%S') : nil,
                'isStale'      => !!(@na_handle && disk_mtime && disk_mtime != @na_loaded_mtime),
                'error'        => @na_load_error
            }
        end

        def self.na_last_error
            @na_functions ? @na_functions[:error].call.to_s : 'engine not loaded'
        end

        def self.na_unavailable_error
            @na_load_error || 'The native engine is not available.'
        end

        def self.na_ruby_free
            defined?(Fiddle::RUBY_FREE) ? Fiddle::RUBY_FREE : nil
        end

        # A NUL-terminated UTF-8 copy that stays alive for the call.
        def self.na_cstr(text)
            text.to_s.encode('UTF-8') + "\0"
        end

        def self.na_key_or_nil(hi, lo)
            hi.to_i.zero? && lo.to_i.zero? ? nil : self.Na__Native__KeyHex(hi, lo)
        end

        def self.na_read_text(function, handle)
            return '' unless handle && @na_functions
            text = Fiddle::Pointer.malloc(NA_TEXT_CAPACITY, self.na_ruby_free)
            @na_functions[function].call(handle, text, NA_TEXT_CAPACITY)
            text.to_s.force_encoding('UTF-8').scrub('?')
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
