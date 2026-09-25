#include "SFCore.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <os/lock.h>
#include <os/log.h>
#include <dispatch/dispatch.h>
#include <crt_externs.h>
#include <string.h>
#include <math.h>
#include <substrate.h>

static __thread int sDepth;

__attribute__((visibility("default"))) void SFSymbolReplacerBypassPush(void) { sDepth++; }
__attribute__((visibility("default"))) void SFSymbolReplacerBypassPop(void) { if (sDepth > 0) sDepth--; }

#define SF_GUARDED(...) do { sDepth++; @try { __VA_ARGS__; } @catch (__unused id e) {} @finally { sDepth--; } } while (0)

#define MSG(ret, ...) ((ret (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)

static char kProduced, kKeepAlive, kCatKind;
static os_unfair_lock sKeepLock = OS_UNFAIR_LOCK_INIT;
static int sInstalled;

static struct { Class str, bundle; SEL isKind, name, catalog, bundlePath, mode, mg, rmode, cgImage; } R;

static void SFResolve(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        R.str = objc_getClass("NSString");
        R.bundle = objc_getClass("NSBundle");
        R.isKind = sel_registerName("isKindOfClass:");
        R.name = sel_registerName("name");
        R.catalog = sel_registerName("_catalog");
        R.bundlePath = sel_registerName("bundlePath");
        R.mode = sel_registerName("imageWithRenderingMode:");
        R.mg = sel_registerName("_managingCoreGlyphs");
        R.rmode = sel_registerName("renderingMode");
        R.cgImage = sel_registerName("CGImage");
    });
}

