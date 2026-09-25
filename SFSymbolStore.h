#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFSymbolStore : NSObject

@property (nonatomic, assign, readonly, getter=isEnabled) BOOL enabled;

+ (instancetype)sharedStore;
+ (void)beginBypass;
+ (void)endBypass;
+ (NSArray<NSString *> *)allAvailableSymbolNames;
+ (nullable NSArray<NSString *> *)loadedSymbolNames;

- (void)setEnabled:(BOOL)enabled;
- (void)reload;
- (void)postReloadNotification;
- (nullable id)preferenceValueForKey:(NSString *)key;
- (void)setPreferenceValue:(nullable id)value forKey:(NSString *)key;

- (BOOL)hasReplacementForSymbolName:(NSString *)name;
- (nullable NSString *)replacementPathForSymbolName:(NSString *)name;
- (NSArray<NSString *> *)replacedSymbolNames;
- (BOOL)keepsColorsForSymbolName:(NSString *)name;
- (BOOL)setKeepsColors:(BOOL)keep forSymbolName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeReplacementForSymbolName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeAllReplacements:(NSError * _Nullable * _Nullable)error;

- (nullable UIImage *)replacementImageForSymbolName:(NSString *)name;
- (BOOL)saveReplacementImage:(UIImage *)image forSymbolName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (BOOL)saveReplacementImage:(UIImage *)image forSymbolName:(NSString *)name notify:(BOOL)notify error:(NSError * _Nullable * _Nullable)error;

+ (CGSize)systemPixelSizeForSymbolNamed:(NSString *)name;
+ (nullable NSData *)originalSymbolPNGDataNamed:(NSString *)name;
+ (nullable UIImage *)placedReplacementForSymbolName:(NSString *)name pointSize:(CGFloat)pointSize;
+ (nullable UIImage *)systemSFImageNamed:(NSString *)name;
+ (nullable UIImage *)renderedOriginalSymbolNamed:(NSString *)name pointSize:(CGFloat)pointSize color:(nullable UIColor *)color;
+ (nullable UIImage *)renderedOriginalSymbolNamed:(NSString *)name
                                   configuration:(nullable UIImageSymbolConfiguration *)cfg
                                           color:(nullable UIColor *)color;

@end

NS_ASSUME_NONNULL_END
