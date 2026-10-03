# =============================================================================
# NA POINT CLOUD VIEWER - TRANSFORM - PLACEMENT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Transform__Placement__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__Placement
# PURPOSE    : Where the cloud sits in the model: a rigid rotation R and a
#              translation t (model inches), plus the lock. Every change the
#              Transform tab or the Move / Rotate tools can make goes through
#              here.
#
# THE MATHS (never a scale):
#   model = R * (k * local) + t
#   k is the exact unit factor chosen at import. R is kept orthonormal (re-
#   orthonormalised after every change), so no transform here can ever resize
#   the survey. t is where the cloud's local origin (the base centre of its
#   box in the LAS) lands in the model.
#
# THE GIMBAL POINT: a point ON the cloud (local coordinates, source units), so
#   it moves and turns with the cloud, like a component's axes. By default the
#   centre of the cloud's box; Set Gimbal Point picks any model point. The
#   Move gimbal sits there, the typed X / Y / Z are its model position, and
#   typed rotations turn the cloud about it.
#
# WHERE IT LIVES: JSON in the model's attribute dictionary
#   'Na__PointCloudViewer__Placement', tagged with the cloud's fingerprint
#   (file name, point count, local origin). Re-importing the same LAS restores
#   its position and lock; a different cloud starts at its import position.
#   Each committed change is one named, undoable operation.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__Placement

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DICT           = 'Na__PointCloudViewer__Placement'.freeze
        NA_KEY            = 'json'.freeze
        NA_SCHEMA         = 'Na__PointCloudViewer__Placement'.freeze
        NA_SCHEMA_VERSION = 1
        NA_IDENTITY       = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0].freeze
        NA_LOCKED_TEXT    = 'The position is locked. Unlock it on the Transform tab first.'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Attach to a Cloud (import) + Reload (undo / redo)
    # -------------------------------------------------------------------------

        # File name + point count + local origin: the same LAS gives the same key
        # on any computer, whatever folder it sits in.
        def self.Na__Placement__CloudKey(cloud)
            origin = (cloud.las_info || {})['localOriginSource'] || [0.0, 0.0, 0.0]
            "#{File.basename(cloud.source_path.to_s)}|#{cloud.total_points.to_i}|#{origin.map { |v| format('%.3f', v.to_f) }.join(',')}"
        end

        # Same scan: point count + survey origin match (the file name may differ:
        # a renamed or moved copy is still the same cloud).
        def self.Na__Placement__SameCloud?(key_a, key_b)
            key_a.to_s.split('|').last(2) == key_b.to_s.split('|').last(2)
        end

        # Called once per import, before the cloud is installed. Returns true
        # when a saved position for this same cloud was restored.
        def self.Na__Placement__AttachCloud(session, cloud)
            key    = self.Na__Placement__CloudKey(cloud)
            stored = self.na_read(session.model)
            session.placement_note = nil
            restored = stored && self.Na__Placement__SameCloud?(stored['key'], key)
            if restored
                session.placement = stored.merge('key' => key)
            else
                session.placement = self.na_default(key)
                if stored
                    session.placement_note = "This model holds a saved position for #{stored['file']}. " \
                                             'This cloud starts at its import position; unlocking it replaces that record.'
                end
            end
            self.na_apply(session, cloud)
            restored ? true : false
        end

        # Undo / Redo: the stored record may have changed under us.
        def self.Na__Placement__Reload(session)
            return unless session.cloud && session.placement
            stored = self.na_read(session.model)
            key = session.placement['key']
            session.placement = stored && self.Na__Placement__SameCloud?(stored['key'], key) ? stored.merge('key' => key) : self.na_default(key)
            self.na_apply(session, session.cloud)
            self.Na__Placement__StopTool(session) if session.placement['locked']
        end

        # A cloud imported before placements existed (or before a plugin reload)
        # gets one now. Its unit factor and local box are read back from the
        # plain unit-factor matrix it was installed with.
        def self.Na__Placement__Ensure(session)
            cloud = session.cloud
            return if !cloud || session.placement
            k = cloud.unit_factor || (cloud.local_to_model ? cloud.local_to_model[0].to_f : nil)
            return unless k && k > 0.0
            cloud.unit_factor ||= k
            if cloud.bounds && !(cloud.local_min && cloud.local_max)
                cloud.local_min = cloud.bounds.min.to_a.map { |v| v / k }
                cloud.local_max = cloud.bounds.max.to_a.map { |v| v / k }
            end
            self.Na__Placement__AttachCloud(session, cloud)
        end

        def self.Na__Placement__Detach(session)
            self.Na__Placement__StopTool(session)
            session.placement = nil
            session.placement_note = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Live Changes (tools, mid-drag) + Save
    # -------------------------------------------------------------------------

        def self.Na__Placement__Locked?(session)
            !session.placement || session.placement['locked'] ? true : false
        end

        # Unsaved: what a tool shows while it is being dragged.
        def self.Na__Placement__SetLive(session, rotation, translation)
            session.placement['rotation']    = rotation
            session.placement['translation'] = translation
            self.na_apply(session, session.cloud)
            Na__RenderController.Na__Render__RefreshExtents(session)
        end

        # One undoable operation per committed change.
        def self.Na__Placement__Save(session, operation_name)
            model = session.model
            return unless model && session.placement
            placement = session.placement
            placement['rotation'] = self.na_orthonormal(placement['rotation'])
            now = Time.now
            data = {
                'schema'        => NA_SCHEMA,
                'schemaVersion' => NA_SCHEMA_VERSION,
                'updatedAt'     => now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'updatedEpoch'  => now.to_f,
                'key'           => placement['key'],
                'file'          => placement['key'].split('|').first,
                'rotation'      => placement['rotation'],
                'translation'   => placement['translation'],
                'gimbal'        => placement['gimbal'],
                'locked'        => placement['locked'] ? true : false
            }
            begin
                model.start_operation(operation_name, true)
                model.set_attribute(NA_DICT, NA_KEY, JSON.generate(data))
                model.commit_operation
            rescue StandardError
                model.abort_operation
                raise
            end
            session.placement_note = nil
            Na__LocalBackup.Na__Backup__AfterSave(model, session)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Changes (each returns nil or a plain-English reason)
    # -------------------------------------------------------------------------

        def self.Na__Placement__SetLocked(session, locked)
            self.Na__Placement__Ensure(session)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return nil if session.placement['locked'] == locked
            self.Na__Placement__StopTool(session) if locked
            session.placement['locked'] = locked
            self.Na__Placement__Save(session, locked ? 'Point Cloud: Lock Position' : 'Point Cloud: Unlock Position')
            nil
        end

        # values: { 'x' => '1200', 'y' => '3.5m', 'z' => '0', 'rotZ' => '12.5', 'rotX' => '0', 'rotY' => '0' }
        def self.Na__Placement__SetValues(session, values, display)
            self.Na__Placement__Ensure(session)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return NA_LOCKED_TEXT if session.placement['locked']
            target = self.Na__Placement__GimbalModel(session)
            { 'x' => 0, 'y' => 1, 'z' => 2 }.each do |key, axis|
                next unless values.key?(key)
                target[axis] = Na__UnitContract.Na__Units__ParseDisplayLength(values[key], display)
            end
            rotation = session.placement['rotation']
            if (values.keys & %w[rotZ rotY rotX]).any?
                angles = self.Na__Placement__EulerDegrees(rotation)
                angles['z'] = self.Na__Placement__ParseAngle(values['rotZ']) if values.key?('rotZ')
                angles['y'] = self.Na__Placement__ParseAngle(values['rotY']) if values.key?('rotY')
                angles['x'] = self.Na__Placement__ParseAngle(values['rotX']) if values.key?('rotX')
                rotation = self.Na__Placement__FromEulerDegrees(angles)
            end
            # The gimbal point lands on `target` under the (new) rotation.
            turned = self.na_mul_vec(rotation, self.Na__Placement__GimbalLocal(session))
            k = session.cloud.unit_factor.to_f
            translation = (0..2).map { |i| target[i] - turned[i] * k }
            self.Na__Placement__SetLive(session, rotation, translation)
            self.Na__Placement__Save(session, 'Point Cloud: Position Values')
            nil
        rescue ArgumentError => error
            error.message
        end

        def self.Na__Placement__Reset(session)
            self.Na__Placement__Ensure(session)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return NA_LOCKED_TEXT if session.placement['locked']
            self.Na__Placement__SetLive(session, NA_IDENTITY.dup, [0.0, 0.0, 0.0])
            self.Na__Placement__Save(session, 'Point Cloud: Reset Position')
            nil
        end

        def self.Na__Placement__ParseAngle(text)
            clean = text.to_s.strip.sub(/\s*(°|deg|degrees)\z/i, '')
            raise ArgumentError, 'Enter an angle in degrees.' if clean.empty?
            Float(clean)
        rescue ArgumentError
            raise ArgumentError, "\"#{text.to_s.strip}\" is not an angle in degrees."
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Gimbal Point
    # -------------------------------------------------------------------------

        def self.Na__Placement__GimbalLocal(session)
            custom = session.placement && session.placement['gimbal']
            return custom if custom
            cloud = session.cloud
            return [0.0, 0.0, 0.0] unless cloud && cloud.local_min && cloud.local_max
            (0..2).map { |i| (cloud.local_min[i] + cloud.local_max[i]) / 2.0 }
        end

        # Model inches, for the current placement (or a given one).
        def self.Na__Placement__GimbalModel(session, rotation = nil, translation = nil)
            rotation    ||= session.placement['rotation']
            translation ||= session.placement['translation']
            k = session.cloud.unit_factor.to_f
            turned = self.na_mul_vec(rotation, self.Na__Placement__GimbalLocal(session))
            (0..2).map { |i| turned[i] * k + translation[i] }
        end

        def self.Na__Placement__GimbalIsCustom?(session)
            session.placement && session.placement['gimbal'] ? true : false
        end

        # model_point: [x, y, z] model inches, for example a picked vertex.
        def self.Na__Placement__SetGimbalPoint(session, model_point)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return NA_LOCKED_TEXT if session.placement['locked']
            r = session.placement['rotation']
            t = session.placement['translation']
            k = session.cloud.unit_factor.to_f
            d = (0..2).map { |i| model_point[i].to_f - t[i] }
            session.placement['gimbal'] = (0..2).map { |c| (r[c] * d[0] + r[3 + c] * d[1] + r[6 + c] * d[2]) / k }   # R^T d / k
            self.Na__Placement__Save(session, 'Point Cloud: Set Gimbal Point')
            nil
        end

        def self.Na__Placement__CentreGimbal(session)
            self.Na__Placement__Ensure(session)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return NA_LOCKED_TEXT if session.placement['locked']
            return nil unless session.placement['gimbal']
            session.placement['gimbal'] = nil
            self.Na__Placement__Save(session, 'Point Cloud: Centre Gimbal')
            nil
        end

        # Set Gimbal Point button: the Move tool, waiting for a pick.
        def self.Na__Placement__PickGimbal(session)
            self.Na__Placement__Ensure(session)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return NA_LOCKED_TEXT if session.placement['locked']
            tool = session.transform_tool
            unless tool && tool.na_kind == 'move'
                problem = self.Na__Placement__StartTool(session, 'move')
                return problem if problem
                tool = session.transform_tool
            end
            tool.na_start_gimbal_pick if tool
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tools (Move gimbal, Rotate protractor)
    # -------------------------------------------------------------------------

        def self.Na__Placement__StartTool(session, kind)
            self.Na__Placement__Ensure(session)
            return 'Import a point cloud first.' unless session.cloud && session.placement
            return NA_LOCKED_TEXT if session.placement['locked']
            tool = kind == 'rotate' ? Na__CloudRotateTool.new(session) : Na__CloudMoveTool.new(session)
            Sketchup.active_model.select_tool(tool)
            nil
        end

        def self.Na__Placement__StopTool(session)
            return nil unless session.transform_tool
            Sketchup.active_model.select_tool(nil)
            session.transform_tool = nil
            nil
        end

        def self.Na__Placement__ToggleTool(session, kind)
            active = session.transform_tool
            if active && active.na_kind == kind
                self.Na__Placement__StopTool(session)
            else
                self.Na__Placement__StartTool(session, kind)
            end
        end

        # Snap preferences: per user (user config), defaults from the plugin config.
        def self.Na__Placement__SnapSettings
            defaults = Na__ConfigLoader.Na__Config__GetOr({}, 'transform')
            defaults = {} unless defaults.is_a?(Hash)
            move_default = defaults.fetch('moveSnapMm', 5).to_f / 25.4
            {
                'moveEnabled'  => Na__UserConfigStore.Na__UserConfig__Get('transform', 'moveSnapEnabled', defaults.fetch('moveSnapEnabled', true)) ? true : false,
                'moveInches'   => Na__UserConfigStore.Na__UserConfig__Get('transform', 'moveSnapInches', move_default).to_f,
                'angleEnabled' => Na__UserConfigStore.Na__UserConfig__Get('transform', 'angleSnapEnabled', defaults.fetch('angleSnapEnabled', false)) ? true : false,
                'angleDegrees' => Na__UserConfigStore.Na__UserConfig__Get('transform', 'angleSnapDegrees', defaults.fetch('angleSnapDegrees', 15)).to_f
            }
        end

        def self.Na__Placement__SetSnap(values, display)
            if values.key?('moveEnabled')
                Na__UserConfigStore.Na__UserConfig__Set('transform', 'moveSnapEnabled', values['moveEnabled'] == true)
            end
            if values.key?('angleEnabled')
                Na__UserConfigStore.Na__UserConfig__Set('transform', 'angleSnapEnabled', values['angleEnabled'] == true)
            end
            if values.key?('moveText')
                step = Na__UnitContract.Na__Units__ParseDisplayLength(values['moveText'], display)
                raise ArgumentError, 'The move snap must be more than zero.' unless step > 0.0
                Na__UserConfigStore.Na__UserConfig__Set('transform', 'moveSnapInches', step)
            end
            if values.key?('angleText')
                step = self.Na__Placement__ParseAngle(values['angleText'])
                raise ArgumentError, 'The angle snap must be more than zero.' unless step > 0.0
                Na__UserConfigStore.Na__UserConfig__Set('transform', 'angleSnapDegrees', step)
            end
            nil
        rescue ArgumentError => error
            error.message
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Rotation Maths (row-major 3x3, angles in degrees at the edges)
    # -------------------------------------------------------------------------

        # Rodrigues: rotation by `angle` radians about the unit vector `axis`.
        def self.Na__Placement__AxisRotation(axis, angle)
            x, y, z = axis
            c = Math.cos(angle)
            s = Math.sin(angle)
            k = 1.0 - c
            [c + x * x * k,     x * y * k - z * s, x * z * k + y * s,
             y * x * k + z * s, c + y * y * k,     y * z * k - x * s,
             z * x * k - y * s, z * y * k + x * s, c + z * z * k]
        end

        # The placement after rotating the whole cloud about a model-space axis
        # through `centre`: R' = Q R, t' = centre + Q (t - centre).
        def self.Na__Placement__RotatedAbout(rotation, translation, axis, angle, centre)
            q = self.Na__Placement__AxisRotation(axis, angle)
            offset = (0..2).map { |i| translation[i] - centre[i] }
            moved  = self.na_mul_vec(q, offset)
            [self.na_mul(q, rotation), (0..2).map { |i| centre[i] + moved[i] }]
        end

        # R = Rz(z) * Ry(y) * Rx(x). Z is the plan rotation; X and Y tilt.
        def self.Na__Placement__FromEulerDegrees(angles)
            rad = ->(deg) { deg.to_f * Math::PI / 180.0 }
            rz = self.Na__Placement__AxisRotation([0.0, 0.0, 1.0], rad.call(angles['z']))
            ry = self.Na__Placement__AxisRotation([0.0, 1.0, 0.0], rad.call(angles['y']))
            rx = self.Na__Placement__AxisRotation([1.0, 0.0, 0.0], rad.call(angles['x']))
            self.na_mul(rz, self.na_mul(ry, rx))
        end

        def self.Na__Placement__EulerDegrees(r)
            deg = 180.0 / Math::PI
            sin_y = [[-r[6], -1.0].max, 1.0].min
            y = Math.asin(sin_y)
            if Math.cos(y).abs > 1e-9
                x = Math.atan2(r[7], r[8])
                z = Math.atan2(r[3], r[0])
            else
                x = 0.0
                z = Math.atan2(-r[1], r[4])
            end
            { 'z' => z * deg, 'y' => y * deg, 'x' => x * deg }
        end

        def self.na_mul(a, b)
            (0..2).flat_map do |r|
                (0..2).map { |c| a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c] }
            end
        end

        def self.na_mul_vec(a, v)
            (0..2).map { |r| a[r * 3] * v[0] + a[r * 3 + 1] * v[1] + a[r * 3 + 2] * v[2] }
        end

        # Gram-Schmidt on the rows: removes float drift so R stays a pure
        # rotation (no creeping scale or shear) however many edits it sees.
        def self.na_orthonormal(r)
            norm = lambda do |v|
                l = Math.sqrt(v.sum { |c| c * c })
                raise ArgumentError, 'The stored rotation is not a rotation.' unless l > 1e-12 && l.finite?
                v.map { |c| c / l }
            end
            r0 = norm.call(r[0, 3])
            row1 = r[3, 3]
            d = (0..2).sum { |i| row1[i] * r0[i] }
            r1 = norm.call((0..2).map { |i| row1[i] - d * r0[i] })
            r2 = [r0[1] * r1[2] - r0[2] * r1[1], r0[2] * r1[0] - r0[0] * r1[2], r0[0] * r1[1] - r0[1] * r1[0]]
            r0 + r1 + r2
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Placement__Payload(session, model)
            return { 'isAvailable' => false } unless session
            self.Na__Placement__Ensure(session)
            display = Na__UnitContract.Na__Units__ModelDisplay(model)
            snap = self.Na__Placement__SnapSettings
            payload = {
                'isAvailable' => true,
                'hasCloud'    => !(session.cloud.nil? || session.placement.nil?),
                'unit'        => display['suffix'],
                'snap'        => {
                    'moveEnabled'  => snap['moveEnabled'],
                    'moveText'     => Na__UnitContract.Na__Units__InchesToPreciseText(snap['moveInches'], display),
                    'angleEnabled' => snap['angleEnabled'],
                    'angleText'    => Na__UnitContract.Na__Units__TrimNumber(snap['angleDegrees'], 3)
                }
            }
            return payload unless payload['hasCloud']
            placement = session.placement
            angles = self.Na__Placement__EulerDegrees(placement['rotation'])
            g = self.Na__Placement__GimbalModel(session)
            tool = session.transform_tool
            payload.merge(
                'locked'           => placement['locked'] ? true : false,
                'activeTool'       => tool ? tool.na_kind : nil,
                'pickingGimbal'    => tool && tool.respond_to?(:na_picking_gimbal?) && tool.na_picking_gimbal? ? true : false,
                'gimbalIsCustom'   => self.Na__Placement__GimbalIsCustom?(session),
                'gimbalSurvey'     => self.na_survey_text(session.cloud, self.Na__Placement__GimbalLocal(session)),
                'position'         => { 'x' => Na__UnitContract.Na__Units__InchesToPreciseText(g[0], display),
                                        'y' => Na__UnitContract.Na__Units__InchesToPreciseText(g[1], display),
                                        'z' => Na__UnitContract.Na__Units__InchesToPreciseText(g[2], display) },
                'rotation'         => { 'z' => Na__UnitContract.Na__Units__TrimNumber(angles['z'], 3),
                                        'x' => Na__UnitContract.Na__Units__TrimNumber(angles['x'], 3),
                                        'y' => Na__UnitContract.Na__Units__TrimNumber(angles['y'], 3) },
                'isImportPosition' => self.na_identity?(placement),
                'surveyPoint'      => self.na_survey_point_text(session.cloud),
                'note'             => session.placement_note
            )
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_default(key)
            { 'key' => key, 'rotation' => NA_IDENTITY.dup, 'translation' => [0.0, 0.0, 0.0], 'gimbal' => nil, 'locked' => true }
        end

        # local_to_model = R * k, then t; the cloud's model bounds follow.
        def self.na_apply(session, cloud)
            return unless cloud && session.placement
            k = (cloud.unit_factor || 1.0).to_f
            rotation    = session.placement['rotation']
            translation = session.placement['translation']
            cloud.local_to_model = rotation.map { |v| v * k } + translation
            cloud.bounds = self.na_model_bounds(cloud) if cloud.local_min && cloud.local_max
        end

        def self.na_model_bounds(cloud)
            m = cloud.local_to_model
            box = Geom::BoundingBox.new
            [0, 1].product([0, 1], [0, 1]).each do |ix, iy, iz|
                p = [ix.zero? ? cloud.local_min[0] : cloud.local_max[0],
                     iy.zero? ? cloud.local_min[1] : cloud.local_max[1],
                     iz.zero? ? cloud.local_min[2] : cloud.local_max[2]]
                box.add(Geom::Point3d.new(*(0..2).map { |r| m[r * 3] * p[0] + m[r * 3 + 1] * p[1] + m[r * 3 + 2] * p[2] + m[9 + r] }))
            end
            box
        end

        def self.na_identity?(placement)
            placement['translation'].all? { |v| v.abs < 1e-9 } &&
                placement['rotation'].each_with_index.all? { |v, i| (v - NA_IDENTITY[i]).abs < 1e-12 }
        end

        def self.na_survey_point_text(cloud)
            self.na_survey_text(cloud, [0.0, 0.0, 0.0])
        end

        # A local point back in the LAS's own coordinates: local origin + local.
        def self.na_survey_text(cloud, local)
            origin = (cloud.las_info || {})['localOriginSource'] || [0.0, 0.0, 0.0]
            "#{(0..2).map { |i| format('%.3f', origin[i].to_f + local[i].to_f) }.join(', ')} #{cloud.source_unit}"
        end

        def self.na_read(model)
            raw = model ? model.get_attribute(NA_DICT, NA_KEY) : nil
            return nil unless raw.is_a?(String) && !raw.empty?
            data = JSON.parse(raw)
            return nil unless data.is_a?(Hash) && data['schema'] == NA_SCHEMA && data['schemaVersion'].to_i <= NA_SCHEMA_VERSION
            rotation    = Array(data['rotation']).map { |v| Float(v) }
            translation = Array(data['translation']).map { |v| Float(v) }
            return nil unless data['key'].is_a?(String) && rotation.length == 9 && translation.length == 3
            gimbal = data['gimbal'].is_a?(Array) ? data['gimbal'].map { |v| Float(v) } : nil
            gimbal = nil unless gimbal && gimbal.length == 3 && gimbal.all?(&:finite?)
            {
                'key'         => data['key'],
                'file'        => data['file'].to_s,
                'rotation'    => self.na_orthonormal(rotation),
                'translation' => translation,
                'gimbal'      => gimbal,
                'locked'      => data['locked'] != false
            }
        rescue JSON::ParserError, ArgumentError, TypeError, ZeroDivisionError => error
            Na__DebugTools.Na__Debug__Warn("Stored point cloud position could not be read and was ignored: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
