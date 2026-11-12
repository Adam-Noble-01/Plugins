# =============================================================================
# NA AGENT OUTLINER - MODEL DATA - WALKER
# =============================================================================
#
# FILE       : Na__AgentOutliner__ModelData__Walker__.rb
# NAMESPACE  : Na__AgentOutliner::Na__Walker
# MODULE     : Na__Walker (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Read the model's Outliner structure (groups, components, images
#              and section planes, and which container holds which), one row
#              per object for the dialog, and the fingerprints the change
#              tracker compares
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - THE TREE IS A GRAPH OF DEFINITIONS, NOT A LIST OF OCCURRENCES. Each object
#   appears once with the definition that holds it; the page expands an
#   instance into its definition's children. A component placed 29 times
#   sends its contents once, so a big model's payload grows with the number of
#   objects, never with the number of places they appear.
# - THE FAST WALK reads ComponentDefinition#instances and each instance's
#   parent: it never touches an edge or a face, so it stays quick on heavy
#   geometry. Images and section planes have no instance list, so they come
#   from a scan of each container's entities, run only on a full refresh (the
#   dialog opening, Refresh, undo and redo) and capped by scan_entity_limit.
# - READ ONLY. Nothing here changes the model.
# - SIZES are the object's own width, depth and height in mm: the definition's
#   bounds times the instance's scale along each of its own axes, so a rotated
#   or scaled copy reports its real size. They are not world bounds.
#
# =============================================================================

