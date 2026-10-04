# =============================================================================
# NA POINT CLOUD VIEWER - LAS IMPORT - CONTROLLER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__LasImport__Controller__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__LasImport
# PURPOSE    : Step 1 - pick a .las, read its header natively, and show the
#              user a plain report plus the unit question.
#              Step 2 - start the threaded import with the unit they chose.
#
# UNITS (the rule): LAS files do not reliably state their units, so the user
#   must choose. A unit is only pre-selected when the file's own coordinate
#   system (WKT) names it - and even then it is shown as "from the file".
#   Each option shows the real-world size it would produce, so a wrong
#   choice (a 59 m building becoming 59 mm) is obvious before importing.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__LasImport

    # -------------------------------------------------------------------------
    # REGION | Step 1 - Pick + Inspect
    # -------------------------------------------------------------------------

        def self.Na__LasImport__PickAndInspect
            folder = Na__UserConfigStore.Na__UserConfig__Get('import', 'lastFolder', '')
            folder = '' unless folder.is_a?(String) && File.directory?(folder)
            path = UI.openpanel('Choose a LAS point cloud', folder, 'LAS point cloud (*.las)|*.las||')
            return Na__DialogManager.Na__Dialog__PushStatus('Import cancelled.', 'info') unless path

            path = path.tr('\\', '/')
            Na__UserConfigStore.Na__UserConfig__Set('import', 'lastFolder', File.dirname(path))
            unless File.extname(path).casecmp('.las').zero?
                return Na__DialogManager.Na__Dialog__PushStatus('Only .las files can be imported in this version. LAZ, E57, PLY and other formats are not supported.', 'error')
            end

            info, header_ms = Na__PerfStats.Na__Perf__Measure { Na__NativeEngine.Na__Native__LasReadHeader(path) }
            if info['isCompressed'].to_i == 1
                return Na__DialogManager.Na__Dialog__PushStatus('This file is LAZ-compressed. Export it as uncompressed LAS; LAZ import is not part of this version.', 'error')
            end
            if info['pointCount'].to_i <= 0
                return Na__DialogManager.Na__Dialog__PushStatus('This LAS file contains no points.', 'error')
            end
            Na__DialogManager.Na__Dialog__Send('lasHeader', self.na_header_payload(path, info, header_ms))
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('LAS header read failed.', error)
            Na__DialogManager.Na__Dialog__PushStatus("The LAS file could not be read: #{error.message}", 'error')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Step 2 - Start
    # -------------------------------------------------------------------------

        def self.Na__LasImport__Start(payload)
            path = payload['path'].to_s
            unit = payload['sourceUnit'].to_s
            refuse = ->(message) { Na__DialogManager.Na__Dialog__SendJobFinished('failed', message, {}) }
            return refuse.('Choose the units this LAS file is in before importing.') unless Na__UnitContract.Na__Units__IsSupportedSourceUnit?(unit)
            return refuse.("The LAS file is no longer at #{path}.") unless File.exist?(path)
            session = Na__ModelRegistry.Na__Registry__ActiveSession
            return refuse.('The point cloud overlay is not available for this model.') unless session
            return refuse.('Another task is still running.') if Na__AsyncJobs.Na__Jobs__Busy?

            options = self.Na__LasImport__CacheOptions(path)
            job = Na__LasImportJob.new(session, Sketchup.active_model.active_view, path, unit, payload['headerMs'], options)
            refuse.('Another task is still running.') unless Na__AsyncJobs.Na__Jobs__Start(job)
        end

        # The cache of this exact LAS when there is one (same scan, same size and
        # time), otherwise read the LAS and write a cache for next time.
        def self.Na__LasImport__CacheOptions(path)
            header = Na__NativeEngine.Na__Native__LasReadHeader(path)
            fingerprint = Na__ModelLink.Na__Link__FingerprintFromHeader(header)
            cached = Na__PointCache.Na__Cache__ForFingerprint(fingerprint)
            if cached && Na__PointCache.Na__Cache__MatchesLas?(cached, path)
                return { 'fromCache' => cached['path'], 'expectCount' => cached['pointCount'].to_i }
            end
            { 'cachePath' => Na__PointCache.Na__Cache__PathFor(fingerprint), 'lasStamp' => Na__PointCache.Na__Cache__LasStamp(path) }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cache skipped for this import: #{error.message}")
            {}
        end

        # A cache load with no LAS on disk (the model link found only the cache).
        def self.Na__LasImport__StartFromCache(session, las_path, unit, cached)
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            options = { 'fromCache' => cached['path'], 'expectCount' => cached['pointCount'].to_i, 'lasMissing' => true }
            job = Na__LasImportJob.new(session, Sketchup.active_model.active_view, las_path, unit, 0, options)
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Report Payload
    # -------------------------------------------------------------------------

        def self.na_header_payload(path, info, header_ms)
            extent = %w[X Y Z].map { |axis| info["max#{axis}"].to_f - info["min#{axis}"].to_f }
            suggested = self.na_wkt_unit(info['wkt'])
            {
                'path'          => path,
                'fileName'      => File.basename(path),
                'headerMs'      => header_ms.round(1),
                'rows'          => self.na_report_rows(path, info, extent),
                'unitOptions'   => Na__UnitContract::NA_SOURCE_UNITS.map do |key, entry|
                    { 'key' => key, 'label' => entry['label'], 'sizeText' => self.na_size_text(extent, key) }
                end,
                'suggestedUnit' => suggested,
                'unitNote'      => suggested ?
                    "The file's coordinate system names its unit as #{Na__UnitContract.Na__Units__SourceUnitLabel(suggested)}. Check it below." :
                    'This file does not state its units. Choose the unit its coordinates are in. Each option shows the size it would give.'
            }
        end

        def self.na_report_rows(path, info, extent)
            crs = if info['hasWkt'].to_i == 1 then 'WKT coordinate system present'
                  elsif info['hasGeoKeys'].to_i == 1 then 'GeoTIFF keys present'
                  else 'None stated (local coordinates)'
                  end
            colour = info['hasRgb'].to_i == 1 ? 'RGB colour' : 'no colour (shown in neutral grey)'
            [
                ['File size', format('%.1f MB', File.size(path) / 1_000_000.0)],
                ['LAS version', "#{info['versionMajor'].to_i}.#{info['versionMinor'].to_i}"],
                ['Point format', "#{info['pointFormat'].to_i} (#{colour})"],
                ['Points', Na__PerfStats.Na__Perf__Thousands(info['pointCount'])],
                ['Extent (file units)', extent.map { |v| format('%.3f', v) }.join(' x ')],
                ['Scale (x, y, z)', %w[X Y Z].map { |a| format('%.3g', info["scale#{a}"]) }.join(', ')],
                ['Offset (x, y, z)', %w[X Y Z].map { |a| format('%.3f', info["offset#{a}"]) }.join(', ')],
                ['Coordinate system', crs],
                ['Written by', [info['software'], info['systemId']].reject(&:empty?).join(' on ')]
            ]
        end

        # Real-world size per unit choice, read in metres / cm / mm.
        def self.na_size_text(extent, unit_key)
            factor = Na__UnitContract.Na__Units__InchesPerSourceUnit(unit_key) * 0.0254
            extent.map do |value|
                metres = value * factor
                if metres >= 1.0 then format('%.1f m', metres)
                elsif metres >= 0.01 then format('%.1f cm', metres * 100.0)
                else format('%.1f mm', metres * 1000.0)
                end
            end.join(' x ')
        end

        # Only a linear UNIT named in the WKT counts as evidence.
        def self.na_wkt_unit(wkt)
            names = wkt.to_s.scan(/UNIT\["([^"]+)"/i).flatten
            return nil if names.empty?
            name = names.last.downcase
            return 'm'  if %w[metre meter metres meters m].include?(name)
            return 'ft' if %w[foot feet ft international_foot].include?(name)
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
