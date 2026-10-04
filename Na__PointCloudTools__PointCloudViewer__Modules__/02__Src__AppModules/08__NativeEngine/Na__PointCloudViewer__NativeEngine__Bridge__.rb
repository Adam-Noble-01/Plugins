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
# LIFETIME OF NATIVE CLOUDS:
#   Each native cloud is a Fiddle::Pointer whose free function is
#   napc_cloud_destroy, so a closed model's cloud is freed by Ruby's GC. Before
#   a hot swap every live cloud is destroyed and its free function cleared;
#   sessions see the generation change and upload again.
#
# =============================================================================

require 'fiddle'

module Na__PointCloudViewer
    module Na__NativeEngine

    # -------------------------------------------------------------------------
    # REGION | Constants (must match the C header)
    # -------------------------------------------------------------------------

        NA_DLL_NAME         = 'Na__PointCloudViewer__NativeEngine.dll'.freeze
        NA_EXPECTED_ABI     = 4
        NA_PARAM_COUNT      = 48
        NA_STAT_COUNT       = 10
        NA_STAT_KEYS        = %w[pointsTested pointsOnScreen threads clearMs rasterMs resolveMs encodeMs writeMs nativeTotalMs pngBytes].freeze
        NA_LAS_INFO_COUNT   = 22
        NA_JOB_POLL_COUNT   = 22
        NA_CACHE_INFO_COUNT = 14
        NA_TEXT_CAPACITY    = 8192

        @na_handle     = nil  unless defined?(@na_handle)
        @na_functions  = nil  unless defined?(@na_functions)
        @na_generation = 0    unless defined?(@na_generation)
        @na_loaded_mtime = nil unless defined?(@na_loaded_mtime)
        @na_load_error = nil  unless defined?(@na_load_error)
        @na_live       = ObjectSpace::WeakMap.new unless defined?(@na_live)
        @na_stats_buffer = nil unless defined?(@na_stats_buffer)

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

        # True when the engine is loaded and current. Loads on first call and
        # hot-swaps when the binary on disk is newer than the loaded copy.
        def self.Na__Native__EnsureLoaded
            path = self.Na__Native__BinaryPath
            unless File.exist?(path)
                @na_load_error = 'The native engine has not been built yet (02__Src__NativeEngine/03__BuildScripts).'
                return false
            end
            mtime = File.mtime(path)
            return true if @na_handle && @na_loaded_mtime == mtime
            self.na_load(path, mtime)
        end

        def self.Na__Native__Available?
            self.Na__Native__EnsureLoaded
        rescue StandardError
            false
        end

        def self.na_load(path, mtime)
            self.na_unload if @na_handle
            shadow = self.na_shadow_copy(path, mtime)
            handle = Fiddle::Handle.new(shadow)
            functions = self.na_bind(handle)
            abi = functions[:abi].call
            if abi != NA_EXPECTED_ABI
                handle.close
                @na_load_error = "The native engine binary speaks ABI #{abi}; this plugin expects #{NA_EXPECTED_ABI}. Rebuild it."
                return false
            end
            @na_handle       = handle
            @na_functions    = functions
            @na_loaded_mtime = mtime
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
            voidp = Fiddle::TYPE_VOIDP
            int   = Fiddle::TYPE_INT
            {
                abi:      Fiddle::Function.new(handle['napc_abi_version'], [], int),
                threads:  Fiddle::Function.new(handle['napc_thread_count'], [], int),
                error:    Fiddle::Function.new(handle['napc_last_error'], [], voidp),
                create:   Fiddle::Function.new(handle['napc_cloud_create'], [voidp, voidp, Fiddle::TYPE_LONG_LONG], voidp),
                destroy:  Fiddle::Function.new(handle['napc_cloud_destroy'], [voidp], Fiddle::TYPE_VOID),
                render:   Fiddle::Function.new(handle['napc_render_png'], [voidp, voidp, int, voidp, voidp, int], int),
                shutdown: Fiddle::Function.new(handle['napc_shutdown'], [], Fiddle::TYPE_VOID),
                las_header:   Fiddle::Function.new(handle['napc_las_read_header'], [voidp, voidp, int, voidp, int], int),
                las_import:   Fiddle::Function.new(handle['napc_las_import_start'], [voidp, voidp, voidp, int], voidp),
                cache_load:   Fiddle::Function.new(handle['napc_cache_load_start'], [voidp, voidp, int], voidp),
                cache_peek:   Fiddle::Function.new(handle['napc_cache_peek'], [voidp, voidp, int], int),
                job_poll:     Fiddle::Function.new(handle['napc_job_poll'], [voidp, voidp, int], int),
                job_error:    Fiddle::Function.new(handle['napc_job_error'], [voidp, voidp, int], int),
                job_cancel:   Fiddle::Function.new(handle['napc_job_cancel'], [voidp], Fiddle::TYPE_VOID),
                job_take:     Fiddle::Function.new(handle['napc_job_take_cloud'], [voidp], voidp),
                job_destroy:  Fiddle::Function.new(handle['napc_job_destroy'], [voidp], Fiddle::TYPE_VOID)
            }
        end

        # Every live native cloud dies with the old DLL; their owners notice the
        # generation change and upload again on the next draw.
        def self.na_unload
            @na_live.each do |pointer, alive|
                next unless alive
                begin
                    pointer.free = nil
                    @na_functions[:destroy].call(pointer)
                rescue StandardError
                    nil
                end
            end
            @na_live = ObjectSpace::WeakMap.new
            @na_functions[:shutdown].call if @na_functions
            @na_handle.close if @na_handle
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('Native engine unload failed.', error)
        ensure
            @na_handle = nil
            @na_functions = nil
            @na_loaded_mtime = nil
        end

        # Windows locks a loaded DLL; loading a copy keeps the build output free.
        def self.na_shadow_copy(path, mtime)
            folder = File.join(Na__AssetResolver.Na__Paths__CacheFolder, '00__NativeShadowCopies')
            FileUtils.mkdir_p(folder)
            Dir.glob(File.join(folder, '*.dll')).each { |old| File.delete(old) rescue nil }   # loaded ones stay locked
            shadow = File.join(folder, "Na__PointCloudViewer__NativeEngine__#{mtime.strftime('%Y%m%d-%H%M%S')}__#{Process.pid}.dll")
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

        # Frees a cloud now instead of waiting for GC (a LAS cloud is ~16 bytes
        # per point of native memory). Safe to call twice.
        def self.Na__Native__CloudRelease(pointer)
            return unless pointer && @na_functions && @na_live[pointer]
            pointer.free = nil
            @na_live[pointer] = false   # WeakMap#delete only exists from Ruby 3.3
            @na_functions[:destroy].call(pointer)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Native cloud release warning: #{error.message}")
        end

        def self.na_adopt_cloud(raw)
            pointer = Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:destroy])
            @na_live[pointer] = true
            pointer
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | LAS (header + threaded import job)
    # -------------------------------------------------------------------------

        NA_LAS_INFO_KEYS = %w[versionMajor versionMinor pointFormat recordLength pointCount
                              scaleX scaleY scaleZ offsetX offsetY offsetZ minX minY minZ maxX maxY maxZ
                              hasRgb vlrCount hasWkt hasGeoKeys isCompressed].freeze
        NA_JOB_KEYS = %w[phase done total finished failed cancelled readMs colourMs shuffleMs totalMs colourBits
                         originX originY originZ minX minY minZ maxX maxY maxZ pointCount cacheState].freeze
        NA_CACHE_INFO_KEYS = %w[pointCount originX originY originZ minX minY minZ maxX maxY maxZ colourBits
                                lasBytes lasMtime version].freeze

        def self.Na__Native__LasReadHeader(path)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            info = Fiddle::Pointer.malloc(8 * NA_LAS_INFO_COUNT, self.na_ruby_free)
            text = Fiddle::Pointer.malloc(NA_TEXT_CAPACITY, self.na_ruby_free)
            code = @na_functions[:las_header].call(Fiddle::Pointer[path.encode('UTF-8')], info, NA_LAS_INFO_COUNT, text, NA_TEXT_CAPACITY)
            raise self.na_last_error if code < 0
            values = info.to_s(8 * NA_LAS_INFO_COUNT).unpack('d*')
            system_id, software, wkt = text.to_s.force_encoding('UTF-8').scrub('?').split("\t", 3)
            NA_LAS_INFO_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
                            .merge('systemId' => system_id.to_s, 'software' => software.to_s, 'wkt' => wkt.to_s)
        end

        # cache_path: also write the point cache there once the cloud is ready
        # (nil = no cache). las_bytes / las_mtime are stored in its header.
        def self.Na__Native__LasImportStart(path, fallback_rgb, cache_path = nil, las_bytes = 0, las_mtime = 0)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            params = (fallback_rgb.map(&:to_f) + [las_bytes.to_f, las_mtime.to_f]).pack('d*')
            cache  = cache_path ? Fiddle::Pointer[cache_path.encode('UTF-8')] : Fiddle::Pointer.new(0)
            raw = @na_functions[:las_import].call(Fiddle::Pointer[path.encode('UTF-8')], cache, Fiddle::Pointer[params], 5)
            raise "The LAS import could not start: #{self.na_last_error}" if raw.null?
            Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:job_destroy])
        end

        # Loads a point cache on the engine's worker thread (same job API as an import).
        def self.Na__Native__CacheLoadStart(cache_path, expect_count)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            params = [expect_count.to_f].pack('d*')
            raw = @na_functions[:cache_load].call(Fiddle::Pointer[cache_path.encode('UTF-8')], Fiddle::Pointer[params], 1)
            raise "The point cache could not be opened: #{self.na_last_error}" if raw.null?
            Fiddle::Pointer.new(raw.to_i, 0, @na_functions[:job_destroy])
        end

        # The validated cache header as a Hash, or nil (missing or not usable).
        def self.Na__Native__CachePeek(cache_path)
            return nil unless File.file?(cache_path)
            raise self.na_unavailable_error unless self.Na__Native__EnsureLoaded
            out = Fiddle::Pointer.malloc(8 * NA_CACHE_INFO_COUNT, self.na_ruby_free)
            code = @na_functions[:cache_peek].call(Fiddle::Pointer[cache_path.encode('UTF-8')], out, NA_CACHE_INFO_COUNT)
            return nil if code < 0
            values = out.to_s(8 * NA_CACHE_INFO_COUNT).unpack('d*')
            NA_CACHE_INFO_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
        end

        def self.Na__Native__JobPoll(job)
            buffer = Fiddle::Pointer.malloc(8 * NA_JOB_POLL_COUNT, self.na_ruby_free)
            @na_functions[:job_poll].call(job, buffer, NA_JOB_POLL_COUNT)
            values = buffer.to_s(8 * NA_JOB_POLL_COUNT).unpack('d*')
            NA_JOB_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
        end

        def self.Na__Native__JobError(job)
            text = Fiddle::Pointer.malloc(NA_TEXT_CAPACITY, self.na_ruby_free)
            @na_functions[:job_error].call(job, text, NA_TEXT_CAPACITY)
            text.to_s.force_encoding('UTF-8').scrub('?')
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

        def self.na_ruby_free
            defined?(Fiddle::RUBY_FREE) ? Fiddle::RUBY_FREE : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Render
    # -------------------------------------------------------------------------

        # params: Array of NA_PARAM_COUNT numbers. Returns the stats Hash.
        def self.Na__Native__RenderPng(cloud_pointer, params, png_path)
            raise self.na_unavailable_error unless @na_functions
            packed = params.pack('d*')
            code = @na_functions[:render].call(cloud_pointer, Fiddle::Pointer[packed], NA_PARAM_COUNT,
                                               Fiddle::Pointer[png_path.encode('UTF-8')], @na_stats_buffer, NA_STAT_COUNT)
            raise "Native render failed: #{self.na_last_error}" if code < 0
            values = @na_stats_buffer.to_s(8 * NA_STAT_COUNT).unpack('d*')
            NA_STAT_KEYS.each_with_index.to_h { |key, index| [key, values[index]] }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Status
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

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
