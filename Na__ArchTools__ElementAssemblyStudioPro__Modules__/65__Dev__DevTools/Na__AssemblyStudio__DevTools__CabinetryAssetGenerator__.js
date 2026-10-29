/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - CABINETRY ASSET GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__CabinetryAssetGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Writes the cabinetry leg and handle assets in the unified asset
                contract the door handles use (meta, Na__Asset__Metadata,
                Na__Asset__Plan2D, Na__Asset__Elevation2D, Na__Asset__Mesh3D
                with per-edge soft / smooth records), from measured drawings
                held here as numbers, so every asset can be regenerated.
   CREATED    : 29-Oct-2026

   HOW TO RUN (needs only Node):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__CabinetryAssetGenerator__.js"

   Writes into 04__Data__AssetLibrary/Cabinetry__Legs__/ and
   04__Data__AssetLibrary/Cabinetry__Handles__/, overwriting the generated
   files only.

   THE ASSETS
   - Leg Type-01  : the UK adjustable plastic plinth leg, 150 nominal: a 48mm
                    foot, a 30mm across-flats hex adjuster, a 22mm threaded
                    column, a 30mm sleeve and a 60mm top plate. The column is
                    the stretch zone, so one asset fits any plinth height.
   - Handle 01    : T-bar handle, 12mm bar, 128mm centres, 188 long, 35 proud.
   - Handle 02    : D handle, 10mm round bar, 160mm centres, 32 proud.
   - Handle 03    : round knob, 30mm, 28.5 proud.

   FRAMES (millimetres)
   - Legs    : origin at the centre of the foot on the floor, Z up.
   - Handles : origin at the centre of the fixings on the door face, X along
               the bar, Y across it, Z out of the door face. (The door handle
               assets lie on their back instead; this family stands up.)

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Paths and Constants
// -----------------------------------------------------------------------------

const NA_ROOT        = path.resolve(__dirname, '..');
const NA_ASSET_ROOT  = path.join(NA_ROOT, '04__Data__AssetLibrary');
const NA_LEG_DIR     = path.join(NA_ASSET_ROOT, 'Cabinetry__Legs__');
const NA_HANDLE_DIR  = path.join(NA_ASSET_ROOT, 'Cabinetry__Handles__');
const NA_DATA_URL    = 'https://raw.githubusercontent.com/Adam-Noble-01/Plugins/main/Na__ArchTools__ElementAssemblyStudioPro__Modules__/04__Data__AssetLibrary/';
const NA_TODAY       = '29-Oct-2026';
const NA_SEGMENTS    = 24;                                                    // <-- Facets round a revolved part
const NA_TUBE_SIDES  = 12;                                                    // <-- Facets round a swept bar
const NA_SMOOTH_TURN_DEG = 35;                                                // <-- Profile turns gentler than this are softened

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Mesh Builder
// -----------------------------------------------------------------------------

