#include "Na__MeshDecimator__NativeQemCore__.hpp"

#include <ruby.h>

#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

using NaMeshDecimatorNative::NaNativeMesh;
using NaMeshDecimatorNative::NaNativeOptions;
using NaMeshDecimatorNative::NaNativeTriangle;
using NaMeshDecimatorNative::NaNativeVertex;
using NaMeshDecimatorNative::Na__NativeQemCore__SimplifyMesh;

namespace {

ID Na__NativeRuby__Id(const char* name)
{
    return rb_intern(name);
}

VALUE Na__NativeRuby__Symbol(const char* name)
{
    return ID2SYM(Na__NativeRuby__Id(name));
}

VALUE Na__NativeRuby__HashValue(VALUE hash, const char* key)
{
    return rb_hash_aref(hash, Na__NativeRuby__Symbol(key));
}

double Na__NativeRuby__OptionDouble(VALUE options, const char* key, double fallback)
{
    VALUE value = Na__NativeRuby__HashValue(options, key);
    return NIL_P(value) ? fallback : NUM2DBL(value);
}

int Na__NativeRuby__OptionInt(VALUE options, const char* key, int fallback)
{
    VALUE value = Na__NativeRuby__HashValue(options, key);
    return NIL_P(value) ? fallback : NUM2INT(value);
}

bool Na__NativeRuby__OptionBool(VALUE options, const char* key, bool fallback)
{
    VALUE value = Na__NativeRuby__HashValue(options, key);
    return NIL_P(value) ? fallback : RTEST(value);
}

std::array<double, 3> Na__NativeRuby__ReadPoint(VALUE rb_point)
{
    Check_Type(rb_point, T_ARRAY);

    if (RARRAY_LEN(rb_point) < 3) {
        rb_raise(rb_eArgError, "point arrays must contain at least 3 numeric values");
    }

    return {
        NUM2DBL(RARRAY_AREF(rb_point, 0)),
        NUM2DBL(RARRAY_AREF(rb_point, 1)),
        NUM2DBL(RARRAY_AREF(rb_point, 2))
    };
}

int Na__NativeRuby__MaterialIndex(
    VALUE rb_material,
    std::vector<VALUE>& material_values,
    std::unordered_map<unsigned long long, int>& material_index_by_object_id
)
{
    const unsigned long long object_id = NUM2ULL(rb_obj_id(rb_material));
    const auto found = material_index_by_object_id.find(object_id);

    if (found != material_index_by_object_id.end()) {
        return found->second;
    }

    const int material_index = static_cast<int>(material_values.size());
    material_values.push_back(rb_material);
    material_index_by_object_id[object_id] = material_index;
    return material_index;
}

NaNativeMesh Na__NativeRuby__ReadMesh(
    VALUE rb_mesh,
    std::vector<VALUE>& material_values
)
{
    Check_Type(rb_mesh, T_HASH);

    VALUE rb_vertices = Na__NativeRuby__HashValue(rb_mesh, "vertices");
    VALUE rb_triangles = Na__NativeRuby__HashValue(rb_mesh, "triangles");

    Check_Type(rb_vertices, T_ARRAY);
    Check_Type(rb_triangles, T_ARRAY);

    NaNativeMesh mesh;
    mesh.vertices.reserve(static_cast<size_t>(RARRAY_LEN(rb_vertices)));
    mesh.triangles.reserve(static_cast<size_t>(RARRAY_LEN(rb_triangles)));

    for (long index = 0; index < RARRAY_LEN(rb_vertices); ++index) {
        VALUE rb_vertex = RARRAY_AREF(rb_vertices, index);
        Check_Type(rb_vertex, T_HASH);

        VALUE rb_point = Na__NativeRuby__HashValue(rb_vertex, "point");

        NaNativeVertex vertex;
        vertex.point = Na__NativeRuby__ReadPoint(rb_point);
        vertex.quadric = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
        mesh.vertices.push_back(vertex);
    }

    std::unordered_map<unsigned long long, int> material_index_by_object_id;
    material_values.reserve(static_cast<size_t>(RARRAY_LEN(rb_triangles)));

    for (long index = 0; index < RARRAY_LEN(rb_triangles); ++index) {
        VALUE rb_triangle = RARRAY_AREF(rb_triangles, index);
        Check_Type(rb_triangle, T_HASH);

        VALUE rb_indices = Na__NativeRuby__HashValue(rb_triangle, "vertices");
        Check_Type(rb_indices, T_ARRAY);

        if (RARRAY_LEN(rb_indices) < 3) {
            continue;
        }

        VALUE rb_material = Na__NativeRuby__HashValue(rb_triangle, "material");

        NaNativeTriangle triangle;
        triangle.vertices = {
            NUM2INT(RARRAY_AREF(rb_indices, 0)),
            NUM2INT(RARRAY_AREF(rb_indices, 1)),
            NUM2INT(RARRAY_AREF(rb_indices, 2))
        };
        triangle.material_index = Na__NativeRuby__MaterialIndex(
            rb_material,
            material_values,
            material_index_by_object_id
        );

        mesh.triangles.push_back(triangle);
    }

    VALUE rb_stopped_early = Na__NativeRuby__HashValue(rb_mesh, "stopped_early");
    mesh.stopped_early = RTEST(rb_stopped_early);

    return mesh;
}

NaNativeOptions Na__NativeRuby__ReadOptions(VALUE rb_options)
{
    Check_Type(rb_options, T_HASH);

    NaNativeOptions options;
    options.maintain_border_edges = Na__NativeRuby__OptionBool(rb_options, "maintain_border_edges", true);
    options.preserve_material_boundary_edges = Na__NativeRuby__OptionBool(rb_options, "preserve_material_boundary_edges", true);
    options.max_seconds_per_group = Na__NativeRuby__OptionDouble(rb_options, "max_seconds_per_group", 10.0);
    options.max_passes_per_group = Na__NativeRuby__OptionInt(rb_options, "max_passes_per_group", 4);
    options.max_candidate_edges_per_pass = Na__NativeRuby__OptionInt(rb_options, "max_candidate_edges_per_pass", 10000);
    return options;
}

VALUE Na__NativeRuby__BuildPointArray(const std::array<double, 3>& point)
{
    VALUE rb_point = rb_ary_new_capa(3);
    rb_ary_push(rb_point, rb_float_new(point[0]));
    rb_ary_push(rb_point, rb_float_new(point[1]));
    rb_ary_push(rb_point, rb_float_new(point[2]));
    return rb_point;
}

VALUE Na__NativeRuby__BuildZeroQuadricArray()
{
    VALUE rb_quadric = rb_ary_new_capa(10);
    for (int index = 0; index < 10; ++index) {
        rb_ary_push(rb_quadric, rb_float_new(0.0));
    }
    return rb_quadric;
}

VALUE Na__NativeRuby__BuildIndexArray(const std::array<int, 3>& indices)
{
    VALUE rb_indices = rb_ary_new_capa(3);
    rb_ary_push(rb_indices, INT2NUM(indices[0]));
    rb_ary_push(rb_indices, INT2NUM(indices[1]));
    rb_ary_push(rb_indices, INT2NUM(indices[2]));
    return rb_indices;
}

VALUE Na__NativeRuby__BuildMeshHash(
    const NaNativeMesh& mesh,
    const std::vector<VALUE>& material_values
)
{
    VALUE rb_vertices = rb_ary_new_capa(static_cast<long>(mesh.vertices.size()));
    VALUE rb_triangles = rb_ary_new_capa(static_cast<long>(mesh.triangles.size()));
    VALUE rb_mesh = rb_hash_new();

    for (const auto& vertex : mesh.vertices) {
        VALUE rb_vertex = rb_hash_new();
        rb_hash_aset(rb_vertex, Na__NativeRuby__Symbol("point"), Na__NativeRuby__BuildPointArray(vertex.point));
        rb_hash_aset(rb_vertex, Na__NativeRuby__Symbol("quadric"), Na__NativeRuby__BuildZeroQuadricArray());
        rb_ary_push(rb_vertices, rb_vertex);
    }

    for (const auto& triangle : mesh.triangles) {
        VALUE rb_triangle = rb_hash_new();
        VALUE rb_material = Qnil;

        if (triangle.material_index >= 0 &&
            triangle.material_index < static_cast<int>(material_values.size())) {
            rb_material = material_values[triangle.material_index];
        }

        rb_hash_aset(rb_triangle, Na__NativeRuby__Symbol("vertices"), Na__NativeRuby__BuildIndexArray(triangle.vertices));
        rb_hash_aset(rb_triangle, Na__NativeRuby__Symbol("material"), rb_material);
        rb_ary_push(rb_triangles, rb_triangle);
    }

    rb_hash_aset(rb_mesh, Na__NativeRuby__Symbol("vertices"), rb_vertices);
    rb_hash_aset(rb_mesh, Na__NativeRuby__Symbol("triangles"), rb_triangles);
    rb_hash_aset(rb_mesh, Na__NativeRuby__Symbol("stopped_early"), mesh.stopped_early ? Qtrue : Qfalse);

    return rb_mesh;
}

VALUE Na__NativeQemEngine__SimplifyMesh(VALUE self, VALUE rb_mesh, VALUE rb_target_triangles, VALUE rb_options)
{
    (void)self;

    std::vector<VALUE> material_values;
    NaNativeMesh mesh = Na__NativeRuby__ReadMesh(rb_mesh, material_values);
    const NaNativeOptions options = Na__NativeRuby__ReadOptions(rb_options);
    const int target_triangles = NUM2INT(rb_target_triangles);

    NaNativeMesh simplified = Na__NativeQemCore__SimplifyMesh(mesh, target_triangles, options);
    return Na__NativeRuby__BuildMeshHash(simplified, material_values);
}

} // namespace

extern "C" __declspec(dllexport) void Init_Na__MeshDecimator__NativeQemEngine()
{
    VALUE root_module = rb_define_module("Na__MeshDecimator");
    VALUE native_module = rb_define_module_under(root_module, "Na__NativeQemEngine");

    rb_define_module_function(
        native_module,
        "na_simplify_mesh",
        RUBY_METHOD_FUNC(Na__NativeQemEngine__SimplifyMesh),
        3
    );
}
