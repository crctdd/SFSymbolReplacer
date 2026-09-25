#include "SFPlace.h"
#include <objc/message.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SF_SCAN_MAX 1024
#define SF_MAX_PX 2048
#define MSG(ret, ...) ((ret (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)

static bool sf_type_is(char *t, const char *want) {
    if (!t) return false;
    const char *p = t;
    while (*p && strchr("rnNoORV", *p)) p++;
    bool ok = !strncmp(p, want, strlen(want));
    free(t);
    return ok;
}

bool sf_sig_ok(Method m, const char *ret, const char **args) {
    if (!m || !sf_type_is(method_copyReturnType(m), ret)) return false;
    unsigned int n = 0;
    while (args && args[n]) n++;
    if (method_getNumberOfArguments(m) != n + 2) return false;
    for (unsigned int i = 0; i < n; i++)
        if (!sf_type_is(method_copyArgumentType(m, i + 2), args[i])) return false;
    return true;
}

id sf_obj_ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable(object_getClass(obj), name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (enc && *enc == '@') ? object_getIvar(obj, iv) : NULL;
}

static struct {
    Class image;
    SEL vg, canvas, scale, mk, with;
    bool swap;
} G;

static bool sf_getter(id o, SEL s, const char *ret) {
    return o && sf_sig_ok(class_getInstanceMethod(object_getClass(o), s), ret, NULL);
}

static bool sf_is(id o, Class c) {
    for (Class k = o ? object_getClass(o) : Nil; k && c; k = class_getSuperclass(k))
        if (k == c) return true;
    return false;
}

static void sf_resolve(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        G.vg = sel_registerName("vectorGlyph");
        G.canvas = sel_registerName("referenceCanvasSize");
        G.scale = sel_registerName("scale");
        G.mk = sel_registerName("imageWithCGImage:scale:orientation:");
        G.with = sel_registerName("_imageWithContent:");
        G.image = objc_getClass("UIImage");
        Ivar iv = G.image ? class_getInstanceVariable(G.image, "_content") : NULL;
        const char *e = iv ? ivar_getTypeEncoding(iv) : NULL;
        G.swap = e && *e == '@'
            && sf_sig_ok(class_getInstanceMethod(G.image, G.with), "@", (const char *[]){ "@", NULL })
            && sf_sig_ok(class_getInstanceMethod(G.image, G.scale), "d", NULL)
            && sf_sig_ok(class_getClassMethod(G.image, G.mk), "@", (const char *[]){ "^{CGImage", "d", "q", NULL });
    });
}

CGSize sf_glyph_canvas(id glyph) {
    sf_resolve();
    CGSize c = sf_getter(glyph, G.canvas, "{CGSize") ? MSG(CGSize)(glyph, G.canvas) : CGSizeZero;
    return (isfinite(c.width) && isfinite(c.height) && c.width > 0 && c.height > 0) ? c : CGSizeZero;
}

CGSize sf_image_canvas(id image) {
    sf_resolve();
    id content = sf_obj_ivar(image, "_content");
    return sf_getter(content, G.vg, "@") ? sf_glyph_canvas(MSG(id)(content, G.vg)) : CGSizeZero;
}

id sf_swap_content(id image, CGImageRef cg) {
    sf_resolve();
    if (!G.swap || !cg || !sf_is(image, G.image)) return NULL;
    double s = MSG(double)(image, G.scale);
    id plain = MSG(id, CGImageRef, double, long)((id)G.image, G.mk, cg, s > 0 ? s : 1.0, 0);
    id content = sf_obj_ivar(plain, "_content");
    id rep = content ? MSG(id, id)(image, G.with, content) : NULL;
    return sf_is(rep, G.image) ? rep : NULL;
}

typedef struct { uint32_t n, r, g, b, a; } sf_bucket;

