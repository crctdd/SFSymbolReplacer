#import "SFSymbolDetailController.h"
#import "SFImageImporter.h"
#import "SFLocalize.h"
#import "SFStyle.h"
#import "../SFSymbolStore.h"

typedef NS_ENUM(NSInteger, SFDetailSection) {
    SFDetailSectionPreview = 0,
    SFDetailSectionInfo,
    SFDetailSectionReplace,
    SFDetailSectionExport,
    SFDetailSectionCount
};

typedef NS_ENUM(NSInteger, SFInfoRow) {
    SFInfoRowName = 0, SFInfoRowPoint, SFInfoRowSystemPx, SFInfoRowReplacementPx, SFInfoRowFileSize, SFInfoRowStatus, SFInfoRowCount
};

typedef NS_ENUM(NSInteger, SFReplaceRow) { SFReplaceRowImport = 0, SFReplaceRowKeepColors, SFReplaceRowRestore };

static const CGFloat kPreviewTile = 128.0;

@interface SFPreviewTile : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UILabel *placeholder;
@end

@implementation SFPreviewTile
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
        self.layer.cornerRadius = 25.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.backgroundColor = [UIColor clearColor];
        _imageView.opaque = NO;
        _imageView.tintColor = [UIColor labelColor];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_imageView];

        _placeholder = [[UILabel alloc] init];
        _placeholder.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _placeholder.textColor = [UIColor systemGrayColor];
        _placeholder.textAlignment = NSTextAlignmentCenter;
        _placeholder.numberOfLines = 2;
        _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_placeholder];

        _caption = [[UILabel alloc] init];
        _caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _caption.textColor = [UIColor systemGrayColor];
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.adjustsFontSizeToFitWidth = YES;
        _caption.minimumScaleFactor = 0.7;
        _caption.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_caption];

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],
            [_imageView.widthAnchor constraintEqualToConstant:kPreviewTile - 36],
            [_imageView.heightAnchor constraintEqualToAnchor:_imageView.widthAnchor],
            [_placeholder.centerXAnchor constraintEqualToAnchor:_imageView.centerXAnchor],
            [_placeholder.centerYAnchor constraintEqualToAnchor:_imageView.centerYAnchor],
            [_placeholder.widthAnchor constraintEqualToAnchor:_imageView.widthAnchor],
            [_caption.topAnchor constraintEqualToAnchor:_imageView.bottomAnchor constant:10],
            [_caption.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_caption.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        ]];
    }
    return self;
}
@end

@interface SFPreviewCell : UITableViewCell
@property (nonatomic, strong) SFPreviewTile *systemTile;
@property (nonatomic, strong) SFPreviewTile *replacementTile;
@property (nonatomic, assign) BOOL configured;
@end

@implementation SFPreviewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _systemTile = [[SFPreviewTile alloc] init];
        _replacementTile = [[SFPreviewTile alloc] init];
        _systemTile.translatesAutoresizingMaskIntoConstraints = NO;
        _replacementTile.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_systemTile];
        [self.contentView addSubview:_replacementTile];
        UIView *c = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_systemTile.topAnchor constraintEqualToAnchor:c.topAnchor constant:14],
            [_systemTile.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-14],
            [_replacementTile.topAnchor constraintEqualToAnchor:c.topAnchor constant:14],
            [_replacementTile.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-14],
            [_systemTile.widthAnchor constraintLessThanOrEqualToConstant:kPreviewTile + 12],
            [_replacementTile.widthAnchor constraintEqualToAnchor:_systemTile.widthAnchor],
            [_systemTile.leadingAnchor constraintGreaterThanOrEqualToAnchor:c.leadingAnchor constant:10],
            [_replacementTile.trailingAnchor constraintLessThanOrEqualToAnchor:c.trailingAnchor constant:-10],
            [_systemTile.trailingAnchor constraintEqualToAnchor:c.centerXAnchor constant:-7],
            [_replacementTile.leadingAnchor constraintEqualToAnchor:c.centerXAnchor constant:7],
        ]];
        NSLayoutConstraint *pref = [_systemTile.widthAnchor constraintEqualToConstant:kPreviewTile + 12];
        pref.priority = UILayoutPriorityDefaultHigh;
        pref.active = YES;
    }
    return self;
}
@end

@interface SFSymbolDetailController ()
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SFImageImporter *importer;
@end

@implementation SFSymbolDetailController

- (instancetype)initWithSymbolName:(NSString *)name {
    self = [super initWithNibName:nil bundle:nil];
    if (self) _symbolName = [name copy] ?: @"";
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.symbolName;
    self.navigationItem.titleView = [self makeTitleView];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    SFSetEmptyBackButton(self);

    self.tableView = SFMakeTableView(self);
    [self.tableView registerClass:[SFPreviewCell class] forCellReuseIdentifier:@"SFPreviewCell"];
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged:)
                                                 name:SFLanguageDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SFApplyNavigationChrome(self);
    [self.tableView reloadData];
}

