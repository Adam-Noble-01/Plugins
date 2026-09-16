/* =============================================================================
   NA ARRAY BUILDER TOOLS - UI PREVIEW
   FILE       : Na__ArrayBuilder__UiPreview__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Fit backend-generated envelopes and paths into an SVG viewport.
   ============================================================================= */

const NA_PREVIEW_EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];

// FUNCTION | Project a Three-Dimensional Coordinate Into the Preview Plane
// -----------------------------------------------------------------------------
function Na__Preview__Project(na_point) {
    return [na_point[0] - na_point[1] * 0.55, -(na_point[2] + na_point[1] * 0.35)];
}

export function Na__Preview__Markup(na_data) {
    const na_boxes = (na_data.boxes || []).slice(0, 400);
    const na_path = na_data.path || [];
    const na_points = [...na_boxes.flat(), ...na_path].filter(na_point => Array.isArray(na_point) && na_point.length === 3 && na_point.every(Number.isFinite)).map(Na__Preview__Project);
    if (!na_points.length) return '';
    const na_x = na_points.map(na_point => na_point[0]);
    const na_y = na_points.map(na_point => na_point[1]);
    const na_min_x = Math.min(...na_x), na_min_y = Math.min(...na_y);
    const na_width = Math.max(1, Math.max(...na_x) - na_min_x);
    const na_height = Math.max(1, Math.max(...na_y) - na_min_y);
    const na_scale = Math.min(640 / na_width, 140 / na_height);
    const Na__Preview__Map = na_point => {
        const na_projected = Na__Preview__Project(na_point);
        return [30 + (640 - na_width * na_scale) / 2 + (na_projected[0] - na_min_x) * na_scale,
                25 + (140 - na_height * na_scale) / 2 + (na_projected[1] - na_min_y) * na_scale];
    };
    let na_markup = '<svg viewBox="0 0 700 190" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">';
    if (na_path.length > 1) na_markup += '<polyline points="' + na_path.map(na_point => Na__Preview__Map(na_point).join(',')).join(' ') + '" fill="none" stroke="#9ab6d9" stroke-width="1.2" stroke-dasharray="5 4"/>';
    na_boxes.forEach(na_box => {
        if (na_box.length !== 8 || !na_box.flat().every(Number.isFinite)) return;
        const na_corners = na_box.map(Na__Preview__Map);
        na_markup += '<polygon points="' + [4,5,6,7].map(na_index => na_corners[na_index].join(',')).join(' ') + '" fill="#dce9fb"/>';
        na_markup += '<path d="' + NA_PREVIEW_EDGES.map(([na_a, na_b]) => 'M' + na_corners[na_a].join(',') + 'L' + na_corners[na_b].join(',')).join(' ') + '" fill="none" stroke="#417bb8" stroke-width="1.2"/>';
    });
    return na_markup + '</svg>';
}

// FUNCTION | Small Parameter-Based Thumbnails; No External or Stored SVG Markup
// -----------------------------------------------------------------------------
export function Na__Preview__Sample(na_config) {
    const na_width = Number(na_config.unit_width_mm) || 110;
    const na_depth = Number(na_config.unit_depth_mm) || 30;
    const na_height = Number(na_config.unit_height_mm) || 75;
    const na_gap = Number(na_config.spacing_mm) || 0;
    const na_boxes = Array.from({ length: 7 }, (_na_unused, na_index) => {
        const na_x = na_index * (na_width + na_gap);
        return [[na_x,0,0],[na_x+na_width,0,0],[na_x+na_width,na_depth,0],[na_x,na_depth,0],
                [na_x,0,na_height],[na_x+na_width,0,na_height],[na_x+na_width,na_depth,na_height],[na_x,na_depth,na_height]];
    });
    return { boxes: na_boxes, path: [[0,0,0],[7*(na_width+na_gap)-na_gap,0,0]] };
}
