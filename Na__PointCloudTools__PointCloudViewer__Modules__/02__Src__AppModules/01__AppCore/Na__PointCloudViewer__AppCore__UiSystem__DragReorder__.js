// =============================================================================
// NA POINT CLOUD VIEWER - APP CORE - UI SYSTEM - DRAG TO REORDER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__AppCore__UiSystem__DragReorder__.js
// NAMESPACE  : window.Na__PointCloudViewer__DragReorder
// PURPOSE    : Drag a list row by its grip to a new place. Used by the clip
//              scenes (Clipping tab) and the point cloud scenes (Scenes tab).
//
// HOW IT FEELS: press a grip and its row lifts and follows the pointer; the
//   other rows slide out of its way as it passes their middles; the list
//   scrolls when the pointer nears the top or bottom of the panel. Letting go
//   drops it there. Esc puts everything back. A grip that has the focus moves
//   its row one place with the up and down arrow keys.
//
// HOW IT SAVES: only a drop that changes the order calls onReorder(ids,
//   movedId) with every row's id, top to bottom. Ruby saves that as one
//   undoable step and pushes state, which repaints the list in that order.
//
// CONTRACT WITH THE TAB:
//   - rows carry data-na-sort-id, grips carry data-na-sort-handle (na_grip
//     makes one). Rows that are not sortable (Full Cloud, notes) stay put.
//   - listeners are delegated to the list, so a repaint never loses them.
//   - while na_is_dragging() the tab must not rebuild the list; onEnd(changed)
//     says when it may again. After a change Ruby's push repaints it anyway.
//   - call na_after_render() after each repaint, so a grip moved with the
//     arrow keys keeps the focus.
//
// =============================================================================

