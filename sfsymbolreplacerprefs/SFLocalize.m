#import "SFLocalize.h"
#import <os/lock.h>
#import "../SFSymbolStore.h"

NSString * const SFLanguageDidChangeNotification = @"SFSymbolReplacerLanguageDidChange";
static NSString * const kLangKey = @"Language";
static NSString *sLang;

static NSDictionary<NSString *, NSString *> *SFTableZH(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"sep": @"，",
            @"ok": @"好",
            @"cancel": @"取消",
            @"appTitle": @"SF 图标替换",
            @"root.subtitle": @"点图标换成你自己的图片。",
            @"root.sec.general": @"通用",
            @"root.sec.symbols": @"图标",
            @"root.sec.system": @"系统",
            @"root.sec.about": @"关于",
            @"root.versionFmt": @"版本 %@",
            @"about.telegram": @"Telegram 频道",
            @"about.x": @"X",
            @"root.footer.general": @"",
            @"root.footer.symbols": @"批量导入按文件名匹配图标。",
            @"root.footer.system": @"",
            @"root.enable": @"启用",
            @"root.language": @"语言",
            @"root.languageValue": @"简体中文",
            @"root.replaced": @"已替换",
            @"root.countFmt": @"%lu 个",
            @"root.none": @"无",
            @"root.browse": @"全部图标",
            @"root.batch": @"批量导入",
            @"root.restoreAll": @"全部恢复",
            @"root.respring": @"注销",
            @"pill.import": @"导入",
            @"pill.applied": @"已应用",
            @"pill.replace": @"更换",
            @"pill.restore": @"恢复",
            @"pill.save": @"保存",
            @"pill.respring": @"注销",
            @"alert.restoreAll.title": @"恢复全部图标？",
            @"alert.restoreAll.action": @"全部恢复",
            @"alert.restoreFailed": @"恢复失败",
            @"alert.respring.title": @"注销？",
            @"alert.language.title": @"语言",
            @"alert.importSource.title": @"导入",
            @"alert.importSource.photos": @"从相册",
            @"alert.importSource.files": @"从文件",
            @"alert.importFailed": @"导入失败",
            @"alert.imported": @"已导入",
            @"alert.noAlpha": @"原图没有透明背景。",
            @"alert.saveFailed": @"保存失败",
            @"alert.copied": @"已拷贝",
            @"alert.unavailable": @"不可用",
            @"alert.unavailable.msg": @"此系统没有这个图标。",
            @"alert.alreadyReplaced": @"已有替换图。",
            @"alert.replaceImage": @"更换",
            @"alert.restoreSymbol": @"恢复",
            @"alert.restoreSymbol.titleFmt": @"恢复“%@”？",
            @"alert.restore": @"恢复",
            @"batch.progressFmt": @"正在导入 %lu/%lu",
            @"batch.summaryFmt": @"导入 %lu 个",
            @"batch.unmatchedFmt": @"%lu 个未匹配",
            @"batch.failedFmt": @"%lu 个失败",
            @"batch.noAlphaFmt": @"%lu 个无透明背景",
            @"batch.moreFmt": @"等 %lu 个",
            @"err.notImage": @"图片无法读取",
            @"err.decode": @"图片无法读取",
            @"err.fileRead": @"文件无法读取",
            @"err.invalid": @"图片无效",
            @"err.pngEncode": @"无法生成 PNG",
            @"err.writeConfigFmt": @"无法写入设置：%@",
            @"err.mkdirFmt": @"无法创建文件夹：%@",
            @"err.writePNGFmt": @"无法写入图片：%@",
            @"err.export": @"无法生成图片",
            @"browser.title": @"全部图标",
            @"browser.search": @"搜索",
            @"browser.sec.replacedFmt": @"已替换（%lu）",
            @"browser.sec.allFmt": @"全部图标（%lu）",
            @"browser.empty": @"无结果",
            @"browser.footer": @"",
            @"browser.sizeFmt": @"%.0f×%.0f 点 · %.0f×%.0f 像素",
            @"browser.unavailable": @"此系统不可用",
            @"detail.sec.preview": @"预览",
            @"detail.sec.info": @"尺寸",
            @"detail.sec.replace": @"替换",
            @"detail.sec.export": @"导出",
            @"detail.tile.system": @"系统原图",
            @"detail.tile.replacement": @"替换图",
            @"detail.tile.replacementOff": @"替换图（已停用）",
            @"detail.tile.tapImport": @"点按导入",
            @"detail.tile.unavailable": @"不可用",
            @"detail.tile.unreadable": @"无法读取",
            @"detail.footer.preview": @"",
            @"detail.name": @"名称",
            @"detail.pointSize": @"点尺寸",
            @"detail.systemPx": @"系统原图",
            @"detail.replacementPx": @"替换图",
            @"detail.fileSize": @"文件大小",
            @"detail.status": @"状态",
            @"detail.status.system": @"系统",
            @"detail.status.replaced": @"已替换",
            @"detail.status.replacedOff": @"已替换（已停用）",
            @"detail.pxFmt": @"%zu×%zu 像素",
            @"detail.ptFmt": @"%.1f×%.1f 点",
            @"detail.import": @"导入",
            @"detail.replace": @"更换",
            @"detail.restore": @"恢复系统图标",
            @"detail.keepColors": @"保留原色",
            @"detail.saveOriginal": @"系统原图",
            @"detail.saveReplacement": @"替换图",
            @"detail.footer.replace": @"整张图片等比缩放进原图标的画布并居中，导出的“系统原图”就是这块画布。关闭“保留原色”时跟随系统颜色。",
            @"detail.footer.export": @"",
            @"detail.replacementSuffix": @"-替换图",
        };
    });
    return t;
}

