# Markdown Watcher — 移动端 Markdown 编辑器设计文档

> 日期:2026-06-25
> 状态:设计已逐节验证;经两轮独立子 agent 复审 + pub.dev/context7 实证,**v3**
> 平台:Flutter(iOS + Android 一套代码)

> **修订记录:**
> - **v2(2026-06-25):** ① Riverpod v2→**v3.3.2**(版本号错误);② 注入改 **JSON/通道**;③ 滚动同步 等比例→**锚点双向**;④ 自动保存原子化;⑤ inappwebview 停滞列为风险 + 渲染器抽象。
> - **v3(2026-06-25):** 修正 v2 引入/遗留的硬伤——① **SAF"原子写(temp+rename)"不成立**,改 **`openOutputStream("wt")` 原地写 + `.bak` + 字节核对**,诚实称"尽力安全写";② **P0 重排**:iOS 真机 WebView 可用性 > bookmark 五场景 > 锚点同步;③ **懒渲染↔锚点矛盾**:锚点基于 placeholder 高度 / 懒渲染仅超阈值长文启用;收敛 mtime 云 URI 假承诺、Mermaid 在线下载口子、渲染器"无痛换"乐观叙述;补 Find/Replace、键盘避让、大文件上限、深色跟随系统、后台恢复、安全深度、发布合规。
> - **v4(2026-06-25,第三轮复审收尾):** ① **§10 P0(a) 纠错**——IntersectionObserver 不属"渲染生死"(MVP 全量渲染不依赖它),移出 P0 生死项,改 "iOS WebView + markdown-it + JS 通道 + KaTeX/高亮实际渲染" 为生死项,IntersectionObserver 降为 P0 顺便探针;② 工具栏补"查找·替换"入口、Find/Replace 归属 `MarkdownEditor` 并给最小 UX;③ 后台恢复**分层厘清**(草稿=仅未命名 / 已命名=.bak / undo=编辑级独立);④ 大文件改**双阈值**(超下限只读 / 超上限拒绝);⑤ 键盘避让补 iOS WebView 获焦 push insets 说明;⑥ §10 Phase 1 补安全基线。

---

## 1. 概述与目标

构建一个**渲染效果顶级的移动端 Markdown 编辑器**,直接读写手机文件系统中用户自己的 `.md` 文件(类似移动版 Typora,但基于文件)。

**核心诉求:**

- 手机端运行,iOS + Android 一套代码(Flutter);
- 原生编辑器 + 实时预览;
- **显示效果顶级**:精致排版与代码高亮、LaTeX 数学公式与 Mermaid 图表、多主题与暗色模式、优秀图片渲染;
- 自适应布局:竖屏 tab 切换,横屏左右分屏;
- 纯文件系统访问(.md 文件),内置文件浏览器 + 系统导入。

**明确不做(YAGNI):** 云同步、**运行期文件监听**(仅 onResume 被动重校验,不做 watcher)、App 内置文档数据库。

---

## 2. 关键决策摘要

| 决策点 | 结论 | 理由 |
|---|---|---|
| 渲染架构 | **混合**:原生编辑器 + WebView 预览,渲染器抽象为 `MarkdownRenderer` 接口 | 打字手感原生 + 显示顶级各取所长;Mermaid/公式强制 Web |
| markdown 解析位置 | **WebView 内 JS 侧**(markdown-it 插件链) | 数学/图表插件天然集成;过桥经 **handler/postMessage 通道**(零拼接)防注入;token 带源码行号可做锚点同步与大纲 |
| 重渲染性能 | **按源码 hash 缓存渲染块** + 视口内懒渲染(仅超阈值长文) | 避免全量重渲染;锚点映射基于 placeholder 高度以兼容懒渲染 |
| 滚动同步 | **锚点同步**(源码行↔渲染元素/placeholder offsetTop),**双向** | 等比例在含图表/图片文档下错位;分屏核心诉求必须双向 |
| 保存模型 | **纯自动保存 + 尽力安全写**(SAF 原地 `wt` 写/iOS `replaceItem`)+ `.bak` + 保存前/onResume mtime 冲突校验 | 移动端约定;SAF 无真原子,诚实降级 |
| iOS 跨启动访问 | **NSURL bookmark 持久化**(原生 plugin 体量) | security-scoped URL 重启失效,bookmark 唯一方案 |
| 状态管理 | **Riverpod v3**(`@riverpod` codegen) | 派生/响应式状态多;当前稳定线 3.3.2 |
| 文件浏览 | 内置目录树 + 系统导入 | 体验连贯 |

