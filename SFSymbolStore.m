#import "SFSymbolStore.h"
#import <CoreFoundation/CoreFoundation.h>
#import <ImageIO/ImageIO.h>
#import <os/lock.h>
#import <dlfcn.h>
#import <roothide.h>
#import <UIKit/UIKit.h>
#import "sfsymbolreplacerprefs/SFLocalize.h"
#import "SFPlace.h"

NS_INLINE NSString *SFStoreFmt1(NSString *key, NSString *arg) {
    return [NSString stringWithFormat:SFL(key), arg ?: @""];
}

#define SF_ERR(c, msg) [NSError errorWithDomain:@"SFSymbolReplacer" code:(c) userInfo:@{ NSLocalizedDescriptionKey: (msg) }]

static NSString * const kSFSymbolReplacerReloadNotification = @"com.iosdump.sfsymbolreplacer/Reload";
static NSString * const kSFSymbolReplacerPrefsDomain = @"com.iosdump.sfsymbolreplacer";
static NSString * const kOldDomain = @"com.zxms.sfsymbolreplacer";
static NSString * const kSFSymbolReplacerEnabledKey = @"Enabled";

static NSString * const kMapFileName = @"Replacements.plist";
static NSString * const kOptionsFileName = @"Options.plist";
static NSString * const kKeepColorsKey = @"KeepColors";
static NSString * const kReplacementsFolder = @"Replacements";

static const CGFloat kSFMaxPx = 2048.0;
static const CGFloat kSFExportSide = 512.0;
static const CGFloat kSFProbePoint = 100.0;

@interface SFSymbolStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *map;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *options;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *imageCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *placedCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *failedNames;
@property (nonatomic, strong) NSLock *lock;
@end

static void SFStoreSetBypass(BOOL on) {
    static void (*push)(void), (*pop)(void);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        push = (__typeof__(push))dlsym(RTLD_DEFAULT, "SFSymbolReplacerBypassPush");
        pop = (__typeof__(pop))dlsym(RTLD_DEFAULT, "SFSymbolReplacerBypassPop");
    });
    __typeof__(push) fn = on ? push : pop;
    if (fn) fn();
}

@implementation SFSymbolStore {
    BOOL _enabled;
}

- (BOOL)isEnabled { return _enabled; }

+ (instancetype)sharedStore {
    static SFSymbolStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [self new]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _map = [NSMutableDictionary dictionary];
        _options = [NSMutableDictionary dictionary];
        _imageCache = [NSMutableDictionary dictionary];
        _placedCache = [NSMutableDictionary dictionary];
        _failedNames = [NSMutableSet set];
        _lock = [[NSLock alloc] init];
        _enabled = YES;
        [self migrate];
        [self reload];
        [self registerDarwinObserver];
    }
    return self;
}

- (NSString *)baseDirectory {
    return jbroot(@"/var/mobile/Library/SFSymbolReplacer");
}

- (NSString *)replacementsDirectory {
    return [[self baseDirectory] stringByAppendingPathComponent:kReplacementsFolder];
}

- (NSString *)mapPlistPath {
    return [[self baseDirectory] stringByAppendingPathComponent:kMapFileName];
}

- (NSString *)optionsPlistPath {
    return [[self baseDirectory] stringByAppendingPathComponent:kOptionsFileName];
}

- (NSString *)prefsPlistPath {
    return jbroot([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kSFSymbolReplacerPrefsDomain]);
}

- (void)migrate {
    @try {
        NSString *path = [self prefsPlistPath];
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:path]) return;
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                           jbroot([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kOldDomain])];
        if (![d isKindOfClass:[NSDictionary class]] || d.count == 0) {
            CFDictionaryRef cf = CFPreferencesCopyMultiple(NULL, (__bridge CFStringRef)kOldDomain,
                                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            d = CFBridgingRelease(cf);
        }
        if (![d isKindOfClass:[NSDictionary class]] || d.count == 0) return;
        CFStringRef dom = (__bridge CFStringRef)kSFSymbolReplacerPrefsDomain;
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)d, NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(dom);
        if (![fm fileExistsAtPath:path]) [d writeToFile:path atomically:YES];
    } @catch (__unused NSException *e) {}
}

