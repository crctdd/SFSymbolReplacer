#import "SFSymbolBrowserController.h"
#import "SFSymbolDetailController.h"
#import "SFImageImporter.h"
#import "SFLocalize.h"
#import "SFStyle.h"
#import "../SFSymbolStore.h"

static NSString * const kRowId = @"SFSymbolRow";
static const CGFloat kIconSide = 30.0;
static const CGFloat kThumbPoint = 20.0;

@interface SFRowAccessory : UIView
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UIButton *pill;
@end
@implementation SFRowAccessory
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithFrame:CGRectMake(0, 0, SFPillSize.width, SFPillSize.height)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _thumb = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kIconSide, kIconSide)];
        _thumb.backgroundColor = [UIColor clearColor];
        _thumb.contentMode = UIViewContentModeScaleAspectFit;
        _thumb.opaque = NO;
        _thumb.hidden = YES;
        [self addSubview:_thumb];
        _pill = SFPillButton(SFL(@"pill.import"), YES, target, action);
        [self addSubview:_pill];
    }
    return self;
}
- (void)configureWithThumb:(UIImage *)thumb title:(NSString *)title active:(BOOL)active animated:(BOOL)animated {
    SFUpdatePillButton(self.pill, title, active);
    self.pill.transform = CGAffineTransformIdentity;
    self.pill.alpha = 1.0;
    BOOL changed = (self.thumb.image != thumb);
    void (^apply)(void) = ^{
        self.thumb.image = thumb;
        self.thumb.hidden = (thumb == nil);
    };
    if (animated && changed && thumb) SFCrossDissolve(self.thumb, apply); else apply();
    CGFloat x = 0;
    if (thumb) { self.thumb.frame = CGRectMake(0, (SFPillSize.height - kIconSide) / 2.0, kIconSide, kIconSide); x = kIconSide + 8; }
    self.pill.frame = CGRectMake(x, 0, SFPillSize.width, SFPillSize.height);
    self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, x + SFPillSize.width, SFPillSize.height);
}
@end

@interface SFSymbolRowCell : UITableViewCell
@property (nonatomic, strong) SFRowAccessory *accessory;
@property (nonatomic, copy) NSString *symbolName;
@end
@implementation SFSymbolRowCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        self.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.textLabel.textColor = [UIColor labelColor];
        self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        self.imageView.tintColor = [UIColor labelColor];
        self.imageView.backgroundColor = [UIColor clearColor];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    }
    return self;
}
@end

@interface SFSymbolBrowserController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSString *> *allNames;
@property (nonatomic, copy) NSArray<NSString *> *replacedNames;
@property (nonatomic, copy) NSArray<NSString *> *shownAll;
@property (nonatomic, copy) NSArray<NSString *> *shownReplaced;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) NSUInteger searchGeneration;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *originalCache;
@property (nonatomic, strong) NSCache<NSString *, id> *replacementCache;
@property (nonatomic, strong) NSCache<NSString *, NSArray *> *metricsCache;
@property (nonatomic, strong) NSOperationQueue *renderQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSOperation *> *inFlight;
@property (nonatomic, strong) UIImage *blankIcon;
@property (nonatomic, assign) NSUInteger replacementGeneration;
@property (nonatomic, strong) SFImageImporter *importer;
@end

@implementation SFSymbolBrowserController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_renderQueue cancelAllOperations];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"browser.title");
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    SFSetEmptyBackButton(self);

    self.originalCache = [[NSCache alloc] init];
    self.originalCache.countLimit = 1500;
    self.replacementCache = [[NSCache alloc] init];
    self.replacementCache.countLimit = 400;
    self.metricsCache = [[NSCache alloc] init];
    self.metricsCache.countLimit = 4000;
    self.renderQueue = [[NSOperationQueue alloc] init];
    self.renderQueue.maxConcurrentOperationCount = 4;
    self.renderQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    self.renderQueue.name = @"SFSymbolReplacer.thumbs";
    self.inFlight = [NSMutableDictionary dictionary];
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    self.blankIcon = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kIconSide, kIconSide) format:fmt]
                      imageWithActions:^(__unused UIGraphicsImageRendererContext *c) {}];

    self.query = @"";
    self.replacedNames = @[];

    self.tableView = SFMakeTableView(self);
    [self.tableView registerClass:[SFSymbolRowCell class] forCellReuseIdentifier:kRowId];
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    self.searchController.searchBar.placeholder = SFL(@"browser.search");
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchController.searchBar.searchTextField.layer.cornerRadius = 18.0;
    self.searchController.searchBar.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
    self.searchController.searchBar.searchTextField.clipsToBounds = YES;
    SFApplySearchBarChrome(self.searchController.searchBar);
    self.definesPresentationContext = YES;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged:)
                                                 name:SFLanguageDidChangeNotification object:nil];

    NSArray *names = [SFSymbolStore loadedSymbolNames];
    if (names) {
        self.allNames = names;
    } else {
        self.allNames = @[];
        UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spin startAnimating];
        self.tableView.backgroundView = spin;
        __weak __typeof__(self) ws = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *loaded = [SFSymbolStore allAvailableSymbolNames];
            dispatch_async(dispatch_get_main_queue(), ^{
                __typeof__(self) s = ws;
                if (!s) return;
                s.allNames = loaded;
                s.tableView.backgroundView = nil;
                [s applyFilter:s.query];
            });
        });
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[SFSymbolStore sharedStore] reload];
    SFApplyNavigationChrome(self);
    self.replacementGeneration++;
    [self.replacementCache removeAllObjects];
    [self refreshReplacedAndFilter];
}