- (void)languageChanged:(NSNotification *)n {
    [self.tableView reloadData];
}

- (UIView *)makeTitleView {
    UIImage *glyph = [SFSymbolStore renderedOriginalSymbolNamed:self.symbolName pointSize:17 color:[UIColor blackColor]];
    UIImageView *iv = [[UIImageView alloc] initWithImage:SFFitImage(glyph, 22, UIImageRenderingModeAlwaysTemplate)];
    iv.tintColor = [UIColor labelColor];
    iv.backgroundColor = [UIColor clearColor];
    [iv.widthAnchor constraintEqualToConstant:22].active = YES;
    [iv.heightAnchor constraintEqualToConstant:22].active = YES;
    UILabel *label = [[UILabel alloc] init];
    label.text = self.symbolName;
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:(glyph ? @[iv, label] : @[label])];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 6;
    stack.alignment = UIStackViewAlignmentCenter;
    return stack;
}

- (BOOL)isReplaced {
    return [[SFSymbolStore sharedStore] hasReplacementForSymbolName:self.symbolName];
}

- (UIImage *)systemImage {
    return [SFSymbolStore systemSFImageNamed:self.symbolName];
}

- (CGSize)systemPixelSize {
    return [SFSymbolStore systemPixelSizeForSymbolNamed:self.symbolName];
}

- (UIImage *)replacementImage {
    return [self isReplaced] ? [[SFSymbolStore sharedStore] replacementImageForSymbolName:self.symbolName] : nil;
}

- (BOOL)keepsColors {
    return [[SFSymbolStore sharedStore] keepsColorsForSymbolName:self.symbolName];
}

- (SFReplaceRow)replaceRowAt:(NSInteger)row {
    if (row == 0) return SFReplaceRowImport;
    return ([self isReplaced] && row == 1) ? SFReplaceRowKeepColors : SFReplaceRowRestore;
}

- (NSString *)pxText:(CGSize)px {
    if (px.width <= 0 || px.height <= 0) return @"—";
    return [NSString stringWithFormat:SFL(@"detail.pxFmt"), (size_t)px.width, (size_t)px.height];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SFDetailSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SFDetailSectionPreview: return 1;
        case SFDetailSectionInfo:    return SFInfoRowCount;
        case SFDetailSectionReplace: return [self isReplaced] ? 3 : 2;
        case SFDetailSectionExport:  return [self isReplaced] ? 2 : 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SFDetailSectionPreview: return SFL(@"detail.sec.preview");
        case SFDetailSectionInfo:    return SFL(@"detail.sec.info");
        case SFDetailSectionReplace: return SFL(@"detail.sec.replace");
        case SFDetailSectionExport:  return SFL(@"detail.sec.export");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SFDetailSectionPreview) return SFL(@"detail.footer.preview");
    if (section == SFDetailSectionReplace) return [self systemImage] ? SFL(@"detail.footer.replace") : SFL(@"alert.unavailable.msg");
    if (section == SFDetailSectionExport) return SFL(@"detail.footer.export");
    return nil;
}

