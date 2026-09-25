#import "SFSymbolRootListController.h"
#import "SFSymbolBrowserController.h"
#import "SFImageImporter.h"
#import "SFLocalize.h"
#import "SFStyle.h"
#import "../SFSymbolStore.h"
#import <objc/runtime.h>
#import <spawn.h>
#import <roothide.h>

enum { kSecHeader, kSecGeneral, kSecSymbols, kSecSystem, kSecAbout, kSecCount };
enum { kRowEnable, kRowLanguage, kRowReplaced, kGeneralCount };
enum { kRowBrowse, kRowBatch, kRowRestoreAll, kSymbolsCount };

static NSString * const kSFVersion = @"1.0.9";
static const CGFloat kHdrIcon = 28.0;

static const struct { __unsafe_unretained NSString *key, *handle, *url, *symbol; uint32_t rgb; } kSFLinks[] = {
    { @"about.telegram", @"@iosdumpzzz", @"https://t.me/iosdumpzzz", @"paperplane.fill", 0x2AABEE },
    { @"about.x",        @"@apsnkizv",   @"https://x.com/apsnkizv",  @"at",              0x000000 },
};
#define SF_LINK_COUNT ((NSInteger)(sizeof(kSFLinks) / sizeof(*kSFLinks)))

NS_INLINE UIColor *SFRGB(uint32_t v) {
    return [UIColor colorWithRed:((v >> 16) & 0xff) / 255.0 green:((v >> 8) & 0xff) / 255.0 blue:(v & 0xff) / 255.0 alpha:1];
}

NS_INLINE NSString *SFCount(NSUInteger n) {
    return [NSString stringWithFormat:SFL(@"root.countFmt"), (unsigned long)n];
}

static void SFOpenURL(NSString *str) {
    NSURL *url = [NSURL URLWithString:str];
    UIApplication *app = [objc_getClass("UIApplication") sharedApplication];
    if (url && [app respondsToSelector:@selector(openURL:options:completionHandler:)])
        [app openURL:url options:@{} completionHandler:nil];
}

static UIImage *SFTile(NSString *symbol, UIColor *color) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%@|%@", symbol, color];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    UIImage *g = [SFSymbolStore renderedOriginalSymbolNamed:symbol pointSize:16 color:[UIColor whiteColor]];
    CGFloat side = SFRowIconSide;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt]
           imageWithActions:^(__unused UIGraphicsImageRendererContext *c) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, side, side));
        CGSize s = g.size;
        if (s.width > 0 && s.height > 0) {
            CGFloat f = MIN(19.0 / s.width, 19.0 / s.height);
            s = CGSizeMake(s.width * f, s.height * f);
            [g drawInRect:CGRectMake((side - s.width) / 2, (side - s.height) / 2, s.width, s.height)];
        }
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (img) [cache setObject:img forKey:key];
    return img;
}

static NSString *SFNameFromFile(NSString *file) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"@[123]x$" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSString *base = [file stringByDeletingPathExtension];
    if (re) base = [re stringByReplacingMatchesInString:base options:0 range:NSMakeRange(0, base.length) withTemplate:@""];
    return [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@interface SFHeaderCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel2;
@property (nonatomic, strong) UILabel *detailLabel2;
@end

@implementation SFHeaderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if (!(self = [super initWithStyle:style reuseIdentifier:rid])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];

    _titleLabel2 = [UILabel new];
    _titleLabel2.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    _titleLabel2.textColor = [UIColor labelColor];
    _titleLabel2.textAlignment = NSTextAlignmentCenter;
    _titleLabel2.adjustsFontSizeToFitWidth = YES;
    _titleLabel2.minimumScaleFactor = 0.6;

    _detailLabel2 = [UILabel new];
    _detailLabel2.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _detailLabel2.textColor = [UIColor secondaryLabelColor];
    _detailLabel2.textAlignment = NSTextAlignmentCenter;
    _detailLabel2.numberOfLines = 0;
    _detailLabel2.translatesAutoresizingMaskIntoConstraints = NO;

    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    SFApplyIconCorners(_iconView, kHdrIcon);

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _titleLabel2]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *cv = self.contentView;
    UILayoutGuide *m = cv.layoutMarginsGuide;
    [cv addSubview:row];
    [cv addSubview:_detailLabel2];
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.widthAnchor constraintEqualToConstant:kHdrIcon],
        [_iconView.heightAnchor constraintEqualToConstant:kHdrIcon],
        [row.topAnchor constraintEqualToAnchor:cv.topAnchor constant:18],
        [row.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
        [row.leadingAnchor constraintGreaterThanOrEqualToAnchor:m.leadingAnchor],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],
        [_detailLabel2.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:6],
        [_detailLabel2.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [_detailLabel2.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [_detailLabel2.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-10],
    ]];
    return self;
}
@end

