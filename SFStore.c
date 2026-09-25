#include "SFCore.h"
#include <ImageIO/ImageIO.h>
#include <dispatch/dispatch.h>
#include <os/lock.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <limits.h>
#include <roothide.h>

#define SF_DOMAIN  CFSTR("com.iosdump.sfsymbolreplacer")
#define SF_OLD     CFSTR("com.zxms.sfsymbolreplacer")
#define SF_RELOAD  CFSTR("com.iosdump.sfsymbolreplacer/Reload")
#define SF_ENABLED CFSTR("Enabled")
#define SF_MAXPX   2048

#define SF_LOCKED(l, ...) do { os_unfair_lock_lock(l); __VA_ARGS__; os_unfair_lock_unlock(l); } while (0)
#define SF_RELEASE(x) do { if (x) CFRelease(x); } while (0)

typedef struct {
    os_unfair_lock lock;
    CFMutableDictionaryRef d;
    CFMutableArrayRef order;
    size_t cost, max_cost, max_count;
} sf_cache;

static struct {
    os_unfair_lock lock;
    CFDictionaryRef map;
    CFSetRef keep;
    CFMutableSetRef failed;
    bool enabled;
    sf_cache src, comp;
    CFStringRef repdir, map_path, opt_path, prefs_path, old_prefs_path;
} st = { .lock = OS_UNFAIR_LOCK_INIT, .enabled = true };

static inline size_t sf_cost(CGImageRef img) {
    return img ? CGImageGetBytesPerRow(img) * CGImageGetHeight(img) : 0;
}

static void cache_init(sf_cache *c, size_t max_cost, size_t max_count) {
    c->lock = OS_UNFAIR_LOCK_INIT;
    c->d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    c->order = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    c->max_cost = max_cost;
    c->max_count = max_count;
}

static void cache_evict_at(sf_cache *c, CFIndex i) {
    CFStringRef k = CFArrayGetValueAtIndex(c->order, i);
    size_t cost = sf_cost((CGImageRef)CFDictionaryGetValue(c->d, k));
    c->cost = cost > c->cost ? 0 : c->cost - cost;
    CFDictionaryRemoveValue(c->d, k);
    CFArrayRemoveValueAtIndex(c->order, i);
}

static CGImageRef cache_copy(sf_cache *c, CFStringRef k) {
    CGImageRef img;
    SF_LOCKED(&c->lock, img = (CGImageRef)CFDictionaryGetValue(c->d, k); if (img) CGImageRetain(img));
    return img;
}

static void cache_put(sf_cache *c, CFStringRef k, CGImageRef img) {
    os_unfair_lock_lock(&c->lock);
    CFIndex i = CFArrayGetFirstIndexOfValue(c->order, CFRangeMake(0, CFArrayGetCount(c->order)), k);
    if (i != kCFNotFound) cache_evict_at(c, i);
    CFDictionarySetValue(c->d, k, img);
    CFArrayAppendValue(c->order, k);
    c->cost += sf_cost(img);
    while (CFArrayGetCount(c->order) && ((size_t)CFArrayGetCount(c->order) > c->max_count || c->cost > c->max_cost))
        cache_evict_at(c, 0);
    os_unfair_lock_unlock(&c->lock);
}

static void cache_clear(sf_cache *c) {
    SF_LOCKED(&c->lock, CFDictionaryRemoveAllValues(c->d); CFArrayRemoveAllValues(c->order); c->cost = 0);
}

static CFStringRef sf_jbpath(const char *p) {
    const char *r = jbroot(p);
    return CFStringCreateWithCString(NULL, r ? r : p, kCFStringEncodingUTF8);
}

static CFURLRef sf_url(CFStringRef path) CF_RETURNS_RETAINED {
    return CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
}

static CFDictionaryRef sf_read_dict(CFStringRef path) CF_RETURNS_RETAINED {
    CFURLRef url = sf_url(path);
    CFReadStreamRef s = url ? CFReadStreamCreateWithFile(NULL, url) : NULL;
    SF_RELEASE(url);
    if (!s) return NULL;
    CFPropertyListRef pl = NULL;
    if (CFReadStreamOpen(s)) {
        pl = CFPropertyListCreateWithStream(NULL, s, 0, kCFPropertyListImmutable, NULL, NULL);
        CFReadStreamClose(s);
    }
    CFRelease(s);
    if (pl && CFGetTypeID(pl) != CFDictionaryGetTypeID()) { CFRelease(pl); pl = NULL; }
    return pl;
}

static bool sf_bool(CFTypeRef v, bool dflt) {
    if (!v) return dflt;
    CFTypeID t = CFGetTypeID(v);
    if (t == CFBooleanGetTypeID()) return CFBooleanGetValue(v);
    if (t == CFNumberGetTypeID()) { double d = 0; CFNumberGetValue(v, kCFNumberDoubleType, &d); return d != 0; }
    if (t == CFStringGetTypeID()) {
        char b[8] = {0};
        CFStringGetCString(v, b, sizeof b, kCFStringEncodingUTF8);
        const char *p = b;
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        if (*p == '+' || *p == '-') p++;
        while (*p == '0') p++;
        return *p && strchr("YyTt123456789", *p);
    }
    return dflt;
}

