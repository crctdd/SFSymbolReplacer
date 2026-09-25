#import "SFStyle.h"
#import "SFLocalize.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../SFSymbolStore.h"

const CGFloat SFRowHeight = 50.0;
const CGFloat SFPillCornerRadius = 25.0;
const CGSize SFPillSize = {68.0, 30.0};
const CGFloat SFPillButtonRadius = 15.0;
const CGFloat SFRowIconSide = 30.0;
const CGFloat SFIconCornerFraction = 0.30;

NS_INLINE CGFloat SFSectionInset(void) {
    if (@available(iOS 13.0, *)) return 20.0;
    return 15.0;
}

void SFApplyIconCorners(UIView *view, CGFloat side) {
    if (!view) return;
    view.layer.cornerRadius = side * SFIconCornerFraction;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
}

UIView *SFValueAccessory(NSString *text, BOOL chevron) {
    UILabel *label = [UILabel new];
    label.text = text ?: @"";
    label.font = [UIFont systemFontOfSize:17];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentRight;
    [label sizeToFit];
    UIImageView *chev = chevron ? SFDisclosureView() : nil;
    CGFloat chevW = chev ? chev.bounds.size.width + 8 : 0;
    CGFloat w = MAX(SFPillSize.width, ceil(label.bounds.size.width) + chevW), h = SFPillSize.height;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    label.frame = CGRectMake(0, 0, w - chevW, h);
    [box addSubview:label];
    if (chev) {
        CGSize c = chev.bounds.size;
        chev.frame = CGRectMake(w - c.width, (h - c.height) / 2.0, c.width, c.height);
        [box addSubview:chev];
    }
    box.userInteractionEnabled = NO;
    return box;
}

UITableViewStyle SFInsetGroupedStyle(void) {
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) style = UITableViewStyleInsetGrouped;
    return style;
}

UITableView *SFMakeTableView(id<UITableViewDataSource, UITableViewDelegate> owner) {
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:SFInsetGroupedStyle()];
    tv.delegate = owner;
    tv.dataSource = owner;
    tv.rowHeight = SFRowHeight;
    tv.estimatedRowHeight = SFRowHeight;
    tv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    if ([tv respondsToSelector:NSSelectorFromString(@"setSectionHeaderTopPadding:")]) {
        @try { [tv setValue:@(0.0) forKey:@"sectionHeaderTopPadding"]; } @catch (__unused NSException *e) {}
    }
    return tv;
}

void SFApplyPillCorners(UITableView *tableView, UITableViewCell *cell, NSIndexPath *indexPath) {
    if (!tableView || !cell || !indexPath) return;
    NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
    CACornerMask mask = 0;
    if (indexPath.row == 0) mask |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (indexPath.row == rows - 1) mask |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    CGFloat radius = mask ? SFPillCornerRadius : 0;

    cell.layer.borderWidth = 0.0;
    cell.layer.borderColor = [UIColor clearColor].CGColor;
    cell.layer.cornerRadius = radius;
    cell.layer.maskedCorners = mask;
    cell.layer.masksToBounds = YES;

    if (@available(iOS 14.0, *)) {
        UIBackgroundConfiguration *bg = cell.backgroundConfiguration;
        if (bg) {
            bg.cornerRadius = radius;
            bg.strokeColor = [UIColor clearColor];
            bg.strokeWidth = 0.0;
            cell.backgroundConfiguration = bg;
        }
    } else if (cell.backgroundView) {
        cell.backgroundView.layer.cornerRadius = radius;
        cell.backgroundView.layer.maskedCorners = mask;
        cell.backgroundView.layer.masksToBounds = YES;
        cell.backgroundView.layer.borderWidth = 0.0;
    }
    if (@available(iOS 13.0, *)) {
        cell.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

UIView *SFHeaderView(NSString *title) {
    if (title.length == 0) return nil;
    UIView *v = [UIView new];
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.textColor = [UIColor systemGrayColor];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:l];
    CGFloat pad = SFSectionInset();
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:pad],
        [l.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-pad],
        [l.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-6],
    ]];
    return v;
}

CGFloat SFHeaderHeight(NSString *title, NSInteger section) {
    if (title.length) return 38.0;
    return section == 0 ? CGFLOAT_MIN : 15.0;
}