- (BOOL)mkdirs:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [self replacementsDirectory];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir) return YES;
    NSError *err = nil;
    BOOL ok = [fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @0755} error:&err];
    if (!ok && error) *error = err;
    return ok;
}

- (void)reload {
    SFStoreSetBypass(YES);
    NSDictionary *disk = nil, *opts = nil, *prefs = nil;
    @try {
        disk = [NSDictionary dictionaryWithContentsOfFile:[self mapPlistPath]];
        opts = [NSDictionary dictionaryWithContentsOfFile:[self optionsPlistPath]];
        prefs = [NSDictionary dictionaryWithContentsOfFile:[self prefsPlistPath]];
    } @catch (__unused NSException *e) {}
    BOOL enabled = YES;
    if (prefs) {
        id en = prefs[kSFSymbolReplacerEnabledKey];
        enabled = (en == nil) ? YES : [en boolValue];
    } else {
        CFPropertyListRef val = CFPreferencesCopyAppValue(
            (__bridge CFStringRef)kSFSymbolReplacerEnabledKey,
            (__bridge CFStringRef)kSFSymbolReplacerPrefsDomain);
        if (val != NULL) {
            if (CFGetTypeID(val) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue((CFBooleanRef)val);
            else if (CFGetTypeID(val) == CFNumberGetTypeID()) enabled = [(__bridge NSNumber *)val boolValue];
            CFRelease(val);
        }
    }
    SFStoreSetBypass(NO);

    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    if ([disk isKindOfClass:[NSDictionary class]]) {
        for (id k in disk) {
            id v = disk[k];
            if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]]) map[k] = v;
        }
    }
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    if ([opts isKindOfClass:[NSDictionary class]]) {
        for (id k in opts) {
            id v = opts[k];
            if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSDictionary class]]) options[k] = v;
        }
    }

    [self.lock lock];
    _map = map;
    _options = options;
    [_imageCache removeAllObjects];
    [_placedCache removeAllObjects];
    [_failedNames removeAllObjects];
    _enabled = enabled;
    [self.lock unlock];
}

- (void)setEnabled:(BOOL)enabled {
    [self.lock lock];
    _enabled = enabled;
    [self.lock unlock];
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)kSFSymbolReplacerEnabledKey,
        (__bridge CFPropertyListRef)@(enabled),
        (__bridge CFStringRef)kSFSymbolReplacerPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSFSymbolReplacerPrefsDomain);
    NSString *prefsPath = [self prefsPlistPath];
    NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:prefsPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    d[kSFSymbolReplacerEnabledKey] = @(enabled);
    [d writeToFile:prefsPath atomically:YES];
    [self postReloadNotification];
}

- (nullable id)preferenceValueForKey:(NSString *)key {
    if (key.length == 0) return nil;
    id v = nil;
    @try {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self prefsPlistPath]];
        v = [d isKindOfClass:[NSDictionary class]] ? d[key] : nil;
        if (!v) {
            CFPropertyListRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kSFSymbolReplacerPrefsDomain);
            if (cf) v = CFBridgingRelease(cf);
        }
    } @catch (__unused NSException *e) { v = nil; }
    return v;
}

- (void)setPreferenceValue:(nullable id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    @try {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                                 (__bridge CFStringRef)kSFSymbolReplacerPrefsDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)kSFSymbolReplacerPrefsDomain);
        NSString *path = [self prefsPlistPath];
        NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
        if (value) d[key] = value; else [d removeObjectForKey:key];
        [d writeToFile:path atomically:YES];
    } @catch (__unused NSException *e) {}
}

- (void)registerDarwinObserver {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        SFDarwinReload,
        (__bridge CFStringRef)kSFSymbolReplacerReloadNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

static void SFDarwinReload(__unused CFNotificationCenterRef c, void *observer, __unused CFStringRef n,
                                        __unused const void *o, __unused CFDictionaryRef ui) {
    SFSymbolStore *store = (__bridge SFSymbolStore *)observer;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [store reload]; });
}

- (void)postReloadNotification {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kSFSymbolReplacerReloadNotification,
        NULL, NULL, true);
}

