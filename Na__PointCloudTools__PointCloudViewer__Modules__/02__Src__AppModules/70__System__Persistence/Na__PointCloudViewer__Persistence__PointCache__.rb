# =============================================================================
# NA POINT CLOUD VIEWER - PERSISTENCE - POINT CACHE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Persistence__PointCache__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__PointCache
# PURPOSE    : Decides when a cloud can come from the engine's .napc cache
#              instead of the LAS (see 01__CppSource/...PointCache__.hpp for
#              the file format).
#
# ONE CACHE PER SCAN, never duplicated: the file name comes from the scan's
#   fingerprint (point count + survey origin), so importing the same LAS again
#   overwrites its cache rather than adding a second one.
#
# A CACHE IS USED ONLY WHEN (all of):
#   - its header passes the engine's checks (magic, version, CRC, length)
#   - its point count and origin give the fingerprint being asked for
#   - the LAS, when it is found, has the size and modified time recorded in
#     the cache (a changed LAS means the cache is out of date: rebuild)
#   A LAS that cannot be found at all still allows the cache (same scan by
#   fingerprint), with a note saying so. Anything else reads the LAS.
#
# Caches live in 90__AppCache__PointCloudCache/01__PointCaches/ on this computer
# and can be deleted at any time (Settings): they rebuild from the LAS.
#
# =============================================================================

require 'zlib'

module Na__PointCloudViewer
    module Na__PointCache

        NA_FOLDER_NAME   = '01__PointCaches'.freeze
        NA_MTIME_SLACK_S = 2.0      # FAT / network shares round modified times

    # -------------------------------------------------------------------------
    # REGION | Paths
    # -------------------------------------------------------------------------

        def self.Na__Cache__Folder
            File.join(Na__AssetResolver.Na__Paths__CacheFolder, NA_FOLDER_NAME)
        end

        def self.Na__Cache__PathFor(fingerprint)
            FileUtils.mkdir_p(self.Na__Cache__Folder)
            File.join(self.Na__Cache__Folder, format('Na__PointCloudViewer__PointCache__%08x.napc', Zlib.crc32(fingerprint.to_s)))
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Checks
    # -------------------------------------------------------------------------

        # The cache header if it holds this scan, else nil.
        def self.Na__Cache__ForFingerprint(fingerprint)
            path = self.Na__Cache__PathFor(fingerprint)
            info = Na__NativeEngine.Na__Native__CachePeek(path)
            return nil unless info
            header_fingerprint = Na__ModelLink.Na__Link__FingerprintFromHeader(
                'pointCount' => info['pointCount'], 'minX' => info['originX'] + info['minX'], 'maxX' => info['originX'] + info['maxX'],
                'minY' => info['originY'] + info['minY'], 'maxY' => info['originY'] + info['maxY'], 'minZ' => info['originZ'] + info['minZ'])
            header_fingerprint == fingerprint ? info.merge('path' => path) : nil
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cache check failed: #{error.message}")
            nil
        end

        # Is this LAS file the one the cache was made from (same size and time)?
        def self.Na__Cache__MatchesLas?(info, las_path)
            return false unless info && las_path && File.file?(las_path)
            File.size(las_path) == info['lasBytes'].to_i && (File.mtime(las_path).to_f - info['lasMtime'].to_f).abs <= NA_MTIME_SLACK_S
        end

        # Size and modified time to record in a new cache.
        def self.Na__Cache__LasStamp(las_path)
            [File.size(las_path), File.mtime(las_path).to_f]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Housekeeping (Settings tab)
    # -------------------------------------------------------------------------

        def self.Na__Cache__Stats
            files = Dir.glob(File.join(self.Na__Cache__Folder, '*.napc'))
            { 'count' => files.length, 'bytes' => files.sum { |file| File.size(file) rescue 0 } }
        end

        # Deletes every cache and any half-written .tmp left by a crash.
        def self.Na__Cache__Clear
            removed = 0
            Dir.glob(File.join(self.Na__Cache__Folder, '*.{napc,tmp}')).each do |file|
                File.delete(file)
                removed += 1
            rescue SystemCallError => error
                Na__DebugTools.Na__Debug__Warn("Could not delete #{File.basename(file)}: #{error.message}")
            end
            removed
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