bool sf_ink_color(CGImageRef img, CGColorRef *color) {
    if (!color) return false;
    *color = NULL;
    size_t iw = img ? CGImageGetWidth(img) : 0, ih = img ? CGImageGetHeight(img) : 0;
    if (!iw || !ih) return false;
    double f = fmin(1.0, (double)SF_SCAN_MAX / (double)(iw > ih ? iw : ih));
    size_t dw = (size_t)fmax(1.0, round(iw * f)), dh = (size_t)fmax(1.0, round(ih * f)), n = dw * dh;
    uint8_t *px = calloc(n, 4);
    sf_bucket *hist = px ? calloc(4096, sizeof(sf_bucket)) : NULL;
    if (!hist) { free(px); return false; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, dw, dh, 8, dw * 4, cs,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (ctx) {
        CGContextSetInterpolationQuality(ctx, f < 1.0 ? kCGInterpolationMedium : kCGInterpolationNone);
        CGContextDrawImage(ctx, CGRectMake(0, 0, dw, dh), img);
        CGContextRelease(ctx);
        uint8_t amax = 0;
        for (size_t i = 0; i < n; i++) if (px[i * 4 + 3] > amax) amax = px[i * 4 + 3];
        uint32_t cut = (uint32_t)amax * 3 / 4, best = 0;
        for (size_t i = 0; amax >= 16 && i < n; i++) {
            const uint8_t *p = px + i * 4;
            if (!p[3] || p[3] < cut) continue;
            uint32_t r = p[0] * 255u / p[3], g = p[1] * 255u / p[3], b = p[2] * 255u / p[3];
            if (r > 255) r = 255;
            if (g > 255) g = 255;
            if (b > 255) b = 255;
            uint32_t k = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
            sf_bucket *e = &hist[k];
            e->n++; e->r += r; e->g += g; e->b += b; e->a += p[3];
            if (e->n > hist[best].n) best = k;
        }
        sf_bucket *e = &hist[best];
        if (e->n) {
            CGFloat c[4] = { e->r / (255.0 * e->n), e->g / (255.0 * e->n), e->b / (255.0 * e->n), e->a / (255.0 * e->n) };
            *color = CGColorCreate(cs, c);
        }
    }
    CGColorSpaceRelease(cs);
    free(hist);
    free(px);
    return *color != NULL;
}

static CGRect sf_fit(double sw, double sh, CGSize canvas, double w, double h) {
    bool ref = canvas.width > 0 && canvas.height > 0;
    double cw = ref ? canvas.width : w, ch = ref ? canvas.height : h;
    double k = fmin(cw / sw, ch / sh);
    double dw = w * sw * k / cw, dh = h * sh * k / ch;
    if (w - dw < 1.0) dw = w;
    if (h - dh < 1.0) dh = h;
    return CGRectMake(round((w - dw) / 2.0), round((h - dh) / 2.0), dw, dh);
}

static CGContextRef sf_context(size_t w, size_t h) {
    if (!w || !h || w > SF_MAX_PX || h > SF_MAX_PX) return NULL;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (ctx) CGContextClearRect(ctx, CGRectMake(0, 0, w, h));
    return ctx;
}

CGImageRef sf_compose(CGImageRef src, CGSize canvas, size_t w, size_t h, CGColorRef fill) {
    size_t sw = src ? CGImageGetWidth(src) : 0, sh = src ? CGImageGetHeight(src) : 0;
    CGContextRef ctx = (sw && sh) ? sf_context(w, h) : NULL;
    if (!ctx) return NULL;
    CGRect r = sf_fit(sw, sh, canvas, w, h);
    bool exact = r.size.width == sw && r.size.height == sh;
    CGContextSetInterpolationQuality(ctx, exact ? kCGInterpolationNone : kCGInterpolationHigh);
    CGContextDrawImage(ctx, r, src);
    if (fill) {
        CGContextSetBlendMode(ctx, kCGBlendModeSourceIn);
        CGContextSetFillColorWithColor(ctx, fill);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    }
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}
