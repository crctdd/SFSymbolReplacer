#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SFImportCompletion)(UIImage *_Nullable image, BOOL hasAlpha, NSString *_Nullable errorMessage);
typedef void (^SFFilesCompletion)(NSArray<NSURL *> *urls);

@interface SFImageImporter : NSObject
- (void)chooseSourceAndImportFrom:(UIViewController *)vc completion:(SFImportCompletion)completion;
- (void)pickFiles:(UIViewController *)vc multiple:(BOOL)multiple completion:(SFFilesCompletion)completion;
@end

void SFDiscardPickerCopy(NSURL *url);
UIImage *_Nullable SFDecodeImageAtURL(NSURL *url, BOOL *_Nullable outHasAlpha);

UIImage *_Nullable SFFitImage(UIImage *_Nullable image, CGFloat side, UIImageRenderingMode mode);

NS_ASSUME_NONNULL_END