static inline bool SFIsKind(id o, Class c) { return o && c && MSG(BOOL, Class)(o, R.isKind, c); }
static inline bool SFResponds(id o, SEL s) { return o && class_respondsToSelector(object_getClass(o), s); }
static inline bool SFIsProduced(id o) { return o && objc_getAssociatedObject(o, &kProduced); }
static inline void SFMarkProduced(id o) { if (o) objc_setAssociatedObject(o, &kProduced, (__bridge id)kCFBooleanTrue, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

static inline bool SFHasSub(CFStringRef s, CFStringRef sub) {
    return CFStringFind(s, sub, 0).location != kCFNotFound;
}

static int SFCatalogKind(id cat) {
    if (!cat) return 0;
    CFTypeRef c = (__bridge CFTypeRef)objc_getAssociatedObject(cat, &kCatKind);
    int kind = 0;
    if (c && CFGetTypeID(c) == CFNumberGetTypeID() && CFNumberGetValue(c, kCFNumberIntType, &kind)) return kind;
    id bundle = sf_obj_ivar(cat, "_bundle");
    if (SFIsKind(bundle, R.bundle)) {
        id p = MSG(id)(bundle, R.bundlePath);
        CFStringRef s = (__bridge CFStringRef)p;
        if (SFIsKind(p, R.str) && CFStringGetLength(s))
            kind = (SFHasSub(s, CFSTR("CoreGlyphs")) || SFHasSub(s, CFSTR("SFSymbols.framework"))) ? 1 : 2;
    }
    if (kind) {
        CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &kind);
        objc_setAssociatedObject(cat, &kCatKind, (__bridge id)n, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CFRelease(n);
    }
    return kind;
}

static id SFGlyphCatalog(id glyph) {
    if (SFResponds(glyph, R.catalog)) return MSG(id)(glyph, R.catalog);
    return sf_obj_ivar(glyph, "_catalog"); // 14/15
}

static bool SFShouldReplace(id glyph, CFStringRef *out) {
    if (sDepth > 0 || !glyph) return false;
    SFResolve();
    bool yes = false;
    SF_GUARDED({
        if (!sf_store_active() || !SFResponds(glyph, R.name)) break;
        id n = MSG(id)(glyph, R.name);
        CFStringRef s = (__bridge CFStringRef)n;
        if (!SFIsKind(n, R.str) || !CFStringGetLength(s) || !sf_store_has(s)) break;
        int k = SFCatalogKind(SFGlyphCatalog(glyph));
        if (k == 1 || (k == 0 && !SFHasSub(s, CFSTR("/")))) {
            if (out) *out = CFStringCreateCopy(NULL, s);
            yes = true;
        }
    });
    return yes;
}

static inline size_t SFPixels(double pt, double scale) {
    if (!(pt > 0) || !(scale > 0)) return 0;
    double px = ceil(pt * scale);
    return px <= 2048.0 ? (size_t)px : 0;
}

static CGImageRef SFCopyRep(id glyph, CFStringRef name, CGImageRef stock, size_t w, size_t h, CGColorRef tint) {
    CGImageRef r = NULL;
    SF_GUARDED({
        bool keep = sf_store_keep(name);
        CGColorRef sampled = NULL;
        if (!keep && !tint && stock) sf_ink_color(stock, &sampled);
        r = sf_store_copy_image(name, w, h, sf_glyph_canvas(glyph), keep ? NULL : (tint ?: sampled));
        CGColorRelease(sampled);
    });
    return r;
}

static CGImageRef SFReplaceOwned(id glyph, double scale, CGSize target, CFStringRef name, CGImageRef orig, CGColorRef tint) {
    size_t w = orig ? CGImageGetWidth(orig) : SFPixels(target.width, scale), h = orig ? CGImageGetHeight(orig) : SFPixels(target.height, scale);
    if (!w || !h) return orig;
    CGImageRef rep = SFCopyRep(glyph, name, orig, w, h, tint);
    if (!rep) return orig;
    if (orig) CGImageRelease(orig);
    return rep;
}

static CGImageRef SFReplaceBorrowed(id glyph, CFStringRef name, CGImageRef orig, CGColorRef tint) {
    if (!orig || !glyph) return orig;
    size_t w = CGImageGetWidth(orig), h = CGImageGetHeight(orig);
    CGImageRef rep = (w && h) ? SFCopyRep(glyph, name, orig, w, h, tint) : NULL;
    if (!rep) return orig;
    bool kept = false;
    os_unfair_lock_lock(&sKeepLock);
    CFMutableSetRef set = (__bridge CFMutableSetRef)objc_getAssociatedObject(glyph, &kKeepAlive);
    if (!set) {
        set = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
        objc_setAssociatedObject(glyph, &kKeepAlive, (__bridge id)set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CFRelease(set);
    }
    if (CFSetContainsValue(set, rep)) kept = true;
    else if (CFSetGetCount(set) < 32) { CFSetAddValue(set, rep); kept = true; }
    os_unfair_lock_unlock(&sKeepLock);
    CGImageRelease(rep);
    return kept ? rep : orig;
}

#define _P(...) __VA_ARGS__

#define SF_RASTER(tag, DECL, CALL, SC, SZ, TINT) \
    static CGImageRef (*o_##tag)(id, SEL _P DECL); \
    static CGImageRef h_##tag(id self, SEL _cmd _P DECL) { \
        CFStringRef name = NULL; \
        if (!SFShouldReplace(self, &name)) return o_##tag(self, _cmd _P CALL); \
        CGImageRef o = NULL; \
        sDepth++; @try { o = o_##tag(self, _cmd _P CALL); } @finally { sDepth--; } \
        o = SFReplaceOwned(self, (SC), (SZ), name, o, (TINT)); \
        CFRelease(name); \
        return o; \
    }

#define SF_IMAGE(tag, DECL, CALL, TINT) \
    static CGImageRef (*o_##tag)(id, SEL _P DECL); \
    static CGImageRef h_##tag(id self, SEL _cmd _P DECL) { \
        CFStringRef name = NULL; \
        if (!SFShouldReplace(self, &name)) return o_##tag(self, _cmd _P CALL); \
        CGImageRef o = NULL; \
        sDepth++; @try { o = o_##tag(self, _cmd _P CALL); } @finally { sDepth--; } \
        o = SFReplaceBorrowed(self, name, o, (TINT)); \
        CFRelease(name); \
        return o; \
    }

#define SF_GLYPH_HOOKS(P) \
    SF_RASTER(P##_r,    (, double s, CGSize z),               (, s, z),    s, z, NULL) \
    SF_RASTER(P##_rCR,  (, double s, CGSize z, id b),         (, s, z, b), s, z, NULL) \
    SF_RASTER(P##_rHCR, (, double s, CGSize z, id b),         (, s, z, b), s, z, NULL) \
    SF_RASTER(P##_rPC,  (, double s, CGSize z, id a),         (, s, z, a), s, z, NULL) \
    SF_RASTER(P##_rPCR, (, double s, CGSize z, id b),         (, s, z, b), s, z, NULL) \
    SF_RASTER(P##_rHPC, (, double s, CGSize z, CGColorRef c), (, s, z, c), s, z, c) \
    SF_RASTER(P##_rTCs, (, double s, CGSize z, id a),         (, s, z, a), s, z, NULL) \
    SF_RASTER(P##_rTC,  (, CGColorRef c, double s, CGSize z), (, c, s, z), s, z, c) \
    SF_IMAGE(P##_i,    (),               (),     NULL) \
    SF_IMAGE(P##_iCR,  (, id b),         (, b),  NULL) \
    SF_IMAGE(P##_iHCR, (, id b),         (, b),  NULL) \
    SF_IMAGE(P##_iPC,  (, id a),         (, a),  NULL) \
    SF_IMAGE(P##_iPCR, (, id b),         (, b),  NULL) \
    SF_IMAGE(P##_iHPC, (, CGColorRef c), (, c),  c) \
    SF_IMAGE(P##_iTC,  (, CGColorRef c), (, c),  c) \
    SF_IMAGE(P##_iTCs, (, id a),         (, a),  NULL) \
    SF_IMAGE(P##_iWTC, (, CGColorRef c), (, c),  c)

SF_GLYPH_HOOKS(G)
SF_GLYPH_HOOKS(V)

static Method SFOwnMethod(Class cls, SEL sel) {
    Method found = NULL;
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    for (unsigned int i = 0; list && i < n && !found; i++)
        if (method_getName(list[i]) == sel) found = list[i];
    free(list);
    return found;
}

static void SFHook(Class cls, bool own, const char *name, IMP h, IMP *o, const char *ret, const char **args) {
    if (!cls) return;
    SEL sel = sel_registerName(name);
    Method m = own ? SFOwnMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (!sf_sig_ok(m, ret, args)) {
        os_log(OS_LOG_DEFAULT, "[SFSymbolReplacer] skip %{public}s %{public}s: unexpected type encoding %{public}s",
               class_getName(cls), name, method_getTypeEncoding(m));
        return;
    }
    MSHookMessageEx(cls, sel, h, o);
    if (*o) sInstalled++;
}

static void SFHookMeta(Class cls, const char *name, IMP h, IMP *o, const char **args) {
    if (!cls) return;
    SEL sel = sel_registerName(name);
    if (!sf_sig_ok(class_getClassMethod(cls, sel), "@", args)) return;
    MSHookMessageEx(object_getClass(cls), sel, h, o);
    if (*o) sInstalled++;
}

#define A(...) ((const char *[]){ __VA_ARGS__, NULL })
#define A0     ((const char *[]){ NULL })
#define CGIMG  "^{CGImage"
#define SZ     "d", "{CGSize"
#define COL    "^{CGColor"

#define HOOK(c, sel, tag, ...)  SFHook(c, true, sel, (IMP)h_##tag, (IMP *)&o_##tag, CGIMG, __VA_ARGS__)
#define HOOKC(c, sel, tag, ...) SFHookMeta(c, sel, (IMP)h_##tag, (IMP *)&o_##tag, __VA_ARGS__)

#define SF_INSTALL_GLYPH(c, P) do { \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:",                            P##_r,    A(SZ)); \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:withColorResolver:",          P##_rCR,  A(SZ, "@")); \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:withHierarchyColorResolver:", P##_rHCR, A(SZ, "@")); \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:withPaletteColors:",          P##_rPC,  A(SZ, "@")); \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:withPaletteColorResolver:",   P##_rPCR, A(SZ, "@")); \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:hierarchicalPrimaryColor:",   P##_rHPC, A(SZ, COL)); \
    HOOK(c, "rasterizeImageUsingScaleFactor:forTargetSize:withTintColors:",             P##_rTCs, A(SZ, "@")); \
    HOOK(c, "rasterizeImageWithTintColor:usingScaleFactor:forTargetSize:",              P##_rTC,  A(COL, SZ)); \
    HOOK(c, "image",                              P##_i,    A0); \
    HOOK(c, "imageWithColorResolver:",            P##_iCR,  A("@")); \
    HOOK(c, "imageWithHierarchyColorResolver:",   P##_iHCR, A("@")); \
    HOOK(c, "imageWithPaletteColors:",            P##_iPC,  A("@")); \
    HOOK(c, "imageWithPaletteColorResolver:",     P##_iPCR, A("@")); \
    HOOK(c, "imageWithHierarchicalPrimaryColor:", P##_iHPC, A(COL)); \
    HOOK(c, "imageTintedWithColor:",              P##_iTC,  A(COL)); \
    HOOK(c, "imageTintedWithColors:",             P##_iTCs, A("@")); \
    HOOK(c, "imageWithTintColor:",                P##_iWTC, A(COL)); \
} while (0)

enum { kRenderAuto = 0, kRenderOriginal = 1, kRenderTemplate = 2 };

static bool sInfo;

static void SFResolveUIKit(Class img) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sInfo = sf_sig_ok(class_getInstanceMethod(img, R.rmode), "q", A0)
             && sf_sig_ok(class_getInstanceMethod(img, R.cgImage), CGIMG, A0);
    });
}

static id SFApply(id named, id orig) {
    if (sDepth > 0 || !orig || SFIsProduced(orig)) return orig;
    SFResolve();
    CFStringRef name = (__bridge CFStringRef)named;
    if (!SFIsKind(named, R.str) || !CFStringGetLength(name)) return orig;
    Class img = objc_getClass("UIImage");
    if (!SFIsKind(orig, img)) return orig;
    SFResolveUIKit(img);
    id res = orig;
    SF_GUARDED({
        if (!sInfo || !sf_store_active() || !sf_store_has(name)) break;
        CGImageRef stock = MSG(CGImageRef)(orig, R.cgImage);
        size_t w = stock ? CGImageGetWidth(stock) : 0, h = stock ? CGImageGetHeight(stock) : 0;
        if (!w || !h) break;
        bool keep = sf_store_keep(name);
        NSInteger mode = MSG(NSInteger)(orig, R.rmode);
        NSInteger want = keep ? kRenderOriginal : (mode == kRenderAuto ? kRenderTemplate : mode);
        CGColorRef tint = NULL;
        if (!keep && want == kRenderOriginal) sf_ink_color(stock, &tint);
        CGImageRef cg = sf_store_copy_image(name, w, h, sf_image_canvas(orig), tint);
        CGColorRelease(tint);
        if (!cg) break;
        id rep = sf_swap_content(orig, cg);
        CGImageRelease(cg);
        if (!rep) break;
        id o = MSG(id, NSInteger)(rep, R.mode, want);
        if (o) rep = o;
        SFMarkProduced(rep);
        res = rep;
    });
    return res;
}

#define SF_H1(t) \
    static id (*o_##t)(id, SEL, id); \
    static id h_##t(id self, SEL _cmd, id n) { return SFApply(n, o_##t(self, _cmd, n)); }
#define SF_H2(t) \
    static id (*o_##t)(id, SEL, id, id); \
    static id h_##t(id self, SEL _cmd, id n, id x) { return SFApply(n, o_##t(self, _cmd, n, x)); }

SF_H1(sys)   SF_H2(sysCfg)   SF_H2(sysTrait)
SF_H1(uuSys) SF_H2(uuSysCfg) SF_H2(uuSysTrait)
SF_H1(uSys)  SF_H2(uSysCfg)  SF_H2(uSysFb)

static id (*o_uSysCfgPriv)(id, SEL, id, id, BOOL);
static id h_uSysCfgPriv(id self, SEL _cmd, id n, id c, BOOL p) { return SFApply(n, o_uSysCfgPriv(self, _cmd, n, c, p)); }
static id (*o_uSysFbCfg)(id, SEL, id, id, id);
static id h_uSysFbCfg(id self, SEL _cmd, id n, id f, id c) { return SFApply(n, o_uSysFbCfg(self, _cmd, n, f, c)); }
static id (*o_sysVV)(id, SEL, id, double, id);
static id h_sysVV(id self, SEL _cmd, id n, double v, id c) { return SFApply(n, o_sysVV(self, _cmd, n, v, c)); }
static id (*o_uSysVV)(id, SEL, id, double, id);
static id h_uSysVV(id self, SEL _cmd, id n, double v, id c) { return SFApply(n, o_uSysVV(self, _cmd, n, v, c)); }

static id (*o_amNamed)(id, SEL, id, id);
static id h_amNamed(id self, SEL _cmd, id n, id c) {
    id r = o_amNamed(self, _cmd, n, c);
    if (sDepth > 0 || !r) return r;
    SFResolve();
    bool glyphs = false;
    @try {
        if (SFResponds(self, R.mg)) glyphs = MSG(BOOL)(self, R.mg);
    } @catch (__unused id e) {}
    return glyphs ? SFApply(n, r) : r;
}

static bool SFWantProcess(void) {
    CFBundleRef b = CFBundleGetMainBundle();
    CFStringRef bid = b ? CFBundleGetIdentifier(b) : NULL;
    if (bid && CFStringGetLength(bid)) return true;
    char **argv = *_NSGetArgv();
    const char *exe = argv ? argv[0] : NULL;
    if (exe && (!strncmp(exe, "/usr/", 5) || !strncmp(exe, "/bin/", 5) || !strncmp(exe, "/sbin/", 6))) return false;
    return true;
}

SF_PRIVATE void SFSymbolReplacerInstallHooks(void) {
    if (!SFWantProcess()) return;
    SFResolve();

    Class c;
    if ((c = objc_getClass("CUINamedVectorGlyph"))) SF_INSTALL_GLYPH(c, G);
    if ((c = objc_getClass("_CUIGraphicVariantVectorGlyph"))) SF_INSTALL_GLYPH(c, V);

    if ((c = objc_getClass("UIImage"))) {
        HOOKC(c, "systemImageNamed:",                                  sys,         A("@"));
        HOOKC(c, "systemImageNamed:withConfiguration:",                sysCfg,      A("@", "@"));
        HOOKC(c, "systemImageNamed:compatibleWithTraitCollection:",    sysTrait,    A("@", "@"));
        HOOKC(c, "__systemImageNamed:",                                uuSys,       A("@"));
        HOOKC(c, "__systemImageNamed:withConfiguration:",              uuSysCfg,    A("@", "@"));
        HOOKC(c, "__systemImageNamed:compatibleWithTraitCollection:",  uuSysTrait,  A("@", "@"));
        HOOKC(c, "_systemImageNamed:",                                 uSys,        A("@"));
        HOOKC(c, "_systemImageNamed:withConfiguration:",               uSysCfg,     A("@", "@"));
        HOOKC(c, "_systemImageNamed:withConfiguration:allowPrivate:",  uSysCfgPriv, A("@", "@", "B"));
        HOOKC(c, "_systemImageNamed:fallback:",                        uSysFb,      A("@", "@"));
        HOOKC(c, "_systemImageNamed:fallback:withConfiguration:",      uSysFbCfg,   A("@", "@", "@"));
        HOOKC(c, "systemImageNamed:variableValue:withConfiguration:",  sysVV,       A("@", "d", "@"));
        HOOKC(c, "_systemImageNamed:variableValue:withConfiguration:", uSysVV,      A("@", "d", "@"));
    }
    if ((c = objc_getClass("_UIAssetManager")))
        SFHook(c, false, "imageNamed:configuration:", (IMP)h_amNamed, (IMP *)&o_amNamed, "@", A("@", "@"));

    os_log(OS_LOG_DEFAULT, "[SFSymbolReplacer] 1.0.9 installed %d hooks", sInstalled);
}