- (UITableViewCell *)valueCell:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SFDetailValue"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"SFDetailValue"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.text = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SFSymbolStore *store = [SFSymbolStore sharedStore];
    BOOL replaced = [self isReplaced];

    if (indexPath.section == SFDetailSectionPreview) {
        SFPreviewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SFPreviewCell" forIndexPath:indexPath];
        UIImage *sys = [SFSymbolStore renderedOriginalSymbolNamed:self.symbolName pointSize:72 color:[UIColor blackColor]];
        cell.systemTile.imageView.image = [sys imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        cell.systemTile.caption.text = SFL(@"detail.tile.system");
        cell.systemTile.placeholder.hidden = (sys != nil);
        cell.systemTile.placeholder.text = SFL(@"detail.tile.unavailable");

        UIImage *rep = [(replaced ? [SFSymbolStore placedReplacementForSymbolName:self.symbolName pointSize:72] : nil)
                        imageWithRenderingMode:[self keepsColors] ? UIImageRenderingModeAlwaysOriginal : UIImageRenderingModeAlwaysTemplate];
        SFPreviewTile *tile = cell.replacementTile;
        UIImage *current = tile.imageView.image;
        BOOL changed = (current != rep) && !(current && rep && current.CGImage == rep.CGImage && current.renderingMode == rep.renderingMode);
        NSString *caption = (replaced && !store.isEnabled) ? SFL(@"detail.tile.replacementOff") : SFL(@"detail.tile.replacement");
        NSString *placeholder = replaced ? SFL(@"detail.tile.unreadable") : SFL(@"detail.tile.tapImport");
        void (^apply)(void) = ^{
            tile.imageView.image = rep;
            tile.caption.text = caption;
            tile.placeholder.hidden = (rep != nil);
            tile.placeholder.text = placeholder;
        };
        if (cell.configured && changed) SFCrossDissolve(tile, apply); else apply();
        cell.configured = YES;

        for (UIView *v in @[cell.systemTile, cell.replacementTile]) {
            for (UIGestureRecognizer *g in [v.gestureRecognizers copy]) [v removeGestureRecognizer:g];
            [v addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)]];
            v.userInteractionEnabled = YES;
        }
        return cell;
    }

    UITableViewCell *cell = [self valueCell:tableView];
    if (indexPath.section == SFDetailSectionInfo) {
        UIImage *sys = [self systemImage];
        switch (indexPath.row) {
            case SFInfoRowName:
                cell.textLabel.text = SFL(@"detail.name");
                cell.detailTextLabel.text = self.symbolName;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
            case SFInfoRowPoint: {
                CGSize pt = sys.size;
                cell.textLabel.text = SFL(@"detail.pointSize");
                cell.detailTextLabel.text = sys ? [NSString stringWithFormat:SFL(@"detail.ptFmt"), pt.width, pt.height] : @"—";
                break;
            }
            case SFInfoRowSystemPx:
                cell.textLabel.text = SFL(@"detail.systemPx");
                cell.detailTextLabel.text = [self pxText:[self systemPixelSize]];
                break;
            case SFInfoRowReplacementPx: {
                UIImage *rep = [self replacementImage];
                CGSize rpx = rep.CGImage ? CGSizeMake(CGImageGetWidth(rep.CGImage), CGImageGetHeight(rep.CGImage)) : CGSizeZero;
                cell.textLabel.text = SFL(@"detail.replacementPx");
                cell.detailTextLabel.text = rep ? [self pxText:rpx] : (replaced ? SFL(@"detail.tile.unreadable") : SFL(@"root.none"));
                break;
            }
            case SFInfoRowFileSize: {
                cell.textLabel.text = SFL(@"detail.fileSize");
                NSString *path = replaced ? [store replacementPathForSymbolName:self.symbolName] : nil;
                NSNumber *bytes = path ? [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileSize] : nil;
                cell.detailTextLabel.text = bytes ? [NSByteCountFormatter stringFromByteCount:bytes.longLongValue
                                                                                   countStyle:NSByteCountFormatterCountStyleFile]
                                                  : SFL(@"root.none");
                break;
            }
            default:
                cell.textLabel.text = SFL(@"detail.status");
                if (!replaced) cell.detailTextLabel.text = SFL(@"detail.status.system");
                else cell.detailTextLabel.text = store.isEnabled ? SFL(@"detail.status.replaced") : SFL(@"detail.status.replacedOff");
                if (replaced) cell.detailTextLabel.textColor = [UIColor systemBlueColor];
                break;
        }
    } else if (indexPath.section == SFDetailSectionReplace) {
        switch ([self replaceRowAt:indexPath.row]) {
            case SFReplaceRowImport:
                cell.textLabel.text = replaced ? SFL(@"detail.replace") : SFL(@"detail.import");
                cell.accessoryView = SFPillButton(replaced ? SFL(@"pill.replace") : SFL(@"pill.import"), YES, self, @selector(importTapped:));
                break;
            case SFReplaceRowKeepColors: {
                cell.textLabel.text = SFL(@"detail.keepColors");
                UISwitch *sw = [[UISwitch alloc] init];
                sw.on = [self keepsColors];
                [sw addTarget:self action:@selector(keepColorsChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
                break;
            }
            case SFReplaceRowRestore:
                cell.textLabel.text = SFL(@"detail.restore");
                cell.accessoryView = SFPillButton(SFL(@"pill.restore"), replaced, self, @selector(restoreTapped:));
                break;
        }
    } else if (indexPath.section == SFDetailSectionExport) {
        if (indexPath.row == 0) {
            cell.textLabel.text = SFL(@"detail.saveOriginal");
            cell.accessoryView = SFPillButton(SFL(@"pill.save"), [self systemImage] != nil, self, @selector(saveOriginalTapped:));
        } else {
            cell.textLabel.text = SFL(@"detail.saveReplacement");
            cell.accessoryView = SFPillButton(SFL(@"pill.save"), YES, self, @selector(saveReplacementTapped:));
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SFDetailSectionPreview) return kPreviewTile + 12 + 28;
    return SFRowHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return SFHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return SFHeaderHeight([self tableView:tableView titleForHeaderInSection:section], section);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return SFFooterView([self tableView:tableView titleForFooterInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return SFFooterHeight(tableView, [self tableView:tableView titleForFooterInSection:section]);
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    SFApplyPillCorners(tableView, cell, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SFDetailSectionInfo && indexPath.row == SFInfoRowName) {
        [UIPasteboard generalPasteboard].string = self.symbolName;
        SFPresentAlert(self, SFL(@"alert.copied"), nil);
    }
}

- (void)keepColorsChanged:(UISwitch *)sw {
    NSError *err = nil;
    if (![[SFSymbolStore sharedStore] setKeepsColors:sw.on forSymbolName:self.symbolName error:&err]) {
        [sw setOn:!sw.on animated:YES];
        SFPresentAlert(self, SFL(@"alert.saveFailed"), err.localizedDescription);
        return;
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SFDetailSectionPreview] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)previewTapped:(UITapGestureRecognizer *)g {
    [self importTapped:nil];
}

- (void)importTapped:(id)sender {
    if (![self systemImage]) {
        SFPresentAlert(self, SFL(@"alert.unavailable"), SFL(@"alert.unavailable.msg"));
        return;
    }
    self.importer = [[SFImageImporter alloc] init];
    NSString *name = self.symbolName;
    __weak __typeof__(self) ws = self;
    [self.importer chooseSourceAndImportFrom:self completion:^(UIImage *image, BOOL hasAlpha, NSString *errorMessage) {
        __typeof__(self) s = ws;
        if (!s) return;
        s.importer = nil;
        if (!image) {
            if (errorMessage) {
                SFPresentAlert(s, SFL(@"alert.importFailed"), errorMessage);
            }
            return;
        }
        NSError *err = nil;
        if (![[SFSymbolStore sharedStore] saveReplacementImage:image forSymbolName:name error:&err]) {
            SFPresentAlert(s, SFL(@"alert.importFailed"), err.localizedDescription);
            return;
        }
        [s.tableView reloadData];
        if (!hasAlpha) SFPresentAlert(s, SFL(@"alert.imported"), SFL(@"alert.noAlpha"));
    }];
}

- (void)restoreTapped:(id)sender {
    if (![self isReplaced]) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SFL(@"alert.restoreSymbol.titleFmt"), self.symbolName]
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    __weak __typeof__(self) ws = self;
    NSString *name = self.symbolName;
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SFL(@"alert.restore") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        __typeof__(self) s = ws;
        if (!s) return;
        NSError *err = nil;
        if (![[SFSymbolStore sharedStore] removeReplacementForSymbolName:name error:&err]) {
            SFPresentAlert(s, SFL(@"alert.restoreFailed"), err.localizedDescription);
        }
        [s.tableView reloadData];
    }]];
    SFPresentController(self, a);
}

