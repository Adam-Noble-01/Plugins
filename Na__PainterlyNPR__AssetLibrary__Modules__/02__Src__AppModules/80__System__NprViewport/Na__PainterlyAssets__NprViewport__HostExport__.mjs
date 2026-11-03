// =============================================================================
// NA PAINTERLYNPR ASSETS - NPR VIEWPORT - HOST, NPR EXPORT
// =============================================================================
//
// FILE       : Na__PainterlyAssets__NprViewport__HostExport__.mjs
// NAMESPACE  : Na__NprHost
// MODULE     : NPR Viewport - Host, Export
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Draw NPR Export's pictures in the NPR Viewport's own engine:
//              each one with its camera, by the engine's own still export, and
//              hand each file to the plugin's local server, which keeps it for
//              Ruby to put where it belongs
// CREATED    : 01-Nov-2026 (v0.3.0)
//
// DESCRIPTION:
// - THE PICTURE IS THE ENGINE'S: PainterlyNPR__Export__Png (86) re-runs every
//   pass at the export's pixels ('dpi:300', 'pdf:300', 'calibration:pdf:300'),
//   the same drawing sharper, and gives a PNG carrying its print size or a
//   true-size PDF. Nothing of it is copied here.
// - THE ENGINE ENDS IN A BROWSER DOWNLOAD (an <a download> clicked on a blob:
//   URL), which SketchUp's browser cannot make. So for the one call the
//   anchor's click is caught: the blob and the engine's own file name are
//   kept, and nothing is downloaded. An engine that saves some other way
//   gives no file, and the item says so.
// - A JPEG is made from the engine's PNG by the browser (the picture's own
//   pixels), with its resolution written in the JFIF header.
// - EACH FILE GOES TO THE SERVER (POST /__na/export with the session's token)
//   as <job>__<item>.<ext>; Ruby is told item by item (exportItem) and once at
//   the end (exportDone). Cancel stops after the picture being drawn.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Module Imports - the Engine (PainterlyNPR, from the cache)
// -----------------------------------------------------------------------------

    import * as StillRender from 'PainterlyNPR/86__Export__StillRender/PainterlyNPR__Export__Png__.mjs';

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Constants and State
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | The Engine's Status Line, Read When It Gave No File
    // ------------------------------------------------------------
    const Na__NprExport__ENGINE_STATUS  =  'PainterlyNPR__App__Status';
    // ------------------------------------------------------------

    // MODULE VARIABLES | The Job Being Drawn
    // ------------------------------------------------------------
    const Na__NprExport__State  =  {
        job        :  null,
        cancelled  :  false,
    };
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | A Job
// -----------------------------------------------------------------------------

    // FUNCTION | Draw a Job's Pictures, One After Another
    // ------------------------------------------------------------
    // message: { Job, Token, Upload, Items: [{ Id, Label, Which, Format, Quality, Dpi, Camera, Points }] }
    // hooks:   { Camera(c), Points(set), PointsDone(), SceneSettled(), Say(text, level), Action(name, payload) }
    async function Na__NprExport__Run(message, hooks) {
        const S      =  Na__NprExport__State;
        const items  =  Array.isArray(message.Items) ? message.Items : [];
        if (S.job) return hooks.Action('exportDone', { Job: message.Job, Ok: false, Message: 'The NPR Viewport is already drawing an export.' });
        S.job        =  message.Job;
        S.cancelled  =  false;
        let done  =  0;
        let failed  =  0;
        let reason  =  '';
        try {
            if (typeof StillRender.PainterlyNPR__Export__Png !== 'function') throw new Error('this PainterlyNPR has no still export (PainterlyNPR__Export__Png)');
            await hooks.SceneSettled();
            for (let index = 0; index < items.length; index++) {
                if (S.cancelled) break;
                const item  =  items[index];
                hooks.Say(`Exporting ${item.Label} (${index + 1} of ${items.length})`, 'busy');
                const result  =  await Na__NprExport__Item(message, item, hooks);
                if (result.Ok) done++;
                else failed++;
                hooks.Action('exportItem', Object.assign({ Job: message.Job, Id: item.Id }, result));
            }
        } catch (error) {
            reason  =  error.message;
            console.error('[Na NPR Export]', error);
        } finally {
            S.job  =  null;
            if (hooks.PointsDone) hooks.PointsDone();                            // <-- The sheet's own points back, whatever a scene's picture drew with
            hooks.Action('exportDone',{ Job: message.Job, Ok: !reason && failed === 0 && !S.cancelled, Cancelled: S.cancelled, Done: done, Failed: failed, Message: reason });
        }
        return null;
    }
    // ------------------------------------------------------------


    // FUNCTION | Stop After the Picture Being Drawn
    // ------------------------------------------------------------
    function Na__NprExport__Cancel(job) {
        const S  =  Na__NprExport__State;
        if (S.job && (!job || job === S.job)) S.cancelled  =  true;
    }
    // ------------------------------------------------------------

    function Na__NprExport__Busy() {
        return Na__NprExport__State.job !== null;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | One Picture
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Draw One, Make It a JPEG If Asked, Hand It to the Server: { Ok, File, Bytes, Width, Height, EngineName, Seconds } or { Ok: false, Message }
    // ------------------------------------------------------------
    async function Na__NprExport__Item(message, item, hooks) {
        const started  =  performance.now();
        try {
            if (item.Points && hooks.Points) hooks.Points(item.Points);
            if (item.Camera) hooks.Camera(item.Camera);
            const caught  =  await Na__NprExport__Catch(() => StillRender.PainterlyNPR__Export__Png(String(item.Which)));
            if (!caught) throw new Error(Na__NprExport__EngineReason());
            const size  =  /__(\d+)x(\d+)__/.exec(caught.Name);
            let blob    =  caught.Blob;
            let ext     =  /\.pdf$/i.test(caught.Name) ? 'pdf' : 'png';
            if (item.Format === 'jpeg' && ext === 'png') {
                blob  =  await Na__NprExport__Jpeg(blob, Number(item.Quality) || 0.92, Number(item.Dpi) || 0);
                ext   =  'jpg';
            }
            const file   =  `${message.Job}__${item.Id}.${ext}`;
            const reply  =  await fetch(message.Upload, {
                method   :  'POST',
                headers  :  { 'X-Na-Token': message.Token, 'X-Na-File': file, 'Content-Type': 'application/octet-stream' },
                body     :  blob,
            });
            const answer  =  await reply.json().catch(() => ({}));
            if (reply.status === 403) throw new Error('the plugin\'s server did not know this window (close the NPR Viewport and open it again)');
            if (!reply.ok) throw new Error(answer.error || `the plugin's server answered ${reply.status}`);
            return {
                Ok          :  true,
                File        :  file,
                Bytes       :  blob.size,
                Width       :  size ? Number(size[1]) : 0,
                Height      :  size ? Number(size[2]) : 0,
                EngineName  :  caught.Name,
                Seconds     :  Math.round((performance.now() - started) / 100) / 10,
            };
        } catch (error) {
            console.error(`[Na NPR Export] ${item.Label}:`, error);
            return { Ok: false, Message: error.message };
        }
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Engine's Download Caught for One Call: { Blob, Name } or null
    // ------------------------------------------------------------
    async function Na__NprExport__Catch(run) {
        const proto  =  HTMLAnchorElement.prototype;
        const click  =  proto.click;
        let caught   =  null;
        proto.click  =  function () {
            if (!caught && this.download && String(this.href).startsWith('blob:')) {
                caught  =  { Url: this.href, Name: this.download };
                return undefined;
            }
            return click.call(this);
        };
        try {
            await run();
        } finally {
            proto.click  =  click;
        }
        if (!caught) return null;
        const blob  =  await (await fetch(caught.Url)).blob();                  // <-- Before the engine lets the URL go (4 s)
        return { Blob: blob, Name: caught.Name };
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | Why the Engine Gave No File (its own status line, in our words)
    // ------------------------------------------------------------
    function Na__NprExport__EngineReason() {
        const line  =  document.getElementById(Na__NprExport__ENGINE_STATUS);
        const text  =  line ? line.textContent.trim() : '';
        const said  =  /^Export failed\s*\W\s*(.*?)\.?\s*(Try 1x\.?)?$/i.exec(text);
        if (said && said[1]) return `the engine could not draw it (${said[1]}). A lower resolution needs less of the graphics card's memory`;
        return 'the engine gave no picture';
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Engine's PNG as a JPEG, Its Resolution in the JFIF Header
    // ------------------------------------------------------------
    async function Na__NprExport__Jpeg(png, quality, dpi) {
        const bitmap  =  await createImageBitmap(png);
        const canvas  =  document.createElement('canvas');
        canvas.width   =  bitmap.width;
        canvas.height  =  bitmap.height;
        const ctx  =  canvas.getContext('2d');
        ctx.fillStyle  =  '#ffffff';                                             // <-- A JPEG has no transparency: anything clear lands on white
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(bitmap, 0, 0);
        bitmap.close();
        const blob  =  await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', Math.max(0.5, Math.min(1, quality))));
        canvas.width  =  0;
        canvas.height =  0;
        if (!blob) throw new Error('the browser could not make a JPEG this size');
        const bytes  =  new Uint8Array(await blob.arrayBuffer());
        const jfif   =  bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF && bytes[3] === 0xE0 &&
                        bytes[6] === 0x4A && bytes[7] === 0x46 && bytes[8] === 0x49 && bytes[9] === 0x46 && bytes[10] === 0;
        if (jfif && dpi > 0) {
            const d  =  Math.max(1, Math.min(65535, Math.round(dpi)));
            bytes[13]  =  1;                                                     // <-- Dots per inch
            bytes[14]  =  d >> 8;
            bytes[15]  =  d & 255;
            bytes[16]  =  d >> 8;
            bytes[17]  =  d & 255;
        }
        return new Blob([bytes], { type: 'image/jpeg' });
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Exports
// -----------------------------------------------------------------------------

    export {
        Na__NprExport__Busy,
        Na__NprExport__Cancel,
        Na__NprExport__Run,
    };

// endregion -------------------------------------------------------------------
