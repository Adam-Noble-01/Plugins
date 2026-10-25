# =============================================================================
# NA POINT CLOUD VIEWER - TRANSFORM - CONFIGURATION EXPORT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Transform__ConfigExport__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ConfigExport
# PURPOSE    : Writes everything that defines how the model's point clouds
#              appear to one readable JSON file, one section per cloud: the
#              source LAS, its unit choice and local origin, the placement
#              (position, rotation, lock, full matrix), its clip box and clip
#              scenes, how it is shown now, and the point cloud scenes with
#              what each one holds for every cloud. No point data.
#
# SCHEMA 2 (v0.10.0): 'clouds' is a list, one entry per cloud, each keyed by
#   its permanent cloudId (the id the scenes and TrueVision use). Schema 1 had
#   one cloud at the top level.
#
# The survey relationship is spelled out in the file, so a placement can be
# checked or rebuilt by hand:  model = R * (k * (source - localOrigin)) + t
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ConfigExport

        NA_SCHEMA         = 'Na__PointCloudViewer__ConfigExport'.freeze
        NA_SCHEMA_VERSION = 2

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # Returns the written path, or nil if the user cancelled.
        def self.Na__Export__Run(session, model)
            title  = model.title.to_s.empty? ? 'Untitled' : model.title.to_s
            folder = model.path.to_s.empty? ? Na__UserConfigStore.Na__UserConfig__Get('import', 'lastFolder', '') : File.dirname(model.path)
            folder = '' unless folder.is_a?(String) && File.directory?(folder)
            path = UI.savepanel('Export Point Cloud Configuration', folder, "#{title}__PointCloudConfig.json")
            return nil unless path
            path = "#{path}.json" unless File.extname(path).casecmp('.json').zero?
            Na__SafeFileWriter.Na__SafeFile__WriteJson(path, self.Na__Export__Build(session, model))
            path
        end

        def self.Na__Export__Build(session, model)
            display = Na__UnitContract.Na__Units__ModelDisplay(model)
            slots   = Na__CloudSet.Na__Slots__All(session)
            active  = Na__CloudSet.Na__Slots__Active(session)
            {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'exportedAt'    => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'plugin'        => { 'name' => 'Na Point Cloud Viewer', 'version' => Na__PointCloudViewer.Na__PublicApi__Version },
                'model'         => { 'title' => model.title.to_s, 'path' => model.path.to_s, 'displayUnit' => display['suffix'],
                                     'internalUnit' => 'inches', 'modelId' => Na__CloudStore.Na__Store__ModelId(session) },
                'activeCloudId' => active ? active.id : nil,
                'pointBudget'   => { 'points' => session.settings['pointBudget'].to_i,
                                     'sharing' => 'Shared by every cloud on show: equal shares, a cloud that holds fewer points (all of them, or all inside its clip box) passes the rest to the others.' },
                'clouds'        => slots.map { |slot| self.na_cloud_section(slot, active, display) },
                'scenes'        => self.na_scenes(session),
                'snap'          => self.na_snap(display)
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Sections
    # -------------------------------------------------------------------------

        def self.na_cloud_section(slot, active, display)
            {
                'cloudId'     => slot.id,
                'name'        => slot.name,
                'colour'      => Na__CloudSet.Na__Slots__HexColour(slot.colour),
                'isActive'    => slot.equal?(active),
                'recordState' => slot.record_state,
                'visible'     => slot.visible ? true : false,
                'display'     => slot.display,
                'link'        => slot.record ? slot.record['link'] : nil,
                'cloud'       => self.na_cloud(slot),
                'placement'   => self.na_placement(slot, display),
                'clip'        => self.na_clip(slot, display)
            }
        end

        def self.na_cloud(slot)
            cloud = slot.cloud
            return { 'isLoaded' => false } unless cloud
            info = cloud.las_info || {}
            {
                'isLoaded'            => true,
                'fileName'            => File.basename(cloud.source_path.to_s),
                'sourcePath'          => cloud.source_path.to_s,
                'pointCount'          => cloud.total_points,
                'sourceUnit'          => cloud.source_unit,
                'sourceUnitLabel'     => Na__UnitContract.Na__Units__SourceUnitLabel(cloud.source_unit),
                'inchesPerSourceUnit' => cloud.unit_factor,
                'localOriginSource'   => info['localOriginSource'],
                'localBoxSource'      => { 'min' => cloud.local_min, 'max' => cloud.local_max },
                'colourBits'          => info['colourBits'],
                'contentKey'          => info['contentKey'],
                'fingerprint'         => slot.placement ? slot.placement['key'] : nil
            }
        end

        # The loaded cloud's placement, else the one saved in its record.
        def self.na_placement(slot, display)
            placement = slot.placement || (slot.record ? Na__Placement.na_valid_part(slot.record['placement']) : nil)
            return nil unless placement
            r = placement['rotation']
            t = placement['translation']
            angles = Na__Placement.Na__Placement__EulerDegrees(r)
            {
                'source'                 => slot.placement ? 'loaded cloud' : 'saved record (the cloud is not loaded)',
                'locked'                 => placement['locked'] ? true : false,
                'isImportPosition'       => Na__Placement.na_identity?(placement),
                'positionInches'         => t,
                'position'               => { 'x' => t[0] / display['inchesPerUnit'], 'y' => t[1] / display['inchesPerUnit'],
                                              'z' => t[2] / display['inchesPerUnit'], 'unit' => display['suffix'] },
                'rotationDegrees'        => { 'aboutZ' => angles['z'], 'aboutY' => angles['y'], 'aboutX' => angles['x'],
                                              'order' => 'R = Rz * Ry * Rx' },
                'rotationMatrix'         => [r[0, 3], r[3, 3], r[6, 3]],
                'gimbal'                 => slot.cloud && slot.placement ? self.na_gimbal(slot, display) : { 'localSource' => placement['gimbal'] },
                'localToModelInches'     => slot.cloud ? { 'matrix' => slot.cloud.local_to_model[0, 9].each_slice(3).to_a,
                                                           'translation' => slot.cloud.local_to_model[9, 3] } : nil,
                'surveyRelationship'     => 'model_inches = R * (inchesPerSourceUnit * (source - localOriginSource)) + positionInches; ' \
                                            'no scale is ever applied beyond the unit factor'
            }
        end

        def self.na_gimbal(slot, display)
            model_point = Na__Placement.Na__Placement__GimbalModel(slot)
            {
                'isCustom'      => Na__Placement.Na__Placement__GimbalIsCustom?(slot),
                'localSource'   => Na__Placement.Na__Placement__GimbalLocal(slot),
                'modelInches'   => model_point,
                'model'         => { 'x' => model_point[0] / display['inchesPerUnit'], 'y' => model_point[1] / display['inchesPerUnit'],
                                     'z' => model_point[2] / display['inchesPerUnit'], 'unit' => display['suffix'] }
            }
        end

        def self.na_clip(slot, display)
            Na__ClipBox.Na__Clip__Ensure(slot)
            box = slot.clip
            to_display = ->(values) { values.map { |v| v / display['inchesPerUnit'] } }
            {
                'enabled'     => box ? box['enabled'] : false,
                'box'         => box ? { 'minInches' => box['min'], 'maxInches' => box['max'],
                                         'min' => to_display.call(box['min']), 'max' => to_display.call(box['max']),
                                         'unit' => display['suffix'] } : nil,
                'activeScene' => slot.clip_active_scene,
                'scenes'      => slot.clip_scenes.map do |scene|
                    { 'id' => scene['id'], 'name' => scene['name'], 'minInches' => scene['min'], 'maxInches' => scene['max'],
                      'min' => to_display.call(scene['min']), 'max' => to_display.call(scene['max']) }
                end
            }
        end

        # Each point cloud scene with what it holds for every cloud, by id.
        def self.na_scenes(session)
            Na__SceneStore.Na__Scenes__Ensure(session)
            session.scenes.map do |scene|
                {
                    'id'          => scene['id'],
                    'sketchUpScene' => scene['page'],
                    'viewType'    => scene['viewType'],
                    'export'      => scene['export'],
                    'pointBudget' => scene.dig('settings', 'pointBudget'),
                    'clouds'      => scene['clouds']
                }
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The point cloud scenes were left out of the configuration: #{error.message}")
            []
        end

        def self.na_snap(display)
            snap = Na__Placement.Na__Placement__SnapSettings
            {
                'moveEnabled'  => snap['moveEnabled'],
                'moveStep'     => snap['moveInches'] / display['inchesPerUnit'],
                'moveUnit'     => display['suffix'],
                'angleEnabled' => snap['angleEnabled'],
                'angleDegrees' => snap['angleDegrees']
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