- (nullable NSString *)replacementPathForSymbolName:(NSString *)name {
    if (name.length == 0) return nil;
    [self.lock lock];
    NSString *path = self.map[name];
    [self.lock unlock];
    if (path.length == 0) return nil;
    if ([path hasPrefix:@"/"]) return path;
    return [[self replacementsDirectory] stringByAppendingPathComponent:path];
}

- (BOOL)hasReplacementForSymbolName:(NSString *)name {
    return [self replacementPathForSymbolName:name] != nil;
}

static CGImageRef SFCopyDecodedCGImageAtPath(NSString *path) CF_RETURNS_RETAINED;
static CGImageRef SFCopyDecodedCGImageAtPath(NSString *path) {
    if (path.length == 0) return NULL;
    CGImageRef cg = NULL;
    SFStoreSetBypass(YES);
    @try {
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef src = url ? CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL) : NULL;
        if (src) {
            if (CGImageSourceGetCount(src) > 0) {
                NSDictionary *opts = @{
                    (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                    (id)kCGImageSourceShouldCacheImmediately: @YES,
                    (id)kCGImageSourceThumbnailMaxPixelSize: @((int)kSFMaxPx),
                };
                cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
            }
            CFRelease(src);
        }
        if (cg && (CGImageGetWidth(cg) == 0 || CGImageGetHeight(cg) == 0)) {
            CGImageRelease(cg);
            cg = NULL;
        }
    } @catch (__unused NSException *e) {
        if (cg) CGImageRelease(cg);
        cg = NULL;
    }
    SFStoreSetBypass(NO);
    return cg;
}

- (nullable UIImage *)replacementImageForSymbolName:(NSString *)name {
    if (name.length == 0) return nil;
    [self.lock lock];
    UIImage *cached = self.imageCache[name];
    BOOL failed = [self.failedNames containsObject:name];
    [self.lock unlock];
    if (cached) return cached;
    if (failed) return nil;

    NSString *path = [self replacementPathForSymbolName:name];
    if (!path) return nil;
    CGImageRef cg = SFCopyDecodedCGImageAtPath(path);
    if (!cg) {
        [self.lock lock];
        [self.failedNames addObject:name];
        [self.lock unlock];
        return nil;
    }
    UIImage *img = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    UIImage *original = [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (!original) return nil;
    [self.lock lock];
    self.imageCache[name] = original;
    [self.lock unlock];
    return original;
}

- (BOOL)persistMap:(NSError **)error {
    [self mkdirs:NULL];
    [self.lock lock];
    NSDictionary *snap = [self.map copy];
    [self.lock unlock];
    NSError *werr = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snap format:NSPropertyListXMLFormat_v1_0 options:0 error:&werr];
    BOOL ok = data && [data writeToFile:[self mapPlistPath] options:NSDataWritingAtomic error:&werr];
    if (!ok && error) *error = SF_ERR(1, SFStoreFmt1(@"err.writeConfigFmt", werr.localizedDescription ?: [self mapPlistPath]));
    return ok;
}

- (BOOL)persistOptions:(NSError **)error {
    [self mkdirs:NULL];
    [self.lock lock];
    NSDictionary *snap = [self.options copy];
    [self.lock unlock];
    NSError *werr = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snap format:NSPropertyListXMLFormat_v1_0 options:0 error:&werr];
    BOOL ok = data && [data writeToFile:[self optionsPlistPath] options:NSDataWritingAtomic error:&werr];
    if (!ok && error) *error = SF_ERR(1, SFStoreFmt1(@"err.writeConfigFmt", werr.localizedDescription ?: [self optionsPlistPath]));
    return ok;
}

