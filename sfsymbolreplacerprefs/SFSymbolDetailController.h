#import <UIKit/UIKit.h>

@interface SFSymbolDetailController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithSymbolName:(NSString *)name;
@end
