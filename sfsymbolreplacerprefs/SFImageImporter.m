#import "SFImageImporter.h"
#import "SFLocalize.h"
#import "SFStyle.h"
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const NSInteger kSFImportMaxPixels = 2048;

UIImage *SFFitImage(UIImage *image, CGFloat side, UIImageRenderingMode mode) {
    if (!image || side <= 0) return nil;
    CGSize s = image.size;
    if (!(s.width > 0) || !(s.height > 0)) return nil;
    UIImage *out = nil;
    @try {
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.opaque = NO;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
        CGFloat f = MIN(1.0, MIN(side / s.width, side / s.height));
        CGSize d = CGSizeMake(s.width * f, s.height * f);
        CGRect rect = CGRectMake((side - d.width) / 2.0, (side - d.height) / 2.0, d.width, d.height);
        UIImage *src = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextSetInterpolationQuality(ctx.CGContext, kCGInterpolationHigh);
            [src drawInRect:rect];
        }];
    } @catch (__unused NSException *e) { out = nil; }
    return [out imageWithRenderingMode:mode];
}

static UIImage *SFDecodeSource(CGImageSourceRef src, BOOL *outHasAlpha) {
    if (!src || CGImageSourceGetCount(src) == 0) return nil;
    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceShouldCacheImmediately: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(kSFImportMaxPixels),
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    if (!cg) return nil;
    if (outHasAlpha) {
        CGImageAlphaInfo a = CGImageGetAlphaInfo(cg);
        *outHasAlpha = !(a == kCGImageAlphaNone || a == kCGImageAlphaNoneSkipFirst || a == kCGImageAlphaNoneSkipLast);
    }
    UIImage *img = (CGImageGetWidth(cg) && CGImageGetHeight(cg))
        ? [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp] : nil;
    CGImageRelease(cg);
    return img;
}

static UIImage *SFDecodeImageData(NSData *data, BOOL *outHasAlpha) {
    if (data.length == 0) return nil;
    UIImage *img = nil;
    @try {
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (src) { img = SFDecodeSource(src, outHasAlpha); CFRelease(src); }
    } @catch (__unused NSException *e) { img = nil; }
    return img;
}

UIImage *SFDecodeImageAtURL(NSURL *url, BOOL *outHasAlpha) {
    if (![url isKindOfClass:[NSURL class]] || !url.isFileURL) return nil;
    UIImage *img = nil;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    @try {
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (src) { img = SFDecodeSource(src, outHasAlpha); CFRelease(src); }
    } @catch (__unused NSException *e) { img = nil; }
    if (scoped) [url stopAccessingSecurityScopedResource];
    SFDiscardPickerCopy(url);
    return img;
}

void SFDiscardPickerCopy(NSURL *url) {
    if (!url.isFileURL) return;
    NSString *path = url.path.stringByStandardizingPath;
    NSString *tmp = NSTemporaryDirectory().stringByStandardizingPath;
    if (path.length && tmp.length && [path hasPrefix:tmp] && [path rangeOfString:@"-Inbox/"].location != NSNotFound) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

@interface SFImageImporter () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, copy) SFImportCompletion completion;
@property (nonatomic, copy) SFFilesCompletion filesCompletion;
@property (nonatomic, strong) SFImageImporter *selfRetain;
@end

@implementation SFImageImporter

- (void)chooseSourceAndImportFrom:(UIViewController *)vc completion:(SFImportCompletion)completion {
    if (!vc || !completion) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SFL(@"alert.importSource.title")
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"alert.importSource.photos") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        [self importFromPhotos:vc completion:completion];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"alert.importSource.files") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        [self importFromFiles:vc completion:completion];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    SFPresentController(vc, a);
}

- (void)importFromPhotos:(UIViewController *)vc completion:(SFImportCompletion)completion {
    if (!vc || !completion) return;
    self.completion = completion;
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    self.selfRetain = self;
    picker.presentationController.delegate = self;
    SFPresentController(vc, picker);
}