- (BOOL)keepsColorsForSymbolName:(NSString *)name {
    if (name.length == 0) return NO;
    [self.lock lock];
    id v = self.options[name][kKeepColorsKey];
    [self.lock unlock];
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

- (BOOL)setKeepsColors:(BOOL)keep forSymbolName:(NSString *)name error:(NSError **)error {
    if (name.length == 0) return NO;
    [self.lock lock];
    NSDictionary *previous = self.options[name];
    NSMutableDictionary *d = [previous mutableCopy] ?: [NSMutableDictionary dictionary];
    if (keep) d[kKeepColorsKey] = @YES; else [d removeObjectForKey:kKeepColorsKey];
    if (d.count) self.options[name] = d; else [self.options removeObjectForKey:name];
    [self.lock unlock];
    if (![self persistOptions:error]) {
        [self.lock lock];
        if (previous) self.options[name] = previous; else [self.options removeObjectForKey:name];
        [self.lock unlock];
        return NO;
    }
    [self postReloadNotification];
    return YES;
}

- (void)dropOptionsForNames:(NSArray<NSString *> *)names {
    [self.lock lock];
    NSUInteger before = self.options.count;
    [self.options removeObjectsForKeys:names];
    BOOL changed = self.options.count != before;
    [self.lock unlock];
    if (changed) [self persistOptions:NULL];
}

static CGImageRef SFCopyUprightCGImage(UIImage *image) CF_RETURNS_RETAINED {
    CGImageRef cg = image.CGImage;
    if (cg && image.imageOrientation == UIImageOrientationUp) return CGImageRetain(cg);
    CGSize px = CGSizeMake(round(image.size.width * image.scale), round(image.size.height * image.scale));
    if (!(px.width > 0) || !(px.height > 0) || px.width > kSFMaxPx || px.height > kSFMaxPx) return NULL;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = NO;
    UIImage *flat = [[[UIGraphicsImageRenderer alloc] initWithSize:px format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *c) {
        [[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:CGRectMake(0, 0, px.width, px.height)];
    }];
    return flat.CGImage ? CGImageRetain(flat.CGImage) : NULL;
}

static NSData *SFPNGData(CGImageRef cg) {
    if (!cg) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    if (!dst) return nil;
    CGImageDestinationAddImage(dst, cg, NULL);
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    return ok && data.length ? data : nil;
}

- (BOOL)saveReplacementImage:(UIImage *)importedImage forSymbolName:(NSString *)name error:(NSError **)error {
    return [self saveReplacementImage:importedImage forSymbolName:name notify:YES error:error];
}

- (BOOL)saveReplacementImage:(UIImage *)importedImage forSymbolName:(NSString *)name notify:(BOOL)notify error:(NSError **)error {
    if (!importedImage || name.length == 0) {
        if (error) *error = SF_ERR(2, SFL(@"err.invalid"));
        return NO;
    }
    CGImageRef upright = NULL;
    @try { upright = SFCopyUprightCGImage(importedImage); } @catch (__unused NSException *e) { upright = NULL; }
    NSData *png = SFPNGData(upright);
    if (upright) CGImageRelease(upright);
    if (!png) {
        if (error) *error = SF_ERR(3, SFL(@"err.pngEncode"));
        return NO;
    }

    NSError *dirErr = nil;
    if (![self mkdirs:&dirErr]) {
        if (error) *error = SF_ERR(5, SFStoreFmt1(@"err.mkdirFmt", dirErr.localizedDescription ?: [self replacementsDirectory]));
        return NO;
    }
    NSString *fileName = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                          stringByAppendingPathExtension:@"png"];
    NSString *dest = [[self replacementsDirectory] stringByAppendingPathComponent:fileName];
    NSError *writeErr = nil;
    if (![png writeToFile:dest options:NSDataWritingAtomic error:&writeErr]) {
        if (error) *error = SF_ERR(4, SFStoreFmt1(@"err.writePNGFmt", writeErr.localizedDescription ?: dest));
        return NO;
    }

    [self.lock lock];
    NSString *previous = self.map[name];
    self.map[name] = fileName;
    [self.failedNames removeObject:name];
    [self.imageCache removeObjectForKey:name];
    [self.placedCache removeAllObjects];
    [self.lock unlock];

    BOOL ok = [self persistMap:error];
    if (!ok) {
        [self.lock lock];
        if (previous) self.map[name] = previous; else [self.map removeObjectForKey:name];
        [self.lock unlock];
        if (!previous) [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        return NO;
    }
    if (notify) [self postReloadNotification];
    return YES;
}

- (BOOL)removeReplacementForSymbolName:(NSString *)name error:(NSError **)error {
    if (name.length == 0) return NO;
    NSString *path = [self replacementPathForSymbolName:name];
    [self.lock lock];
    NSString *previous = self.map[name];
    [self.map removeObjectForKey:name];
    [self.failedNames removeObject:name];
    [self.imageCache removeObjectForKey:name];
    [self.placedCache removeAllObjects];
    [self.lock unlock];
    if (![self persistMap:error]) {
        [self.lock lock];
        if (previous) self.map[name] = previous;
        [self.lock unlock];
        return NO;
    }
    if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [self dropOptionsForNames:@[name]];
    [self postReloadNotification];
    return YES;
}

- (NSArray<NSString *> *)replacedSymbolNames {
    [self.lock lock];
    NSArray *keys = [self.map allKeys];
    [self.lock unlock];
    return [keys sortedArrayUsingSelector:@selector(localizedStandardCompare:)] ?: @[];
}

- (BOOL)removeAllReplacements:(NSError **)error {
    NSArray<NSString *> *names = [self replacedSymbolNames];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *n in names) {
        NSString *p = [self replacementPathForSymbolName:n];
        if (p) [paths addObject:p];
    }
    [self.lock lock];
    NSDictionary *previous = [self.map copy];
    [self.map removeAllObjects];
    [self.imageCache removeAllObjects];
    [self.placedCache removeAllObjects];
    [self.failedNames removeAllObjects];
    [self.lock unlock];
    if (![self persistMap:error]) {
        [self.lock lock];
        [self.map addEntriesFromDictionary:previous ?: @{}];
        [self.lock unlock];
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in paths) [fm removeItemAtPath:p error:nil];
    [self dropOptionsForNames:names];
    [self postReloadNotification];
    return YES;
}

+ (void)beginBypass { SFStoreSetBypass(YES); }
+ (void)endBypass { SFStoreSetBypass(NO); }

+ (nullable UIImage *)renderedOriginalSymbolNamed:(NSString *)name
                                   configuration:(nullable UIImageSymbolConfiguration *)cfg
                                           color:(nullable UIColor *)color {
    if (name.length == 0) return nil;
    UIImage *out = nil;
    SFStoreSetBypass(YES);
    @try {
        UIImage *sym = cfg ? [UIImage systemImageNamed:name withConfiguration:cfg] : [UIImage systemImageNamed:name];
        if (sym && sym.size.width > 0 && sym.size.height > 0) {
            UIImage *tinted = color ? [sym imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : sym;
            UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
            fmt.opaque = NO;
            if (sym.scale > 0) fmt.scale = sym.scale;
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sym.size format:fmt];
            out = [r imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
                [tinted drawInRect:CGRectMake(0, 0, sym.size.width, sym.size.height)];
            }];
            out = [out imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    } @catch (__unused NSException *e) { out = nil; }
    SFStoreSetBypass(NO);
    return out;
}

+ (nullable UIImage *)renderedOriginalSymbolNamed:(NSString *)name pointSize:(CGFloat)pointSize color:(UIColor *)color {
    if (pointSize <= 0) return nil;
    return [self renderedOriginalSymbolNamed:name
                               configuration:[UIImageSymbolConfiguration configurationWithPointSize:pointSize]
                                       color:color];
}

static CGImageRef SFCopyStockRaster(NSString *name, UIImageSymbolConfiguration *cfg, UIImage **outSym) CF_RETURNS_RETAINED {
    CGImageRef cg = NULL;
    UIImage *sym = nil;
    SFStoreSetBypass(YES);
    @try {
        sym = cfg ? [UIImage systemImageNamed:name withConfiguration:cfg] : [UIImage systemImageNamed:name];
        cg = sym.CGImage ? CGImageRetain(sym.CGImage) : NULL;
    } @catch (__unused NSException *e) { cg = NULL; }
    SFStoreSetBypass(NO);
    if (cg && (!CGImageGetWidth(cg) || !CGImageGetHeight(cg))) { CGImageRelease(cg); cg = NULL; }
    if (outSym) *outSym = cg ? sym : nil;
    return cg;
}

+ (nullable NSData *)originalSymbolPNGDataNamed:(NSString *)name {
    if (name.length == 0) return nil;
    CGImageRef cg = SFCopyStockRaster(name, [UIImageSymbolConfiguration configurationWithPointSize:kSFProbePoint], NULL);
    CGFloat side = cg ? MAX(CGImageGetWidth(cg), CGImageGetHeight(cg)) : 0;
    if (cg) CGImageRelease(cg);
    if (!(side > 0)) return nil;
    cg = SFCopyStockRaster(name, [UIImageSymbolConfiguration configurationWithPointSize:kSFProbePoint * kSFExportSide / side], NULL);
    NSData *png = SFPNGData(cg);
    if (cg) CGImageRelease(cg);
    return png;
}

+ (nullable UIImage *)placedReplacementForSymbolName:(NSString *)name pointSize:(CGFloat)pointSize {
    SFSymbolStore *store = [self sharedStore];
    NSString *key = [NSString stringWithFormat:@"%@|%.1f", name, pointSize];
    [store.lock lock];
    UIImage *hit = store.placedCache[key];
    [store.lock unlock];
    if (hit) return hit;
    UIImage *srcImage = [store replacementImageForSymbolName:name];
    CGImageRef src = srcImage.CGImage ? CGImageRetain(srcImage.CGImage) : NULL;
    if (!src || pointSize <= 0) { if (src) CGImageRelease(src); return nil; }
    UIImage *out = nil;
    UIImage *sym = nil;
    CGImageRef stock = SFCopyStockRaster(name, [UIImageSymbolConfiguration configurationWithPointSize:pointSize], &sym);
    @try {
        CGImageRef cg = stock ? sf_compose(src, sf_image_canvas(sym), CGImageGetWidth(stock), CGImageGetHeight(stock), NULL) : NULL;
        if (cg) {
            out = sf_swap_content(sym, cg) ?: [UIImage imageWithCGImage:cg scale:(sym.scale > 0 ? sym.scale : 1.0) orientation:UIImageOrientationUp];
            out = [out imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            CGImageRelease(cg);
        }
    } @catch (__unused NSException *e) { out = nil; }
    if (stock) CGImageRelease(stock);
    CGImageRelease(src);
    if (out) {
        [store.lock lock];
        if (store.placedCache.count > 64) [store.placedCache removeAllObjects];
        store.placedCache[key] = out;
        [store.lock unlock];
    }
    return out;
}

+ (CGSize)systemPixelSizeForSymbolNamed:(NSString *)name {
    if (name.length == 0) return CGSizeZero;
    static NSCache<NSString *, NSValue *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 4000; });
    NSValue *v = [cache objectForKey:name];
    if (v) return v.CGSizeValue;
    CGImageRef cg = SFCopyStockRaster(name, nil, NULL);
    CGSize px = cg ? CGSizeMake(CGImageGetWidth(cg), CGImageGetHeight(cg)) : CGSizeZero;
    if (cg) CGImageRelease(cg);
    if (px.width > 0 && px.height > 0) [cache setObject:[NSValue valueWithCGSize:px] forKey:name];
    return px;
}

+ (nullable UIImage *)systemSFImageNamed:(NSString *)name {
    if (name.length == 0) return nil;
    SFStoreSetBypass(YES);
    UIImage *img = nil;
    @try { img = [UIImage systemImageNamed:name]; } @catch (__unused NSException *e) {}
    SFStoreSetBypass(NO);
    return img;
}

static NSArray<NSString *> *sNames;
static os_unfair_lock sNamesLock = OS_UNFAIR_LOCK_INIT;

+ (NSArray<NSString *> *)allAvailableSymbolNames {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *n = [self glyphNamesFromDisk] ?: @[];
        os_unfair_lock_lock(&sNamesLock);
        sNames = n;
        os_unfair_lock_unlock(&sNamesLock);
    });
    return [self loadedSymbolNames] ?: @[];
}