(function () {
    'use strict';

    var DragReorder = {};

    var NA_EDGE_PX   = 40;      // auto scroll band at the top and bottom of the panel
    var NA_SCROLL_PX = 14;      // per frame, at the very edge
    var NA_SLIDE_MS  = 140;     // rows sliding out of the way, and the drop settling

    // -------------------------------------------------------------------------
    // REGION | Grip
    // -------------------------------------------------------------------------

    DragReorder.na_grip = function (name) {
        var grip = document.createElement('button');
        grip.type = 'button';
        grip.className = 'na-grip';
        grip.setAttribute('data-na-sort-handle', '');
        grip.title = 'Drag to reorder, or use the up and down arrow keys';
        grip.setAttribute('aria-label', 'Move ' + (name || 'this row') + '. Drag it, or use the up and down arrow keys.');
        return grip;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Attach
    // -------------------------------------------------------------------------

    // options: canDrag() -> bool, onReorder(ids, movedId), onEnd(changed)
    DragReorder.na_attach = function (list, options) {
        var drag      = null;      // the drag in progress
        var refocusId = null;      // grip to focus after the next repaint

        function na_items() {
            return Array.prototype.filter.call(list.children, function (el) {
                return el.hasAttribute('data-na-sort-id');
            });
        }

        function na_ids() {
            return na_items().map(function (el) { return el.getAttribute('data-na-sort-id'); });
        }

        function na_can_drag() {
            return !options.canDrag || options.canDrag();
        }

        // The nearest ancestor that actually scrolls: the tab panel.
        function na_scroller() {
            var el = list.parentElement;
            while (el && el !== document.body) {
                var overflow = window.getComputedStyle(el).overflowY;
                if ((overflow === 'auto' || overflow === 'scroll') && el.scrollHeight > el.clientHeight) return el;
                el = el.parentElement;
            }
            return null;
        }

        // Puts the row in front of beforeNode (null = after the last sortable
        // row) and slides the rows that moved from where they were (FLIP).
        function na_move_slot(item, beforeNode) {
            if (beforeNode === item || item.nextSibling === beforeNode) return;
            var others = na_items().filter(function (el) { return el !== item; });
            var tops = others.map(function (el) { return el.getBoundingClientRect().top; });
            list.insertBefore(item, beforeNode);
            others.forEach(function (el, index) {
                var dy = tops[index] - el.getBoundingClientRect().top;
                if (!dy) return;
                el.style.transition = 'none';
                el.style.transform = 'translateY(' + dy + 'px)';
                void el.offsetHeight;
                el.style.transition = 'transform ' + NA_SLIDE_MS + 'ms ease';
                el.style.transform = '';
            });
        }

        function na_after_last(items) {
            return items.length ? items[items.length - 1].nextSibling : null;
        }

        // The slot under the pointer: in front of the first other row whose
        // middle is below it.
        function na_place(clientY) {
            var item = drag.item;
            var others = na_items().filter(function (el) { return el !== item; });
            for (var i = 0; i < others.length; i += 1) {
                var rect = others[i].getBoundingClientRect();
                if (clientY < rect.top + rect.height / 2) {
                    na_move_slot(item, others[i]);
                    return;
                }
            }
            if (others.length) na_move_slot(item, na_after_last(others));
        }

        // The lifted row stays under the pointer, but never leaves the list.
        function na_follow(clientY) {
            var item = drag.item;
            item.style.transform = '';
            var natural = item.getBoundingClientRect();
            var bounds = list.getBoundingClientRect();
            var top = clientY - drag.grabOffset;
            top = Math.max(bounds.top, Math.min(bounds.bottom - natural.height, top));
            item.style.transform = 'translateY(' + Math.round(top - natural.top) + 'px)';
        }

        function na_tick() {
            if (!drag) return;
            var box = drag.scroller ? drag.scroller.getBoundingClientRect() : null;
            if (box) {
                var speed = 0;
                if (drag.lastY < box.top + NA_EDGE_PX) {
                    speed = -Math.ceil(NA_SCROLL_PX * (1 - Math.max(0, drag.lastY - box.top) / NA_EDGE_PX));
                } else if (drag.lastY > box.bottom - NA_EDGE_PX) {
                    speed = Math.ceil(NA_SCROLL_PX * (1 - Math.max(0, box.bottom - drag.lastY) / NA_EDGE_PX));
                }
                if (speed) {
                    var before = drag.scroller.scrollTop;
                    drag.scroller.scrollTop = before + speed;
                    if (drag.scroller.scrollTop !== before) {
                        na_place(drag.lastY);
                        na_follow(drag.lastY);
                    }
                }
            }
            drag.frame = window.requestAnimationFrame(na_tick);
        }

        function na_on_key(event) {
            if (event.key !== 'Escape' || !drag) return;
            event.preventDefault();
            event.stopPropagation();
            na_finish(false);
        }

        function na_finish(commit) {
            var done = drag;
            drag = null;
            window.cancelAnimationFrame(done.frame);
            document.removeEventListener('keydown', na_on_key, true);
            try { done.handle.releasePointerCapture(done.pointerId); } catch (ignore) { /* already released */ }
            list.classList.remove('na-sort-list--active');
            done.item.classList.remove('na-sort-item--dragging');

            // Esc, a cancelled pointer, or a list that went away: put it back
            if (!commit && done.item.isConnected) {
                var current = na_items();
                if (current.length) {
                    var marker = document.createComment('na-sort');
                    list.insertBefore(marker, current[0]);
                    done.startItems.forEach(function (el) { if (el.isConnected) list.insertBefore(el, marker); });
                    list.removeChild(marker);
                }
            }
            na_items().forEach(function (el) {
                if (el === done.item) return;
                el.style.transition = '';
                el.style.transform = '';
            });
            // The dropped row settles into its slot
            done.item.style.transition = 'transform ' + NA_SLIDE_MS + 'ms ease';
            done.item.style.transform = '';
            window.setTimeout(function () { done.item.style.transition = ''; }, NA_SLIDE_MS + 20);

            var ids = na_ids();
            var changed = commit && done.item.isConnected && ids.join('\n') !== done.startIds.join('\n');
            if (changed) options.onReorder(ids, done.item.getAttribute('data-na-sort-id'));
            if (options.onEnd) options.onEnd(changed);
        }

        list.addEventListener('pointerdown', function (event) {
            if (drag || event.button !== 0) return;
            var handle = event.target.closest ? event.target.closest('[data-na-sort-handle]') : null;
            if (!handle || !list.contains(handle)) return;
            var item = handle.closest('[data-na-sort-id]');
            if (!item || item.parentNode !== list || !na_can_drag()) return;
            event.preventDefault();
            var rect = item.getBoundingClientRect();
            drag = {
                item:       item,
                handle:     handle,
                pointerId:  event.pointerId,
                grabOffset: event.clientY - rect.top,
                lastY:      event.clientY,
                startIds:   na_ids(),
                startItems: na_items(),
                scroller:   na_scroller(),
                frame:      0
            };
            try { handle.setPointerCapture(event.pointerId); } catch (ignore) { /* no capture: moves still bubble */ }
            handle.focus();
            item.style.transition = 'none';
            item.classList.add('na-sort-item--dragging');
            list.classList.add('na-sort-list--active');
            document.addEventListener('keydown', na_on_key, true);
            drag.frame = window.requestAnimationFrame(na_tick);
        });

        list.addEventListener('pointermove', function (event) {
            if (!drag || event.pointerId !== drag.pointerId) return;
            drag.lastY = event.clientY;
            na_place(event.clientY);
            na_follow(event.clientY);
        });

        list.addEventListener('pointerup', function (event) {
            if (drag && event.pointerId === drag.pointerId) na_finish(true);
        });

        list.addEventListener('pointercancel', function (event) {
            if (drag && event.pointerId === drag.pointerId) na_finish(false);
        });

        // A grip with the focus: the arrow keys move its row one place.
        list.addEventListener('keydown', function (event) {
            if (drag || (event.key !== 'ArrowUp' && event.key !== 'ArrowDown')) return;
            var handle = event.target.closest ? event.target.closest('[data-na-sort-handle]') : null;
            if (!handle || !list.contains(handle)) return;
            var item = handle.closest('[data-na-sort-id]');
            if (!item || item.parentNode !== list || !na_can_drag()) return;
            event.preventDefault();
            var items = na_items();
            var from = items.indexOf(item);
            var to = from + (event.key === 'ArrowUp' ? -1 : 1);
            if (to < 0 || to >= items.length) return;
            na_move_slot(item, event.key === 'ArrowUp' ? items[to] : items[to].nextSibling);
            refocusId = item.getAttribute('data-na-sort-id');
            handle.focus();
            options.onReorder(na_ids(), refocusId);
        });

        return {
            na_is_dragging: function () { return !!drag; },
            na_after_render: function () {
                if (!refocusId) return;
                var wanted = refocusId;
                refocusId = null;
                var item = na_items().filter(function (el) { return el.getAttribute('data-na-sort-id') === wanted; })[0];
                var grip = item ? item.querySelector('[data-na-sort-handle]') : null;
                if (grip) grip.focus();
            }
        };
    };

    // endregion ----------------------------------------------------------------

    window.Na__PointCloudViewer__DragReorder = DragReorder;
})();