@interface SFRootRowCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel2;
@end

@implementation SFRootRowCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) return nil;
    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    SFApplyIconCorners(_iconView, SFRowIconSide);

    _titleLabel2 = [UILabel new];
    _titleLabel2.font = [UIFont systemFontOfSize:17];
    _titleLabel2.textColor = [UIColor labelColor];
    _titleLabel2.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *cv = self.contentView;
    UILayoutGuide *m = cv.layoutMarginsGuide;
    [cv addSubview:_iconView];
    [cv addSubview:_titleLabel2];
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:SFRowIconSide],
        [_iconView.heightAnchor constraintEqualToConstant:SFRowIconSide],
        [_titleLabel2.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:15],
        [_titleLabel2.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],
        [_titleLabel2.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
    ]];
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = CGRectGetMinX(self.titleLabel2.frame);
    UIEdgeInsets i = self.separatorInset;
    if (x > 0 && i.left != x) {
        i.left = x;
        self.separatorInset = i;
    }
}
@end

@interface SFSymbolRootListController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SFImageImporter *importer;
@property (nonatomic, copy) NSArray<NSString *> *symbolNames;
@property (nonatomic, assign) BOOL batchRunning;
@end

@implementation SFSymbolRootListController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"appTitle");
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UITableView *tv = self.tableView = SFMakeTableView(self);
    [tv registerClass:[SFHeaderCell class] forCellReuseIdentifier:@"SFHeaderCell"];
    [tv registerClass:[SFRootRowCell class] forCellReuseIdentifier:@"SFRootRowCell"];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    SFSetEmptyBackButton(self);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged:)
                                                 name:SFLanguageDidChangeNotification object:nil];

    self.symbolNames = [SFSymbolStore loadedSymbolNames];
    if (!self.symbolNames) {
        __weak __typeof__(self) ws = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *names = [SFSymbolStore allAvailableSymbolNames];
            dispatch_async(dispatch_get_main_queue(), ^{
                __typeof__(self) s = ws;
                if (!s) return;
                s.symbolNames = names;
                [s.tableView reloadData];
            });
        });
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[SFSymbolStore sharedStore] reload];
    SFApplyNavigationChrome(self);
    self.title = SFL(@"appTitle");
    [self.tableView reloadData];
}