+ (nullable NSArray<NSString *> *)loadedSymbolNames {
    os_unfair_lock_lock(&sNamesLock);
    NSArray *n = sNames;
    os_unfair_lock_unlock(&sNamesLock);
    return n;
}

+ (nullable NSArray<NSString *> *)glyphNamesFromDisk {
    NSArray<NSString *> *bundleCandidates = @[
        @"/System/Library/CoreServices/CoreGlyphs.bundle",
        @"/System/Library/PrivateFrameworks/CoreGlyphs.framework/CoreGlyphs.bundle",
        @"/System/Library/PrivateFrameworks/SFSymbols.framework",
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *bundlePath in bundleCandidates) {
        if (![fm fileExistsAtPath:bundlePath]) continue;

        NSString *orderPath = [bundlePath stringByAppendingPathComponent:@"symbol_order.plist"];
        if ([fm fileExistsAtPath:orderPath]) {
            id obj = [NSArray arrayWithContentsOfFile:orderPath];
            if (![obj isKindOfClass:[NSArray class]]) {
                obj = [NSDictionary dictionaryWithContentsOfFile:orderPath];
            }
            NSArray *names = [self namesFromPlistObject:obj];
            if (names.count > 0) return names;
        }

        NSString *availPath = [bundlePath stringByAppendingPathComponent:@"name_availability.plist"];
        if ([fm fileExistsAtPath:availPath]) {
            id obj = [NSDictionary dictionaryWithContentsOfFile:availPath];
            NSArray *names = [self namesFromPlistObject:obj];
            if (names.count > 0) return names;
        }

        NSString *resOrder = [bundlePath stringByAppendingPathComponent:@"Resources/symbol_order.plist"];
        if ([fm fileExistsAtPath:resOrder]) {
            NSArray *names = [self namesFromPlistObject:[NSArray arrayWithContentsOfFile:resOrder]];
            if (names.count == 0) {
                names = [self namesFromPlistObject:[NSDictionary dictionaryWithContentsOfFile:resOrder]];
            }
            if (names.count > 0) return names;
        }
        NSString *resAvail = [bundlePath stringByAppendingPathComponent:@"Resources/name_availability.plist"];
        if ([fm fileExistsAtPath:resAvail]) {
            NSArray *names = [self namesFromPlistObject:[NSDictionary dictionaryWithContentsOfFile:resAvail]];
            if (names.count > 0) return names;
        }
    }

    return @[
        @"square.and.arrow.up", @"heart", @"star", @"star.fill", @"house", @"gear",
        @"magnifyingglass", @"person", @"person.circle", @"bell", @"bookmark",
        @"trash", @"folder", @"doc", @"photo", @"camera", @"message", @"phone",
        @"safari", @"play", @"pause", @"backward", @"forward", @"plus", @"minus",
        @"xmark", @"checkmark", @"chevron.left", @"chevron.right", @"ellipsis"
    ];
}