- (void)shareData:(NSData *)png fileName:(NSString *)fileName from:(UIView *)source {
    if (png.length == 0) {
        SFPresentAlert(self, SFL(@"alert.saveFailed"), SFL(@"err.export"));
        return;
    }
    NSString *safe = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SFSymbolReplacerExport"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:safe]];
    NSError *err = nil;
    if (![png writeToURL:url options:NSDataWritingAtomic error:&err]) {
        SFPresentAlert(self, SFL(@"alert.saveFailed"), err.localizedDescription);
        return;
    }
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    if (!info[@"NSPhotoLibraryAddUsageDescription"] && !info[@"NSPhotoLibraryUsageDescription"]) {
        avc.excludedActivityTypes = @[UIActivityTypeSaveToCameraRoll];
    }
    __weak __typeof__(self) ws = self;
    avc.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *activityError) {
        if (!completed && activityError) {
            SFPresentAlert(ws, SFL(@"alert.saveFailed"), activityError.localizedDescription);
        }
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    };
    UIPopoverPresentationController *pop = avc.popoverPresentationController;
    if (pop) {
        UIView *anchor = (source.window ? source : self.view);
        pop.sourceView = anchor;
        pop.sourceRect = anchor.bounds;
    }
    SFPresentController(self, avc);
}

- (void)saveOriginalTapped:(UIButton *)sender {
    if (![self systemImage]) {
        SFPresentAlert(self, SFL(@"alert.unavailable"), SFL(@"alert.unavailable.msg"));
        return;
    }
    NSData *png = [SFSymbolStore originalSymbolPNGDataNamed:self.symbolName];
    [self shareData:png fileName:[self.symbolName stringByAppendingPathExtension:@"png"] from:sender];
}

- (void)saveReplacementTapped:(UIButton *)sender {
    NSString *path = [[SFSymbolStore sharedStore] replacementPathForSymbolName:self.symbolName];
    NSData *png = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSString *file = [[self.symbolName stringByAppendingString:SFL(@"detail.replacementSuffix")] stringByAppendingPathExtension:@"png"];
    [self shareData:png fileName:file from:sender];
}

@end