module Na__AgentOutliner
    module Na__Walker

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_KIND_GROUP     = 'g'.freeze unless defined?(NA_KIND_GROUP)
        NA_KIND_COMPONENT = 'c'.freeze unless defined?(NA_KIND_COMPONENT)
        NA_KIND_IMAGE     = 'i'.freeze unless defined?(NA_KIND_IMAGE)
        NA_KIND_SECTION   = 's'.freeze unless defined?(NA_KIND_SECTION)
        NA_ROOT_KEY       = 'root'.freeze unless defined?(NA_ROOT_KEY)

        NA_TYPE_NAMES     = { 'g' => 'Group', 'c' => 'Component', 'i' => 'Image', 's' => 'Section Plane' }.freeze unless defined?(NA_TYPE_NAMES)
        NA_GENERIC_NAME   = /\A(?:Group|Component|Image)(?:#\d+)?\z/.freeze unless defined?(NA_GENERIC_NAME)
        NA_MM_PER_INCH    = 25.4 unless defined?(NA_MM_PER_INCH)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | What Counts as a Row
# -----------------------------------------------------------------------------

        # FUNCTION | The Row Kind of an Entity ('g', 'c', 'i', 's') or nil
        # ------------------------------------------------------------
        def self.Na__Walker__Kind(entity)
            case entity
            when Sketchup::Group             then NA_KIND_GROUP
            when Sketchup::ComponentInstance then NA_KIND_COMPONENT
            when Sketchup::Image             then NA_KIND_IMAGE
            when Sketchup::SectionPlane      then NA_KIND_SECTION
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Container's Key: 'root' for the Model, Else Its Definition's
        # ------------------------------------------------------------
        def self.Na__Walker__ContainerKey(container)
            return NA_ROOT_KEY if container.nil? || container.is_a?(Sketchup::Model)

            self.Na__Walker__DefKey(container)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Definition's Key (its persistent id; entityID before 2020.1)
        # ------------------------------------------------------------
        def self.Na__Walker__DefKey(definition)
            return nil unless definition

            pid = definition.respond_to?(:persistent_id) ? definition.persistent_id.to_i : 0
            pid > 0 ? "d#{pid}" : "e#{definition.entityID}"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Structure Walk
# -----------------------------------------------------------------------------

        # FUNCTION | Walk the Whole Structure
        # ------------------------------------------------------------
        # Returns {
        #   'children' => { container key => [entities in that container] },
        #   'defs'     => { def key => definition },
        #   'scanned'  => true when images and section planes were scanned,
        #   'capped'   => true when the scan stopped at its entity limit
        # }
        # Only containers reachable from the model root matter to the tree, but
        # every container is listed: the page walks down from the root.
        def self.Na__Walker__Structure(model, scan: false)
            children = Hash.new { |hash, key| hash[key] = [] }
            defs     = {}

            model.definitions.each do |definition|
                next if definition.image?

                key = self.Na__Walker__DefKey(definition)
                defs[key] = definition
                definition.instances.each do |instance|
                    next unless instance.valid?

                    children[self.Na__Walker__ContainerKey(instance.parent)] << instance
                end
            end

            capped = false
            if scan
                capped = self.na_scan_images_and_sections(model, defs, children)
            end

            { 'children' => children, 'defs' => defs, 'scanned' => scan, 'capped' => capped }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Images and Section Planes Directly in One Container
        # ------------------------------------------------------------
        def self.Na__Walker__ScanContainer(entities)
            entities.select { |entity| entity.is_a?(Sketchup::Image) || entity.is_a?(Sketchup::SectionPlane) }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rows (what the dialog shows for one object)
# -----------------------------------------------------------------------------

        # FUNCTION | One Object's Row
        # ------------------------------------------------------------
        # context = { layer0:, prefixes:, seen: } (Na__Payloads.Na__Payload__Context),
        # built once per payload. Short keys keep a big model's payload small:
        #   p pid, k kind, n name, dn display name, d definition key,
        #   t tag ('' for Untagged; the page knows which tags are shown),
        #   m material, h hidden, l locked, sz [w, d, h] mm, pre the naming
        #   prefix it carries, sa section plane active, plus the notes summary
        #   keys from Na__Notes.Na__Notes__RowSummary.
        def self.Na__Walker__Row(entity, context)
            kind = self.Na__Walker__Kind(entity)
            row = {
                'p'  => entity.persistent_id,
                'k'  => kind,
                'n'  => self.Na__Walker__Name(entity),
                'dn' => self.Na__Walker__DisplayName(entity),
                'd'  => (kind == NA_KIND_GROUP || kind == NA_KIND_COMPONENT) ? self.Na__Walker__DefKey(entity.definition) : nil,
                't'  => self.Na__Walker__TagName(entity.layer, context[:layer0]),
                'm'  => self.Na__Walker__MaterialName(entity),
                'h'  => entity.hidden? ? true : false,
                'l'  => self.Na__Walker__Locked?(entity),
                'sz' => self.Na__Walker__SizeMm(entity)
            }
            row['pre'] = self.Na__Walker__PrefixLabel(row['n'], context[:prefixes])
            row['sa']  = entity.active? ? true : false if kind == NA_KIND_SECTION && entity.respond_to?(:active?)
            row.merge!(Na__AgentOutliner::Na__Notes.Na__Notes__RowSummary(entity, context[:seen]))
            row
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Definition's Row (the children are filled in by the caller)
        # ------------------------------------------------------------
        def self.Na__Walker__DefRow(definition)
            {
                'k'  => self.Na__Walker__DefKey(definition),
                'n'  => definition.name.to_s,
                'g'  => definition.group? ? true : false,
                'ni' => definition.instances.length,
                'ds' => definition.description.to_s[0, 200]
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name an Object Itself Carries ('' when none)
        # ------------------------------------------------------------
        def self.Na__Walker__Name(entity)
            case entity
            when Sketchup::Group, Sketchup::ComponentInstance
                entity.name.to_s
            when Sketchup::SectionPlane
                entity.respond_to?(:name) ? entity.name.to_s : ''
            else
                ''
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Name the Outliner Shows (falls back like SketchUp's own)
        # ------------------------------------------------------------
        def self.Na__Walker__DisplayName(entity)
            name = self.Na__Walker__Name(entity)
            case entity
            when Sketchup::Group
                name.empty? ? 'Group' : name
            when Sketchup::ComponentInstance
                name.empty? ? entity.definition.name.to_s : name
            when Sketchup::Image
                file = File.basename(entity.path.to_s)
                file.empty? ? 'Image' : "Image: #{file}"
            when Sketchup::SectionPlane
                symbol = entity.respond_to?(:symbol) ? entity.symbol.to_s : ''
                return name unless name.empty?

                symbol.empty? ? 'Section Plane' : "Section Plane #{symbol}"
            else
                entity.typename.to_s
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Name Only SketchUp's Placeholder? (Group, Component#3)
        # ------------------------------------------------------------
        def self.Na__Walker__GenericName?(name)
            text = name.to_s.strip
            text.empty? || text.match?(NA_GENERIC_NAME)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Tag's Name as SketchUp Shows It ('' for Untagged)
        # ------------------------------------------------------------
        def self.Na__Walker__TagName(layer, layer0)
            return '' if layer.nil? || layer.equal?(layer0) || layer == layer0

            layer.respond_to?(:display_name) ? layer.display_name.to_s : layer.name.to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Tag (and Every Tag Folder Above It) Shown?
        # ------------------------------------------------------------
        def self.Na__Walker__TagShown?(layer)
            return true if layer.nil?
            return false unless layer.visible?

            folder = layer.respond_to?(:folder) ? layer.folder : nil
            guard = 0
            while folder && guard < 32
                return false unless folder.visible?

                folder = folder.respond_to?(:folder) ? folder.folder : nil
                guard += 1
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Material's Name ('' for the default material)
        # ------------------------------------------------------------
        def self.Na__Walker__MaterialName(entity)
            return '' unless entity.respond_to?(:material)

            material = entity.material
            material ? material.display_name.to_s : ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is It Locked? (only groups and components lock)
        # ------------------------------------------------------------
        def self.Na__Walker__Locked?(entity)
            return false unless entity.respond_to?(:locked?)

            entity.locked? ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Object's Own Size in mm [width, depth, height]
        # ------------------------------------------------------------
        def self.Na__Walker__SizeMm(entity)
            case entity
            when Sketchup::Group, Sketchup::ComponentInstance
                bounds = entity.definition.bounds
                return nil if bounds.empty?

                scales = self.Na__Walker__AxisScales(entity.transformation)
                [
                    (bounds.width.to_f  * scales[0] * NA_MM_PER_INCH).round(1),
                    (bounds.height.to_f * scales[1] * NA_MM_PER_INCH).round(1),
                    (bounds.depth.to_f  * scales[2] * NA_MM_PER_INCH).round(1)
                ]
            when Sketchup::Image
                [(entity.width.to_f * NA_MM_PER_INCH).round(1), (entity.height.to_f * NA_MM_PER_INCH).round(1), 0.0]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Scale Along Each of an Instance's Own Axes
        # ------------------------------------------------------------
        # BoundingBox#width/height/depth are its extents along x, y and z. The
        # transformation's columns are the instance's axes in its parent; their
        # lengths (over the homogeneous w) are the scale factors.
        def self.Na__Walker__AxisScales(transformation)
            a = transformation.to_a
            w = a[15].to_f
            w = 1.0 if w.abs < 1.0e-12
            [
                Math.sqrt(a[0]**2 + a[1]**2 + a[2]**2) / w,
                Math.sqrt(a[4]**2 + a[5]**2 + a[6]**2) / w,
                Math.sqrt(a[8]**2 + a[9]**2 + a[10]**2) / w
            ].map(&:abs)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Naming Prefix a Name Carries ('' when none)
        # ------------------------------------------------------------
        # The longest label wins, so CAD__SideElevation__Left is found before a
        # shorter CAD__SideElevation would be.
        def self.Na__Walker__PrefixLabel(name, prefixes)
            entry = Na__AgentOutliner::Na__Naming.Na__Naming__MatchPrefix(name, prefixes)
            entry ? entry['label'] : ''
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fingerprints (what the change tracker compares)
# -----------------------------------------------------------------------------

        # FUNCTION | An Object's Fingerprint: One Value per Tracked Field
        # ------------------------------------------------------------
        # Field order matches NA_FINGERPRINT_FIELDS. The transformation is
        # rounded so floating noise never reads as a move.
        NA_FINGERPRINT_FIELDS = %w[name tag material visibility lock transform definition].freeze unless defined?(NA_FINGERPRINT_FIELDS)

        def self.Na__Walker__Fingerprint(entity)
            transform = entity.respond_to?(:transformation) ? self.na_matrix_text(entity.transformation) : ''
            transform = "#{transform}|#{entity.path}" if entity.is_a?(Sketchup::Image)
            definition = entity.respond_to?(:definition) && !entity.is_a?(Sketchup::Image) ? self.Na__Walker__DefKey(entity.definition) : ''
            layer = entity.layer
            [
                self.Na__Walker__Name(entity),
                layer ? layer.name.to_s : '',
                self.Na__Walker__MaterialName(entity),
                entity.hidden? ? '1' : '0',
                self.Na__Walker__Locked?(entity) ? '1' : '0',
                transform,
                definition.to_s
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Fields Differ Between Two Fingerprints
        # ------------------------------------------------------------
        def self.Na__Walker__ChangedFields(before, after)
            return [] if before.nil? || after.nil?

            NA_FINGERPRINT_FIELDS.each_index.select { |index| before[index] != after[index] }.map { |index| NA_FINGERPRINT_FIELDS[index] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Definition's Cheap Signature (count and extents)
        # ------------------------------------------------------------
        # Constant time: Entities#length and the cached bounds. Catches added or
        # erased geometry and anything that moves the extents; the tracker's
        # precise signature covers edits inside the group Adam has open.
        def self.Na__Walker__DefSignature(definition)
            bounds = definition.bounds
            extent = bounds.empty? ? '' : (bounds.min.to_a + bounds.max.to_a).map { |value| value.to_f.round(4) }.join(',')
            "#{definition.entities.length}|#{extent}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Definition's Precise Signature (every edge and face)
        # ------------------------------------------------------------
        # Used only for the definition Adam is editing inside, where a vertex
        # move changes no count and may change no extent. Over the limit it
        # falls back to the cheap signature.
        def self.Na__Walker__PreciseSignature(definition, limit)
            entities = definition.entities
            return self.Na__Walker__DefSignature(definition) if entities.length > limit

            crc = 0
            entities.each do |entity|
                text = case entity
                       when Sketchup::Edge
                           "E#{entity.start.position.to_a.map { |v| v.to_f.round(4) }.join(',')}>#{entity.end.position.to_a.map { |v| v.to_f.round(4) }.join(',')}" \
                               "#{self.na_material_key(entity)}#{entity.soft? ? 's' : ''}#{entity.smooth? ? 'm' : ''}#{entity.hidden? ? 'h' : ''}"
                       when Sketchup::Face
                           "F#{entity.vertices.length}#{self.na_material_key(entity)}/#{entity.back_material ? entity.back_material.name : ''}#{entity.hidden? ? 'h' : ''}"
                       when Sketchup::Group, Sketchup::ComponentInstance
                           "I#{entity.persistent_id}#{self.na_matrix_text(entity.transformation)}"
                       else
                           "O#{entity.typename}"
                       end
                crc = Zlib.crc32(text, crc)
            end
            "#{entities.length}|#{crc}"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Paths (where an object sits)
# -----------------------------------------------------------------------------

        # FUNCTION | The First Path From the Root to an Object
        # ------------------------------------------------------------
        # An object inside a component placed several times has several paths;
        # this follows the first placed instance of each definition upwards.
        # Returns [root-level instance, ..., entity], or nil when unplaced.
        def self.Na__Walker__FirstPath(entity)
            path  = [entity]
            guard = 0
            container = entity.parent
            while container.is_a?(Sketchup::ComponentDefinition) && guard < 64
                holder = container.instances.find(&:valid?)
                return nil unless holder

                path.unshift(holder)
                container = holder.parent
                guard += 1
            end
            container.is_a?(Sketchup::Model) ? path : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Path as [{id, name}] for Agents and the Copy for Agent Text
        # ------------------------------------------------------------
        def self.Na__Walker__PathSummary(path)
            Array(path).map { |item| { 'id' => item.persistent_id, 'name' => self.Na__Walker__DisplayName(item) } }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # Images and section planes from every container that is placed (or the
        # root), stopping at the entity limit so a gigantic model stays usable.
        def self.na_scan_images_and_sections(model, defs, children)
            limit   = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('scan_entity_limit', 600_000).to_i
            seen    = 0
            capped  = false
            show_images   = Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('outliner', 'show_images') != false
            show_sections = Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('outliner', 'show_sections') != false
            return false unless show_images || show_sections

            containers = [[NA_ROOT_KEY, model.entities]]
            defs.each do |key, definition|
                next if definition.instances.empty?

                containers << [key, definition.entities]
            end

            containers.each do |key, entities|
                seen += entities.length
                if seen > limit
                    capped = true
                    break
                end

                entities.each do |entity|
                    if (show_images && entity.is_a?(Sketchup::Image)) || (show_sections && entity.is_a?(Sketchup::SectionPlane))
                        children[key] << entity
                    end
                end
            end
            capped
        end

        def self.na_matrix_text(transformation)
            transformation.to_a.map { |value| value.to_f.round(6) }.join(',')
        end

        def self.na_material_key(entity)
            material = entity.material
            material ? "@#{material.name}" : ''
        end

# endregion -------------------------------------------------------------------

    end # module Na__Walker
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
