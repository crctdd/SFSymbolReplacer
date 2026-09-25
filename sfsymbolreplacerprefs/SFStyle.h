#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const CGFloat SFRowHeight;
FOUNDATION_EXPORT const CGFloat SFPillCornerRadius;
FOUNDATION_EXPORT const CGSize SFPillSize;
FOUNDATION_EXPORT const CGFloat SFPillButtonRadius;
FOUNDATION_EXPORT const CGFloat SFRowIconSide;
FOUNDATION_EXPORT const CGFloat SFIconCornerFraction;

UITableViewStyle SFInsetGroupedStyle(void);
UITableView *SFMakeTableView(id<UITableViewDataSource, UITableViewDelegate> owner);
void SFApplyPillCorners(UITableView *tableView, UITableViewCell *cell, NSIndexPath *indexPath);
UIView *_Nullable SFHeaderView(NSString *_Nullable title);
CGFloat SFHeaderHeight(NSString *_Nullable title, NSInteger section);
UIView *_Nullable SFFooterView(NSString *_Nullable text);
CGFloat SFFooterHeight(UITableView *tableView, NSString *_Nullable text);

UIButton *SFPillButton(NSString *title, BOOL active, id _Nullable target, SEL _Nullable action);
void SFUpdatePillButton(UIButton *button, NSString *title, BOOL active);
UIView *SFValueAccessory(NSString *_Nullable text, BOOL chevron);
void SFApplyIconCorners(UIView *view, CGFloat side);

UIImage *_Nullable SFChromeIcon(NSString *symbol, CGFloat pointSize, UIImageSymbolWeight weight, UIImageSymbolScale scale);
UIImageView *SFDisclosureView(void);
void SFApplySearchBarChrome(UISearchBar *searchBar);
void SFApplyNavigationChrome(UIViewController *vc);
void SFSetEmptyBackButton(UIViewController *vc);

void SFPresentController(UIViewController *_Nullable vc, UIViewController *controller);
void SFPresentAlert(UIViewController *_Nullable vc, NSString *_Nullable title, NSString *_Nullable message);
void SFDismissThen(UIViewController *controller, void (^_Nullable then)(void));
void SFCrossDissolve(UIView *_Nullable view, void (^changes)(void));

NS_ASSUME_NONNULL_END
