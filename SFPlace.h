#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <objc/runtime.h>
#include <stdbool.h>

CF_EXTERN_C_BEGIN

#define SF_PRIVATE __attribute__((visibility("hidden")))

SF_PRIVATE bool sf_sig_ok(Method m, const char *ret, const char **args);
SF_PRIVATE id sf_obj_ivar(id obj, const char *name);
SF_PRIVATE CGSize sf_glyph_canvas(id glyph);
SF_PRIVATE CGSize sf_image_canvas(id image);
SF_PRIVATE id sf_swap_content(id image, CGImageRef cg);
SF_PRIVATE bool sf_ink_color(CGImageRef img, CGColorRef *color);
SF_PRIVATE CGImageRef sf_compose(CGImageRef src, CGSize canvas, size_t w, size_t h, CGColorRef fill) CF_RETURNS_RETAINED;

CF_EXTERN_C_END
