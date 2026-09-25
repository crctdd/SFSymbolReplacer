#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SFLanguageDidChangeNotification;

NSString *SFL(NSString *key);
NSString *SFLanguage(void);
void SFSetLanguage(NSString *lang);

NS_ASSUME_NONNULL_END
