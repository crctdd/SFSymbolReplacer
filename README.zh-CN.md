<p align="center"><a href="README.md">English</a> · <b>简体中文</b></p>

<p align="center"><img src="assets/icon.png" width="128" height="128" alt="SFSymbolReplacer"></p>

<h1 align="center">SFSymbolReplacer</h1>

<p align="center">用自己的 PNG 全局替换系统 SF 图标。</p>

<p align="center">
  <img src="assets/badges/ios.svg" alt="iOS 14–26">
  <img src="assets/badges/jailbreak.svg" alt="rootful · rootless · roothide">
  <a href="LICENSE"><img src="assets/badges/license.svg" alt="MIT"></a>
</p>

## 使用

设置里找 **SF 图标替换**，界面有中文和英文，在「语言」里切换。

- 进 **全部图标**，选一个图标，从相册或文件导入 PNG，透明背景效果最好。
- **批量导入** 一次选多个文件，按文件名对应图标：`heart.fill.png`、`heart.fill@3x.png` 都行，对不上的会列出来并跳过。
- **导出** 里「系统原图」那一行点 **保存**，得到系统图标的 PNG。
- 默认替换图跟系统图标一样着色，打开 **保留原色** 则用 PNG 自己的颜色。
- **恢复系统图标** 或 **全部恢复** 换回系统图标。已经显示的图标要等重绘才更新，注销后全局生效。

详情页显示的是系统尺寸，比如 45×61 px；保存导出的是同一块画布，长边约 512 px（比如 377×511），放大显示也清晰。替换图会缩放到系统实际绘制的大小。

## 原理

dylib 通过 `com.apple.CoreUI` 过滤器注入。

hook 的是 `CUINamedVectorGlyph` 的光栅化和取图方法（16 起还有 `_CUIGraphicVariantVectorGlyph`）、`+[UIImage systemImageNamed:]` 及其变体，以及 CoreGlyphs 那个 `_UIAssetManager` 的 `imageNamed:configuration:`。只替换 CoreGlyphs 和 SFSymbols.framework 里的图标，App 自带的资源和自定义符号不动。

放置只走一个函数：`SFPlace.c` 里的 `sf_compose`。整张 PNG 按画布比例等比缩放进系统正在画的那块光栅（也就是图标画布）并居中，不到 1 px 的空隙直接填满。UIKit 这边只用 `_imageWithContent:` 换掉系统图的像素内容，像素尺寸不变，尺寸、alignment insets 和 baseline 都还是系统的。

<details>
<summary>hook 列表</summary>

CoreUI（`CUINamedVectorGlyph`、`_CUIGraphicVariantVectorGlyph`）：

- `rasterizeImageUsingScaleFactor:forTargetSize:`，以及带 `withColorResolver:`、`withHierarchyColorResolver:`、`withPaletteColors:`、`withPaletteColorResolver:`、`hierarchicalPrimaryColor:`、`withTintColors:` 的版本
- `rasterizeImageWithTintColor:usingScaleFactor:forTargetSize:`
- `image`、`imageWithColorResolver:`、`imageWithHierarchyColorResolver:`、`imageWithPaletteColors:`、`imageWithPaletteColorResolver:`、`imageWithHierarchicalPrimaryColor:`、`imageTintedWithColor:`、`imageTintedWithColors:`、`imageWithTintColor:`

UIKit：

- `systemImageNamed:`、`…withConfiguration:`、`…compatibleWithTraitCollection:`、`…variableValue:withConfiguration:`，以及 `_` / `__` 开头的私有版本
- `-[_UIAssetManager imageNamed:configuration:]`

各版本不完全一样：14 有 `…withTintColors:` 和 `imageTintedWithColor(s):`，15 加了 hierarchy 和 palette，16 加了 palette resolver、hierarchical primary color 和 variant 类，26 加了 tint color 那两个。

</details>

## 已知限制

- SwiftUI / RenderBox 直接画矢量路径的图标替换不了，iOS 18 控制中心大多是这种。
- 多色图标不开「保留原色」就只有一种颜色。
- iOS 26 的玻璃和材质效果可能会再处理位图。
- 宽高比和图标画布不一样的 PNG 会等比放进去，两边留空。
- 原图按 regular 字重导出，其他字重的画布略有差别。

## 存储

```
jbroot:/var/mobile/Library/SFSymbolReplacer/
  Replacements.plist        图标名 -> 文件
  Replacements/<name>.png   名字里的 "/" 换成 "_"
  Options.plist             每个图标的选项（KeepColors）
```

导入时只转成正向的 PNG 存一次，不缩放不裁剪。解码上限 2048 px。改动通过 Darwin 通知 `com.iosdump.sfsymbolreplacer/Reload` 广播。

## 编译

roothide Theos + iOS 14.5 SDK（`TARGET = iphone:clang:14.5:14.0`）：

```sh
make package FINALPACKAGE=1
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

源码：`SFHooks.m`（hook）、`SFStore.c`（dylib 用的存储）、`SFPlace.c`（放置，和设置页共用）、`SFSymbolStore.m`（设置页用的存储）、`sfsymbolreplacerprefs/`（设置页）。

## 许可

[MIT](LICENSE)

## 链接

- Telegram：<https://t.me/iosdumpzzz>
- X：<https://x.com/apsnkizv>
