# =============================================================================
# NA POINT CLOUD VIEWER - CLEAN - CROP AND CUT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Clean__Boxes__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CleanBoxes
# PURPOSE    : The Clean tab's Crop and Cut section (v0.11.0). The clip box is
#              captured as a box that removes points for good, into a NEW LAS:
#                Remove Outside  the Keep box: every point outside it goes, so
#                                the cloud is cropped to the area you want
#                                (one per cloud; capturing again replaces it)
#                Remove Inside   a Cut box: every point inside it goes (a tree,
#                                a car, a clump of noise; up to 20 per cloud)
#              The result shows live in the model, the dialog gives exact
#              counts, and Remove Points & Export LAS writes it.
#
# THE ORIGINAL IS NEVER TOUCHED: the export is Clean & Export's own path
#   (Na__CleanExportJob, kind 'boxes'): Save As every time and nothing ever
#   overwritten; the source LAS only read; every kept record copied byte for
#   byte; the new file read back and checked, then published without
#   replacing anything; loaded with its own point cache (the original's is
#   kept); and only then used by the model, in ONE undoable operation. Undo
#   puts the model's link (and the boxes) back and never changes a file.
#
# ONE TEST: the engine decides what a box removes with one function
#   (BoxFilter.hpp) for the picture, the counts and the export, so the counts
#   shown are exactly what the export removes. A box holds its own faces: a
#   point on a Keep box face stays, a point on a Cut box face goes.
#
# WHERE THE BOXES LIVE: the cloud's own record in the model, key 'cropCut':
#     { 'keep' => { 'min', 'max' } or nil,
#       'cuts' => [{ 'id', 'name', 'min', 'max' }] }
#   in model inches, axis-aligned in the model like the clip box. They stay
#   put if the cloud is moved; what they remove follows the cloud's position
#   at the time, and the picture always shows exactly that. Each change is one
#   named, undoable operation. When the model starts using the new file the
#   boxes are cleared in that same operation: they have done their work, and
#   one Undo brings back both.
#
# WHAT IS SHOWN (view settings, never written): per cloud 'original',
#   'result' (what the boxes remove is not drawn) or 'differences' (drawn in
#   the removed colour, the rest faded). Only the ACTIVE cloud's boxes show,
#   and only while the Clean tab is the active tab, like the filter preview.
#   One thing shows at a time: while the boxes show, the filter preview waits;
#   Cleaned or Differences on the filter card hands the model back to it, and
#   Original on either card shows the cloud as it is.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__CleanBoxes

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_RECORD_KEY = 'cropCut'.freeze
        NA_KEEP_ID    = 'keep'.freeze
        NA_VIEWS      = %w[original result differences].freeze
        NA_EDGES      = [[0, 4], [2, 6], [1, 5], [3, 7], [0, 2], [4, 6], [1, 3], [5, 7], [0, 1], [2, 3], [4, 5], [6, 7]].freeze
        NA_IDENTITY   = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read (from the cloud's record; cheap, used every frame)
    # -------------------------------------------------------------------------

        # { 'keep' => box or nil, 'cuts' => [box + 'id', 'name'] } as the
        # cloud's record holds them now. A box that is not one is left out with
        # a log line. Cached for the record object it was read from, so an
        # Undo, a Redo or any write (all of which replace the record) re-reads.
        def self.Na__Boxes__Get(slot)
            return { 'keep' => nil, 'cuts' => [] } unless slot
            record = slot.record
            return slot.box_parsed if slot.box_parsed && slot.box_parsed_from.equal?(record)
            parsed = self.na_parse(record ? record[NA_RECORD_KEY] : nil, slot)
            slot.box_parsed = parsed
            slot.box_parsed_from = record
            parsed
        end

        def self.Na__Boxes__Any?(slot)
            boxes = self.Na__Boxes__Get(slot)
            !boxes['keep'].nil? || !boxes['cuts'].empty?
        end

        def self.Na__Boxes__MaxCuts
            wanted = Na__ConfigLoader.Na__Config__GetOr(Na__NativeEngine::NA_MAX_CUT_BOXES, 'clean', 'boxes', 'maxCutBoxes').to_i
            [[wanted, 1].max, Na__NativeEngine::NA_MAX_CUT_BOXES].min
        end

        def self.Na__Boxes__View(slot)
            slot && NA_VIEWS.include?(slot.box_view) ? slot.box_view : 'result'
        end

        # The Clean tab shows this cloud and it has boxes: their outlines are drawn.
        def self.Na__Boxes__OnTab?(slot)
            session = slot ? slot.session : nil
            return false unless session && session.clean_tab_active
            Na__CloudSet.Na__Slots__Active(session).equal?(slot) && self.Na__Boxes__Any?(slot) ? true : false
        end

        # The model shows what the boxes do (Result or Differences).
        def self.Na__Boxes__Shown?(slot)
            self.Na__Boxes__OnTab?(slot) && self.Na__Boxes__View(slot) != 'original'
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Renderer Hooks (ImageRenderer, RenderController)
    # -------------------------------------------------------------------------

        # The tail of the cloud's render block (Api.h, NAPC_P_BOX_MODE onwards):
        # how to show the boxes and the boxes themselves; all zeros when they
        # do not show.
        def self.Na__Boxes__RenderParams(slot)
            return self.na_off_tail unless self.Na__Boxes__Shown?(slot)
            mode = self.Na__Boxes__View(slot) == 'differences' ? 2 : 1
            colours = Na__CleanPreview.na_diff_colours
            [mode, *colours[0, 3], *colours[18, 3], colours[21]].map(&:to_f) + self.Na__Boxes__Block(self.Na__Boxes__Get(slot))
        end

        # Part of the image renderer's cache key: any change re-renders.
        def self.Na__Boxes__Key(slot)
            return nil unless self.Na__Boxes__Shown?(slot)
            [self.Na__Boxes__View(slot), self.Na__Boxes__Block(self.Na__Boxes__Get(slot))]
        end

        # The engine's box block (Na__BoxBlockIndex): the Keep box (flag, min,
        # max), the number of Cut boxes and each one's min and max, zero padded.
        def self.Na__Boxes__Block(boxes)
            keep = boxes['keep']
            block = keep ? [1.0] + keep['min'] + keep['max'] : [0.0] * 7
            cuts = boxes['cuts'].first(Na__NativeEngine::NA_MAX_CUT_BOXES)
            block << cuts.length
            cuts.each { |cut| block.concat(cut['min'] + cut['max']) }
            block.concat([0.0] * (Na__NativeEngine::NA_BOX_BLOCK_COUNT - block.length))
            block.map(&:to_f)
        end

        # What part of the cloud's box the picture can hold. In the Result view
        # the Keep box cuts it, so the image is no bigger than it needs to be;
        # nil when the Keep box holds none of it (nothing is drawn).
        def self.Na__Boxes__TrimBounds(slot, bounds)
            return bounds unless bounds && !bounds.empty? && self.Na__Boxes__Shown?(slot) && self.Na__Boxes__View(slot) == 'result'
            keep = self.Na__Boxes__Get(slot)['keep']
            return bounds unless keep
            lo = (0..2).map { |i| [bounds.min.to_a[i], keep['min'][i]].max }
            hi = (0..2).map { |i| [bounds.max.to_a[i], keep['max'][i]].min }
            return nil unless (0..2).all? { |i| hi[i] >= lo[i] }
            Geom::BoundingBox.new.add(Geom::Point3d.new(*lo), Geom::Point3d.new(*hi))
        end

        # The box corners, for the camera's near and far planes while drawn.
        def self.Na__Boxes__ExtentPoints(slot)
            return [] unless self.Na__Boxes__OnTab?(slot)
            boxes = self.Na__Boxes__Get(slot)
            ([boxes['keep']].compact + boxes['cuts']).flat_map { |box| [Geom::Point3d.new(*box['min']), Geom::Point3d.new(*box['max'])] }
        end

        # The outlines of the active cloud's boxes while the Clean tab shows
        # them: the Keep box green, Cut boxes red, each with its name; the box
        # last put into the clip box drawn heavier. Drawn by the overlay after
        # the cloud image, so the picture never covers them.
        def self.Na__Boxes__DrawCages(session, view)
            slot = Na__CloudSet.Na__Slots__Active(session)
            return unless slot && self.Na__Boxes__OnTab?(slot)
            boxes = self.Na__Boxes__Get(slot)
            showing = self.na_showing_id(slot)
            view.line_stipple = ''
            keep_colour = self.na_colour('keepColour', [24, 128, 56])
            cut_colour  = self.na_colour('cutColour', [214, 32, 32])
            self.na_draw_box(view, boxes['keep'], keep_colour, showing == NA_KEEP_ID, 'Keep') if boxes['keep']
            boxes['cuts'].each { |cut| self.na_draw_box(view, cut, cut_colour, showing == cut['id'], cut['name']) }
            view.line_width = 1
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The Crop and Cut boxes could not be drawn: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Changes (each returns nil or a plain-English reason)
    # -------------------------------------------------------------------------

        # Remove Outside: the clip box becomes this cloud's Keep box (replacing
        # the one it had).
        def self.Na__Boxes__RemoveOutside(slot)
            box, problem = self.na_clip_box(slot)
            return problem if problem
            boxes = self.na_copy(self.Na__Boxes__Get(slot))
            had = !boxes['keep'].nil?
            boxes['keep'] = box
            problem = self.na_write(slot, boxes, had ? 'Replace Keep Box' : 'Set Keep Box')
            return problem if problem
            self.na_after_capture(slot, NA_KEEP_ID)
            nil
        end

        # Remove Inside: the clip box becomes a new Cut box of this cloud.
        def self.Na__Boxes__RemoveInside(slot)
            box, problem = self.na_clip_box(slot)
            return problem if problem
            boxes = self.na_copy(self.Na__Boxes__Get(slot))
            max = self.Na__Boxes__MaxCuts
            if boxes['cuts'].length >= max
                return "#{slot.name} already has #{max} Cut boxes, the most one cloud can have. Delete one, or export and carry on with the new file."
            end
            id = self.na_new_cut_id(boxes)
            boxes['cuts'] << box.merge('id' => id, 'name' => self.na_new_cut_name(boxes))
            problem = self.na_write(slot, boxes, 'Add Cut Box')
            return problem if problem
            self.na_after_capture(slot, id)
            nil
        end

        # The box takes the clip box as it is now (after being shown in it and
        # adjusted).
        def self.Na__Boxes__Update(slot, id)
            box, problem = self.na_clip_box(slot)
            return problem if problem
            boxes = self.na_copy(self.Na__Boxes__Get(slot))
            target = self.na_find(boxes, id)
            return 'That box no longer exists.' unless target
            target.merge!(box)
            problem = self.na_write(slot, boxes, "Update #{self.na_label(id, target)}")
            return problem if problem
            self.na_after_capture(slot, id.to_s)
            nil
        end

        def self.Na__Boxes__Rename(slot, id, name)
            boxes = self.na_copy(self.Na__Boxes__Get(slot))
            cut = boxes['cuts'].find { |each_cut| each_cut['id'] == id.to_s }
            return 'Only a Cut box has a name of its own.' if id.to_s == NA_KEEP_ID
            return 'That Cut box no longer exists.' unless cut
            clean = name.to_s.strip[0, 60]
            return 'Give the box a name.' if clean.empty?
            return nil if clean == cut['name']
            old = cut['name']
            cut['name'] = clean
            self.na_write(slot, boxes, "Rename #{old} to #{clean}")
        end

        def self.Na__Boxes__Delete(slot, id)
            boxes = self.na_copy(self.Na__Boxes__Get(slot))
            target = self.na_find(boxes, id)
            return 'That box no longer exists.' unless target
            label = self.na_label(id, target)
            if id.to_s == NA_KEEP_ID
                boxes['keep'] = nil
            else
                boxes['cuts'].reject! { |cut| cut['id'] == id.to_s }
            end
            problem = self.na_write(slot, boxes, "Delete #{label}")
            return problem if problem
            slot.box_showing = nil if slot.box_showing && slot.box_showing['id'] == id.to_s
            self.na_changed(slot)
            nil
        end

        def self.Na__Boxes__DeleteAll(slot)
            return 'There are no boxes to delete.' unless self.Na__Boxes__Any?(slot)
            problem = self.na_write(slot, { 'keep' => nil, 'cuts' => [] }, 'Delete Crop and Cut Boxes')
            return problem if problem
            slot.box_showing = nil
            self.na_changed(slot)
            nil
        end

        # Puts a box into the clip box (clipping on), so it can be seen and
        # adjusted with the clip box tools, then saved with Update. A Cut box
        # in the Result view would show an empty box (all of it is removed), so
        # the view turns to Differences, where its points are red.
        # Returns [nil or a reason, a note for the status bar or nil].
        def self.Na__Boxes__ShowInClip(slot, id)
            return ['There is no point cloud in this model yet.', nil] unless slot
            boxes = self.Na__Boxes__Get(slot)
            target = self.na_find(boxes, id)
            return ['That box no longer exists.', nil] unless target
            Na__ClipBox.Na__Clip__Ensure(slot)
            slot.clip = { 'enabled' => true, 'min' => target['min'].dup, 'max' => target['max'].dup }
            slot.clip_active_scene = nil
            # on failure Na__Clip__Save reads the clip box back from the model
            problem = Na__ClipBox.Na__Clip__Save(slot, Na__ClipBox.na_op(slot, "Clip to #{self.na_label(id, target)}"))
            return [problem, nil] if problem
            slot.box_showing = { 'id' => id.to_s }
            note = nil
            if id.to_s != NA_KEEP_ID && self.Na__Boxes__View(slot) == 'result'
                slot.box_view = 'differences'
                note = "The clip box is now #{target['name']}. Differences shows its points in red, so you can fit it: " \
                       'move its sides with Edit Clip Box, then press Update on its row.'
            end
            self.na_changed(slot)
            [nil, note]
        end

        # Original, Result or Differences. Original on this card shows the
        # cloud as it is, so the filter preview's own switch goes to Original
        # too; any other view hands the model to the boxes (the filter preview
        # waits, Na__CleanPreview).
        def self.Na__Boxes__SetView(slot, view)
            return 'Unknown view.' unless NA_VIEWS.include?(view.to_s)
            slot.box_view = view.to_s
            Na__CleanPreview.Na__Clean__State(slot).display = 'original' if view.to_s == 'original'
            self.na_changed(slot)
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Counts (exactly what the export removes)
    # -------------------------------------------------------------------------

        # { 'points', 'outside', 'inside', 'kept' } for the cloud as it is placed
        # now, or nil (not loaded, no boxes). Counted by the engine with the
        # export's own test, again only when the boxes or the placement change.
        def self.Na__Boxes__Counts(slot)
            cloud = slot ? slot.cloud : nil
            return nil unless cloud && self.Na__Boxes__Any?(slot) && self.na_engine_ready?(cloud)
            transform = cloud.local_to_model || NA_IDENTITY
            block = self.Na__Boxes__Block(self.Na__Boxes__Get(slot))
            key = [cloud.object_id, cloud.native_generation, transform, block]
            cached = slot.box_counts
            return cached['value'] if cached && cached['key'] == key
            value = Na__NativeEngine.Na__Native__BoxCount(cloud.native_cloud, transform, block)
            slot.box_counts = { 'key' => key, 'value' => value }
            value
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The points the Crop and Cut boxes remove could not be counted: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Export (a NEW LAS without the points the boxes remove)
    # -------------------------------------------------------------------------

        # nil, or why Remove Points & Export LAS cannot start (shown under it).
        def self.Na__Boxes__ExportBlocker(slot)
            cloud = slot ? slot.cloud : nil
            return 'Capture a box first: Remove Outside or Remove Inside.' unless self.Na__Boxes__Any?(slot)
            problem = Na__CleanExport.Na__CleanExport__SourceBlocker(slot)
            return problem if problem
            unless self.na_engine_ready?(cloud)
                return "The native engine was reloaded after #{slot.name} was loaded. Reload it (View tab) first."
            end
            counts = self.Na__Boxes__Counts(slot)
            return 'The points the boxes remove could not be counted. Details are in Settings > Technical Log.' unless counts
            return 'The boxes remove no point of this cloud. Fit them over the points to remove first.' if counts['kept'] >= counts['points']
            return 'The boxes remove every point of this cloud, so nothing would be left to save.' if counts['kept'] <= 0
            return 'Another task is still running.' if Na__AsyncJobs.Na__Jobs__Busy?
            nil
        end

        def self.Na__Boxes__SuggestedName(source_path)
            Na__CleanExport.Na__CleanExport__SuggestedName(source_path, self.na_suffix)
        end

        # Returns nil when the job has started, 'cancelled', or a reason.
        def self.Na__Boxes__ExportStart(slot)
            problem = self.Na__Boxes__ExportBlocker(slot)
            return problem if problem
            cloud = slot.cloud
            source = cloud.source_path.to_s
            problem, key = Na__CleanExport.na_check_source(cloud)
            return problem if problem
            dest = Na__CleanExport.na_ask_destination(source, 'Save the cloud without the removed points as a NEW LAS file', self.na_suffix)
            return 'cancelled' unless dest
            Na__Placement.Na__Placement__Ensure(slot)
            return 'The loaded cloud has no position record; Reload it first.' unless slot.placement
            boxes = self.Na__Boxes__Get(slot)
            transform = cloud.local_to_model || NA_IDENTITY
            block = self.Na__Boxes__Block(boxes)
            counts = self.Na__Boxes__Counts(slot)
            info = cloud.las_info || {}
            job = Na__CleanExportJob.new(slot, Sketchup.active_model.active_view, {
                'kind'       => 'boxes',
                'source'     => source,
                'dest'       => dest,
                'transform'  => transform,
                'block'      => block,
                'provenance' => self.na_provenance(slot, cloud, key, boxes, transform, counts),
                'origin'     => info['localOriginSource'],
                'sourceKey'  => key,
                'counts'     => counts
            })
            Na__AsyncJobs.Na__Jobs__Start(job) ? nil : 'Another task is still running.'
        end

        # Written into the new LAS (VLR NobleArch_PCV): which boxes, in which
        # frame, and the rule, so the file explains itself.
        def self.na_provenance(slot, cloud, source_key, boxes, transform, counts)
            model = slot.model
            JSON.generate(
                'tool'      => Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'plugin', 'name'),
                'version'   => Na__PointCloudViewer.Na__PublicApi__Version,
                'operation' => 'cropCut',
                'exportId'  => format('%016x', Random.new.rand(2**64)),   # every export a distinct file (and content key)
                'createdAt' => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'source'    => { 'fileName' => File.basename(cloud.source_path.to_s), 'contentKey' => source_key,
                                 'pointCount' => cloud.total_points, 'sourceUnit' => cloud.source_unit },
                'boxes'     => {
                    'frame'              => 'SketchUp model inches, each box axis-aligned in the model',
                    'rule'               => 'A point is removed when its model position is outside the Keep box or inside a Cut box. ' \
                                            'A box holds its own faces.',
                    'modelPosition'      => 'R * (k * (source - localOriginSource)) + t, i.e. localToModelInches applied to source - localOriginSource',
                    'localToModelInches' => transform,
                    'localOriginSource'  => (cloud.las_info || {})['localOriginSource'],
                    'keep'               => boxes['keep'] ? { 'min' => boxes['keep']['min'], 'max' => boxes['keep']['max'] } : nil,
                    'cuts'               => boxes['cuts'].map { |cut| { 'name' => cut['name'], 'min' => cut['min'], 'max' => cut['max'] } }
                },
                'counts'    => counts ? { 'outsideKeep' => counts['outside'], 'insideCut' => counts['inside'], 'kept' => counts['kept'] } : nil,
                'model'     => { 'title' => model ? model.title.to_s : '' }
            )
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Words (status messages)
    # -------------------------------------------------------------------------

        # What a capture did, in a sentence for the status bar.
        def self.Na__Boxes__CaptureMessage(slot, kind)
            counts = self.Na__Boxes__Counts(slot)
            first = kind == 'outside' ? 'Keep box set: every point outside it will be removed.' : 'Cut box added: every point inside it will be removed.'
            return "#{first} Load the cloud to see how many points that is." unless counts
            removed = counts['points'] - counts['kept']
            "#{first} The boxes remove #{Na__PerfStats.Na__Perf__Thousands(removed)} points " \
                "(#{self.na_share(removed, counts['points'])}) so far. Nothing is removed until Remove Points & Export LAS saves a new file."
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__Boxes__Payload(slot)
            state = slot ? Na__CleanPreview.Na__Clean__State(slot) : nil
            base = {
                'isAvailable' => true,
                'maxCuts'     => self.Na__Boxes__MaxCuts,
                'busy'        => Na__AsyncJobs.Na__Jobs__Busy?
            }
            return base.merge('inModel' => false, 'hasCloud' => false, 'keep' => nil, 'cuts' => [], 'view' => 'result', 'shown' => false,
                              'clip' => { 'hasBox' => false, 'enabled' => false, 'editing' => false, 'sizeText' => '' },
                              'captureBlocker' => 'Import a point cloud first.', 'counts' => nil,
                              'exportBlocker' => 'Load a point cloud first.', 'lastExport' => nil, 'retryLoad' => nil) unless slot
            boxes = self.Na__Boxes__Get(slot)
            Na__ClipBox.Na__Clip__Ensure(slot)
            clip = slot.clip
            showing = self.na_showing_id(slot)
            row = lambda do |id, name, box|
                is_showing = showing == id
                { 'id' => id, 'name' => name, 'sizeText' => self.na_size_text(box), 'isShowing' => is_showing,
                  'isChanged' => is_showing && clip ? !self.na_same_box?(box, clip) : false }
            end
            cloud = slot.cloud
            retry_info = state.retry_load
            base.merge(
                'inModel'        => true,
                'cloudId'        => slot.id,
                'cloudName'      => slot.name,
                'hasCloud'       => !cloud.nil?,
                'keep'           => boxes['keep'] ? row.call(NA_KEEP_ID, 'Keep box', boxes['keep']) : nil,
                'cuts'           => boxes['cuts'].map { |cut| row.call(cut['id'], cut['name'], cut) },
                'view'           => self.Na__Boxes__View(slot),
                'shown'          => self.Na__Boxes__Shown?(slot),
                'clip'           => {
                    'hasBox'   => !clip.nil?,
                    'enabled'  => clip && clip['enabled'] ? true : false,
                    'editing'  => slot.clip_editing ? true : false,
                    'sizeText' => clip ? self.na_size_text(clip) : ''
                },
                'captureBlocker' => self.na_clip_box(slot)[1],
                'counts'         => self.Na__Boxes__Counts(slot),
                'exportBlocker'  => self.Na__Boxes__ExportBlocker(slot),
                'suggestedName'  => cloud ? self.Na__Boxes__SuggestedName(cloud.source_path.to_s) : '',
                'lastExport'     => state.last_box_export,
                'retryLoad'      => retry_info && retry_info['kind'] == 'boxes' ?
                    { 'fileName' => File.basename(retry_info['path'].to_s), 'path' => retry_info['path'] } : nil
            )
        end

        # Each cloud's boxes in the configuration export (Transform tab).
        def self.Na__Boxes__ConfigPart(slot, display)
            boxes = self.Na__Boxes__Get(slot)
            to_display = ->(values) { values.map { |v| v / display['inchesPerUnit'] } }
            box_part = lambda do |box|
                { 'minInches' => box['min'], 'maxInches' => box['max'], 'min' => to_display.call(box['min']),
                  'max' => to_display.call(box['max']), 'unit' => display['suffix'] }
            end
            {
                'keep' => boxes['keep'] ? box_part.call(boxes['keep']) : nil,
                'cuts' => boxes['cuts'].map { |cut| { 'id' => cut['id'], 'name' => cut['name'] }.merge(box_part.call(cut)) },
                'rule' => 'A point is removed when its model position is outside the Keep box or inside a Cut box (a box holds its own faces). ' \
                          'Nothing is removed until Remove Points & Export LAS writes a new file.'
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_parse(raw, slot)
            out = { 'keep' => nil, 'cuts' => [] }
            return out unless raw.is_a?(Hash)
            out['keep'] = self.na_valid_box(raw['keep'])
            seen = {}
            Array(raw['cuts']).each do |cut|
                box = self.na_valid_box(cut)
                next unless box && cut['id'].is_a?(String) && !cut['id'].empty? && !seen[cut['id']]
                seen[cut['id']] = true
                out['cuts'] << box.merge('id' => cut['id'], 'name' => self.na_clean_name(cut['name'], out['cuts'].length + 1))
            end
            out['cuts'] = out['cuts'].first(self.Na__Boxes__MaxCuts)
            out
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The Crop and Cut boxes of #{slot ? slot.name : 'a cloud'} could not be read and were ignored: #{error.message}")
            { 'keep' => nil, 'cuts' => [] }
        end

        def self.na_valid_box(raw)
            return nil unless raw.is_a?(Hash)
            min = Array(raw['min']).map { |v| Float(v) }
            max = Array(raw['max']).map { |v| Float(v) }
            return nil unless min.length == 3 && max.length == 3 && (0..2).all? { |i| min[i].finite? && max[i].finite? && max[i] > min[i] }
            { 'min' => min, 'max' => max }
        rescue ArgumentError, TypeError
            nil
        end

        def self.na_clean_name(name, number)
            clean = name.to_s.strip[0, 60]
            clean.empty? ? "Cut #{number}" : clean
        end

        def self.na_copy(boxes)
            Marshal.load(Marshal.dump(boxes))
        end

        def self.na_find(boxes, id)
            id.to_s == NA_KEEP_ID ? boxes['keep'] : boxes['cuts'].find { |cut| cut['id'] == id.to_s }
        end

        def self.na_label(id, box)
            id.to_s == NA_KEEP_ID ? 'Keep Box' : box['name'].to_s
        end

        def self.na_new_cut_id(boxes)
            used = boxes['cuts'].map { |cut| cut['id'] }
            number = boxes['cuts'].length + 1
            number += 1 while used.include?("cut#{number}")
            "cut#{number}"
        end

        def self.na_new_cut_name(boxes)
            used = boxes['cuts'].map { |cut| cut['name'] }
            number = boxes['cuts'].length + 1
            number += 1 while used.include?("Cut #{number}")
            "Cut #{number}"
        end

        # [box, nil] from the clip box, or [nil, why it cannot be captured].
        def self.na_clip_box(slot)
            return [nil, 'There is no point cloud in this model yet. Import one first.'] unless slot
            Na__ClipBox.Na__Clip__Ensure(slot)
            clip = slot.clip
            return [nil, 'There is no clip box yet. Press Edit Clip Box and fit it round the area first.'] unless clip
            unless clip['enabled'] || slot.clip_editing
                return [nil, 'Turn the clip box on (or press Edit Clip Box) and fit it round the area first, so you can see what you capture.']
            end
            [{ 'min' => clip['min'].map(&:to_f), 'max' => clip['max'].map(&:to_f) }, nil]
        end

        # ONE undoable operation; nil, or why nothing was written.
        def self.na_write(slot, boxes, text)
            part = self.na_part(boxes)
            Na__CloudStore.Na__Store__WriteSlots(slot.session, [slot], Na__CloudSet.Na__Slots__OpName(slot, text)) do |_slot, record|
                if part
                    record[NA_RECORD_KEY] = part
                else
                    record.delete(NA_RECORD_KEY)
                end
            end
        end

        def self.na_part(boxes)
            return nil if boxes['keep'].nil? && boxes['cuts'].empty?
            {
                'keep' => boxes['keep'] ? { 'min' => boxes['keep']['min'], 'max' => boxes['keep']['max'] } : nil,
                'cuts' => boxes['cuts'].map { |cut| { 'id' => cut['id'], 'name' => cut['name'], 'min' => cut['min'], 'max' => cut['max'] } }
            }
        end

        # A box was captured or updated: it is the one in the clip box now, and
        # the model shows what the boxes do (Result, unless Differences was on).
        def self.na_after_capture(slot, id)
            slot.box_showing = { 'id' => id }
            slot.box_view = 'result' unless %w[result differences].include?(slot.box_view)
            self.na_changed(slot)
        end

        # Something the picture depends on changed: the filter preview pauses
        # or resumes, the extents and the view follow.
        def self.na_changed(slot)
            Na__CleanPreview.Na__Clean__Changed(slot)
            Na__RenderController.Na__Render__RefreshExtents(slot.session)
            self.na_invalidate(slot)
        end

        # The id of the box last put into the clip box, while the clip box is
        # on (or being edited) and that box still exists; else nil.
        def self.na_showing_id(slot)
            showing = slot.box_showing
            return nil unless showing && slot.clip && (slot.clip['enabled'] || slot.clip_editing)
            self.na_find(self.Na__Boxes__Get(slot), showing['id']) ? showing['id'] : nil
        end

        def self.na_same_box?(a, b)
            (0..2).all? { |i| (a['min'][i] - b['min'][i]).abs < 1e-6 && (a['max'][i] - b['max'][i]).abs < 1e-6 }
        end

        # Metres, whatever the model's units: a site is read in metres.
        def self.na_size_text(box)
            (0..2).map { |i| format('%.2f m', (box['max'][i] - box['min'][i]) * 0.0254) }.join(' x ')
        end

        def self.na_share(part, whole)
            return '0 %' unless whole.to_f > 0
            value = 100.0 * part / whole
            value > 0 && value < 0.1 ? '<0.1 %' : format(value < 10 ? '%.1f %%' : '%.0f %%', value)
        end

        def self.na_engine_ready?(cloud)
            cloud && cloud.native_cloud && cloud.native_generation == Na__NativeEngine.Na__Native__Generation &&
                Na__NativeEngine.Na__Native__CloudLive?(cloud.native_cloud) ? true : false
        end

        def self.na_suffix
            Na__ConfigLoader.Na__Config__GetOr('_Cropped_', 'clean', 'boxes', 'suffix').to_s
        end

        def self.na_off_tail
            [0.0] * (Na__NativeEngine::NA_RENDER_PARAM_COUNT - Na__NativeEngine::NA_PARAM_COUNT)
        end

        def self.na_colour(key, fallback)
            rgb = Na__ConfigLoader.Na__Config__GetOr(fallback, 'clean', 'boxes', key)
            rgb = fallback unless rgb.is_a?(Array) && rgb.length == 3
            Sketchup::Color.new(*rgb.map { |v| [[v.to_i, 0].max, 255].min })
        end

        def self.na_draw_box(view, box, colour, emphasised, label)
            lo = box['min']
            hi = box['max']
            corners = [0, 1].product([0, 1], [0, 1]).map do |ix, iy, iz|
                Geom::Point3d.new(ix.zero? ? lo[0] : hi[0], iy.zero? ? lo[1] : hi[1], iz.zero? ? lo[2] : hi[2])
            end
            view.line_width = emphasised ? 3 : 2
            view.drawing_color = colour
            view.draw(GL_LINES, NA_EDGES.flat_map { |a, b| [corners[a], corners[b]] })
            top = Geom::Point3d.new((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0, hi[2])
            return unless Na__ClipBox.na_in_front?(view, top)
            screen = view.screen_coords(top)
            view.draw_text(Geom::Point3d.new(screen.x + 6.0, screen.y - 18.0, 0), label.to_s, size: 10, bold: true, color: colour)
        end

        def self.na_invalidate(slot)
            model = slot ? slot.model : nil
            model.active_view.invalidate if model && model.valid? && model == Sketchup.active_model
        rescue StandardError
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
