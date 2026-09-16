/* =============================================================================
   NA ARRAY BUILDER TOOLS - UI PREVIEW
   FILE       : Na__ArrayBuilder__UiPreview__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Project instanced source meshes into a shaded SVG preview.
   ============================================================================= */

const NA_PREVIEW_EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];

// FUNCTION | Project a Three-Dimensional Coordinate Into the Preview Plane
// -----------------------------------------------------------------------------
function Na__Preview__Project(na_point) {
    return [na_point[0] - na_point[1] * 0.55, -(na_point[2] + na_point[1] * 0.35)];
}

export function Na__Preview__Markup(na_data) {
    if (na_data.mesh) return Na__Preview__MeshMarkup(na_data);
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

// FUNCTION | Instance One Source Mesh Using the Same Matrices as SketchUp
// -----------------------------------------------------------------------------
export function Na__Preview__Transform(na_point, na_matrix) {
    return [0,1,2].map(na_axis => na_matrix[na_axis] * na_point[0] + na_matrix[4 + na_axis] * na_point[1] + na_matrix[8 + na_axis] * na_point[2] + na_matrix[12 + na_axis]);
}

function Na__Preview__MeshMarkup(na_data) {
    const na_mesh = na_data.mesh;
    const na_path = na_data.path || [];
    const na_instances = (na_data.instances || []).slice(0, 400).map(na_matrix => na_mesh.points.map(na_point => Na__Preview__Transform(na_point, na_matrix)));
    let na_min_x = Infinity, na_min_y = Infinity, na_max_x = -Infinity, na_max_y = -Infinity;
    [...na_instances, na_path].forEach(na_points => na_points.forEach(na_point => {
        const [na_x, na_y] = Na__Preview__Project(na_point);
        na_min_x = Math.min(na_min_x, na_x); na_max_x = Math.max(na_max_x, na_x);
        na_min_y = Math.min(na_min_y, na_y); na_max_y = Math.max(na_max_y, na_y);
    }));
    if (![na_min_x, na_min_y, na_max_x, na_max_y].every(Number.isFinite)) return '';
    const na_width = Math.max(0.01, na_max_x - na_min_x), na_height = Math.max(0.01, na_max_y - na_min_y);
    const na_scale = Math.min(640 / na_width, 140 / na_height);
    const Na__Preview__MapMesh = na_point => {
        const [na_x, na_y] = Na__Preview__Project(na_point);
        return [(30 + (640 - na_width * na_scale) / 2 + (na_x - na_min_x) * na_scale).toFixed(2),
                (25 + (140 - na_height * na_scale) / 2 + (na_y - na_min_y) * na_scale).toFixed(2)].join(',');
    };
    const na_faces = [];
    const na_lines = [];
    na_instances.forEach(na_points => {
        na_mesh.triangles.forEach(([na_a, na_b, na_c, na_rgb]) => {
            const na_face = [na_points[na_a], na_points[na_b], na_points[na_c]];
            const na_u = na_face[1].map((na_value, na_index) => na_value - na_face[0][na_index]);
            const na_v = na_face[2].map((na_value, na_index) => na_value - na_face[0][na_index]);
            const na_normal = [na_u[1]*na_v[2]-na_u[2]*na_v[1], na_u[2]*na_v[0]-na_u[0]*na_v[2], na_u[0]*na_v[1]-na_u[1]*na_v[0]];
            const na_length = Math.hypot(...na_normal) || 1;
            const na_light = 0.62 + 0.38 * Math.abs((na_normal[0]*0.3 - na_normal[1]*0.4 + na_normal[2]*0.86) / na_length);
            const na_colour = 'rgb(' + na_rgb.map(na_value => Math.round(Math.max(0, Math.min(255, na_value * na_light)))).join(',') + ')';
            na_faces.push({ depth: na_face.reduce((na_sum, na_point) => na_sum - 0.55*na_point[0] - na_point[1] + 0.35*na_point[2], 0),
                markup: '<polygon points="' + na_face.map(Na__Preview__MapMesh).join(' ') + '" fill="' + na_colour + '" stroke="' + na_colour + '" stroke-width="0.35"/>' });
        });
        na_mesh.edges.forEach(([na_a, na_b]) => na_lines.push('M' + Na__Preview__MapMesh(na_points[na_a]) + 'L' + Na__Preview__MapMesh(na_points[na_b])));
    });
    na_faces.sort((na_a, na_b) => na_a.depth - na_b.depth);
    return '<svg viewBox="0 0 700 190" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
        '<polyline points="' + na_path.map(Na__Preview__MapMesh).join(' ') + '" fill="none" stroke="#9ab6d9" stroke-dasharray="5 4"/>' +
        na_faces.map(na_face => na_face.markup).join('') + '<path d="' + na_lines.join(' ') + '" fill="none" stroke="#24496e" stroke-opacity="0.28" stroke-width="0.7"/></svg>';
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