UIView *SFFooterView(NSString *text) {
    if (text.length == 0) return nil;
    UIView *v = [UIView new];
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor systemGrayColor];
    l.numberOfLines = 0;
    l.lineBreakMode = NSLineBreakByWordWrapping;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:l];
    CGFloat pad = SFSectionInset();
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:pad],
        [l.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-pad],
        [l.topAnchor constraintEqualToAnchor:v.topAnchor constant:6],
        [l.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-6],
    ]];
    return v;
}

CGFloat SFFooterHeight(UITableView *tableView, NSString *text) {
    if (text.length == 0) return CGFLOAT_MIN;
    CGFloat width = MAX(tableView.bounds.size.width - 2 * SFSectionInset(), 100.0);
    CGRect rect = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12]}
                                     context:nil];
    return ceil(rect.size.height) + 24.0;
}

void SFCrossDissolve(UIView *view, void (^changes)(void)) {
    if (!changes) return;
    if (!view.window || ![UIView areAnimationsEnabled]) { changes(); return; }
    [UIView transitionWithView:view
                      duration:0.2
                       options:UIViewAnimationOptionTransitionCrossDissolve |
                               UIViewAnimationOptionAllowUserInteraction |
                               UIViewAnimationOptionBeginFromCurrentState
                    animations:changes
                    completion:nil];
}

@interface SFPillPressHandler : NSObject
+ (instancetype)shared;
@end

@implementation SFPillPressHandler
+ (instancetype)shared {
    static SFPillPressHandler *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [self new]; });
    return h;
}
- (void)pressDown:(UIButton *)b {
    [UIView animateWithDuration:0.12 delay:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        b.transform = CGAffineTransformMakeScale(0.94, 0.94);
        b.alpha = 0.8;
    } completion:nil];
}
- (void)pressUp:(UIButton *)b {
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        b.transform = CGAffineTransformIdentity;
        b.alpha = 1.0;
    } completion:nil];
}
@end

void SFUpdatePillButton(UIButton *button, NSString *title, BOOL active) {
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = active ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
}

UIButton *SFPillButton(NSString *title, BOOL active, id target, SEL action) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 0, SFPillSize.width, SFPillSize.height);
    btn.layer.cornerRadius = SFPillButtonRadius;
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    SFUpdatePillButton(btn, title, active);
    SFPillPressHandler *press = [SFPillPressHandler shared];
    [btn addTarget:press action:@selector(pressDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [btn addTarget:press action:@selector(pressUp:)
  forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    if (target && action) [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

void SFSetEmptyBackButton(UIViewController *vc) {
    vc.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
}

static char kSFCancelledKey;

static void SFPresentAttempt(UIViewController *vc, UIViewController *controller, int tries) {
    if (!vc || !controller) return;
    if (objc_getAssociatedObject(controller, &kSFCancelledKey)) return;
    if (controller.presentingViewController || controller.isBeingPresented) return;
    if (!vc.isViewLoaded || (!vc.view.window && !vc.presentedViewController)) return;
    UIViewController *top = vc;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    BOOL busy = top.isBeingPresented || top.isBeingDismissed ||
                (top.presentedViewController && top.presentedViewController.isBeingDismissed);
    if (busy) {
        if (tries >= 12) return;
        __weak UIViewController *wvc = vc;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SFPresentAttempt(wvc, controller, tries + 1);
        });
        return;
    }
    UIPopoverPresentationController *pop = controller.popoverPresentationController;
    if (pop && !pop.sourceView && !pop.barButtonItem) {
        pop.sourceView = top.view;
        pop.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
        pop.permittedArrowDirections = 0;
    }
    [top presentViewController:controller animated:YES completion:nil];
}

void SFPresentController(UIViewController *vc, UIViewController *controller) {
    if (!vc || !controller) return;
    if (![NSThread isMainThread]) {
        __weak UIViewController *wvc = vc;
        dispatch_async(dispatch_get_main_queue(), ^{ SFPresentController(wvc, controller); });
        return;
    }
    SFPresentAttempt(vc, controller, 0);
}

void SFPresentAlert(UIViewController *vc, NSString *title, NSString *message) {
    if (!vc) return;
    if (title.length == 0 && message.length == 0) return;
    if (![NSThread isMainThread]) {
        __weak UIViewController *wvc = vc;
        dispatch_async(dispatch_get_main_queue(), ^{ SFPresentAlert(wvc, title, message); });
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"ok") style:UIAlertActionStyleCancel handler:nil]];
    SFPresentController(vc, a);
}