- (void)languageChanged:(__unused NSNotification *)n {
    self.title = SFL(@"appTitle");
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return kSecCount;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    switch (sec) {
        case kSecHeader:  return 1;
        case kSecGeneral: return kGeneralCount;
        case kSecSymbols: return kSymbolsCount;
        case kSecSystem:  return 1;
        case kSecAbout:   return SF_LINK_COUNT;
        default:          return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sec {
    switch (sec) {
        case kSecGeneral: return SFL(@"root.sec.general");
        case kSecSymbols: return SFL(@"root.sec.symbols");
        case kSecSystem:  return SFL(@"root.sec.system");
        case kSecAbout:   return SFL(@"root.sec.about");
        default:          return nil;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)sec {
    switch (sec) {
        case kSecGeneral: return SFL(@"root.footer.general");
        case kSecSymbols: return SFL(@"root.footer.symbols");
        case kSecSystem:  return SFL(@"root.footer.system");
        case kSecAbout:   return [NSString stringWithFormat:SFL(@"root.versionFmt"), kSFVersion];
        default:          return nil;
    }
}

- (SFRootRowCell *)rowCell:(UITableView *)tv indexPath:(NSIndexPath *)ip title:(NSString *)title symbol:(NSString *)symbol color:(UIColor *)color {
    SFRootRowCell *c = [tv dequeueReusableCellWithIdentifier:@"SFRootRowCell" forIndexPath:ip];
    c.titleLabel2.text = title;
    c.iconView.image = SFTile(symbol, color);
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SFSymbolStore *store = [SFSymbolStore sharedStore];
    NSUInteger replaced = [store replacedSymbolNames].count;
    SFRootRowCell *c = nil;

    switch (ip.section) {
    case kSecHeader: {
        SFHeaderCell *h = [tv dequeueReusableCellWithIdentifier:@"SFHeaderCell" forIndexPath:ip];
        UIImage *icon = [UIImage imageNamed:@"icon" inBundle:[NSBundle bundleForClass:[self class]] compatibleWithTraitCollection:nil];
        h.iconView.image = icon;
        h.iconView.hidden = !icon;
        h.titleLabel2.text = SFL(@"appTitle");
        h.detailLabel2.text = SFL(@"root.subtitle");
        return h;
    }
    case kSecGeneral:
        switch (ip.row) {
        case kRowEnable: {
            c = [self rowCell:tv indexPath:ip title:SFL(@"root.enable") symbol:@"wand.and.stars" color:[UIColor systemBlueColor]];
            UISwitch *sw = [UISwitch new];
            sw.on = store.isEnabled;
            [sw addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            break;
        }
        case kRowLanguage:
            c = [self rowCell:tv indexPath:ip title:SFL(@"root.language") symbol:@"globe" color:[UIColor systemGreenColor]];
            c.accessoryView = SFPillButton(SFL(@"root.languageValue"), YES, self, @selector(languageTapped:));
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        default:
            c = [self rowCell:tv indexPath:ip title:SFL(@"root.replaced") symbol:@"photo.on.rectangle" color:[UIColor systemIndigoColor]];
            c.accessoryView = SFValueAccessory(replaced ? SFCount(replaced) : SFL(@"root.none"), NO);
            break;
        }
        break;
    case kSecSymbols:
        switch (ip.row) {
        case kRowBrowse:
            c = [self rowCell:tv indexPath:ip title:SFL(@"root.browse") symbol:@"square.grid.2x2" color:[UIColor systemTealColor]];
            c.accessoryView = SFValueAccessory(self.symbolNames ? SFCount(self.symbolNames.count) : nil, YES);
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        case kRowBatch:
            c = [self rowCell:tv indexPath:ip title:SFL(@"root.batch") symbol:@"square.and.arrow.down.on.square" color:[UIColor systemPurpleColor]];
            c.accessoryView = SFPillButton(SFL(@"pill.import"), !self.batchRunning, self, @selector(batchTapped:));
            break;
        default:
            c = [self rowCell:tv indexPath:ip title:SFL(@"root.restoreAll") symbol:@"arrow.counterclockwise" color:[UIColor systemOrangeColor]];
            c.accessoryView = SFPillButton(SFL(@"pill.restore"), replaced > 0, self, @selector(restoreAllTapped:));
            break;
        }
        break;
    case kSecSystem:
        c = [self rowCell:tv indexPath:ip title:SFL(@"root.respring") symbol:@"arrow.clockwise" color:[UIColor systemRedColor]];
        c.accessoryView = SFPillButton(SFL(@"pill.respring"), YES, self, @selector(respringTapped:));
        break;
    case kSecAbout: {
        NSInteger i = MIN(MAX(ip.row, 0), SF_LINK_COUNT - 1);
        c = [self rowCell:tv indexPath:ip title:SFL(kSFLinks[i].key) symbol:kSFLinks[i].symbol color:SFRGB(kSFLinks[i].rgb)];
        c.accessoryView = SFValueAccessory(kSFLinks[i].handle, YES);
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        break;
    }
    }
    return c ?: [self rowCell:tv indexPath:ip title:@"" symbol:@"questionmark" color:[UIColor systemGrayColor]];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == kSecHeader ? UITableViewAutomaticDimension : SFRowHeight;
}

- (CGFloat)tableView:(UITableView *)tv estimatedHeightForRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == kSecHeader ? 110.0 : SFRowHeight;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)sec {
    return SFHeaderView([self tableView:tv titleForHeaderInSection:sec]);
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)sec {
    return SFHeaderHeight([self tableView:tv titleForHeaderInSection:sec], sec);
}

- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)sec {
    return SFFooterView([self tableView:tv titleForFooterInSection:sec]);
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)sec {
    return SFFooterHeight(tv, [self tableView:tv titleForFooterInSection:sec]);
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != kSecHeader) SFApplyPillCorners(tv, cell, ip);
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == kSecSymbols && ip.row == kRowBrowse)
        [self.navigationController pushViewController:[SFSymbolBrowserController new] animated:YES];
    else if (ip.section == kSecGeneral && ip.row == kRowLanguage)
        [self chooseLanguage];
    else if (ip.section == kSecAbout && ip.row >= 0 && ip.row < SF_LINK_COUNT)
        SFOpenURL(kSFLinks[ip.row].url);
}

- (void)enabledChanged:(UISwitch *)sw {
    [[SFSymbolStore sharedStore] setEnabled:sw.isOn];
}

- (void)languageTapped:(__unused UIButton *)sender {
    [self chooseLanguage];
}

- (void)chooseLanguage {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SFL(@"alert.language.title") message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"简体中文" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        SFSetLanguage(@"zh");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"English" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        SFSetLanguage(@"en");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    SFPresentController(self, a);
}