---

## 3. 整体架构与分层

```
┌─────────────────────────────────────────────┐
│  UI 层 (Flutter Widgets)                      │
│  ┌──────────────┐  ┌───────────────────────┐ │
│  │ FileBrowser  │  │ EditorScreen(自适应)   │ │
│  │ 文件/文件夹树  │  │  ┌─原生编辑器(左/竖tab)│ │
│  │ + 最近列表    │  │  │   └ 工具栏/Find·Replace│ │
│  └──────────────┘  │  └─MarkdownRenderer     │ │
│                   │     └─WebViewRenderer   │ │
│                   │       (NativeRenderer    │ │
│                   │        = 停维生存兜底)    │ │
├─────────────────────────────────────────────┤
│  状态管理 (Riverpod v3)                       │
│  当前文档 / 文本 / 主题 / 大纲 / 未保存标记     │
├─────────────────────────────────────────────┤
│  服务层 (Dart)                                │
│  FileRepository · MarkdownBridge ·          │
│  ThemeService · RecentFilesService ·        │
│  UndoHistory(持久化)· ConflictChecker       │
├─────────────────────────────────────────────┤
│  预览运行时 (WebView 内: HTML模板)            │
│  markdown-it + KaTeX + highlight.js +        │
│  mermaid.js + 主题CSS                        │
└─────────────────────────────────────────────┘
```

**关键组件:**

- **`MarkdownEditor`(原生)**:`TextField` 代码风格编辑器,等宽字体,键盘上方 Markdown 工具栏;**含 Find/Replace**。
- **`MarkdownRenderer`(抽象接口)**:`render(markdown, theme)` + `syncScrollTo(line)` + 大纲回调 + 滚动监听。`WebViewRenderer` 为默认实现;**`NativeRenderer`(`markdown_widget`)仅作"WebView 包停维时的生存兜底",非日常可换等价实现**(富内容降级即体验塌缩,且锚点/主题各需一套实现)。
- **`PreviewWebView`/`WebViewRenderer`**:`flutter_inappwebview` 加载本地 HTML 模板。
- **`FileRepository`**:统一封装 SAF / iOS(security-scoped + bookmark)差异;**尽力安全写**(§5)。
- **`MarkdownBridge`**:管理 WebView 通道(防抖、入队、**handler/postMessage 通道**、JS 回调)。过桥通信 bug 高发,重点测试。
- **`ConflictChecker`**:载入/onResume 时比对磁盘 mtime+size,检测外部改动。
- **`UndoHistory`**:文本编辑级 undo 栈,**持久化**到 App 私有区。
- **`ThemeService`**:当前主题与暗色模式(含**跟随系统**)。

---

## 4. 预览渲染管线(核心数据流)

```
用户敲键
  │  (防抖 ~400ms)
  ▼
MarkdownBridge.push(rawMarkdownText)
  │  ★ 走 addJavaScriptHandler / postMessage 通道(零字符串拼接,防注入首选)
  │    或 jsonEncode 编码为合法 JS 字面量后插值(次选);Phase 0 二选一定死
  ▼  (WebView 内 JS:window.__render__(textLiteral, themeLiteral))
① markdown-it + 插件链 → token 流(block token 带 map 源码行号)+ HTML
   插件: texmath/katex(数学) · footnote · task-list(手写规则) · anchor(TOC)
② 每个 block 元素写 data-source-line(来自 token.map;null-check,tight list 的 hidden token 另处理)
③ KaTeX 渲染 $...$ 与 $$...$$
④ hljs.highlightElement(el) / mermaid.run({nodes}) —— 仅超阈值长文走 IntersectionObserver 懒触发;MVP 全量
⑤ 回传标题树(H1-H6,带源码行号)给 Dart 做大纲
```

