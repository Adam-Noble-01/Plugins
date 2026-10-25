# =============================================================================
# NA POINT CLOUD VIEWER - LAS IMPORT - CONTROLLER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__LasImport__Controller__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__LasImport
# PURPOSE    : Step 1 - pick a .las, read its header natively, and show the
#              user a plain report plus the unit question. A .laz (or a
#              LAZ-compressed file named .las) is first decompressed into a
#              NEW LAS (LazConvert.rb), whose report is then shown.
#              Step 2 - start the threaded import with the unit they chose.
#
# WHICH CLOUD (v0.10.0): a LAS the model already holds (the same content)
#   loads into that cloud; any other LAS becomes a NEW cloud of the model, up
#   to clouds.maxClouds. Reload and Locate load into the cloud they belong to.
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
            path = UI.openpanel('Choose a LAS or LAZ point cloud', folder, 'LAS or LAZ point cloud (*.las;*.laz)|*.las;*.laz||')
            return Na__DialogManager.Na__Dialog__PushStatus('Import cancelled.', 'info') unless path

            path = path.tr('\\', '/')
            Na__UserConfigStore.Na__UserConfig__Set('import', 'lastFolder', File.dirname(path))
            extension = File.extname(path).downcase
            unless %w[.las .laz].include?(extension)
                return Na__DialogManager.Na__Dialog__PushStatus('Only .las and .laz files can be imported. E57, PLY and other formats are not supported.', 'error')
            end
            return self.Na__LazConvert__Start(path) if extension == '.laz'
            self.Na__LasImport__Inspect(path)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('LAS header read failed.', error)
            Na__DialogManager.Na__Dialog__PushStatus("The LAS file could not be read: #{error.message}", 'error')
        end

        # Reads the header and shows the report. conversion: the LAZ converter's
        # report (Na__LazConvert__Report) when this LAS was just made from a LAZ.
        def self.Na__LasImport__Inspect(path, conversion = nil)
            info, header_ms = Na__PerfStats.Na__Perf__Measure { Na__NativeEngine.Na__Native__LasReadHeader(path) }
            if info['isCompressed'].to_i == 1
                return self.Na__LazConvert__Start(path) unless conversion
                return Na__DialogManager.Na__Dialog__PushStatus('The converted file is still LAZ-compressed; it was not imported.', 'error')
            end
            if info['pointCount'].to_i <= 0
                return Na__DialogManager.Na__Dialog__PushStatus('This LAS file contains no points.', 'error')
            end
            Na__DialogManager.Na__Dialog__Send('lasHeader', self.na_header_payload(path, info, header_ms, conversion))
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('LAS header read failed.', error)
            Na__DialogManager.Na__Dialog__PushStatus("The LAS file could not be read: #{error.message}", 'error')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Step 2 - Start
    # -------------------------------------------------------------------------

        # payload: 'path', 'sourceUnit', 'headerMs', optional 'slotId' (load into
        # that cloud) and 'extraOptions'.
        def self.Na__LasImport__Start(payload)
            path = payload['path'].to_s
            unit = payload['sourceUnit'].to_s
            refuse = ->(message) { Na__DialogManager.Na__Dialog__SendJobFinished('failed', message, {}) }
            return refuse.('Choose the units this LAS file is in before importing.') unless Na__UnitContract.Na__Units__IsSupportedSourceUnit?(unit)
            return refuse.("The LAS file is no longer at #{path}.") unless File.exist?(path)
            session = Na__ModelRegistry.Na__Registry__ActiveSession
            return refuse.('The point cloud overlay is not available for this model.') unless session
            return refuse.('Another task is still running.') if Na__AsyncJobs.Na__Jobs__Busy?

            options = self.Na__LasImport__CacheOptions(path).merge(payload['extraOptions'].is_a?(Hash) ? payload['extraOptions'] : {})
            options['slotId'] = payload['slotId'].to_s if payload['slotId']
            problem = self.na_room_for(session, path, options)
            return refuse.(problem) if problem
            job = Na__LasImportJob.new(session, Sketchup.active_model.active_view, path, unit, payload['headerMs'], options)
            refuse.('Another task is still running.') unless Na__AsyncJobs.Na__Jobs__Start(job)
        end

        # The job that loads one cloud from a reload plan (Na__ModelLink):
        # its LAS (or this computer's cache of it), into that cloud's slot.
        # extra: more job options (for example 'noZoom').
        def self.Na__LasImport__JobForPlan(slot, plan, extra = {})
            view = Sketchup.active_model.active_view
            if plan['kind'] == 'cache'
                cached = plan['cached']
                options = { 'fromCache' => cached['path'], 'expectCount' => cached['pointCount'].to_i, 'lasMissing' => true,
                            'contentKey' => cached['contentKey'], 'slotId' => slot.id }.merge(extra)
                return Na__LasImportJob.new(slot.session, view, plan['lasPath'], plan['unit'], 0, options)
            end
            options = self.Na__LasImport__CacheOptions(plan['path']).merge('slotId' => slot.id).merge(extra)
            Na__LasImportJob.new(slot.session, view, plan['path'], plan['unit'], plan['headerMs'], options)
        end

        # nil, or why a NEW cloud cannot be added: the model already holds
        # clouds.maxClouds. A file the model already holds always loads.
        def self.na_room_for(session, path, options)
            return nil if options['slotId'] || options['onCloud']
            slots = Na__CloudSet.Na__Slots__All(session)
            max = Na__CloudStore.Na__Store__MaxClouds
            return nil if slots.length < max
            key = options['contentKey']
            header = Na__NativeEngine.Na__Native__LasReadHeader(path)
            fingerprint = Na__ModelLink.Na__Link__FingerprintFromHeader(header)
            return nil if Na__CloudSet.Na__Slots__ForFile(session, key, fingerprint)
            "This model holds #{max} point clouds, the most it can hold. Remove one (View tab) before importing another."
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The point cloud count could not be checked: #{error.message}")
            nil
        end

        # The cache of this exact LAS when there is one (same content key, and
        # the file unchanged since the cache was written), otherwise read the
        # LAS and write a cache, named by its content key, for next time.
        def self.Na__LasImport__CacheOptions(path)
            key = Na__NativeEngine.Na__Native__LasContentKey(path)
            header = Na__NativeEngine.Na__Native__LasReadHeader(path)
            cached = Na__PointCache.Na__Cache__ForKey(key, header['pointCount'].to_i)
            if cached && Na__PointCache.Na__Cache__MatchesLas?(cached, path)
                return { 'fromCache' => cached['path'], 'expectCount' => cached['pointCount'].to_i, 'contentKey' => key }
            end
            { 'cachePath' => Na__PointCache.Na__Cache__PathForKey(key), 'lasStamp' => Na__PointCache.Na__Cache__LasStamp(path), 'contentKey' => key }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Point cache skipped for this import: #{error.message}")
            {}
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Report Payload
    # -------------------------------------------------------------------------

        def self.na_header_payload(path, info, header_ms, conversion = nil)
            extent = %w[X Y Z].map { |axis| info["max#{axis}"].to_f - info["min#{axis}"].to_f }
            suggested = self.na_wkt_unit(info['wkt'])
            {
                'path'          => path,
                'fileName'      => File.basename(path),
                'headerMs'      => header_ms.round(1),
                'rows'          => (conversion ? conversion['rows'] : []) + self.na_report_rows(path, info, extent),
                'statusText'    => conversion ? conversion['statusText'] : nil,
                'statusLevel'   => conversion ? conversion['statusLevel'] : nil,
                'unitOptions'   => Na__UnitContract::NA_SOURCE_UNITS.map do |key, entry|
                    { 'key' => key, 'label' => entry['label'], 'sizeText' => self.na_size_text(extent, key) }
                end,
                'suggestedUnit' => suggested,
                'unitNote'      => suggested ?
                    "The file's coordinate system names its unit as #{Na__UnitContract.Na__Units__SourceUnitLabel(suggested)}. Check it below." :
                    'This file does not state its units. Choose the unit its coordinates are in. Each option shows the size it would give.',
                'target'        => self.na_target_payload(path, info)
            }
        end

        # What importing this LAS does to the model, said before Import is
        # pressed: 'first' (the model's first cloud), 'new' (one more cloud),
        # 'existing' (a cloud the model already holds: it loads into that
        # cloud) or 'full' (refused: the model holds clouds.maxClouds).
        def self.na_target_payload(path, info)
            session = Na__ModelRegistry.Na__Registry__ActiveSession
            return nil unless session
            slots = Na__CloudSet.Na__Slots__All(session)
            key = Na__NativeEngine.Na__Native__LasContentKey(path)
            slot = Na__CloudSet.Na__Slots__ForFile(session, key, Na__ModelLink.Na__Link__FingerprintFromHeader(info))
            max = Na__CloudStore.Na__Store__MaxClouds
            if slot
                { 'kind' => 'existing', 'cloudId' => slot.id, 'cloudName' => slot.name,
                  'text' => "This LAS is already a cloud of this model (#{slot.name}). Importing loads it into that cloud, with its saved position and clip box." }
            elsif slots.empty?
                { 'kind' => 'first', 'text' => nil }
            elsif slots.length >= max
                { 'kind' => 'full', 'text' => "This model holds #{max} point clouds, the most it can hold. Remove one (View tab) before importing another." }
            else
                { 'kind' => 'new', 'text' => "Importing adds it to this model as cloud #{slots.length + 1} of #{max}, with its own colour, position and clip box. The clouds already here are not changed." }
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("Which cloud this LAS becomes could not be worked out: #{error.message}")
            nil
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
