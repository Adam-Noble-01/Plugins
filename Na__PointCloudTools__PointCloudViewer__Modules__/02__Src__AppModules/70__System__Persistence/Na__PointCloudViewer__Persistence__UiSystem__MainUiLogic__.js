// =============================================================================
// NA POINT CLOUD VIEWER - PERSISTENCE - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Persistence__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__LinkCard
// PURPOSE    : What the model has saved, and this computer's backup of it:
//              the backup note and Restore on the View tab's Point Clouds card,
//              and the Settings tab's section (backups folder, Remove Point
//              Cloud Data From Model). Everything here is an explicit button
//              press; nothing loads on its own. Reload and Locate LAS are on
//              each cloud's own row (the CloudSet script).
//
// =============================================================================

(function () {
    'use strict';

    var LinkCard = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;

    var NA_CONFIRM_MS = 3000;
    var na_link = null;
    var na_remove_armed = false;
    var na_remove_timer = null;

    function na_el(id) { return document.getElementById(id); }

    // -------------------------------------------------------------------------
    // REGION | Backup Note (View tab, Point Clouds card)
    // -------------------------------------------------------------------------

    function na_names_text(names) {
        if (!names || !names.length) return 'its point clouds';
        if (names.length === 1) return names[0];
        return names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
    }

    function na_render_card(link) {
        var backup = link.backup || {};
        var only   = link.state === 'backupOnly';
        var newer  = link.state === 'linked' && backup.newer;
        var note   = na_el('na-link-backup-note');
        note.classList.toggle('na-hidden', !(only || newer));
        if (only) {
            note.textContent = (link.unreadable ? 'The point cloud records in this model could not be read. ' : 'No point cloud is saved in this model. ') +
                               'This computer has a backup of its setup for ' + na_names_text(backup.cloudNames) + ', saved ' + backup.savedText + '. ' +
                               'Restore writes it into the model; Undo takes it out again.';
        } else if (newer) {
            note.textContent = 'This computer holds later changes to the clouds\' positions or clip boxes (saved ' + backup.savedText + ') than the copy in the model. ' +
                               'That happens when SketchUp closes without saving. Restore them first, or carry on with the model\'s copy.';
        } else {
            note.textContent = '';
        }
        var restore = na_el('na-link-restore');
        restore.classList.toggle('na-hidden', !(only || newer));
        restore.textContent = only ? 'Restore From Backup' : 'Restore Newer Backup';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Settings Section
    // -------------------------------------------------------------------------

    function na_disarm_remove() {
        if (na_remove_timer) window.clearTimeout(na_remove_timer);
        na_remove_timer = null;
        na_remove_armed = false;
    }

    function na_render_settings(link) {
        var remove = na_el('na-settings-remove-link');
        var hasData = link.state === 'linked';
        if (!hasData) na_disarm_remove();
        remove.disabled = !hasData;
        remove.textContent = na_remove_armed ? 'Click again to remove every cloud (Undo restores them)' : 'Remove Point Cloud Data From Model';
        remove.classList.toggle('na-button--danger', na_remove_armed);
        var count = link.cloudCount || 0;
        var text;
        if (hasData) {
            text = (count === 1 ? 'This model holds one point cloud. ' : 'This model holds ' + count + ' point clouds, each in its own record. ') +
                   (link.backup && link.backup.exists ? 'A backup is on this computer.' : 'No backup on this computer yet; one is made with the next change.');
            if (link.legacy) text += ' Its records were saved by an earlier version of the viewer. They are read as they are, and take the new form (one record per cloud) with the next change you make, in that same Undo step.';
        } else {
            text = link.state === 'backupOnly' ? 'This model has no readable point cloud records, but a backup for it is on this computer.' : 'This model holds no point cloud data.';
        }
        Shell.na_text('na-settings-link-status', text);
    }

    // endregion ----------------------------------------------------------------

    LinkCard.na_render = function (state) {
        if (!state || !state.link) return;
        na_link = state.link;
        na_render_card(na_link);
        na_render_settings(na_link);
    };

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        na_el('na-link-restore').addEventListener('click', function () {
            Bridge.na_call('link_restore_backup', {});
        });
        na_el('na-settings-open-backups').addEventListener('click', function () {
            Bridge.na_call('open_backups_folder', {});
        });
        na_el('na-settings-remove-link').addEventListener('click', function () {
            if (!na_remove_armed) {
                na_remove_armed = true;
                na_remove_timer = window.setTimeout(function () {
                    na_disarm_remove();
                    if (na_link) na_render_settings(na_link);
                }, NA_CONFIRM_MS);
                if (na_link) na_render_settings(na_link);
                return;
            }
            na_disarm_remove();
            Bridge.na_call('link_remove', {});
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', LinkCard.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__LinkCard = LinkCard;
})();