**资源打包与体积:**

- markdown-it、KaTeX、highlight.js(`common` 子集 + 罕见语言按需)离线打进 assets;
- **Mermaid(~1.5MB)离线打进包**(接受体积,移除"按需下载"口子——离线优先 + 移动网络下不可靠);体积预算由 Phase 0 实测资源 gzip 表确定(不再拍脑袋);
- 长文(>阈值,如 2 万字)才启用懒渲染;MVP 全量渲染。

**注入防护(安全硬约束):**

- 首选 `addJavaScriptHandler` + JS 侧 `postMessage`/`JavaScriptChannel` 双向通道,**零字符串拼接**;次选 Dart `jsonEncode` 编码为合法 JS 字面量后插值(自定界,安全);
- 澄清:`</script>` **仅在 `loadHtmlString` 内联 `<script>` 路径**有风险(HTML parser);`evaluateJavascript` 路径走 JS 引擎不经 HTML parser,无此坑;U+2028/2029 在 ES2019+(全部目标平台)安全;
- 若日后改用内联 HTML 注入,必须额外转义 `<`。

**滚动同步(锚点,双向):**

- 渲染时每个 block 写 `data-source-line`(markdown-it block token 的 `map` = `[line_begin, line_end)` 0-indexed);
- **锚点映射基于 layout placeholder 高度**(而非已渲染 offsetTop),以兼容懒渲染下未渲染元素;
- 编辑器滚动 → 可视首行 → JS scrollTo 到覆盖该行的元素;预览滚动(分屏)→ 顶部可视元素 `data-source-line` → 编辑器跳行;
- 已知局限:长段落内只能锚到段首(inline token 无 map),如实记录;
- 横屏分屏**必须双向**;竖屏 tab 可省略。⚠️ P1 工程验证项(非 P0,见 §10/§11)。

---

## 5. 文件访问与数据流

`FileRepository` 抽象平台差异,上层统一 `read/write/list/create/rename/delete`。

```
                    ┌─────────────┐
   UI / 服务层  ───► │FileRepository│ ── 尽力安全写 / 权限封装
                    └──────┬──────┘
              ┌────────────┴────────────┐
              ▼                         ▼
   AndroidStrategy               iOSStrategy
   (SAF / 文件树 URI)           (security-scoped + bookmark)
```

**Android(SAF):** 系统选择器授权根目录树 URI + `takePersistableUriPermission`;`saf_util`+`saf_stream` 的 `DocumentFile` 增删改查。

**iOS:** `file_picker` 选文件/目录返 security-scoped URL;**首次访问生成 `NSURL bookmark` 持久化**,下次解析回 URL;用完 `stopAccessingSecurityScopedResource`;**需一个原生 plugin 体量**。

**bookmark 失效三分支:** ① `isStale` 但可解析 → 覆盖存新 bookmark;② 完全失效(移动/改名/删除)→ 重新走 picker;③ iCloud/file-provider 托管文件单独适配。
- **Phase 0 真机五场景:** 正常重启 / 杀进程重启 / 系统升级 / 文件被移动 / iCloud 文件。

**保存语义(纯自动保存 + 尽力安全写):**

- 内容有真实改动才触发,防抖后写入;
- **尽力安全写(非原子,诚实降级):**
  - **Android SAF:** `ContentResolver.openOutputStream(uri, "wt")` **原地 truncate-write**(URI 永不消失,并发读者只见旧或新);写前**复制当前内容到 `.bak`**,写后**字节数核对**;中途崩溃留截断文件 → 下次打开检测到截断则提示从 `.bak` 恢复。⚠️ `"wt"` 截断行为 provider-dependent,Phase 0 验证所用 provider。
  - **iOS:** 临时文件写 **App 私有 `temporaryDirectory`**(单文件 picker 不授权父目录)→ `FileManager.replaceItem(at:原, withItemAt:临时)` **原子替换**,全程包 `startAccessingSecurityScopedResource()`。
