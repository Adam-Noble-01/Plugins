# =============================================================================
# NA POINT CLOUD VIEWER - TRANSFORM - CONFIGURATION EXPORT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Transform__ConfigExport__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ConfigExport
# PURPOSE    : Writes everything that defines how the cloud appears in this
#              model to one readable JSON file: the source LAS, its unit
#              choice and local origin, the placement (position, rotation,
#              lock, full matrix), the clip box, the clip scenes, the display
#              settings and the snap preferences. No point data.
#
# The survey relationship is spelled out in the file, so a placement can be
# checked or rebuilt by hand:  model = R * (k * (source - localOrigin)) + t
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ConfigExport

        NA_SCHEMA         = 'Na__PointCloudViewer__ConfigExport'.freeze
        NA_SCHEMA_VERSION = 1

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
            {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'exportedAt'    => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'plugin'        => { 'name' => 'Na Point Cloud Viewer', 'version' => Na__PointCloudViewer.Na__PublicApi__Version },
                'model'         => { 'title' => model.title.to_s, 'path' => model.path.to_s, 'displayUnit' => display['suffix'],
                                     'internalUnit' => 'inches' },
                'cloud'         => self.na_cloud(session),
                'placement'     => self.na_placement(session, display),
                'clip'          => self.na_clip(session, display),
                'display'       => session.settings,
                'snap'          => self.na_snap(display)
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Sections
    # -------------------------------------------------------------------------

        def self.na_cloud(session)
            cloud = session.cloud
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
                'fingerprint'         => session.placement ? session.placement['key'] : nil
            }
        end

        def self.na_placement(session, display)
            placement = session.placement
            return nil unless placement
            r = placement['rotation']
            t = placement['translation']
            angles = Na__Placement.Na__Placement__EulerDegrees(r)
            {
                'locked'                 => placement['locked'] ? true : false,
                'isImportPosition'       => Na__Placement.na_identity?(placement),
                'positionInches'         => t,
                'position'               => { 'x' => t[0] / display['inchesPerUnit'], 'y' => t[1] / display['inchesPerUnit'],
                                              'z' => t[2] / display['inchesPerUnit'], 'unit' => display['suffix'] },
                'rotationDegrees'        => { 'aboutZ' => angles['z'], 'aboutY' => angles['y'], 'aboutX' => angles['x'],
                                              'order' => 'R = Rz * Ry * Rx' },
                'rotationMatrix'         => [r[0, 3], r[3, 3], r[6, 3]],
                'gimbal'                 => self.na_gimbal(session, display),
                'localToModelInches'     => session.cloud ? { 'matrix' => session.cloud.local_to_model[0, 9].each_slice(3).to_a,
                                                              'translation' => session.cloud.local_to_model[9, 3] } : nil,
                'surveyRelationship'     => 'model_inches = R * (inchesPerSourceUnit * (source - localOriginSource)) + positionInches; ' \
                                            'no scale is ever applied beyond the unit factor'
            }
        end

        def self.na_gimbal(session, display)
            model_point = Na__Placement.Na__Placement__GimbalModel(session)
            {
                'isCustom'      => Na__Placement.Na__Placement__GimbalIsCustom?(session),
                'localSource'   => Na__Placement.Na__Placement__GimbalLocal(session),
                'modelInches'   => model_point,
                'model'         => { 'x' => model_point[0] / display['inchesPerUnit'], 'y' => model_point[1] / display['inchesPerUnit'],
                                     'z' => model_point[2] / display['inchesPerUnit'], 'unit' => display['suffix'] }
            }
        end

        def self.na_clip(session, display)
            Na__ClipBox.Na__Clip__Ensure(session)
            box = session.clip
            to_display = ->(values) { values.map { |v| v / display['inchesPerUnit'] } }
            {
                'enabled'     => box ? box['enabled'] : false,
                'box'         => box ? { 'minInches' => box['min'], 'maxInches' => box['max'],
                                         'min' => to_display.call(box['min']), 'max' => to_display.call(box['max']),
                                         'unit' => display['suffix'] } : nil,
                'activeScene' => session.clip_active_scene,
                'scenes'      => session.clip_scenes.map do |scene|
                    { 'id' => scene['id'], 'name' => scene['name'], 'minInches' => scene['min'], 'maxInches' => scene['max'],
                      'min' => to_display.call(scene['min']), 'max' => to_display.call(scene['max']) }
                end
            }
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