- (void)languageChanged:(NSNotification *)n {
    self.title = SFL(@"browser.title");
    self.searchController.searchBar.placeholder = SFL(@"browser.search");
    [self.tableView reloadData];
}

- (void)refreshReplacedAndFilter {
    self.replacedNames = [[SFSymbolStore sharedStore] replacedSymbolNames] ?: @[];
    [self applyFilter:self.query];
}

- (void)applyFilter:(NSString *)rawQuery {
    NSString *q = [rawQuery ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.query = q;
    NSUInteger gen = ++self.searchGeneration;
    NSArray<NSString *> *all = self.allNames ?: @[];
    NSArray<NSString *> *rep = self.replacedNames ?: @[];
    if (q.length == 0) {
        self.shownAll = all;
        self.shownReplaced = rep;
        [self.tableView reloadData];
        return;
    }
    __weak __typeof__(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSString *> *fa = [NSMutableArray array];
        for (NSString *n in all) {
            if ([n rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) [fa addObject:n];
        }
        NSMutableArray<NSString *> *fr = [NSMutableArray array];
        for (NSString *n in rep) {
            if ([n rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) [fr addObject:n];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) s = ws;
            if (!s || gen != s.searchGeneration) return;
            s.shownAll = fa;
            s.shownReplaced = fr;
            [s.tableView reloadData];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter:searchController.searchBar.text];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self applyFilter:@""];
}

- (BOOL)hasReplacedSection {
    return self.shownReplaced.count > 0;
}

- (NSArray<NSString *> *)namesForSection:(NSInteger)section {
    if ([self hasReplacedSection] && section == 0) return self.shownReplaced;
    return self.shownAll;
}

- (NSString *)nameAtIndexPath:(NSIndexPath *)ip {
    NSArray<NSString *> *names = [self namesForSection:ip.section];
    if (ip.row < 0 || (NSUInteger)ip.row >= names.count) return nil;
    return names[ip.row];
}

- (NSString *)metricsText:(NSArray *)m {
    if (m.count != 2) return SFL(@"browser.unavailable");
    CGSize pt = [m[0] CGSizeValue], px = [m[1] CGSizeValue];
    return [NSString stringWithFormat:SFL(@"browser.sizeFmt"), pt.width, pt.height, px.width, px.height];
}

- (UIImage *)originalThumbForName:(NSString *)name {
    UIImage *hit = [self.originalCache objectForKey:name];
    if (hit) return hit;
    UIImage *out = SFFitImage([SFSymbolStore renderedOriginalSymbolNamed:name pointSize:kThumbPoint color:[UIColor blackColor]],
                              kIconSide, UIImageRenderingModeAlwaysTemplate) ?: self.blankIcon;
    [self.originalCache setObject:out forKey:name];
    return out;
}

- (NSArray *)metricsForName:(NSString *)name {
    NSArray *m = [self.metricsCache objectForKey:name];
    if (m) return m;
    UIImage *sys = [SFSymbolStore systemSFImageNamed:name];
    if (sys) {
        CGSize pt = sys.size;
        CGSize px = [SFSymbolStore systemPixelSizeForSymbolNamed:name];
        m = @[[NSValue valueWithCGSize:pt], [NSValue valueWithCGSize:px]];
    } else {
        m = @[];
    }
    [self.metricsCache setObject:m forKey:name];
    return m;
}

- (void)requestReplacementForName:(NSString *)name {
    if (name.length == 0 || self.inFlight[name]) return;
    if (![[SFSymbolStore sharedStore] hasReplacementForSymbolName:name]) return;
    NSString *token = [NSUUID UUID].UUIDString;
    __weak __typeof__(self) ws = self;
    NSUInteger gen = self.replacementGeneration;
    NSBlockOperation *op = [[NSBlockOperation alloc] init];
    __weak NSBlockOperation *weakOp = op;
    UIImageRenderingMode mode = [[SFSymbolStore sharedStore] keepsColorsForSymbolName:name] ? UIImageRenderingModeAlwaysOriginal
                                                                                           : UIImageRenderingModeAlwaysTemplate;
    [op addExecutionBlock:^{
        UIImage *thumb = nil;
        BOOL cancelled = weakOp.isCancelled;
        if (!cancelled) {
            thumb = SFFitImage([SFSymbolStore placedReplacementForSymbolName:name pointSize:kThumbPoint], kIconSide, mode);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) s = ws;
            if (!s) return;
            if ([s.inFlight[name].name isEqualToString:token]) [s.inFlight removeObjectForKey:name];
            if (cancelled || gen != s.replacementGeneration) return;
            [s.replacementCache setObject:(thumb ?: (id)[NSNull null]) forKey:name];
            [s refreshVisibleCellsForName:name];
        });
    }];
    op.name = token;
    op.queuePriority = NSOperationQueuePriorityVeryHigh;
    self.inFlight[name] = op;
    [self.renderQueue addOperation:op];
}