- **冲突校验(`ConflictChecker`):**
  - 保存前 + **onResume/回前台时**比对磁盘 mtime+size 与载入时;不符 → 弹"覆盖 / 重载 / 另存";
  - ⚠️ SAF 云 URI(Google Drive 等)`COLUMN_LAST_MODIFIED` 常为 null → **防御性回退**(size + 首尾字节比对,或诚实告知"无法检测外部改动");本机文件作乐观并发提示。
- undo 持久化 + `.bak`(上一份已保存内容)作反悔与崩溃兜底;undo 栈有上限与防抖持久化(避免每键写穿闪存)。

**最近列表:** `{显示名, 路径/URI, bookmark, 最后修改}`;打开校验权限,失效引导重授权(不静默失败)。

**大文件上限(双阈值,按字节,Phase 0 定值):** 超下限(如 2MB)→ 警告后**只读打开**(可读不可编辑,预览正常);超上限(如 10MB)→ 拒绝打开并提示。防止无虚拟化下的卡死。

---

## 6. 状态管理与编辑器交互

**Riverpod v3(`@riverpod` codegen + `AsyncNotifierProvider`):** `currentDocumentProvider`、`editorTextProvider`、`outlineProvider`、`themeProvider`、`dirtyIndicatorProvider`、`recentFilesProvider`;四件套(riverpod/flutter_riverpod/riverpod_annotation/riverpod_generator)同主版本。

