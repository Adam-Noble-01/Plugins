#include <ruby.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace {

struct Na__Uv {
    double u;
    double v;
};

double Na__WrapUnit(double value)
{
    double wrapped = std::fmod(value, 1.0);
    return wrapped < 0.0 ? wrapped + 1.0 : wrapped;
}

Na__Uv Na__LerpUv(const Na__Uv& start_uv, const Na__Uv& end_uv, double fraction)
{
    return {
        start_uv.u + ((end_uv.u - start_uv.u) * fraction),
        start_uv.v + ((end_uv.v - start_uv.v) * fraction)
    };
}

Na__Uv Na__BilinearUv(const Na__Uv corners[4], double x_fraction, double y_fraction)
{
    const Na__Uv bottom = Na__LerpUv(corners[0], corners[1], x_fraction);
    const Na__Uv top = Na__LerpUv(corners[3], corners[2], x_fraction);
    return Na__LerpUv(bottom, top, y_fraction);
}

void Na__CopyPixel(
    const unsigned char* source,
    int source_width,
    int source_height,
    int bytes_per_pixel,
    int stride,
    double u,
    double v,
    unsigned char* destination
)
{
    const double wrapped_u = Na__WrapUnit(u);
    const double wrapped_v = Na__WrapUnit(v);
    int source_x = static_cast<int>(wrapped_u * source_width);
    int source_y_from_bottom = static_cast<int>(wrapped_v * source_height);

    if (source_x >= source_width) {
        source_x = source_width - 1;
    }
    if (source_y_from_bottom >= source_height) {
        source_y_from_bottom = source_height - 1;
    }

    const int source_row = source_height - 1 - source_y_from_bottom;
    const unsigned char* pixel = source + (source_row * stride) + (source_x * bytes_per_pixel);

    if (bytes_per_pixel >= 4) {
        destination[0] = pixel[0];
        destination[1] = pixel[1];
        destination[2] = pixel[2];
        destination[3] = pixel[3];
        return;
    }

    if (bytes_per_pixel == 3) {
        destination[0] = pixel[0];
        destination[1] = pixel[1];
        destination[2] = pixel[2];
        destination[3] = 255;
        return;
    }

    destination[0] = pixel[0];
    destination[1] = pixel[0];
    destination[2] = pixel[0];
    destination[3] = 255;
}

VALUE Na__NativeSampler__SampleTexture(
    VALUE self,
    VALUE rb_pixels,
    VALUE rb_source_width,
    VALUE rb_source_height,
    VALUE rb_bits_per_pixel,
    VALUE rb_row_padding,
    VALUE rb_corner_uvs,
    VALUE rb_output_width,
    VALUE rb_output_height
)
{
    (void)self;
    Check_Type(rb_pixels, T_STRING);
    Check_Type(rb_corner_uvs, T_ARRAY);

    if (RARRAY_LEN(rb_corner_uvs) < 8) {
        rb_raise(rb_eArgError, "corner UVs must contain 8 numbers");
    }

    const int source_width = NUM2INT(rb_source_width);
    const int source_height = NUM2INT(rb_source_height);
    const int bits_per_pixel = NUM2INT(rb_bits_per_pixel);
    const int row_padding = NUM2INT(rb_row_padding);
    const int output_width = NUM2INT(rb_output_width);
    const int output_height = NUM2INT(rb_output_height);
    const int bytes_per_pixel = bits_per_pixel / 8;

    if (source_width < 1 || source_height < 1 || output_width < 1 || output_height < 1) {
        rb_raise(rb_eArgError, "image dimensions must be positive");
    }
    if (bytes_per_pixel != 1 && bytes_per_pixel != 3 && bytes_per_pixel != 4) {
        rb_raise(rb_eArgError, "unsupported bits per pixel");
    }

    const int stride = (source_width * bytes_per_pixel) + row_padding;
    const long required_bytes = static_cast<long>(stride) * source_height;
    if (RSTRING_LEN(rb_pixels) < required_bytes) {
        rb_raise(rb_eArgError, "pixel buffer is shorter than the image dimensions");
    }

    Na__Uv corners[4];
    for (int corner_index = 0; corner_index < 4; ++corner_index) {
        corners[corner_index].u = NUM2DBL(RARRAY_AREF(rb_corner_uvs, corner_index * 2));
        corners[corner_index].v = NUM2DBL(RARRAY_AREF(rb_corner_uvs, (corner_index * 2) + 1));
    }

    const unsigned char* source = reinterpret_cast<const unsigned char*>(RSTRING_PTR(rb_pixels));
    std::vector<unsigned char> output(static_cast<size_t>(output_width) * output_height * 4);

    for (int row = 0; row < output_height; ++row) {
        const double y_fraction = output_height == 1
            ? 0.0
            : static_cast<double>(output_height - 1 - row) / static_cast<double>(output_height - 1);

        for (int column = 0; column < output_width; ++column) {
            const double x_fraction = output_width == 1
                ? 0.0
                : static_cast<double>(column) / static_cast<double>(output_width - 1);
            const Na__Uv uv = Na__BilinearUv(corners, x_fraction, y_fraction);
            unsigned char* destination = output.data() + ((static_cast<size_t>(row) * output_width + column) * 4);
            Na__CopyPixel(source, source_width, source_height, bytes_per_pixel, stride, uv.u, uv.v, destination);
        }
    }

    return rb_str_new(reinterpret_cast<const char*>(output.data()), static_cast<long>(output.size()));
}

} // namespace

extern "C" __declspec(dllexport) void Init_Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler()
{
    VALUE root_module = rb_define_module("Na__Noble3dModellingTools");
    VALUE native_module = rb_define_module_under(root_module, "Na__TexturedPlaneToImage__NativeSampler");

    rb_define_module_function(
        native_module,
        "na_sample_texture",
        RUBY_METHOD_FUNC(Na__NativeSampler__SampleTexture),
        8
    );
}