static NSDictionary<NSString *, NSString *> *SFTableEN(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"sep": @", ",
            @"ok": @"OK",
            @"cancel": @"Cancel",
            @"appTitle": @"SF Symbol Replacer",
            @"root.subtitle": @"Tap a symbol to use your own image.",
            @"root.sec.general": @"General",
            @"root.sec.symbols": @"Symbols",
            @"root.sec.system": @"System",
            @"root.sec.about": @"About",
            @"root.versionFmt": @"Version %@",
            @"about.telegram": @"Telegram Channel",
            @"about.x": @"X",
            @"root.footer.general": @"",
            @"root.footer.symbols": @"Batch Import matches file names to symbols.",
            @"root.footer.system": @"",
            @"root.enable": @"Enabled",
            @"root.language": @"Language",
            @"root.languageValue": @"English",
            @"root.replaced": @"Replaced",
            @"root.countFmt": @"%lu",
            @"root.none": @"None",
            @"root.browse": @"All Symbols",
            @"root.batch": @"Batch Import",
            @"root.restoreAll": @"Restore All",
            @"root.respring": @"Respring",
            @"pill.import": @"Import",
            @"pill.applied": @"Applied",
            @"pill.replace": @"Replace",
            @"pill.restore": @"Restore",
            @"pill.save": @"Save",
            @"pill.respring": @"Respring",
            @"alert.restoreAll.title": @"Restore all symbols?",
            @"alert.restoreAll.action": @"Restore All",
            @"alert.restoreFailed": @"Restore Failed",
            @"alert.respring.title": @"Respring?",
            @"alert.language.title": @"Language",
            @"alert.importSource.title": @"Import",
            @"alert.importSource.photos": @"Photos",
            @"alert.importSource.files": @"Files",
            @"alert.importFailed": @"Import Failed",
            @"alert.imported": @"Imported",
            @"alert.noAlpha": @"The image has no transparency.",
            @"alert.saveFailed": @"Save Failed",
            @"alert.copied": @"Copied",
            @"alert.unavailable": @"Unavailable",
            @"alert.unavailable.msg": @"Not available on this iOS version.",
            @"alert.alreadyReplaced": @"Already replaced.",
            @"alert.replaceImage": @"Replace",
            @"alert.restoreSymbol": @"Restore",
            @"alert.restoreSymbol.titleFmt": @"Restore \"%@\"?",
            @"alert.restore": @"Restore",
            @"batch.progressFmt": @"Importing %lu/%lu",
            @"batch.summaryFmt": @"%lu imported",
            @"batch.unmatchedFmt": @"%lu not matched",
            @"batch.failedFmt": @"%lu failed",
            @"batch.noAlphaFmt": @"%lu without transparency",
            @"batch.moreFmt": @"and %lu more",
            @"err.notImage": @"Can't Read Image",
            @"err.decode": @"Can't Read Image",
            @"err.fileRead": @"Can't Read File",
            @"err.invalid": @"Invalid image",
            @"err.pngEncode": @"Can't create PNG",
            @"err.writeConfigFmt": @"Can't save settings: %@",
            @"err.mkdirFmt": @"Can't create folder: %@",
            @"err.writePNGFmt": @"Can't save image: %@",
            @"err.export": @"Can't create image",
            @"browser.title": @"All Symbols",
            @"browser.search": @"Search",
            @"browser.sec.replacedFmt": @"Replaced (%lu)",
            @"browser.sec.allFmt": @"All Symbols (%lu)",
            @"browser.empty": @"No Results",
            @"browser.footer": @"",
            @"browser.sizeFmt": @"%.0f×%.0f pt · %.0f×%.0f px",
            @"browser.unavailable": @"Not available on this iOS",
            @"detail.sec.preview": @"Preview",
            @"detail.sec.info": @"Size",
            @"detail.sec.replace": @"Replacement",
            @"detail.sec.export": @"Export",
            @"detail.tile.system": @"Original",
            @"detail.tile.replacement": @"Replacement",
            @"detail.tile.replacementOff": @"Replacement (Off)",
            @"detail.tile.tapImport": @"Tap to Import",
            @"detail.tile.unavailable": @"Unavailable",
            @"detail.tile.unreadable": @"Can't Read",
            @"detail.footer.preview": @"",
            @"detail.name": @"Name",
            @"detail.pointSize": @"Point Size",
            @"detail.systemPx": @"Original",
            @"detail.replacementPx": @"Replacement",
            @"detail.fileSize": @"File Size",
            @"detail.status": @"Status",
            @"detail.status.system": @"System",
            @"detail.status.replaced": @"Replaced",
            @"detail.status.replacedOff": @"Replaced (Off)",
            @"detail.pxFmt": @"%zu×%zu px",
            @"detail.ptFmt": @"%.1f×%.1f pt",
            @"detail.import": @"Import",
            @"detail.replace": @"Replace",
            @"detail.restore": @"Restore Original",
            @"detail.keepColors": @"Keep Colors",
            @"detail.saveOriginal": @"Original",
            @"detail.saveReplacement": @"Replacement",
            @"detail.footer.replace": @"The whole image is scaled to fit the original symbol's canvas and centered; the exported Original is that canvas. With Keep Colors off, the icon uses the system color.",
            @"detail.footer.export": @"",
            @"detail.replacementSuffix": @"-replacement",
        };
    });
    return t;
}