static void SFDismissAttempt(UIViewController *controller, void (^then)(void), int tries) {
    if (controller.isBeingPresented && tries < 12) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SFDismissAttempt(controller, then, tries + 1);
        });
        return;
    }
    if (controller.presentingViewController && !controller.isBeingDismissed) {
        [controller.presentingViewController dismissViewControllerAnimated:YES completion:then];
    } else if (then) {
        then();
    }
}

void SFDismissThen(UIViewController *controller, void (^then)(void)) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ SFDismissThen(controller, then); });
        return;
    }
    if (!controller) { if (then) then(); return; }
    objc_setAssociatedObject(controller, &kSFCancelledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SFDismissAttempt(controller, then, 0);
}

UIImage *SFChromeIcon(NSString *symbol, CGFloat pointSize, UIImageSymbolWeight weight, UIImageSymbolScale scale) {
    if (symbol.length == 0 || pointSize <= 0) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 64; });
    NSString *key = [NSString stringWithFormat:@"%@|%.2f|%ld|%ld", symbol, pointSize, (long)weight, (long)scale];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight scale:scale];
    UIImage *raster = [SFSymbolStore renderedOriginalSymbolNamed:symbol configuration:cfg color:[UIColor blackColor]];
    if (!raster) return nil;
    UIImage *tmpl = [raster imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if ([symbol containsString:@"backward"] || [symbol containsString:@"forward"]) {
        tmpl = [tmpl imageFlippedForRightToLeftLayoutDirection];
    }
    if (tmpl) [cache setObject:tmpl forKey:key];
    return tmpl;
}

UIImageView *SFDisclosureView(void) {
    UIImage *img = SFChromeIcon(@"chevron.right", 13, UIImageSymbolWeightSemibold, UIImageSymbolScaleMedium);
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.tintColor = [UIColor tertiaryLabelColor];
    iv.contentMode = UIViewContentModeCenter;
    CGSize s = img ? img.size : CGSizeMake(8, 13);
    iv.frame = CGRectMake(0, 0, MAX(s.width, 8), MAX(s.height, 13));
    return iv;
}

void SFApplySearchBarChrome(UISearchBar *searchBar) {
    if (!searchBar) return;
    @try {
        UIImage *mag = SFChromeIcon(@"magnifyingglass", 15, UIImageSymbolWeightMedium, UIImageSymbolScaleMedium);
        UIImage *clr = SFChromeIcon(@"xmark.circle.fill", 15, UIImageSymbolWeightRegular, UIImageSymbolScaleMedium);
        if (mag) [searchBar setImage:mag forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
        if (clr) [searchBar setImage:clr forSearchBarIcon:UISearchBarIconClear state:UIControlStateNormal];
    } @catch (__unused NSException *e) {}
}

void SFApplyNavigationChrome(UIViewController *vc) {
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (!bar) return;
    UIImage *chev = SFChromeIcon(@"chevron.backward", 17, UIImageSymbolWeightSemibold, UIImageSymbolScaleLarge);
    if (!chev) return;
    @try {
        UINavigationBarAppearance *std = [bar.standardAppearance copy] ?: [[UINavigationBarAppearance alloc] init];
        [std setBackIndicatorImage:chev transitionMaskImage:chev];
        vc.navigationItem.standardAppearance = std;
        UINavigationBarAppearance *compact = [bar.compactAppearance copy];
        if (compact) {
            [compact setBackIndicatorImage:chev transitionMaskImage:chev];
            vc.navigationItem.compactAppearance = compact;
        }
        UINavigationBarAppearance *edge = [bar.scrollEdgeAppearance copy];
        // 15+: nil scrollEdgeAppearance is transparent
        if (!edge && [[[UIDevice currentDevice] systemVersion] compare:@"15.0" options:NSNumericSearch] != NSOrderedAscending) {
            edge = [std copy];
            [edge configureWithTransparentBackground];
            edge.titleTextAttributes = std.titleTextAttributes;
            edge.largeTitleTextAttributes = std.largeTitleTextAttributes;
            edge.buttonAppearance = std.buttonAppearance;
            edge.backButtonAppearance = std.backButtonAppearance;
        }
        if (edge) {
            [edge setBackIndicatorImage:chev transitionMaskImage:chev];
            vc.navigationItem.scrollEdgeAppearance = edge;
        }
    } @catch (__unused NSException *e) {}
}