static void sf_keep_string_pair(const void *k, const void *v, void *ctx) {
    if (k && v && CFGetTypeID(k) == CFStringGetTypeID() && CFGetTypeID(v) == CFStringGetTypeID())
        CFDictionarySetValue(ctx, k, v);
}

static void sf_keep_colors(const void *k, const void *v, void *ctx) {
    if (k && v && CFGetTypeID(k) == CFStringGetTypeID() && CFGetTypeID(v) == CFDictionaryGetTypeID() &&
        sf_bool(CFDictionaryGetValue(v, CFSTR("KeepColors")), false))
        CFSetAddValue(ctx, k);
}

static void sf_reload(void) {
    SFSymbolReplacerBypassPush();
    CFDictionaryRef disk = sf_read_dict(st.map_path);
    CFDictionaryRef opts = sf_read_dict(st.opt_path);
    CFDictionaryRef prefs = sf_read_dict(st.prefs_path);
    if (!prefs) prefs = sf_read_dict(st.old_prefs_path);
    bool en = true;
    if (prefs) {
        en = sf_bool(CFDictionaryGetValue(prefs, SF_ENABLED), true);
    } else {
        CFPropertyListRef v = CFPreferencesCopyAppValue(SF_ENABLED, SF_DOMAIN);
        if (!v) v = CFPreferencesCopyAppValue(SF_ENABLED, SF_OLD);
        if (v) {
            CFTypeID t = CFGetTypeID(v);
            if (t == CFBooleanGetTypeID() || t == CFNumberGetTypeID()) en = sf_bool(v, true);
            CFRelease(v);
        }
    }
    SFSymbolReplacerBypassPop();

    CFMutableDictionaryRef map = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (disk) CFDictionaryApplyFunction(disk, sf_keep_string_pair, map);
    CFMutableSetRef keep = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
    if (opts) CFDictionaryApplyFunction(opts, sf_keep_colors, keep);
    SF_RELEASE(disk);
    SF_RELEASE(opts);
    SF_RELEASE(prefs);

    CFDictionaryRef old;
    CFSetRef old_keep;
    SF_LOCKED(&st.lock, old = st.map; st.map = map; old_keep = st.keep; st.keep = keep;
              st.enabled = en; CFSetRemoveAllValues(st.failed));
    SF_RELEASE(old);
    SF_RELEASE(old_keep);
    cache_clear(&st.src);
    cache_clear(&st.comp);
}

static void sf_darwin_cb(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef ui) {
    (void)c; (void)o; (void)n; (void)obj; (void)ui;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ sf_reload(); });
}

static void sf_migrate(void) {
    char dst[PATH_MAX], src[PATH_MAX], tmp[PATH_MAX + 32];
    if (geteuid() != 501) return;
    if (!CFStringGetFileSystemRepresentation(st.prefs_path, dst, sizeof dst) ||
        !CFStringGetFileSystemRepresentation(st.old_prefs_path, src, sizeof src)) return;
    if (access(dst, F_OK) == 0 || access(src, R_OK) != 0) return;
    CFDictionaryRef d = sf_read_dict(st.old_prefs_path);
    CFDataRef data = d ? CFPropertyListCreateData(NULL, d, kCFPropertyListBinaryFormat_v1_0, 0, NULL) : NULL;
    SF_RELEASE(d);
    if (!data) return;
    snprintf(tmp, sizeof tmp, "%s.%d.tmp", dst, (int)getpid());
    int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd >= 0) {
        CFIndex len = CFDataGetLength(data);
        bool ok = write(fd, CFDataGetBytePtr(data), (size_t)len) == (ssize_t)len;
        ok = (close(fd) == 0) && ok;
        if (ok) link(tmp, dst);
        unlink(tmp);
    }
    CFRelease(data);
}

static void sf_boot(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFStringRef base = sf_jbpath("/var/mobile/Library/SFSymbolReplacer");
        st.repdir = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/Replacements"), base);
        st.map_path = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/Replacements.plist"), base);
        st.opt_path = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/Options.plist"), base);
        CFRelease(base);
        st.prefs_path = sf_jbpath("/var/mobile/Library/Preferences/com.iosdump.sfsymbolreplacer.plist");
        st.old_prefs_path = sf_jbpath("/var/mobile/Library/Preferences/com.zxms.sfsymbolreplacer.plist");
        st.failed = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
        cache_init(&st.src, 16u << 20, 256);
        cache_init(&st.comp, 12u << 20, 512);
        SFSymbolReplacerBypassPush();
        sf_migrate();
        SFSymbolReplacerBypassPop();
        sf_reload();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &st, sf_darwin_cb, SF_RELOAD, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}

