// =============================================================================
// NA POINT CLOUD VIEWER - PERSISTENCE - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Persistence__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__LinkCard
// PURPOSE    : The "Saved With This Model" card on the View tab (Reload Point
//              Cloud, Locate LAS, Restore Newer Backup) and the matching
//              section on the Settings tab (backups folder, Remove Point Cloud
//              Data From Model). Everything here is an explicit button press;
//              nothing loads on its own.
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
    // REGION | View Tab Card
    // -------------------------------------------------------------------------

    function na_render_card(link) {
        var card = na_el('na-link-card');
        var show = link.state === 'backupOnly' || (link.state === 'linked' && !link.loaded);
        card.classList.toggle('na-hidden', !show);
        if (!show) return;

        var cloudText = link.fileName + ' (' + link.unitLabel + ', ' + link.pointsText + ' points)';
        var summary;
        if (link.state === 'backupOnly') {
            summary = (link.unreadable ? 'The point cloud record in this model could not be read. ' : 'No point cloud link is saved in this model. ') +
                      'This computer has a backup of its setup for ' + cloudText + ', saved ' + link.backup.savedText + '.';
        } else {
            summary = 'This model is linked to ' + cloudText + '.';
            if (link.otherLoaded) summary += ' A different point cloud is loaded now; Reload replaces it.';
        }
        Shell.na_text('na-link-summary', summary);
        Shell.na_text('na-link-position', link.state === 'linked' ? link.positionText : 'Restore writes the backup into the model; Undo takes it out again.');

        var path = na_el('na-link-path');
        path.classList.toggle('na-hidden', link.state !== 'linked');
        path.classList.toggle('na-link-path--missing', !link.foundPath);
        path.textContent = link.foundPath ? 'Found: ' + link.foundPath : 'Not found at: ' + (link.lastPath || '') + '. Use Locate LAS to point to it.';

        var note = na_el('na-link-backup-note');
        var newer = link.state === 'linked' && link.backup && link.backup.newer;
        note.classList.toggle('na-hidden', !newer);
        note.textContent = newer
            ? 'This computer holds later changes to the position or clip box (saved ' + link.backup.savedText + ') than the copy in the model. ' +
              'That happens when SketchUp closes without saving. Restore them first, or Reload to use the model\'s copy.'
            : '';

        var reload = na_el('na-link-reload');
        reload.classList.toggle('na-hidden', link.state !== 'linked');
        reload.disabled = !link.foundPath;
        na_el('na-link-locate').classList.toggle('na-hidden', link.state !== 'linked');

        var restore = na_el('na-link-restore');
        var offerRestore = link.state === 'backupOnly' || newer;
        restore.classList.toggle('na-hidden', !offerRestore);
        restore.textContent = link.state === 'backupOnly' ? 'Restore From Backup' : 'Restore Newer Backup';
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
        remove.textContent = na_remove_armed ? 'Click again to remove (Undo restores it)' : 'Remove Point Cloud Data From Model';
        remove.classList.toggle('na-button--danger', na_remove_armed);
        Shell.na_text('na-settings-link-status', hasData
            ? 'This model is linked to ' + link.fileName + '. ' + (link.backup && link.backup.exists ? 'A backup is on this computer.' : 'No backup on this computer yet; one is made with the next change.')
            : (link.state === 'backupOnly' ? 'This model has no readable link, but a backup for it is on this computer.' : 'This model holds no point cloud data.'));
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
        na_el('na-link-reload').addEventListener('click', function () {
            if (!na_link) return;
            Bridge.na_call_after_paint('link_reload', {}, 'Reloading ' + na_link.fileName, 'Checking the LAS file...');
        });
        na_el('na-link-locate').addEventListener('click', function () {
            Bridge.na_call('link_locate', {});
        });
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