- (void)importFromFiles:(UIViewController *)vc completion:(SFImportCompletion)completion {
    if (!vc || !completion) return;
    SFImportCompletion cb = [completion copy];
    [self pickFiles:vc multiple:NO completion:^(NSArray<NSURL *> *urls) {
        NSURL *url = urls.firstObject;
        if (!url) { cb(nil, YES, nil); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            BOOL alpha = YES;
            UIImage *img = SFDecodeImageAtURL(url, &alpha);
            dispatch_async(dispatch_get_main_queue(), ^{
                cb(img, alpha, img ? nil : SFL(@"err.fileRead"));
            });
        });
    }];
}

- (void)pickFiles:(UIViewController *)vc multiple:(BOOL)multiple completion:(SFFilesCompletion)completion {
    if (!vc || !completion) return;
    self.filesCompletion = completion;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePNG, UTTypeImage] asCopy:YES];
    picker.allowsMultipleSelection = multiple;
    picker.delegate = self;
    self.selfRetain = self;
    picker.presentationController.delegate = self;
    SFPresentController(vc, picker);
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if (self.filesCompletion) [self finishFiles:@[]];
    if (self.completion) [self finishWithImage:nil alpha:YES error:nil];
}

- (void)finishFiles:(NSArray<NSURL *> *)urls {
    dispatch_async(dispatch_get_main_queue(), ^{
        SFFilesCompletion cb = self.filesCompletion;
        self.filesCompletion = nil;
        if (cb) cb(urls ?: @[]);
        self.selfRetain = nil;
    });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self finishFiles:urls];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self finishFiles:@[]];
}

- (void)finishWithImage:(UIImage *)image alpha:(BOOL)alpha error:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        SFImportCompletion cb = self.completion;
        self.completion = nil;
        if (cb) cb(image, alpha, error);
        self.selfRetain = nil;
    });
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    PHPickerResult *result = [results isKindOfClass:[NSArray class]] ? results.firstObject : nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!result) { [self finishWithImage:nil alpha:YES error:nil]; return; }

    NSItemProvider *provider = result.itemProvider;
    NSString *type = UTTypeImage.identifier;
    if ([provider hasItemConformingToTypeIdentifier:type]) {
        [provider loadDataRepresentationForTypeIdentifier:type completionHandler:^(NSData *data, NSError *error) {
            BOOL alpha = YES;
            UIImage *img = SFDecodeImageData(data, &alpha);
            if (img) { [self finishWithImage:img alpha:alpha error:nil]; return; }
            [self fallbackLoad:provider];
        }];
    } else {
        [self fallbackLoad:provider];
    }
}

- (void)fallbackLoad:(NSItemProvider *)provider {
    NSString *type = UTTypeImage.identifier;
    if ([provider hasItemConformingToTypeIdentifier:type]) {
        [provider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *error) {
            BOOL alpha = YES;
            UIImage *img = nil;
            if (url) {
                @try {
                    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
                    if (src) { img = SFDecodeSource(src, &alpha); CFRelease(src); }
                } @catch (__unused NSException *e) { img = nil; }
            }
            if (img) [self finishWithImage:img alpha:alpha error:nil];
            else [self lastResortLoad:provider];
        }];
        return;
    }
    [self lastResortLoad:provider];
}

- (void)lastResortLoad:(NSItemProvider *)provider {
    if (![provider canLoadObjectOfClass:[UIImage class]]) {
        [self finishWithImage:nil alpha:YES error:SFL(@"err.notImage")];
        return;
    }
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        UIImage *img = [(NSObject *)object isKindOfClass:[UIImage class]] ? (UIImage *)object : nil;
        if (!img) { [self finishWithImage:nil alpha:YES error:SFL(@"err.decode")]; return; }
        CGImageRef cg = img.CGImage;
        BOOL alpha = YES;
        if (cg) {
            CGImageAlphaInfo a = CGImageGetAlphaInfo(cg);
            alpha = !(a == kCGImageAlphaNone || a == kCGImageAlphaNoneSkipFirst || a == kCGImageAlphaNoneSkipLast);
        }
        [self finishWithImage:img alpha:alpha error:nil];
    }];
}

@end