bool sf_store_active(void) {
    sf_boot();
    bool r;
    SF_LOCKED(&st.lock, r = st.enabled && st.map && CFDictionaryGetCount(st.map) > 0);
    return r;
}

bool sf_store_has(CFStringRef name) {
    if (!name || !CFStringGetLength(name)) return false;
    sf_boot();
    bool r;
    SF_LOCKED(&st.lock, r = st.enabled && st.map && CFDictionaryContainsKey(st.map, name));
    return r;
}

bool sf_store_keep(CFStringRef name) {
    if (!name) return false;
    sf_boot();
    bool r;
    SF_LOCKED(&st.lock, r = st.keep && CFSetContainsValue(st.keep, name));
    return r;
}

static CFStringRef sf_path_for(CFStringRef name) CF_RETURNS_RETAINED {
    CFStringRef rel;
    SF_LOCKED(&st.lock, rel = st.map ? CFDictionaryGetValue(st.map, name) : NULL; if (rel) CFRetain(rel));
    if (!rel) return NULL;
    CFStringRef out = NULL;
    if (CFStringGetLength(rel))
        out = CFStringHasPrefix(rel, CFSTR("/")) ? CFRetain(rel) : CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/%@"), st.repdir, rel);
    CFRelease(rel);
    return out;
}

static CFDictionaryRef sf_thumb_opts(void) {
    static CFDictionaryRef opts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int px = SF_MAXPX;
        CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &px);
        const void *k[] = { kCGImageSourceCreateThumbnailFromImageAlways, kCGImageSourceCreateThumbnailWithTransform,
                            kCGImageSourceShouldCacheImmediately, kCGImageSourceThumbnailMaxPixelSize };
        const void *v[] = { kCFBooleanTrue, kCFBooleanTrue, kCFBooleanTrue, n };
        opts = CFDictionaryCreate(NULL, k, v, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(n);
    });
    return opts;
}

static CGImageRef sf_decode(CFStringRef path) CF_RETURNS_RETAINED {
    CGImageRef cg = NULL;
    SFSymbolReplacerBypassPush();
    CFURLRef url = sf_url(path);
    CGImageSourceRef src = url ? CGImageSourceCreateWithURL(url, NULL) : NULL;
    SF_RELEASE(url);
    if (src) {
        if (CGImageSourceGetCount(src) > 0) cg = CGImageSourceCreateThumbnailAtIndex(src, 0, sf_thumb_opts());
        CFRelease(src);
    }
    if (cg && (!CGImageGetWidth(cg) || !CGImageGetHeight(cg))) { CGImageRelease(cg); cg = NULL; }
    SFSymbolReplacerBypassPop();
    return cg;
}

static CGImageRef sf_copy_decoded(CFStringRef name) CF_RETURNS_RETAINED {
    bool on, failed;
    SF_LOCKED(&st.lock, on = st.enabled; failed = CFSetContainsValue(st.failed, name));
    if (!on) return NULL;
    CGImageRef cg = cache_copy(&st.src, name);
    if (cg || failed) return cg;
    CFStringRef path = sf_path_for(name);
    if (!path) return NULL;
    cg = sf_decode(path);
    CFRelease(path);
    if (cg) cache_put(&st.src, name, cg);
    else SF_LOCKED(&st.lock, CFSetAddValue(st.failed, name));
    return cg;
}

CGImageRef sf_store_copy_image(CFStringRef name, size_t w, size_t h, CGSize canvas, CGColorRef tint) {
    if (!w || !h || w > SF_MAXPX || h > SF_MAXPX || !name || !CFStringGetLength(name)) return NULL;
    sf_boot();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGColorRef fill = tint ? CGColorCreateCopyByMatchingToColorSpace(cs, kCGRenderingIntentDefault, tint, NULL) : NULL;
    CGColorSpaceRelease(cs);
    CFMutableStringRef key = CFStringCreateMutable(NULL, 0);
    CFStringAppendFormat(key, NULL, CFSTR("%@|%zu|%zu|%.5f"), name, w, h, canvas.height > 0 ? canvas.width / canvas.height : 0.0);
    if (fill) {
        const CGFloat *c = CGColorGetComponents(fill);
        for (size_t i = 0, n = CGColorGetNumberOfComponents(fill); c && i < n && i < 4; i++)
            CFStringAppendFormat(key, NULL, CFSTR("|%.3f"), c[i]);
    }
    CGImageRef out = cache_copy(&st.comp, key);
    CGImageRef src = out ? NULL : sf_copy_decoded(name);
    if (src) {
        SFSymbolReplacerBypassPush();
        out = sf_compose(src, canvas, w, h, fill);
        SFSymbolReplacerBypassPop();
        if (out) cache_put(&st.comp, key, out);
        CGImageRelease(src);
    }
    SF_RELEASE(fill);
    CFRelease(key);
    return out;
}