- (void)refreshVisibleCellsForName:(NSString *)name {
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (![[self nameAtIndexPath:ip] isEqualToString:name]) continue;
        UITableViewCell *c = [self.tableView cellForRowAtIndexPath:ip];
        if ([c isKindOfClass:[SFSymbolRowCell class]] && [((SFSymbolRowCell *)c).symbolName isEqualToString:name]) {
            [self configureCell:(SFSymbolRowCell *)c name:name animated:YES];
        }
    }
}

- (void)configureCell:(SFSymbolRowCell *)cell name:(NSString *)name animated:(BOOL)animated {
    BOOL sameName = [cell.symbolName isEqualToString:name];
    cell.symbolName = name;
    BOOL replaced = [[SFSymbolStore sharedStore] hasReplacementForSymbolName:name];

    cell.imageView.image = [self originalThumbForName:name];
    cell.textLabel.text = name;
    cell.detailTextLabel.text = [self metricsText:[self metricsForName:name]];

    id rep = replaced ? [self.replacementCache objectForKey:name] : nil;
    UIImage *thumb = [rep isKindOfClass:[UIImage class]] ? rep : nil;
    if (!cell.accessory) cell.accessory = [[SFRowAccessory alloc] initWithTarget:self action:@selector(pillTapped:)];
    [cell.accessory configureWithThumb:thumb
                                 title:(replaced ? SFL(@"pill.applied") : SFL(@"pill.import"))
                                active:!replaced
                              animated:(animated || sameName)];
    cell.accessory.pill.accessibilityIdentifier = name;
    cell.accessoryView = cell.accessory;

    if (replaced && !rep) [self requestReplacementForName:name];
}

- (void)replacementChangedForName:(NSString *)name {
    self.replacementGeneration++;
    if (name.length) [self.replacementCache removeObjectForKey:name];
    [self refreshReplacedAndFilter];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasReplacedSection] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self namesForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self hasReplacedSection] && section == 0) {
        return [NSString stringWithFormat:SFL(@"browser.sec.replacedFmt"), (unsigned long)self.shownReplaced.count];
    }
    return [NSString stringWithFormat:SFL(@"browser.sec.allFmt"), (unsigned long)self.shownAll.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == [self numberOfSectionsInTableView:tableView] - 1) {
        return self.shownAll.count == 0 ? SFL(@"browser.empty") : SFL(@"browser.footer");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SFSymbolRowCell *cell = [tableView dequeueReusableCellWithIdentifier:kRowId forIndexPath:indexPath];
    NSString *name = [self nameAtIndexPath:indexPath] ?: @"";
    [self configureCell:cell name:name animated:NO];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
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

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:[SFSymbolRowCell class]]) return;
    NSString *name = ((SFSymbolRowCell *)cell).symbolName;
    if (name.length == 0) return;
    for (UITableViewCell *c in tableView.visibleCells) {
        if (c != cell && [c isKindOfClass:[SFSymbolRowCell class]] && [((SFSymbolRowCell *)c).symbolName isEqualToString:name]) return;
    }
    NSOperation *op = self.inFlight[name];
    if (op && !op.isExecuting) {
        [op cancel];
        [self.inFlight removeObjectForKey:name];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = [self nameAtIndexPath:indexPath];
    if (!name) return;
    SFSymbolDetailController *detail = [[SFSymbolDetailController alloc] initWithSymbolName:name];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)pillTapped:(UIButton *)sender {
    NSString *name = sender.accessibilityIdentifier;
    if (name.length == 0) return;
    if ([[SFSymbolStore sharedStore] hasReplacementForSymbolName:name]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:name message:SFL(@"alert.alreadyReplaced")
                                                            preferredStyle:UIAlertControllerStyleAlert];
        __weak __typeof__(self) ws = self;
        [a addAction:[UIAlertAction actionWithTitle:SFL(@"alert.replaceImage") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [ws importForName:name];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:SFL(@"alert.restoreSymbol") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            __typeof__(self) s = ws;
            if (!s) return;
            NSError *err = nil;
            if (![[SFSymbolStore sharedStore] removeReplacementForSymbolName:name error:&err]) {
                SFPresentAlert(s, SFL(@"alert.restoreFailed"), err.localizedDescription);
            }
            [s replacementChangedForName:name];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:SFL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
        SFPresentController(self, a);
        return;
    }
    [self importForName:name];
}

- (void)importForName:(NSString *)name {
    self.importer = [[SFImageImporter alloc] init];
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
        [s replacementChangedForName:name];
        if (!hasAlpha) SFPresentAlert(s, SFL(@"alert.imported"), SFL(@"alert.noAlpha"));
    }];
}

@end