**Markdown 工具栏:** 粗体/斜体/删除线/标题(H1–H3)/无序·有序·任务列表/引用/代码·代码块/链接/图片/表格/分隔线/**查找·替换**。选中文本两端插配对语法。

**Find/Replace(归属 `MarkdownEditor`,Phase 2):** 工具栏按钮触发 → 底部 sheet(输入框 + 匹配数 + 上一个/下一个/替换/全替换 + 正则/大小写开关);匹配高亮上限(如 1000,超限降级为不全高亮);单步替换复用 undo 栈。

**undo 语义:** undo 作用域 = 文本编辑操作;另设"恢复到上次已保存版本(`.bak`)"独立概念。

**键盘避让:** `SafeArea` + `MediaQuery.viewInsets`;编辑器获焦时键盘上方浮工具栏;预览只读不抢键盘;分屏时按获焦面板避让;**iOS 上 WebView 内若需输入(未来富文本),获焦时由 JS 回调 push insets 给原生**(`flutter_inappwebview` 已知坑:WebView 不自动响应原生键盘 insets)。

**深色模式:** 三套主题(亮/暗/护眼)+ **跟随系统**;跟随系统时映射:亮→亮主题、暗/护眼→暗主题(可在设置改默认映射)。

**后台被杀恢复(三层兜底,边界厘清):**

- **草稿恢复 = 仅未命名新文档**:内容 + 草稿路径持久化到 App 私有区 `drafts/`,启动检测未保存草稿 → 弹"恢复 / 丢弃";
- **已命名文档** 靠 §5 `.bak`(上一份已保存内容),不写草稿;
- **undo 持久化** = 编辑操作级,独立存储,三者互不混淆(同一崩溃不产生多个冲突恢复源)。

**大纲导航:** markdown-it 回传标题树(带源码行号)→ 侧滑列表跳转(复用锚点映射)。

---

## 7. 错误处理、无障碍与安全

| 场景 | 处理 |
|---|---|
| WebView 未就绪时已打字 | 更新请求**入队**,`onLoadStop` 后 flush |
| JS 渲染报错 | `onConsoleMessage` 捕获,仅 debug 可见 |
| 用户输入含特殊字符 | 走通道/JSON 编码,禁字符串拼接 |
| 文件权限吊销/bookmark 失效 | 引导**重新授权**(三分支) |
| **写入中断/磁盘满** | `.bak` 兜底 + 重开提示恢复(SAF 非原子,诚实) |
| **保存/onResume 检测外部改动** | 弹"覆盖/重载/另存"(云 URI 防御性回退) |
| Mermaid 语法错误 | 错误框渲染,不中断整页 |
| 图片加载失败 | 占位符 + 可选重试 |
| App 被系统杀进程 | 三层兜底(§6):未命名→草稿恢复 / 已命名→`.bak` / 编辑操作→undo 持久化 |

**安全(深化):**

- markdown-it **`html: false`(默认禁 raw HTML)**;若需开,必配 sanitizer(DOMPurify);
- 外链 `<a href>` 点击经 handler 拦截 → **系统浏览器**打开,不在 WebView 内导航;
- 禁 WebView `file://` 跨域;`<iframe>`/`<form>` 随 html 开关决定;
- KaTeX/Mermaid 版本选择**关注历史 CVE**,锁定可修复版本;
- 用户 markdown 经通道注入(防 JS 逃逸);本地图片路径经 `FileRepository` 解析防路径逃逸。

**无障碍:** 工具栏 `Semantics`;编辑器按行语义提示(H1/列表/正文);WebView 注入 ARIA + "跳到下一标题" handler;**已知缺口**:WebView 完整 a11y 受限,Phase 3 推进,目标 WCAG AA 或如实记录。

---

## 8. 测试策略(按可测性分层)

- **JS 渲染管线(Node+jsdom):** 单元/快照,覆盖基础/表格/任务/脚注/TOC/数学/Mermaid/高亮;复用同一 bundle;Mermaid 快照测结构锁版本防 flaky。
- **JS 视觉 golden(Playwright):** HTML 模板视觉回归。
- **★ MarkdownBridge 过桥集成测试(bug 高发区):** 未就绪入队→flush;防抖多次更新只发一次;**注入回归(含 `` ` ``/`</script>`/U+2028 不逃逸)**;大纲回传时序;锚点同步正确性(跳到正确锚点,可断言)。
- **Flutter 单元/Widget:** 工具栏配对插入;`FileRepository` 测**尽力安全写(`.bak`+字节核对)、`"wt"` 截断、mtime/size 冲突、权限降级、云 URI 防御回退**;`UndoHistory` 持久化往返;`LayoutBuilder` 竖/横屏。
- **`integration_test` 冒烟** + **手动 QA:** SAF 选权限、手势、iOS bookmark 真机五场景、键盘避让。

---

## 9. 依赖锁定与 API 核对清单

> 原则:context7 核对 + 精确锁定 + JS 锁次版本。版本经 pub.dev/npm/context7 **实证(2026-06-25)**。

### Dart / Flutter

| 包 | 建议锁定 | 状态(实证) | 备注 |
|---|---|---|---|
| `flutter_inappwebview` | `^6.1.5` | ⚠️ 6.1.5(2024-10,**~20 月未更新**;有 6.2.0-beta) | 头号风险;**P0 真机验 iOS 可用性**;渲染器接口对冲 |
| `flutter_riverpod`+`riverpod_annotation`+`riverpod_generator` | `^3.3.2`(同主版本) | ✅ stable(2026-06-10) | `@riverpod` codegen + `AsyncNotifierProvider` |
| `file_picker` | `^11.0.2` | ⚠️ stable 11;v12 beta.7 即将发布 | 锁 v11;v12 stable 后评估迁移 |
| `saf_util`+`saf_stream` | `^3.1.0` | ✅ 活跃 | SAF API 演进中 |
| `path_provider` | `^2.1.6` | ✅ 稳定 | — |
| 图片放大 | **内置 `InteractiveViewer`** | — | 弃用 `photo_view`(2024-04,2+ 年停更) |
| 崩溃上报 | `sentry_flutter: ^9.22.0` 或 `firebase_crashlytics: ^5.2.4` | ✅ 均活跃 | 二选一 |

### JS(精确锁次版本)

```
markdown-it: 14.2.0
markdown-it-texmath: 1.0.0          # 4 年未更新;备选 @vscode/markdown-it-katex
markdown-it-footnote: 4.0.0
markdown-it-task-lists: ❌ 替换     # archive → 手写规则或 task-checkbox
markdown-it-anchor: 9.2.0
katex: 0.17.0
highlight.js: 11.11.1               # common 子集 + 按需
mermaid: 11.15.0                    # 离线打进包;initialize({startOnLoad:false})+run()
```

### 破坏性变更 / 风险关注清单(实证)

| 依赖 | 关注点 |
|---|---|
| `flutter_inappwebview` | **维护停滞 + iOS 2026 可用性(头号风险)**;v5→v6 `evaluateJavascript` 改 `source:` |
| `flutter_riverpod` | v2→v3;`StateNotifier` 弃用、codegen 推荐 |
| `file_picker` | v12 即将发布 |
| `saf_util`/`saf_stream` | API 演进;`"wt"` 截断行为 provider-dependent |
| `photo_view`/`markdown-it-task-lists`/`texmath` | 停更/archive,已定替代 |

---

## 10. MVP 分期

**Phase 0 — 脚手架 + P0 生死验证**
- 项目初始化 · 依赖锁定(§9)· 渲染器接口 + `WebViewRenderer` hello world · 主题注入;
- **★ P0(按生死优先级):**
  - **(a) iOS 真机 WebView 渲染生死(最高优先级):** 加载本地 assets HTML + markdown-it 解析 + JS 双向通道(handler/postMessage)+ **实际渲染一段含代码高亮与 KaTeX 的样本**(决定方案生死);`IntersectionObserver` **不属生死项**(MVP 全量渲染不依赖它),仅作 P0 顺便探针,长文懒渲染留 Phase 2;
  - **(b) iOS bookmark 五场景真机矩阵;**
  - **(c) SAF 尽力安全写:** `openOutputStream("wt")` 截断行为 + `.bak` 恢复验证;
  - **(d) 资源 gzip 实测表 + 大文件打开双阈值确定。**
  - 任一(a)(b)不过 → 回设计台。锚点同步为 **P1**,Phase 1 内验证。

**Phase 1 — MVP(最小可发布)**
- 单文件打开(SAF/iOS picker);
- 原生编辑器 + 预览(基础 markdown:标题/列表/粗斜体/代码/引用/链接);
- 尽力安全自动保存 + mtime/size 冲突校验 + 持久化 undo/`.bak`;
- 3 主题 + 跟随系统;
- 竖屏 tab / 横屏分屏自适应 + **双向锚点滚动同步(P1 验证)**;
- MarkdownBridge 通道 + 注入防护;
- **安全基线:** markdown-it `html:false`、外链拦截到系统浏览器、禁 `file://` 跨域(CVE 版本锁定属 Phase 0 依赖动作);
- 键盘避让、大文件双阈值、后台草稿恢复(分层,见 §6)。

**Phase 2 — 富内容 + 编辑增强**
表格 · 任务列表 · 脚注 · TOC · 数学公式(KaTeX) · 代码高亮按需 · Mermaid(离线) · 图片(本地+网络+`InteractiveViewer`) · 大纲导航 · hash 缓存 · **Find/Replace** · 长文懒渲染(超阈值)。

**Phase 3 — 打磨与发布**
内置文件浏览器(目录树/新建/重命名/删除/移动) · 最近列表 · 崩溃上报 · **a11y 推进(WCAG AA)** · 多主题扩展 · **发布合规(iOS PrivacyInfo、Android 权限/数据安全、商店素材、首次启动引导)**。

---

## 11. 风险与未决

1. **🔴 `flutter_inappwebview` 维护停滞 + 2026 iOS 可用性(头号风险):** 核心渲染通道;**P0 真机验可用性**;对冲:渲染器接口化,`NativeRenderer`(`markdown_widget`)仅作停维生存兜底。
2. **🟡 锚点滚动同步:** 工程问题非可行性;Phase 1 内验证(基于 placeholder 高度,长段落内只能锚段首)。
3. **🟡 iOS bookmark 原生通道:** plugin 体量 + 三类失效 + 五场景;P0 验证。
4. **🟡 SAF 尽力安全写:** 无真原子;`"wt"` 截断 provider-dependent;`.bak` + 字节核对 + 截断恢复兜底;P0 验证。
5. **🟡 mtime 云 URI 不可靠:** 防御性回退(size+首尾字节)。
6. **🟡 Mermaid 体积:** ~1.5MB 离线打进包;Phase 0 实测 gzip 表定预算。
7. **🟡 TextField 长文性能:** 1 万行+ 输入延迟需 Phase 0 量化(代码风格编辑器着色叠加)。
8. **MVP 范围**为提议,可在文档内调整后定稿。