- (void)restoreAllTapped:(__unused UIButton *)sender {
    if (![[SFSymbolStore sharedStore] replacedSymbolNames].count) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SFL(@"alert.restoreAll.title") message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    __weak __typeof__(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"alert.restoreAll.action") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        __typeof__(self) s = ws;
        if (!s) return;
        NSError *err = nil;
        if (![[SFSymbolStore sharedStore] removeAllReplacements:&err])
            SFPresentAlert(s, SFL(@"alert.restoreFailed"), err.localizedDescription);
        [s.tableView reloadData];
    }]];
    SFPresentController(self, a);
}

- (void)respringTapped:(__unused UIButton *)sender {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SFL(@"alert.respring.title") message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"pill.respring") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [[SFSymbolStore sharedStore] postReloadNotification];
        pid_t pid = 0;
        const char *argv[] = { "killall", "-9", "SpringBoard", NULL };
        const char *path = jbroot("/usr/bin/killall");
        if (path) posix_spawn(&pid, path, NULL, NULL, (char * const *)argv, NULL);
    }]];
    SFPresentController(self, a);
}

- (void)batchTapped:(__unused UIButton *)sender {
    if (self.batchRunning) return;
    self.importer = [SFImageImporter new];
    __weak __typeof__(self) ws = self;
    [self.importer pickFiles:self multiple:YES completion:^(NSArray<NSURL *> *urls) {
        __typeof__(self) s = ws;
        if (!s) { for (NSURL *u in urls) SFDiscardPickerCopy(u); return; }
        s.importer = nil;
        if (urls.count) [s runBatch:urls];
    }];
}

- (void)runBatch:(NSArray<NSURL *> *)urls {
    self.batchRunning = YES;
    [self.tableView reloadData];
    NSUInteger total = urls.count;
    UIAlertController *hud = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SFL(@"batch.progressFmt"), 0UL, (unsigned long)total]
                                                                 message:nil preferredStyle:UIAlertControllerStyleAlert];
    SFPresentController(self, hud);

    __weak __typeof__(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSSet<NSString *> *known = [NSSet setWithArray:[SFSymbolStore allAvailableSymbolNames] ?: @[]];
        SFSymbolStore *store = [SFSymbolStore sharedStore];
        NSMutableArray<NSString *> *unmatched = [NSMutableArray array];
        NSUInteger ok = 0, failed = 0, noAlpha = 0, i = 0;
        for (NSURL *url in urls) @autoreleasepool {
            NSUInteger done = ++i;
            dispatch_async(dispatch_get_main_queue(), ^{
                hud.title = [NSString stringWithFormat:SFL(@"batch.progressFmt"), (unsigned long)done, (unsigned long)total];
            });
            NSString *file = url.lastPathComponent ?: @"";
            NSString *name = SFNameFromFile(file);
            if (!name.length || ![known containsObject:name]) {
                [unmatched addObject:file];
                SFDiscardPickerCopy(url);
                continue;
            }
            BOOL alpha = YES;
            UIImage *img = SFDecodeImageAtURL(url, &alpha);
            if (!img) { failed++; continue; }
            if (!alpha) noAlpha++;
            if ([store saveReplacementImage:img forSymbolName:name notify:NO error:NULL]) ok++;
            else failed++;
        }
        [store postReloadNotification];

        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:SFL(@"batch.summaryFmt"), (unsigned long)ok]];
        if (unmatched.count) [parts addObject:[NSString stringWithFormat:SFL(@"batch.unmatchedFmt"), (unsigned long)unmatched.count]];
        if (failed) [parts addObject:[NSString stringWithFormat:SFL(@"batch.failedFmt"), (unsigned long)failed]];
        if (noAlpha) [parts addObject:[NSString stringWithFormat:SFL(@"batch.noAlphaFmt"), (unsigned long)noAlpha]];
        NSString *summary = [parts componentsJoinedByString:SFL(@"sep")];
        NSString *list = nil;
        if (unmatched.count) {
            NSUInteger shown = MIN(unmatched.count, (NSUInteger)8);
            list = [[unmatched subarrayWithRange:NSMakeRange(0, shown)] componentsJoinedByString:@"\n"];
            if (unmatched.count > shown)
                list = [list stringByAppendingFormat:@"\n%@", [NSString stringWithFormat:SFL(@"batch.moreFmt"), (unsigned long)(unmatched.count - shown)]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            SFDismissThen(hud, ^{
                __typeof__(self) s = ws;
                if (!s) return;
                s.batchRunning = NO;
                [s.tableView reloadData];
                SFPresentAlert(s, summary, list);
            });
        });
    });
}

@end