// FUNCTION | Create an Empty Mesh That Collects Vertices, Faces and Edges
// ------------------------------------------------------------
function na_mesh() {
    return { vertices: [], faces: [], edgeFlags: {} };
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Round a Coordinate to 3 Decimal Places (as Stored)
// ------------------------------------------------------------
function na_r3(value) {
    const rounded = Math.round(value * 1000) / 1000;
    return Object.is(rounded, -0) ? 0 : rounded;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Add a Vertex, Returning Its Id
// ------------------------------------------------------------
function na_add_vertex(mesh, x, y, z) {
    const id = 'V' + String(mesh.vertices.length + 1).padStart(3, '0');
    mesh.vertices.push({ VertexId: id, VertexName: 'Na__Mesh__Vertex__' + id, PosX_mm: na_r3(x), PosY_mm: na_r3(y), PosZ_mm: na_r3(z) });
    return id;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Add a Face From Vertex Ids (Duplicates Collapsed)
// ------------------------------------------------------------
function na_add_face(mesh, ids) {
    const loop = ids.filter((id, index) => id !== ids[(index + ids.length - 1) % ids.length]);
    if (loop.length < 3) return;
    const id = 'F' + String(mesh.faces.length + 1).padStart(3, '0');
    mesh.faces.push({ FaceId: id, FaceName: 'Na__Mesh__Face__' + id, OuterLoop_VertexIds: loop, InnerLoops: [] });
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Record Whether the Edge Between Two Vertices Is Soft
// ------------------------------------------------------------
// Soft and smooth together: the edge disappears and the faces either side
// shade as one curved surface (the same flags the door handle assets carry).
function na_flag_edge(mesh, a, b, soft) {
    if (a === b) return;
    const key = a < b ? a + '|' + b : b + '|' + a;
    if (!(key in mesh.edgeFlags)) mesh.edgeFlags[key] = soft;
    else mesh.edgeFlags[key] = mesh.edgeFlags[key] && soft;
}
// ---------------------------------------------------------------

// FUNCTION | Revolve a Profile Round the Z Axis
// ------------------------------------------------------------
// @param profile  [[r, z], ...] from the bottom centre (r = 0) out, up and
//                 back in to the top centre, counter-clockwise in the (r, z)
//                 half plane, so every face points outward.
// @param ringFn   Optional (index, r, z) -> [[x, y], ...] for a ring that is
//                 not a circle (the hex adjuster); must return NA_SEGMENTS points.
// @param hardFn   Optional (profileIndex, segment) -> true where the edge
//                 along the profile must stay hard (the hex corners).
function na_revolve(mesh, profile, ringFn, hardFn) {
    const rings = profile.map(([r, z], index) => {
        if (r === 0) {
            const pole = na_add_vertex(mesh, 0, 0, z);
            return new Array(NA_SEGMENTS).fill(pole);
        }
        const points = ringFn ? ringFn(index, r, z) : null;
        const ids = [];
        for (let j = 0; j < NA_SEGMENTS; j += 1) {
            const angle = 2 * Math.PI * j / NA_SEGMENTS;
            const xy    = points ? points[j] : [r * Math.cos(angle), r * Math.sin(angle)];
            ids.push(na_add_vertex(mesh, xy[0], xy[1], z));
        }
        return ids;
    });

    for (let i = 0; i < profile.length - 1; i += 1) {
        const lower = rings[i];
        const upper = rings[i + 1];
        for (let j = 0; j < NA_SEGMENTS; j += 1) {
            const k = (j + 1) % NA_SEGMENTS;
            na_add_face(mesh, [lower[j], lower[k], upper[k], upper[j]]);
            const meridianSoft = !(hardFn && hardFn(i, j));
            na_flag_edge(mesh, lower[j], upper[j], meridianSoft);              // <-- Along the profile, between facets
        }
    }

    for (let i = 0; i < profile.length; i += 1) {
        const ring = rings[i];
        const turn = na_profile_turn(profile, i);
        for (let j = 0; j < NA_SEGMENTS; j += 1) {
            na_flag_edge(mesh, ring[j], ring[(j + 1) % NA_SEGMENTS], turn < NA_SMOOTH_TURN_DEG);
        }
    }
}
// ---------------------------------------------------------------

// HELPER FUNCTION | How Sharply a Profile Turns at One Point (Degrees)
// ------------------------------------------------------------
function na_profile_turn(profile, i) {
    if (i === 0 || i === profile.length - 1) return 180;
    const a = [profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]];
    const b = [profile[i + 1][0] - profile[i][0], profile[i + 1][1] - profile[i][1]];
    const dot = (a[0] * b[0] + a[1] * b[1]) / (Math.hypot(a[0], a[1]) * Math.hypot(b[0], b[1]));
    return Math.acos(Math.max(-1, Math.min(1, dot))) * 180 / Math.PI;
}
// ---------------------------------------------------------------

// FUNCTION | Sweep a Round Bar Along a Path in the XZ Plane
// ------------------------------------------------------------
// The path is a polyline (rounded corners already sampled into it); each
// point gets a ring of NA_TUBE_SIDES perpendicular to the path, and both
// ends are capped flat. Ring edges round a bend are softened.
function na_sweep_tube(mesh, pathPoints, radius) {
    const rings = pathPoints.map((point, index) => {
        const prev = pathPoints[Math.max(0, index - 1)];
        const next = pathPoints[Math.min(pathPoints.length - 1, index + 1)];
        let tx = next[0] - prev[0];
        let tz = next[2] - prev[2];
        const length = Math.hypot(tx, tz) || 1;
        tx /= length; tz /= length;
        const nx = -tz;                                                        // <-- In-plane normal N = T x Y
        const nz = tx;
        const ids = [];
        for (let j = 0; j < NA_TUBE_SIDES; j += 1) {
            const angle = 2 * Math.PI * j / NA_TUBE_SIDES;
            const c = Math.cos(angle) * radius;
            const s = Math.sin(angle) * radius;
            ids.push(na_add_vertex(mesh, point[0] + s * nx, point[1] + c, point[2] + s * nz));
        }
        return ids;
    });

    // Ring order runs from Y towards N, so (ring step) x (path step) points
    // out of the bar; the start cap is reversed to face back along the path.
    for (let i = 0; i < rings.length - 1; i += 1) {
        for (let j = 0; j < NA_TUBE_SIDES; j += 1) {
            const k = (j + 1) % NA_TUBE_SIDES;
            na_add_face(mesh, [rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]]);
            na_flag_edge(mesh, rings[i][j], rings[i + 1][j], true);
        }
    }
    rings.forEach((ring, index) => {
        const ends = index === 0 || index === rings.length - 1;
        for (let j = 0; j < NA_TUBE_SIDES; j += 1) na_flag_edge(mesh, ring[j], ring[(j + 1) % NA_TUBE_SIDES], !ends);
    });

    na_add_face(mesh, rings[0].slice().reverse());                             // <-- Start cap, facing back along the path
    na_add_face(mesh, rings[rings.length - 1].slice());                        // <-- End cap, facing on along the path
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Sample a Rounded Corner Between Two Straight Runs
// ------------------------------------------------------------
// Returns points from `from` to `to` (both on the XZ plane, y = 0) about
// `centre`, `steps` segments.
function na_arc(centre, radius, startDeg, endDeg, steps) {
    const points = [];
    for (let i = 0; i <= steps; i += 1) {
        const angle = (startDeg + (endDeg - startDeg) * i / steps) * Math.PI / 180;
        points.push([centre[0] + radius * Math.cos(angle), 0, centre[1] + radius * Math.sin(angle)]);
    }
    return points;
}
// ---------------------------------------------------------------

// FUNCTION | Finish a Mesh Into the Na__Asset__Mesh3D Block
// ------------------------------------------------------------
function na_mesh_block(mesh, originNote) {
    const xs = mesh.vertices.map(v => v.PosX_mm);
    const ys = mesh.vertices.map(v => v.PosY_mm);
    const zs = mesh.vertices.map(v => v.PosZ_mm);
    const edges = Object.keys(mesh.edgeFlags).map((key, index) => {
        const [a, b] = key.split('|');
        const soft = mesh.edgeFlags[key];
        return { EdgeId: 'E' + String(index + 1).padStart(3, '0'), StartVertex: a, EndVertex: b,
                 IsSoft: soft, IsSmooth: soft, IsHidden: false, CastsShadows: true };
    });
    const soft = edges.filter(edge => edge.IsSoft).length;
    return {
        Na__Geometry__OriginNote   : originNote,
        Na__Geometry__CoordSystem  : 'Right-handed | X=right, Y=front, Z=up | Units=mm',
        Na__Geometry__BoundingBox  : {
            Na__Geometry__MinX_mm: Math.min(...xs), Na__Geometry__MaxX_mm: Math.max(...xs),
            Na__Geometry__MinY_mm: Math.min(...ys), Na__Geometry__MaxY_mm: Math.max(...ys),
            Na__Geometry__MinZ_mm: Math.min(...zs), Na__Geometry__MaxZ_mm: Math.max(...zs)
        },
        Na__Geometry__Counts       : {
            Na__Geometry__VertexCount: mesh.vertices.length, Na__Geometry__FaceCount: mesh.faces.length,
            Na__Geometry__EdgeCount: edges.length, Na__Geometry__HardEdgeCount: edges.length - soft,
            Na__Geometry__SoftEdgeCount: soft, Na__Geometry__SmoothEdgeCount: soft
        },
        Na__Geometry__Vertices     : mesh.vertices,
        Na__Geometry__Faces        : mesh.faces,
        Na__Geometry__Edges        : edges
    };
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | 2D Path Helpers
// -----------------------------------------------------------------------------

// HELPER FUNCTION | A Circle Path Record
// ------------------------------------------------------------
function na_circle(name, x, y, radius) {
    return { PathType: 'Circle', VertexName: name, Center_mm: { X: na_r3(x), Y: na_r3(y) }, Radius_mm: na_r3(radius),
             StartAngle_deg: 0, EndAngle_deg: 360, Sweep_deg: 360,
             StartPoint_mm: { X: na_r3(x + radius), Y: na_r3(y) }, EndPoint_mm: { X: na_r3(x + radius), Y: na_r3(y) }, IsCircle: true };
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Closed Polygon Path Record
// ------------------------------------------------------------
function na_polygon(name, points) {
    return { PathType: 'Polygon', VertexName: name, Vertices_mm: points.map(([x, y]) => ({ X: na_r3(x), Y: na_r3(y) })) };
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Rectangle as a Polygon Path Record
// ------------------------------------------------------------
function na_rect(name, x0, y0, x1, y1) {
    return na_polygon(name, [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]);
}
// ---------------------------------------------------------------

// FUNCTION | Wrap Path Records Into a Plan2D / Elevation2D Block
// ------------------------------------------------------------
function na_view_block(originNote, coordSystem, paths) {
    const xs = [];
    const ys = [];
    paths.forEach(entry => {
        if (entry.PathType === 'Circle') {
            xs.push(entry.Center_mm.X - entry.Radius_mm, entry.Center_mm.X + entry.Radius_mm);
            ys.push(entry.Center_mm.Y - entry.Radius_mm, entry.Center_mm.Y + entry.Radius_mm);
        } else {
            entry.Vertices_mm.forEach(point => { xs.push(point.X); ys.push(point.Y); });
        }
    });
    const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
    return {
        Na__Geometry__OriginNote  : originNote,
        Na__Geometry__CoordSystem : coordSystem,
        Na__Geometry__BoundingBox : {
            Na__Geometry__MinX_mm: na_r3(minX), Na__Geometry__MaxX_mm: na_r3(maxX),
            Na__Geometry__MinY_mm: na_r3(minY), Na__Geometry__MaxY_mm: na_r3(maxY),
            Na__Geometry__Width_mm: na_r3(maxX - minX), Na__Geometry__Height_mm: na_r3(maxY - minY)
        },
        Na__Geometry__Counts      : {
            Na__Geometry__EdgeCount: 0, Na__Geometry__ArcCount: 0, Na__Geometry__LineCount: 0,
            Na__Geometry__PolygonCount: paths.filter(entry => entry.PathType === 'Polygon').length,
            Na__Geometry__CircleCount : paths.filter(entry => entry.PathType === 'Circle').length
        },
        Na__Geometry__Paths       : paths
    };
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Asset File Wrapper
// -----------------------------------------------------------------------------

// FUNCTION | Assemble and Write One Asset File
// ------------------------------------------------------------
function na_write_asset(folder, key, description, metadata, plan, elevation, mesh) {
    const fileName = key + '__.json';
    const asset = {
        meta: {
            fileName        : fileName,
            description     : description,
            version         : '1.0.0',
            lastUpdated     : NA_TODAY,
            generator       : '65__Dev__DevTools/Na__AssemblyStudio__DevTools__CabinetryAssetGenerator__.js',
            namingConvention: 'All custom keys prefixed Na__. Three-stage form Na__Section__SubSection__FieldName. Geometry primitives in Paths arrays use PathType (Line | Arc | Circle | Polygon).',
            fieldPrefixes   : {
                Na__Asset__            : 'Top-level asset metadata and content blocks',
                Na__Geometry__         : 'Geometry-related sub-fields (BoundingBox, Counts, OriginNote, CoordSystem)',
                Na__CabinetPlacement__ : 'Cabinet mounting data read by the Interior Cabinetry builders'
            },
            Data__URL       : NA_DATA_URL + path.basename(folder) + '/' + fileName
        },
        Na__Asset__Metadata    : metadata,
        Na__Asset__Plan2D      : plan,
        Na__Asset__Elevation2D : elevation,
        Na__Asset__Mesh3D      : mesh
    };
    fs.mkdirSync(folder, { recursive: true });
    fs.writeFileSync(path.join(folder, fileName), JSON.stringify(asset, null, 4) + '\n', 'utf8');
    console.log('  wrote ' + path.basename(folder) + '/' + fileName + '  (' + mesh.Na__Geometry__Counts.Na__Geometry__VertexCount +
                ' vertices, ' + mesh.Na__Geometry__Counts.Na__Geometry__FaceCount + ' faces)');
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Common Metadata Fields
// ------------------------------------------------------------
function na_base_metadata(name, code, type, description, notes, finishes) {
    return {
        Na__Asset__Name               : name,
        Na__Asset__Code               : code,
        Na__Asset__Type               : type,
        Na__Asset__Description        : description,
        Na__Asset__Notes              : notes,
        Na__Asset__Supplier           : '',
        Na__Asset__SupplierProductCode: '',
        Na__Asset__SupplierPrice_GBP  : '',
        Na__Asset__Has2dPlan          : true,
        Na__Asset__Has2dElevation     : true,
        Na__Asset__Has3d              : true,
        Na__Asset__Has2dProfile       : false,
        Na__Asset__AvailableFinishes  : finishes
    };
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Leg Type-01 - Adjustable Plinth Leg, 150 Nominal
// -----------------------------------------------------------------------------

// HELPER FUNCTION | A Hexagon Ring Sampled at NA_SEGMENTS Points
// ------------------------------------------------------------
// Four points per side, so it joins the round rings above and below quad
// for quad. Corners sit on segments 0, 4, 8, 12, 16 and 20.
function na_hex_ring(acrossFlats) {
    const corner = acrossFlats / Math.sqrt(3);
    const corners = [];
    for (let c = 0; c < 6; c += 1) corners.push([corner * Math.cos(c * Math.PI / 3), corner * Math.sin(c * Math.PI / 3)]);
    const points = [];
    for (let c = 0; c < 6; c += 1) {
        const a = corners[c];
        const b = corners[(c + 1) % 6];
        for (let s = 0; s < NA_SEGMENTS / 6; s += 1) {
            const f = s / (NA_SEGMENTS / 6);
            points.push([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]);
        }
    }
    return points;
}
// ---------------------------------------------------------------

// FUNCTION | Build and Write the Adjustable Plinth Leg
// ------------------------------------------------------------
function na_build_leg() {
    const HEX_AF   = 30;
    const profile  = [
        [0, 0], [24, 0], [24, 4], [21, 7],                                     // <-- 48 foot, chamfered
        [HEX_AF, 7], [HEX_AF, 19],                                             // <-- Hex adjuster (r is a placeholder; the ring is the hexagon)
        [11, 19], [11, 95],                                                    // <-- 22 threaded column (stretch zone 25..90)
        [15, 95], [15, 130],                                                   // <-- 30 sleeve
        [30, 138], [30, 150], [0, 150]                                         // <-- Flared to the 60 top plate under the carcass
    ];
    const HEX_RINGS = new Set([4, 5]);
    const HEX_BAND  = 4;                                                       // <-- Profile step from ring 4 to ring 5: the hex flats
    const corners   = new Set([0, 4, 8, 12, 16, 20]);
    const mesh      = na_mesh();
    na_revolve(mesh, profile,
               index => (HEX_RINGS.has(index) ? na_hex_ring(HEX_AF) : null),
               (index, segment) => index === HEX_BAND && corners.has(segment));

    const outline = [[-24, 0], [24, 0], [24, 4], [21, 7], [17.32, 7], [17.32, 19], [11, 19], [11, 95], [15, 95], [15, 130],
                     [30, 138], [30, 150], [-30, 150], [-30, 138], [-15, 130], [-15, 95], [-11, 95], [-11, 19],
                     [-17.32, 19], [-17.32, 7], [-21, 7], [-24, 4]];

    const metadata = Object.assign(
        na_base_metadata(
            'Adjustable Plinth Leg (150mm)', 'NA__LEG__001', 'CabinetLeg',
            'UK kitchen cabinet leg: black plastic, screw adjustable, push-fit into the base panel, with the plinth clipped to the front legs. 150mm nominal.',
            'Measured from the common UK 150mm adjustable leg (Howdens / Wren pattern). Origin = centre of the foot on the floor, Z up. The threaded column between 25 and 90 stretches or shrinks to the plinth height, so the foot, adjuster, sleeve and plate keep their true sizes.',
            ['MAT304__Paint__FarrowAndBall__DownPipe']
        ),
        {
            Na__CabinetPlacement__NominalHeight_mm   : 150,
            Na__CabinetPlacement__StretchZoneMin_mm  : 25,
            Na__CabinetPlacement__StretchZoneMax_mm  : 90,
            Na__CabinetPlacement__MinHeight_mm       : 86,
            Na__CabinetPlacement__FootprintRadius_mm : 30,
            Na__CabinetPlacement__Note               : 'Placed at each leg point with its top plate touching the carcass underside.'
        }
    );

    const plan = na_view_block(
        'Local 0,0 = centre of the leg. Seen from above.',
        'XY plane | X=right, Y=forward | Units=mm',
        [na_circle('Na__Plan__TopPlate', 0, 0, 30), na_circle('Na__Plan__Foot', 0, 0, 24),
         na_polygon('Na__Plan__HexAdjuster', na_hex_ring(HEX_AF).filter((p, i) => i % 4 === 0))]
    );
    const elevation = na_view_block(
        'Local 0,0 = centre of the foot on the floor. Seen from the side.',
        'XY plane | X=right, Y=up | Units=mm',
        [na_polygon('Na__Elevation__LegOutline', outline)]
    );

    na_write_asset(NA_LEG_DIR, 'Na__Cabinetry__Leg__Type-01__AdjustablePlinthLeg__h150mm',
                   'Adjustable plinth leg for kitchen and wardrobe carcasses (Interior Cabinetry). Unified asset: plan, side elevation, 3D mesh and cabinet placement data. Units mm.',
                   metadata, plan, elevation,
                   na_mesh_block(mesh, 'Local 0,0,0 = centre of the foot on the floor; Z up to the top plate (150 nominal).'));
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Handles
// -----------------------------------------------------------------------------

// HELPER FUNCTION | Handle Placement Metadata
// ------------------------------------------------------------
function na_handle_placement(kind, length, projection, centres) {
    return {
        Na__CabinetPlacement__Kind         : kind,
        Na__CabinetPlacement__Length_mm    : length,
        Na__CabinetPlacement__Projection_mm: projection,
        Na__CabinetPlacement__Centres_mm   : centres,
        Na__CabinetPlacement__Note         : 'Origin on the door face at the centre of the fixings; X runs along the bar, Z stands out of the door.'
    };
}
// ---------------------------------------------------------------

// FUNCTION | Build and Write the T-Bar Handle (128mm Centres)
// ------------------------------------------------------------
function na_build_bar_handle() {
    const CENTRES = 128, LENGTH = 188, BAR_R = 6, BAR_Z = 35, POST_R = 5;
    const mesh = na_mesh();
    na_sweep_tube(mesh, [[-LENGTH / 2, 0, BAR_Z], [LENGTH / 2, 0, BAR_Z]], BAR_R);
    [-CENTRES / 2, CENTRES / 2].forEach(x => na_sweep_tube(mesh, [[x, 0, 0], [x, 0, BAR_Z - BAR_R / 2]], POST_R));

    const metadata = Object.assign(
        na_base_metadata('Bar Handle (128mm centres)', 'NA__CHD__001', 'CabinetHandle',
            'T-bar cabinet handle: 12mm round bar, 188 long on two 10mm posts at 128mm centres, standing 41 proud of the door.',
            'The most common UK kitchen handle size. Origin on the door face between the fixings.',
            ['MAT615__Metal__Ironmongery__Chrome', 'MAT616__Metal__Ironmongery__BrushedSteel', 'MAT614__Metal__Ironmongery__SatinNickel', 'MAT612__Metal__Ironmongery__Brass', 'MAT613__Metal__Ironmongery__Bronze']),
        na_handle_placement('Bar', LENGTH, BAR_Z + BAR_R, CENTRES));
    const elevation = na_view_block('Local 0,0 = centre of the fixings. Seen from the front of the door.', 'XY plane | X=along the bar, Y=across | Units=mm',
        [na_rect('Na__Elevation__Bar', -LENGTH / 2, -BAR_R, LENGTH / 2, BAR_R)]);
    const plan = na_view_block('Local 0,0 = centre of the fixings on the door face. Seen from above, Y out of the door.', 'XY plane | X=along the bar, Y=out of the door | Units=mm',
        [na_rect('Na__Plan__Bar', -LENGTH / 2, BAR_Z - BAR_R, LENGTH / 2, BAR_Z + BAR_R),
         na_rect('Na__Plan__PostLeft', -CENTRES / 2 - POST_R, 0, -CENTRES / 2 + POST_R, BAR_Z - BAR_R),
         na_rect('Na__Plan__PostRight', CENTRES / 2 - POST_R, 0, CENTRES / 2 + POST_R, BAR_Z - BAR_R)]);

    na_write_asset(NA_HANDLE_DIR, 'Na__Cabinetry__Handle__Type-01__BarHandle__cc128mm',
                   'T-bar cabinet handle, 128mm centres (Interior Cabinetry). Unified asset: plan, elevation, 3D mesh and cabinet placement data. Units mm.',
                   metadata, plan, elevation, na_mesh_block(mesh, 'Local 0,0,0 = centre of the fixings on the door face; Z out of the door.'));
}
// ---------------------------------------------------------------

// FUNCTION | Build and Write the D Handle (160mm Centres)
// ------------------------------------------------------------
function na_build_d_handle() {
    const CENTRES = 160, PROUD = 32, BAR_R = 5, BEND_R = 10, STEPS = 6;
    const half = CENTRES / 2;
    const pathPoints = [[-half, 0, 0], [-half, 0, PROUD - BEND_R]]
        .concat(na_arc([-half + BEND_R, PROUD - BEND_R], BEND_R, 180, 90, STEPS).slice(1))
        .concat([[half - BEND_R, 0, PROUD]])
        .concat(na_arc([half - BEND_R, PROUD - BEND_R], BEND_R, 90, 0, STEPS).slice(1))
        .concat([[half, 0, 0]]);
    const mesh = na_mesh();
    na_sweep_tube(mesh, pathPoints, BAR_R);

    const metadata = Object.assign(
        na_base_metadata('D Handle (160mm centres)', 'NA__CHD__002', 'CabinetHandle',
            'D handle: 10mm round bar bent to a D, 160mm centres, standing 37 proud of the door.',
            'Classic UK D handle, a good match for shaker doors. Origin on the door face between the fixings.',
            ['MAT615__Metal__Ironmongery__Chrome', 'MAT616__Metal__Ironmongery__BrushedSteel', 'MAT614__Metal__Ironmongery__SatinNickel', 'MAT612__Metal__Ironmongery__Brass', 'MAT613__Metal__Ironmongery__Bronze']),
        na_handle_placement('Bar', CENTRES + 2 * BAR_R, PROUD + BAR_R, CENTRES));
    const elevation = na_view_block('Local 0,0 = centre of the fixings. Seen from the front of the door.', 'XY plane | X=along the bar, Y=across | Units=mm',
        [na_rect('Na__Elevation__Grip', -half - BAR_R, -BAR_R, half + BAR_R, BAR_R)]);
    const plan = na_view_block('Local 0,0 = centre of the fixings on the door face. Seen from above, Y out of the door.', 'XY plane | X=along the bar, Y=out of the door | Units=mm',
        [na_polygon('Na__Plan__DOutline', pathPoints.map(point => [point[0], point[2]]))]);

    na_write_asset(NA_HANDLE_DIR, 'Na__Cabinetry__Handle__Type-02__DHandle__cc160mm',
                   'D handle, 160mm centres (Interior Cabinetry). Unified asset: plan, elevation, 3D mesh and cabinet placement data. Units mm.',
                   metadata, plan, elevation, na_mesh_block(mesh, 'Local 0,0,0 = centre of the fixings on the door face; Z out of the door.'));
}
// ---------------------------------------------------------------

// FUNCTION | Build and Write the Round Knob (30mm)
// ------------------------------------------------------------
function na_build_knob() {
    const profile = [[0, 0], [9, 0], [9, 2], [6, 6], [6, 12], [10, 15], [13.5, 18], [15, 21], [15, 23], [13.5, 26], [10, 28], [5, 28.5], [0, 28.5]];
    const mesh = na_mesh();
    na_revolve(mesh, profile, null, null);

    const metadata = Object.assign(
        na_base_metadata('Round Knob (30mm)', 'NA__CHD__003', 'CabinetHandle',
            'Round cabinet knob, 30mm across, on an 18mm base, 28.5 proud of the door.',
            'Single fixing. Placed by its centre.',
            ['MAT615__Metal__Ironmongery__Chrome', 'MAT616__Metal__Ironmongery__BrushedSteel', 'MAT614__Metal__Ironmongery__SatinNickel', 'MAT612__Metal__Ironmongery__Brass', 'MAT613__Metal__Ironmongery__Bronze']),
        na_handle_placement('Knob', 30, 28.5, 0));
    const elevation = na_view_block('Local 0,0 = the fixing. Seen from the front of the door.', 'XY plane | X=right, Y=up | Units=mm',
        [na_circle('Na__Elevation__Knob', 0, 0, 15), na_circle('Na__Elevation__Base', 0, 0, 9)]);
    const plan = na_view_block('Local 0,0 = the fixing on the door face. Seen from above, Y out of the door.', 'XY plane | X=right, Y=out of the door | Units=mm',
        [na_polygon('Na__Plan__KnobProfile', profile.map(([r, z]) => [r, z]).concat(profile.slice().reverse().map(([r, z]) => [-r, z])))]);

    na_write_asset(NA_HANDLE_DIR, 'Na__Cabinetry__Handle__Type-03__Knob__d30mm',
                   'Round knob, 30mm (Interior Cabinetry). Unified asset: plan, elevation, 3D mesh and cabinet placement data. Units mm.',
                   metadata, plan, elevation, na_mesh_block(mesh, 'Local 0,0,0 = the fixing on the door face; Z out of the door.'));
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Run
// -----------------------------------------------------------------------------

if (require.main === module) {
    console.log('Cabinetry assets:');
    na_build_leg();
    na_build_bar_handle();
    na_build_d_handle();
    na_build_knob();
}

module.exports = { na_build_leg, na_build_bar_handle, na_build_d_handle, na_build_knob };

// endregion -------------------------------------------------------------------

/* =============================================================================
   END OF FILE
   ============================================================================= */