+ (NSArray<NSString *> *)namesFromPlistObject:(id)obj {
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        for (id e in (NSArray *)obj) {
            if ([e isKindOfClass:[NSString class]] && [(NSString *)e length] > 0) {
                [out addObject:e];
            } else if ([e isKindOfClass:[NSDictionary class]]) {
                NSString *n = e[@"name"] ?: e[@"symbol"] ?: e[@"Name"];
                if ([n isKindOfClass:[NSString class]] && n.length > 0) [out addObject:n];
            }
        }
        return [out copy];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        if ([dict[@"names"] isKindOfClass:[NSArray class]]) {
            return [self namesFromPlistObject:dict[@"names"]];
        }
        if ([dict[@"symbols"] isKindOfClass:[NSDictionary class]]) {
            return [[(NSDictionary *)dict[@"symbols"] allKeys] sortedArrayUsingSelector:@selector(compare:)];
        }
        if ([dict[@"symbols"] isKindOfClass:[NSArray class]]) {
            return [self namesFromPlistObject:dict[@"symbols"]];
        }
        NSArray *keys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        for (id k in keys) {
            if ([k isKindOfClass:[NSString class]] && [(NSString *)k length] > 0 &&
                ![k hasPrefix:@"CF"] && ![k isEqualToString:@"version"]) {
                [out addObject:k];
            }
        }
        return [out copy];
    }
    return @[];
}

@end