static os_unfair_lock sLangLock = OS_UNFAIR_LOCK_INIT;

NSString *SFLanguage(void) {
    os_unfair_lock_lock(&sLangLock);
    NSString *cur = sLang;
    os_unfair_lock_unlock(&sLangLock);
    if (cur) return cur;
    id v = [[SFSymbolStore sharedStore] preferenceValueForKey:kLangKey];
    NSString *l = ([v isKindOfClass:[NSString class]] && [v isEqualToString:@"en"]) ? @"en" : @"zh";
    os_unfair_lock_lock(&sLangLock);
    if (!sLang) sLang = l;
    cur = sLang;
    os_unfair_lock_unlock(&sLangLock);
    return cur;
}

void SFSetLanguage(NSString *lang) {
    NSString *l = [lang isEqualToString:@"en"] ? @"en" : @"zh";
    os_unfair_lock_lock(&sLangLock);
    sLang = l;
    os_unfair_lock_unlock(&sLangLock);
    [[SFSymbolStore sharedStore] setPreferenceValue:l forKey:kLangKey];
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SFLanguageDidChangeNotification object:nil];
    };
    if ([NSThread isMainThread]) post(); else dispatch_async(dispatch_get_main_queue(), post);
}

NSString *SFL(NSString *key) {
    if (key.length == 0) return @"";
    NSString *zh = SFTableZH()[key];
    if ([SFLanguage() isEqualToString:@"en"]) {
        NSString *en = SFTableEN()[key];
        if (en) return en;
    }
    return zh ?: key;
}
