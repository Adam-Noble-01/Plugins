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
# ONE CACHE PER LAS CONTENT (cache version 2, v0.8.0): the file name is the
#   LAS file's CONTENT KEY (LasFile.cpp: its size, header, VLRs and sampled
#   blocks of the point records), which the cache also records inside. Two
#   different files never share a cache, even with the same point count and
#   survey position: a cleaned copy whose points only moved is a different
#   file and gets its own cache, never the original's.
#
# A CACHE IS USED ONLY WHEN (all of):
#   - its header passes the engine's checks (magic, version, CRC, length)
#   - it records the content key being asked for (the engine checks again
#     when it loads, so a renamed cache file cannot be passed off)
#   - it knows each point's LAS record (needed to export a cleaned copy)
#   - the LAS, when present, still has the size and modified time recorded
#     in the cache (a file edited in place rebuilds its cache)
#   A LAS that cannot be found at all still allows its cache (the model link
#   records the key), with a note saying so.
#
# MIGRATION: version 1 caches (named by point count + origin) are never used
#   when the LAS is present: the LAS is read again and a version 2 cache is
#   written. With the LAS missing, a version 1 cache can still show the cloud
#   (it cannot be cleaned and exported until the LAS is found).
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
        NA_FLAG_INDEX    = 1        # the cache knows each point's LAS record
        NA_FLAG_TIME     = 2        # ... and its GPS time

    # -------------------------------------------------------------------------
    # REGION | Paths
    # -------------------------------------------------------------------------

        def self.Na__Cache__Folder
            File.join(Na__AssetResolver.Na__Paths__CacheFolder, NA_FOLDER_NAME)
        end

        # Version 2: named by the LAS content key (16 hex digits).
        def self.Na__Cache__PathForKey(key_hex)
            raise ArgumentError, 'A point cache needs the LAS content key.' unless key_hex.to_s.match?(/\A[0-9a-f]{16}\z/)
            FileUtils.mkdir_p(self.Na__Cache__Folder)
            File.join(self.Na__Cache__Folder, "Na__PointCloudViewer__PointCache__k#{key_hex}.napc")
        end

        # Version 1 (before v0.8.0): named by the point count + survey origin.
        def self.Na__Cache__LegacyPathFor(fingerprint)
            File.join(self.Na__Cache__Folder, format('Na__PointCloudViewer__PointCache__%08x.napc', Zlib.crc32(fingerprint.to_s)))
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Checks
    # -------------------------------------------------------------------------

        # The cache header if a version 2 cache of exactly this content exists
        # and knows every point's LAS record; else nil.
        def self.Na__Cache__ForKey(key_hex, expect_count = nil)
            return nil unless key_hex.to_s.match?(/\A[0-9a-f]{16}\z/)
            path = self.Na__Cache__PathForKey(key_hex)
            info = Na__NativeEngine.Na__Native__CachePeek(path)
            return nil unless info
            return nil unless info['version'].to_i >= 2 && info['contentKey'] == key_hex
            return nil unless (info['flags'].to_i & NA_FLAG_INDEX) != 0
            return nil if expect_count && info['pointCount'].to_i != expect_count.to_i
            info.merge('path' => path)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cache check failed: #{error.message}")
            nil
        end

        # A version 1 cache of this scan (for showing a cloud whose LAS is
        # missing, from a link made before v0.8.0). Never used to export.
        def self.Na__Cache__LegacyForFingerprint(fingerprint)
            path = self.Na__Cache__LegacyPathFor(fingerprint)
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

        # Is this LAS file, as it is on disk now, the one the cache was made
        # from (same size and modified time)? A file edited in place, even
        # where the content key does not sample, fails this and is read again.
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

        # Deletes every cache and any half-written .tmp left by a crash. Never
        # touches a LAS file.
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
