import AppKit
import Foundation
import WebKit

let sampleMarkdown = """
---
course: 货币金融学
tags:
  - finance/rate
---

# 魏碑 Markdown Web 验收

| 能力 | 状态 |
| --- | --- |
| 表格 | 可编辑 |
| Agent | 可追问 |
| 双链 | [[货币理论\\|理论别名]] |
| 转义 | A \\| B |

- [ ] todo
- [x] done
- 普通列表
  - 嵌套列表

~~删除线~~、==重点高亮==、[[货币理论|理论别名]]、[[货币理论#利率]]、[[货币理论#^rate-block]]、[[#本页标题]]、[[^^利率搜索]]。
%%这是一条只在写作时弱显示的注释%%
%%
这是一段块注释
跨行也应该弱显示
%%
#finance #nested/tag
重点段落 ^rate-block

HTML 换行第一行<br />第二行，选区应读作两行。

脚注引用[^1]，行内脚注^[行内脚注内容]。

[^1]: 这是脚注内容。

> [!note]- 可编辑标题
>
> 温和洞察应该放在不打断阅读的位置。

> [!quote] 选区摘录
>
> 利率是资金使用价格的表达。
>
> 来源：Mishkin 教材样例，第 12 页
>
> Source: Mishkin sample, page 13

> [!quote] 旧摘录
>
> [!quote] 旧逻辑泄露
> 这行旧摘录正文不能带着控制符显示。

> > [!quote] 嵌套摘录
> >
> > 嵌套摘录里的控制符不应该露出来。

> [!attention]+ 自定义标题
>
> 自定义 Callout 不应该漏出源标记。

> 引用里的代码块：
>
> ```txt
> \\#quoted-code \\$5 \\[!note] <br />
> ```

行内公式 $E = mc^2$、$\\alpha_1 + \\beta^2$、$A^*$，普通金额 $5 不应该被误伤。

Milkdown 公式插件应直接渲染 $text^*$，不能额外生成源码灰块。

$$
\\frac{a_1}{b^2} + \\sum_{i=1}^{n} x_i
$$

$$
\\begin{bmatrix}
a & b \\\\
c & d
\\end{bmatrix}
$$

```swift
let note = "魏碑"
print(note)
```

行内代码 `<br />` 不应被当成换行。
双反引号 ``内部 ` <br />`` 也要保留源码。
行内代码 `[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />` 不应触发魏碑语法装饰。
行内代码 `\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]` 保存时不能被清理反斜杠。
转义反引号 \\` 后面的 \\[\\[转义双链\\]\\] \\#escaped-tag \\$5 仍应按正文保存。

```html
<span>保留<br />源码</span>
```

```txt
\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]
```

```mermaid
graph TD
  A[阅读] --> B[整理]
```

![魏碑测试图|100x80](assets/weibei.svg)
![远程测试图](https://example.com/weibei.png)
![[assets/weibei.svg|100]]
![[货币理论#利率]]
"""

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("web-editor-check failed: \(message)\n", stderr)
        exit(1)
    }
}

func json(_ value: String) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\""
}

final class EditorHarness: NSObject, WKScriptMessageHandler {
    private struct Snapshot {
        let documentID: String
        let documentGeneration: Int
        let revision: Int
        let markdown: String
    }

    private let webView: WKWebView
    private var isDone = false
    private var failure: String?
    private var activatedWikiTitle: String?
    private var attachmentRequests = 0
    private var linkEditorRequests = 0
    private var imagePickerRequests = 0
    private var activatedSelectionAskThreadID: String?
    private var editorFailures = 0
    private var currentDocumentID = "web-editor-check"
    private var currentDocumentGeneration = 0
    private var currentRevision = 0
    private var isDirty = false
    private var snapshotCount = 0
    private var snapshotCallbacks: [String: (Snapshot) -> Void] = [:]
    private var outlineEvents: [(documentID: String, items: [[String: Any]])] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let source = """
        document.documentElement.setAttribute("writingsuggestions", "false");
        window.initialMarkdown = \(json(sampleMarkdown));
        window.weiBeiDocumentID = "web-editor-check";
        window.weiBeiMarkdownEditable = true;
        window.weiBeiEditorCheckMode = true;
        window.weiBeiLocalImageScheme = "weibeiimage";
        window.weiBeiMarkdownBaseURL = \(json(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/WeiBei/Resources/Editor/").absoluteString));
        """
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        super.init()
        for name in ["editorReady", "dirtyChanged", "snapshotReady", "outlineChanged", "selectionChanged", "askAgentWithSelection", "linkEditorRequested", "wikiLinkActivated", "imageAttachmentRequested", "imagePickerRequested", "selectionAskMark", "editorFailure"] {
            controller.add(self, name: name)
        }
    }

    func run() {
        let indexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        let timeout = Date().addingTimeInterval(30)
        while !isDone && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if let failure {
            fputs("web-editor-check failed: \(failure)\n", stderr)
            exit(1)
        }
        expect(isDone, "editable editor validation did not finish within 30 seconds")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "editorReady":
            guard updateSession(from: message.body), currentDocumentID == "web-editor-check" else {
                fail("editorReady did not include the V2 document identity")
                return
            }
            validateInitialMarkdown()
        case "dirtyChanged":
            guard updateSession(from: message.body),
                  let dirty = (message.body as? [String: Any])?["dirty"] as? Bool else {
                fail("dirtyChanged did not include the V2 session and dirty state")
                return
            }
            isDirty = dirty
        case "snapshotReady":
            guard updateSession(from: message.body),
                  let body = message.body as? [String: Any],
                  let requestID = body["requestID"] as? String,
                  let markdown = body["markdown"] as? String,
                  let callback = snapshotCallbacks.removeValue(forKey: requestID) else {
                fail("snapshotReady did not match a V2 snapshot request")
                return
            }
            snapshotCount += 1
            callback(Snapshot(
                documentID: currentDocumentID,
                documentGeneration: currentDocumentGeneration,
                revision: currentRevision,
                markdown: markdown
            ))
        case "outlineChanged":
            guard updateSession(from: message.body),
                  let items = (message.body as? [String: Any])?["items"] as? [[String: Any]] else {
                fail("outlineChanged did not include a V2 session and outline payload")
                return
            }
            outlineEvents.append((currentDocumentID, items))
        case "wikiLinkActivated":
            activatedWikiTitle = (message.body as? [String: Any])?["title"] as? String
        case "imageAttachmentRequested":
            attachmentRequests += 1
        case "linkEditorRequested":
            linkEditorRequests += 1
        case "imagePickerRequested":
            imagePickerRequests += 1
        case "selectionAskMark":
            activatedSelectionAskThreadID = (message.body as? [String: Any])?["threadId"] as? String
        case "editorFailure":
            editorFailures += 1
        default:
            break
        }
    }

    private func updateSession(from value: Any) -> Bool {
        guard let body = value as? [String: Any],
              body["protocolVersion"] as? Int == 2,
              let documentID = body["documentID"] as? String,
              let documentGeneration = body["documentGeneration"] as? Int,
              let revision = body["revision"] as? Int else { return false }
        currentDocumentID = documentID
        currentDocumentGeneration = documentGeneration
        currentRevision = revision
        return true
    }

    private func requestSnapshot(completion: @escaping (Snapshot) -> Void) {
        let requestID = UUID().uuidString
        snapshotCallbacks[requestID] = completion
        let command: [String: Any] = [
            "protocolVersion": 2,
            "commandID": "web-editor-check-snapshot-\(requestID)",
            "requestID": requestID,
            "documentID": currentDocumentID,
            "documentGeneration": currentDocumentGeneration,
            "minimumRevision": currentRevision,
            "type": "requestSnapshot",
            "payload": [:],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let encoded = String(data: data, encoding: .utf8) else {
            fail("could not encode V2 snapshot request")
            return
        }
        webView.evaluateJavaScript("window.WeiBeiEditor.dispatchCommand(\(encoded))") { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.snapshotCallbacks.removeValue(forKey: requestID)
                self.fail("V2 snapshot request was rejected: \(String(describing: error))")
                return
            }
        }
    }

    private func validateInitialMarkdown() {
        requestSnapshot { [weak self] snapshot in
            guard let self else { return }
            self.validate(snapshot.markdown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.validateObsidianDecorations {
                    self.validateReadOnlyInkstoneDecorations {
                        self.validateSelectionAskMark {
                            self.validateRenderedImageSource {
                                self.validateWikiLinkActivation()
                            }
                        }
                    }
                }
            }
        }
    }

    private func validateObsidianDecorations(completion: @escaping () -> Void) {
        let script = """
        (() => ({
          writingSuggestionsDisabled: Boolean(document.querySelector('.ProseMirror')?.closest('[writingsuggestions="false"]')),
          wikilinkText: document.querySelector('.weibei-wikilink')?.textContent || '',
          inlineFootnoteText: document.querySelector('.weibei-inline-footnote')?.textContent || '',
          inlineFootnotes: document.querySelectorAll('.weibei-inline-footnote').length,
          comments: document.querySelectorAll('.weibei-comment').length,
          commentsWeak: (() => {
            const comments = Array.from(document.querySelectorAll('.weibei-comment'));
            if (comments.length < 1) return false;
            return comments.every((comment) => {
              const style = getComputedStyle(comment);
              return parseFloat(style.opacity || '1') <= 0.72
                || style.color === 'rgba(0, 0, 0, 0)'
                || parseFloat(style.fontSize || '16') <= 12;
            });
          })(),
          tags: document.querySelectorAll('.weibei-tag').length,
          blockIds: document.querySelectorAll('.weibei-block-id').length,
          frontmatterTitle: document.querySelector('.frontmatter-title')?.textContent || '',
          embeds: document.querySelectorAll('.weibei-embed-preview').length,
          sourceReferences: document.querySelectorAll('.weibei-source-reference').length,
          sourceReferenceTitle: document.querySelector('.weibei-source-reference')?.getAttribute('title') || '',
          hardBreaks: document.querySelectorAll('.ProseMirror br').length,
          noteEmbedLinks: document.querySelectorAll('.weibei-embed-note[role="link"][tabindex="0"][data-wikilink-title]').length,
          mermaid: document.querySelectorAll('.weibei-mermaid-render').length,
          mermaidSvg: document.querySelectorAll('.weibei-mermaid-render svg').length,
          mermaidPlaceholder: document.body.textContent.includes('渲染器未安装完成') ? 1 : 0,
          mermaidText: document.querySelector('.weibei-mermaid-render')?.textContent || '',
          mermaidSourceOpacity: getComputedStyle(document.querySelector('.weibei-mermaid-block') || document.body).opacity,
          mathInlinePreview: document.querySelectorAll('.weibei-math-inline > .weibei-math-preview > .katex').length,
          mathBlockPreview: document.querySelectorAll('.weibei-math-block > .weibei-math-preview > .katex-display').length,
          mathSourcesHidden: Array.from(document.querySelectorAll('.weibei-math-source')).every((source) => getComputedStyle(source).display === 'none'),
          mathContainersVisible: Array.from(document.querySelectorAll('.weibei-math-node')).every((node) => {
            const style = getComputedStyle(node);
            const rect = node.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && rect.width > 0 && rect.height > 0;
          }),
          foldedCallout: document.querySelector('blockquote.weibei-callout')?.getAttribute('data-callout-fold') || '',
          calloutTitle: document.querySelector('blockquote.weibei-callout')?.getAttribute('data-callout-title') || '',
          calloutHeadingVisible: (() => {
            const header = document.querySelector('blockquote.weibei-callout .weibei-callout-header');
            const type = header?.querySelector('.weibei-callout-type');
            const title = header?.querySelector('.weibei-callout-title');
            if (!header || !type || !title) return false;
            const style = getComputedStyle(header);
            return style.display !== 'none' && !type.disabled && !title.readOnly && title.value === '可编辑标题';
          })(),
          calloutSourceMarkerAbsent: (() => {
            const callout = document.querySelector('blockquote.weibei-callout[data-type="callout"]');
            return Boolean(callout)
              && callout.querySelector('.weibei-callout-marker') === null
              && !callout.textContent.includes('[!');
          })(),
          quoteCalloutTitle: document.querySelector('blockquote.weibei-callout-quote')?.getAttribute('data-callout-title') || '',
          quoteCalloutText: document.querySelector('blockquote.weibei-callout-quote')?.textContent || '',
          quoteCalloutCount: document.querySelectorAll('blockquote.weibei-callout-quote').length,
          visibleRawCalloutMarkers: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return -1;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
              const parent = node.parentElement;
              if (parent?.closest('code, pre')) continue;
              if (parent?.closest('.weibei-callout-marker')) continue;
              const style = getComputedStyle(parent);
              const visible = style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0'
                && style.color !== 'rgba(0, 0, 0, 0)'
                && parseFloat(style.fontSize || '0') > 0;
              if (visible) count += 1;
            }
            return count;
          })(),
          customCalloutType: document.querySelector('blockquote[data-callout="attention"]')?.getAttribute('data-callout') || '',
          customCalloutFold: document.querySelector('blockquote[data-callout="attention"]')?.getAttribute('data-callout-fold') || '',
          customCalloutTitle: document.querySelector('blockquote[data-callout="attention"]')?.getAttribute('data-callout-title') || '',
          customCalloutText: document.querySelector('blockquote[data-callout="attention"]')?.textContent || '',
          inlineCodeSyntaxDecorations: document.querySelectorAll('code .weibei-wikilink, code .weibei-highlight, code .weibei-comment, code .weibei-tag, code .weibei-html-break-source').length,
          inlineCodeSyntaxText: Array.from(document.querySelectorAll('code'))
            .map((node) => node.textContent || '')
            .find((text) => text.includes('[[不是链接]]')) || ''
        }))();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("Obsidian decoration check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("Obsidian decoration check returned \(String(describing: value))")
                return
            }
            if result["writingSuggestionsDisabled"] as? Bool != true {
                self.fail("editor self-check must disable system writing suggestions")
                return
            }
            if result["wikilinkText"] as? String != "理论别名" {
                self.fail("alias wikilink did not display alias")
                return
            }
            if result["inlineFootnoteText"] as? String != "行内脚注内容"
                || (result["inlineFootnotes"] as? Int ?? 0) < 1 {
                self.fail("inline footnote was not decorated")
                return
            }
            for key in ["comments", "tags", "blockIds", "embeds", "sourceReferences", "mermaid"] {
                if (result[key] as? Int ?? 0) < 1 {
                    self.fail("missing Obsidian decoration: \(key)")
                    return
                }
            }
            if !(result["sourceReferenceTitle"] as? String ?? "").hasPrefix("打开来源：") {
                self.fail("source reference title should be localized in Chinese mode")
                return
            }
            if (result["comments"] as? Int ?? 0) < 2 {
                self.fail("block comment was not decorated")
                return
            }
            if result["commentsWeak"] as? Bool != true {
                self.fail("Obsidian comments should be weakly visible, not compete with body text")
                return
            }
            if result["frontmatterTitle"] as? String != "属性" {
                self.fail("frontmatter panel title should follow the current Chinese interface language: \(result["frontmatterTitle"] as? String ?? "__missing__")")
                return
            }
            if (result["hardBreaks"] as? Int ?? 0) < 1 {
                self.fail("HTML break syntax was not normalized into a real editor line break")
                return
            }
            if (result["noteEmbedLinks"] as? Int ?? 0) < 1 {
                self.fail("note embed was not keyboard/click activatable")
                return
            }
            if (result["mermaidSvg"] as? Int ?? 0) < 1 || (result["mermaidPlaceholder"] as? Int ?? 0) > 0 {
                self.fail("Mermaid block did not render to SVG: \(result["mermaidText"] as? String ?? "")")
                return
            }
            if let opacityText = result["mermaidSourceOpacity"] as? String,
               (Double(opacityText) ?? 0) < 0.7 {
                self.fail("Mermaid source block is too faint to edit: \(opacityText)")
                return
            }
            if (result["mathInlinePreview"] as? Int ?? 0) < 1
                || (result["mathBlockPreview"] as? Int ?? 0) < 1 {
                self.fail("valid inline and block formulas must render through their NodeView previews")
                return
            }
            if result["mathSourcesHidden"] as? Bool != true
                || result["mathContainersVisible"] as? Bool != true {
                self.fail("formula sources should be hidden by default while their NodeView containers remain visible")
                return
            }
            if result["foldedCallout"] as? String != "-" {
                self.fail("callout folded marker was not recognized")
                return
            }
            if result["calloutTitle"] as? String != "可编辑标题" {
                self.fail("callout title swallowed body text")
                return
            }
            if result["calloutHeadingVisible"] as? Bool != true {
                self.fail("callout title should stay visible and editable in writing mode")
                return
            }
            if result["calloutSourceMarkerAbsent"] as? Bool != true {
                self.fail("semantic callout should not keep its source marker in the editable document")
                return
            }
            if result["quoteCalloutTitle"] as? String != "选区摘录" {
                self.fail("quote callout title should be kept without exposing the source marker")
                return
            }
            if !(result["quoteCalloutText"] as? String ?? "").contains("利率是资金使用价格的表达。") {
                self.fail("quote callout body text disappeared")
                return
            }
            if (result["quoteCalloutCount"] as? Int ?? 0) < 2 {
                self.fail("nested quote callout was not recognized")
                return
            }
            if (result["visibleRawCalloutMarkers"] as? Int ?? -1) != 0 {
                self.fail("nested callout source markers should not leak as visible text")
                return
            }
            if result["customCalloutType"] as? String != "attention" {
                self.fail("unknown Obsidian callout type was not recognized")
                return
            }
            if result["customCalloutFold"] as? String != "+" {
                self.fail("unknown Obsidian callout fold marker was not preserved")
                return
            }
            if result["customCalloutTitle"] as? String != "自定义标题" {
                self.fail("unknown Obsidian callout title was not preserved")
                return
            }
            if !(result["customCalloutText"] as? String ?? "").contains("自定义 Callout 不应该漏出源标记。") {
                self.fail("unknown Obsidian callout body disappeared")
                return
            }
            if (result["inlineCodeSyntaxDecorations"] as? Int ?? -1) != 0
                || !(result["inlineCodeSyntaxText"] as? String ?? "").contains("[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />") {
                self.fail("inline code should not receive WeiBei Markdown syntax decorations")
                return
            }
            self.validateStructuredMarkdownNodes {
                self.validateStreamingSnapshotIntegrity {
                    self.validateFrontmatterLanguageCycle(completion: completion)
                }
            }
        }
    }

    private func validateStructuredMarkdownNodes(completion: @escaping () -> Void) {
        let editScript = """
        (() => {
          const selectors = [
            '[data-type="wiki_link"]',
            'mark.weibei-highlight',
            '[data-type="inline_footnote"]',
            'blockquote[data-type="callout"]',
            '[data-type="embed"]'
          ];
          const missing = selectors.filter((selector) => !document.querySelector(selector));
          if (missing.length) throw new Error('missing structured nodes: ' + missing.join(', '));
          const wiki = document.querySelector('[data-type="wiki_link"]');
          wiki.click();
          const inputs = wiki.querySelectorAll('.weibei-structured-input');
          if (inputs.length !== 2) throw new Error('wiki link did not open its in-place editor');
          inputs[0].value = '现场理论';
          inputs[1].value = '现场别名';
          document.querySelector('.ProseMirror')?.focus();
          return true;
        })();
        """
        webView.evaluateJavaScript(editScript) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("structured Markdown interaction failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.webView.evaluateJavaScript("Boolean(document.querySelector('[data-type=\"wiki_link\"][data-wikilink-target=\"现场理论\"]'))") { [weak self] value, error in
                    guard let self else { return }
                    guard error == nil, value as? Bool == true else {
                        self.fail("wiki link in-place edit was not committed")
                        return
                    }
                    self.requestSnapshot { [weak self] snapshot in
                        guard let self else { return }
                        guard snapshot.markdown.contains("[[现场理论|现场别名]]")
                                || snapshot.markdown.contains("[[现场理论\\|现场别名]]") else {
                            self.fail("structured Markdown snapshot lost the in-place wiki edit: \(snapshot.markdown.prefix(500))")
                            return
                        }
                        let historyScript = """
                (() => {
                  const count = () => document.querySelectorAll('[data-type="wiki_link"], mark.weibei-highlight, [data-type="inline_footnote"], blockquote[data-type="callout"], [data-type="embed"]').length;
                  window.WeiBeiEditor.pressKeyForCheck('a', { metaKey: true });
                  window.WeiBeiEditor.pressKeyForCheck('Backspace');
                  const deleted = count() === 0;
                  window.WeiBeiEditor.undoForCheck();
                  const undone = count() > 0;
                  window.WeiBeiEditor.redoForCheck();
                  const redone = count() === 0;
                  window.WeiBeiEditor.undoForCheck();
                  return { deleted, undone, redone };
                })();
                """
                        self.webView.evaluateJavaScript(historyScript) { [weak self] value, error in
                            guard let self else { return }
                            guard error == nil,
                                  let result = value as? [String: Any],
                                  result["deleted"] as? Bool == true,
                                  result["undone"] as? Bool == true,
                                  result["redone"] as? Bool == true else {
                                self.fail("structured Markdown delete/undo/redo failed: \(String(describing: error)); \(String(describing: value))")
                                return
                            }
                            self.webView.evaluateJavaScript("window.WeiBeiEditor.setMarkdown(\(json(sampleMarkdown)))") { _, error in
                                guard error == nil else {
                                    self.fail("structured Markdown check could not restore the fixture: \(String(describing: error))")
                                    return
                                }
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Regression: cumulative snapshots must update one ProseMirror document.
    /// Token fragments may not become standalone paragraphs, and settled
    /// leading blocks must keep their DOM identity through completion.
    private func validateStreamingSnapshotIntegrity(completion: @escaping () -> Void) {
        let script = """
        (() => {
          window.WeiBeiEditor.setMarkdown("");
          window.WeiBeiEditor.updateStreamingMarkdown("第一段落完整内容。");
          const root = document.querySelector('.ProseMirror');
          const firstBlock = root?.firstElementChild;
          window.__weiBeiStreamingFirstBlockForCheck = firstBlock;
          window.WeiBeiEditor.updateStreamingMarkdown("第一段落完整内容。\\n\\n第二段带 **加");
          const unfinishedText = root?.textContent || '';
          const hiddenUnfinishedSyntax = Array.from(
            root?.querySelectorAll('[data-weibei-streaming-syntax-hidden="true"]') || []
          ).map((node) => node.textContent || '').join('');
          window.WeiBeiEditor.updateStreamingMarkdown("第一段落完整内容。\\n\\n第二段带 **加粗** 与 $a+b$ 内容。");
          const closedSyntaxStillHidden = Boolean(
            root?.querySelector('[data-weibei-streaming-syntax-hidden="true"]')
          );
          window.WeiBeiEditor.updateStreamingMarkdown("第一段落完整内容。\\n\\n第二段带 **加粗** 与 $a+b$ 内容。\\n\\n- 列表甲");
          window.WeiBeiEditor.updateStreamingMarkdown("第一段落完整内容。\\n\\n第二段带 **加粗** 与 $a+b$ 内容。\\n\\n- 列表甲\\n- 列表乙");
          const finalMarkdown = "第一段落完整内容。\\n\\n第二段带 **加粗** 与 $a+b$ 内容。\\n\\n- 列表甲\\n- 列表乙\\n\\n收尾一段。";
          window.WeiBeiEditor.finishStreamingMarkdown(finalMarkdown);
          const blocks = root ? Array.from(root.children).filter((node) => !node.classList.contains('ProseMirror-trailingBreak') && !node.classList.contains('wb-stream-caret')) : [];
          return JSON.stringify({
            blockCount: blocks.length,
            firstBlockPreserved: firstBlock === root?.firstElementChild,
            unfinishedBodyVisible: unfinishedText.includes('加'),
            hiddenUnfinishedSyntax,
            closedSyntaxStillHidden,
            text: (root?.textContent || '').replace(/\\s+/g, ''),
            markdown: window.WeiBeiEditor.getMarkdown()
          });
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("streaming snapshot check threw \(error.localizedDescription)")
                return
            }
            guard let raw = value as? String,
                  let data = raw.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.fail("streaming snapshot check returned no result")
                return
            }
            let blockCount = result["blockCount"] as? Int ?? -1
            let text = result["text"] as? String ?? ""
            // 3 paragraphs + 1 list = 4 top-level blocks; fragmentation inflates this.
            guard blockCount == 4 else {
                self.fail("streaming snapshots fragmented blocks: expected 4 top-level blocks, got \(blockCount)")
                return
            }
            guard result["firstBlockPreserved"] as? Bool == true else {
                self.fail("streaming snapshots replaced an unchanged leading DOM block")
                return
            }
            guard result["unfinishedBodyVisible"] as? Bool == true,
                  result["hiddenUnfinishedSyntax"] as? String == "**" else {
                self.fail("streaming snapshots hid unfinished body text or exposed its marker: \(result)")
                return
            }
            guard result["closedSyntaxStillHidden"] as? Bool == false else {
                self.fail("streaming snapshots kept hiding a closed emphasis marker")
                return
            }
            guard text.contains("第二段带") else {
                self.fail("streaming snapshots lost content: \(text)")
                return
            }
            guard text.contains("收尾一段。"), text.contains("列表甲"), text.contains("列表乙") else {
                self.fail("streaming snapshots dropped final blocks: \(text)")
                return
            }
            // Completion serialization is asynchronous. Keep the document alive
            // through that callback window before accepting DOM continuity.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.webView.evaluateJavaScript("""
                (() => {
                  const root = document.querySelector('.ProseMirror');
                  const blocks = root ? Array.from(root.children).filter((node) => !node.classList.contains('ProseMirror-trailingBreak') && !node.classList.contains('wb-stream-caret')) : [];
                  const preserved = Boolean(root
                    && window.__weiBeiStreamingFirstBlockForCheck === root.firstElementChild
                    && blocks.length === 4
                    && root.textContent.includes('收尾一段。'));
                  delete window.__weiBeiStreamingFirstBlockForCheck;
                  return preserved;
                })();
                """) { value, error in
                    guard error == nil, value as? Bool == true else {
                        self.fail("streaming completion replaced the document after the serializer callback")
                        return
                    }
                    // Restore the fixture document for the checks that follow.
                    self.webView.evaluateJavaScript("window.WeiBeiEditor.setMarkdown(\(json(sampleMarkdown)))") { _, _ in
                        completion()
                    }
                }
            }
        }
    }

    private func validateFrontmatterLanguageCycle(completion: @escaping () -> Void) {
        let script = """
        (() => {
          const read = () => [
            document.querySelector('.frontmatter-title')?.textContent || '',
            document.querySelector('.weibei-inline-footnote')?.getAttribute('title') || '',
            document.querySelector('.weibei-wikilink')?.getAttribute('title') || '',
            document.querySelector('.weibei-embed-note')?.textContent || '',
            document.querySelector('.weibei-embed-note')?.getAttribute('title') || '',
            document.querySelector('.weibei-source-reference')?.getAttribute('title') || ''
          ].join('::');
          const initial = read();
          window.WeiBeiEditor.setInterfaceLanguage('en');
          const english = read();
          window.WeiBeiEditor.setInterfaceLanguage('zh-Hans');
          const restored = read();
          return [initial, english, restored].join('|');
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("frontmatter language switch check threw \(error.localizedDescription)")
                return
            }
            guard let raw = value as? String else {
                self.fail("frontmatter panel title should refresh when switching interface languages: \(String(describing: value))")
                return
            }
            let phases = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard phases.count == 3,
                  phases[0].hasPrefix("属性::行内脚注："),
                  phases[1].hasPrefix("Properties::Inline footnote:"),
                  phases[1].contains("::Open or create note:"),
                  phases[1].contains("::Embed:"),
                  phases[1].contains("::Open source:"),
                  phases[2].hasPrefix("属性::行内脚注："),
                  phases[2].contains("::嵌入："),
                  phases[2].contains("::打开来源：") else {
                self.fail("web editor chrome labels should refresh when switching interface languages: \(raw)")
                return
            }
            completion()
        }
    }

    private func validateReadOnlyInkstoneDecorations(completion: @escaping () -> Void) {
        let prepare = """
        window.WeiBeiEditor.setTheme('inkstone');
        window.WeiBeiEditor.setEditable(false);
        """
        webView.evaluateJavaScript(prepare) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("read-only inkstone setup threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.inspectReadOnlyInkstone(completion: completion)
            }
        }
    }

    private func inspectReadOnlyInkstone(completion: @escaping () -> Void) {
        let script = """
        (() => {
          const root = document.querySelector('.ProseMirror');
          const quote = document.querySelector('blockquote.weibei-callout-quote');
          const marker = quote?.querySelector('.weibei-callout-marker');
          const heading = quote?.querySelector('.weibei-callout-header');
          const textNodeWalker = document.createTreeWalker(root || document.body, NodeFilter.SHOW_TEXT);
          let visibleBareMarkers = 0;
          let node;
          while ((node = textNodeWalker.nextNode())) {
            if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
            const parent = node.parentElement;
            if (parent?.closest('.weibei-callout-marker')) continue;
            if (!parent?.closest('blockquote.weibei-callout')) continue;
            const style = getComputedStyle(parent);
            const visible = style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0'
              && style.color !== 'rgba(0, 0, 0, 0)'
              && parseFloat(style.fontSize || '0') > 0;
            if (visible) visibleBareMarkers += 1;
          }
          const headingStyle = heading ? getComputedStyle(heading) : null;
          const sampleText = quote?.querySelector('p:last-child') || quote || root || document.body;
          const sampleColor = getComputedStyle(sampleText).color;
          const folded = document.querySelector('blockquote.weibei-callout[data-callout-fold="-"]');
          const visibleFoldChildren = () => Array.from(folded?.children || []).filter((child) => {
            const style = getComputedStyle(child);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0'
              && child.getBoundingClientRect().height > 0.5;
          }).length;
          const foldedVisibleBefore = visibleFoldChildren();
          folded?.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          const foldedVisibleAfter = visibleFoldChildren();
          return {
            editable: document.body.dataset.editable || '',
            theme: document.documentElement.dataset.weibeiTheme || '',
            markerAbsent: marker === null,
            headingHidden: headingStyle ? headingStyle.display === 'none' : false,
            visibleBareMarkers,
            sampleColor,
            foldedVisibleBefore,
            foldedVisibleAfter
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("read-only inkstone check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("read-only inkstone check returned \(String(describing: value))")
                return
            }
            if result["editable"] as? String != "false" || result["theme"] as? String != "inkstone" {
                self.fail("read-only inkstone state was not applied: \(result)")
                return
            }
            if result["markerAbsent"] as? Bool != true || result["headingHidden"] as? Bool != true {
                self.fail("read-only callout heading or marker leaked: \(result)")
                return
            }
            if (result["visibleBareMarkers"] as? Int ?? -1) != 0 {
                self.fail("read-only callout source marker leaked as visible text")
                return
            }
            if (result["foldedVisibleBefore"] as? Int ?? -1) != 0
                || (result["foldedVisibleAfter"] as? Int ?? 0) < 1 {
                self.fail("read-only folded callout should start collapsed and expand on click: \(result)")
                return
            }
            if (result["sampleColor"] as? String ?? "").contains("255, 255, 255") {
                self.fail("read-only inkstone text fell back to pure white")
                return
            }
            completion()
        }
    }

    private func validateSelectionAskMark(completion: @escaping () -> Void) {
        activatedSelectionAskThreadID = nil
        let threadID = "8a311629-157e-43fd-9256-b9d67803fcff"
        let selectedText = "利率是资金使用价格的表达。"
        let script = """
        (() => {
          if (typeof window.WeiBeiEditor.setSelectionAskMarks !== 'function') {
            throw new Error('selection ask marks are not owned by the editor');
          }
          window.WeiBeiEditor.setSelectionAskMarks([{
            id: \(json(threadID)),
            text: \(json(selectedText))
          }]);
          const mark = document.querySelector('.weibei-selection-ask-mark');
          if (!mark) throw new Error('selection ask mark was not rendered');
          mark.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          return {
            markCount: document.querySelectorAll('.weibei-selection-ask-mark').length,
            editorAlive: !!document.querySelector('.ProseMirror')
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("selection ask mark check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any],
                  (result["markCount"] as? Int ?? 0) >= 1,
                  result["editorAlive"] as? Bool == true else {
                self.fail("selection ask mark damaged the editor: \(String(describing: value))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedSelectionAskThreadID == threadID else {
                    self.fail("selection ask mark did not send its thread identity")
                    return
                }
                guard self.editorFailures == 0 else {
                    self.fail("selection ask mark triggered \(self.editorFailures) editor failure(s)")
                    return
                }
                self.webView.evaluateJavaScript("""
                ({
                  markCount: document.querySelectorAll('.weibei-selection-ask-mark').length,
                  editorAlive: !!document.querySelector('.ProseMirror'),
                  failureText: document.querySelector('.editor-status.error')?.textContent || ''
                })
                """) { value, error in
                    guard error == nil,
                          let final = value as? [String: Any],
                          (final["markCount"] as? Int ?? 0) >= 1,
                          final["editorAlive"] as? Bool == true,
                          (final["failureText"] as? String ?? "").isEmpty else {
                        self.fail("selection ask mark click destabilized the editor: \(String(describing: value)); error=\(String(describing: error))")
                        return
                    }
                    completion()
                }
            }
        }
    }

    private func validateRenderedImageSource(completion: @escaping () -> Void) {
        let script = """
        Array.from(document.querySelectorAll('.ProseMirror img'))
          .map((image) => image.getAttribute('src') || image.src || '')
          .filter((source) => source.startsWith('weibeiimage://image'))
          .join('\\n')
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("image source check threw \(error.localizedDescription)")
                return
            }
            guard let rawSrc = value as? String else {
                self.fail("local markdown image did not use controlled scheme: \(String(describing: value))")
                return
            }
            let sources = rawSrc
                .split(separator: "\n")
                .map(String.init)
            guard sources.count >= 2,
                  sources.allSatisfy({ $0.hasPrefix("weibeiimage://image") }),
                  sources.contains(where: {
                      $0.contains("https%3A%2F%2Fexample.com%2Fweibei.png")
                  }) else {
                self.fail("markdown images did not use controlled scheme: \(rawSrc)")
                return
            }
            completion()
        }
    }

    private func validateWikiLinkActivation() {
        let script = """
        const link = document.querySelector('.weibei-wikilink');
        if (!link) throw new Error('missing wikilink decoration');
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("wikilink click threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论" else {
                    self.fail("wikilink did not send canonical title to native bridge: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateHeadingWikiLinkActivation()
            }
        }
    }

    private func validateHeadingWikiLinkActivation() {
        activatedWikiTitle = nil
        let script = """
        (() => {
        const links = Array.from(document.querySelectorAll('.weibei-wikilink'));
        const link = links.find((node) => node.getAttribute('data-wikilink-target') === '货币理论#利率');
        if (!link) {
          return { ok: false, targets: links.map((node) => node.getAttribute('data-wikilink-target')).join('|') };
        }
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        return { ok: true, targets: links.map((node) => node.getAttribute('data-wikilink-target')).join('|') };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("heading wikilink click threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any], result["ok"] as? Bool == true else {
                self.fail("missing heading wikilink decoration: \((value as? [String: Any])?["targets"] as? String ?? String(describing: value))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论#利率" else {
                    self.fail("heading wikilink did not keep target fragment: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateEmbedWikiLinkActivation()
            }
        }
    }

    private func validateEmbedWikiLinkActivation() {
        activatedWikiTitle = nil
        let script = """
        (() => {
          const embed = document.querySelector('.weibei-embed-note[data-wikilink-target="货币理论#利率"]');
          if (!embed) return false;
          embed.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("note embed click threw \(error.localizedDescription)")
                return
            }
            guard value as? Bool == true else {
                self.fail("missing clickable note embed")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论#利率" else {
                    self.fail("note embed did not keep target fragment: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateReadOnlyImagePaste()
            }
        }
    }

    private func validateReadOnlyImagePaste() {
        let script = """
        window.WeiBeiEditor.setEditable(false);
        const editor = document.querySelector('.ProseMirror');
        const data = new DataTransfer();
        data.items.add(new File([new Uint8Array([1, 2, 3])], 'readonly.png', { type: 'image/png' }));
        const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data });
        editor.dispatchEvent(event);
        window.WeiBeiEditor.setEditable(true);
        event.defaultPrevented;
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("readonly paste check threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.attachmentRequests != 0 {
                    self.fail("readonly image paste should not request attachment save")
                    return
                }
                self.validateEditableMarkdownPaste()
            }
        }
    }

    private func validateEditableMarkdownPaste() {
        let script = """
        (() => {
          window.WeiBeiEditor.setMarkdown('![旧图](https://example.com/old.png)\\n\\n旧正文');
          window.WeiBeiEditor.pressKeyForCheck('a', { metaKey: true });
          window.WeiBeiEditor.pressKeyForCheck('Backspace');
          const clearedMarkdown = window.WeiBeiEditor.getMarkdown();
          const clearedImages = document.querySelectorAll('.ProseMirror img.weibei-image').length;
          const data = new DataTransfer();
          data.setData('text/plain', '# 图片安全验收\\n\\n![公网图](https://example.com/public.png)\\n\\n![本机图](https://127.0.0.1:9/private.png)');
          const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data });
          document.querySelector('.ProseMirror')?.dispatchEvent(event);
          const markdown = window.WeiBeiEditor.getMarkdown();
          const text = document.querySelector('.ProseMirror')?.textContent || '';
          return {
            oldCleared: clearedMarkdown === '' && clearedImages === 0,
            heading: document.querySelectorAll('.ProseMirror h1').length,
            images: document.querySelectorAll('.ProseMirror img.weibei-image').length,
            markdown,
            text
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("editable Markdown paste check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any],
                  result["oldCleared"] as? Bool == true,
                  result["heading"] as? Int == 1,
                  result["images"] as? Int == 2,
                  let markdown = result["markdown"] as? String,
                  let text = result["text"] as? String,
                  markdown.contains("# 图片安全验收"),
                  markdown.contains("https://example.com/public.png"),
                  markdown.contains("https://127.0.0.1:9/private.png"),
                  !markdown.contains("旧正文"),
                  !markdown.contains("old.png"),
                  !text.contains("![") else {
                self.fail("editable Markdown paste did not replace and parse the document: \(String(describing: value))")
                return
            }
            self.validateRichClipboardPaste()
        }
    }

    /// Chat windows and browsers put text/html next to text/plain on the clipboard; the
    /// Markdown source in text/plain must still parse into math/bold nodes on paste.
    /// Phase 1 clears the document, phase 2 (past prosemirror-history's 500ms grouping
    /// window, so undo reverts the paste alone) pastes and asserts.
    private func validateRichClipboardPaste() {
        webView.evaluateJavaScript("window.WeiBeiEditor.setMarkdown('')") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("rich clipboard paste could not clear baseline: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.runRichClipboardPasteAssertion()
            }
        }
    }

    private func runRichClipboardPasteAssertion() {
        let script = """
        (() => {
          const data = new DataTransfer();
          data.setData('text/plain', '公式 $\\\\mathcal{F}(x)$ 与 \\\\(x^2\\\\) 加 **粗体**,价格 $100');
          data.setData('text/html', '<div>公式与粗体与价格</div>');
          const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data });
          const beforePaste = window.WeiBeiEditor.getMarkdown();
          document.querySelector('.ProseMirror')?.dispatchEvent(event);
          const markdown = window.WeiBeiEditor.getMarkdown();
          const text = document.querySelector('.ProseMirror')?.textContent || '';
          const mathNodes = document.querySelectorAll('.ProseMirror [data-type="math_inline"]').length;
          const strongNodes = document.querySelectorAll('.ProseMirror strong').length;
          window.WeiBeiEditor.undoForCheck();
          const afterUndo = window.WeiBeiEditor.getMarkdown();
          return {
            mathNodes,
            strongNodes,
            boldRendered: text.includes('粗体') && !text.includes('**'),
            mathConverted: markdown.includes('x^2') && !markdown.includes('\\\\(x^2\\\\)'),
            currencyKept: markdown.includes('$100') || markdown.includes('\\\\$100'),
            undoRestoresBaseline: afterUndo === beforePaste
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("rich clipboard paste check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any],
                  result["mathNodes"] as? Int == 2,
                  result["strongNodes"] as? Int == 1,
                  result["boldRendered"] as? Bool == true,
                  result["mathConverted"] as? Bool == true,
                  result["currencyKept"] as? Bool == true,
                  result["undoRestoresBaseline"] as? Bool == true else {
                self.fail("rich clipboard paste did not parse Markdown source: \(String(describing: value))")
                return
            }
            self.validateTSVTablePaste()
        }
    }

    private func validateTSVTablePaste() {
        let script = """
        (() => {
          const editor = window.WeiBeiEditor;
          const paste = (text) => {
            const data = new DataTransfer();
            data.setData('text/plain', text);
            return document.querySelector('.ProseMirror')?.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data }));
          };

          editor.setDocumentID('table-tsv');
          editor.setMarkdown('替换我');
          const outsideBefore = editor.getMarkdown();
          editor.selectFirstTextForCheck('替换我');
          paste('A\\tB\\n1\\t2');
          const outsideMarkdown = editor.getMarkdown();
          const outsideRows = document.querySelectorAll('.ProseMirror table tr').length;
          editor.undoForCheck();
          const outsideUndo = editor.getMarkdown() === outsideBefore;
          editor.setMarkdown(outsideMarkdown);
          const outsideReload = document.querySelectorAll('.ProseMirror table tr').length === 2;

          editor.setMarkdown('| H1 | H2 |\\n| --- | --- |\\n| a | b |');
          const insideBefore = editor.getMarkdown();
          editor.selectFirstTextForCheck('a');
          paste('甲\\t乙\\t丙\\n丁\\t戊\\t己');
          const insideMarkdown = editor.getMarkdown();
          const rows = Array.from(document.querySelectorAll('.ProseMirror table tr')).map((row) => Array.from(row.querySelectorAll('th,td')).map((cell) => cell.textContent));
          editor.undoForCheck();
          const insideUndo = editor.getMarkdown() === insideBefore;
          editor.setMarkdown(insideMarkdown);
          editor.selectFirstTextForCheck('甲');
          const reloadRows = document.querySelectorAll('.ProseMirror table tr').length;
          const reloadColumns = document.querySelector('.ProseMirror table tr')?.querySelectorAll('th,td').length || 0;
          document.querySelector('.weibei-table-toolbar button[data-action="deleteTable"]')?.click();
          return {
            outsideRows,
            outsideUndo,
            outsideReload,
            insideRows: rows.length,
            insideColumns: rows[0]?.length || 0,
            values: rows.slice(1).flat().join(','),
            insideUndo,
            reloadRows,
            reloadColumns,
            deleted: !document.querySelector('.ProseMirror table')
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["outsideRows"] as? Int == 2,
                  result["outsideUndo"] as? Bool == true,
                  result["outsideReload"] as? Bool == true,
                  result["insideRows"] as? Int == 3,
                  result["insideColumns"] as? Int == 3,
                  result["values"] as? String == "甲,乙,丙,丁,戊,己",
                  result["insideUndo"] as? Bool == true,
                  result["reloadRows"] as? Int == 3,
                  result["reloadColumns"] as? Int == 3,
                  result["deleted"] as? Bool == true else {
                self.fail("TSV table paste, undo, reload, or delete check failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            self.webView.evaluateJavaScript("window.WeiBeiEditor.setMarkdown(\(json(sampleMarkdown)))") { _, error in
                if let error {
                    self.fail("table paste check could not restore fixture: \(error.localizedDescription)")
                    return
                }
                self.validateSelectionReplacement()
            }
        }
    }

    private func validateSelectionReplacement() {
        replaceFirst("可追问", with: "已改写") { [weak self] in
            guard let self else { return }
            self.replaceFirst("温和洞察", with: "Agent 洞察") { [weak self] in
                guard let self else { return }
                self.requestSnapshot { markdownSnapshot in
                    let markdown = markdownSnapshot.markdown
                    let tableReplaced = markdown.contains("| Agent | 已改写 |")
                        || (markdown.contains("| Agent") && markdown.contains("已改写"))
                    if !tableReplaced {
                        self.fail("table selection replacement was not serialized back to markdown")
                        return
                    }
                    if !markdown.contains("> [!note]- 可编辑标题") || !markdown.contains("Agent 洞察") {
                        self.fail("callout selection replacement was not serialized back to markdown")
                        return
                    }
                    self.validateAgentPatch()
                }
            }
        }
    }

    private func replaceFirst(_ needle: String, with replacement: String, completion: @escaping () -> Void) {
        let script = """
        if (!window.WeiBeiEditor.selectFirstTextForCheck(\(json(needle)))) {
          throw new Error("missing selection target: \(needle)");
        }
        window.WeiBeiEditor.replaceSelection(\(json(replacement)));
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.fail("replaceSelection threw \(error.localizedDescription)")
                return
            }
            completion()
        }
    }

    private func validateAgentPatch() {
        let patch = "\n## Agent 整理建议\n补充一条可写回的整理建议。"
        webView.evaluateJavaScript("window.WeiBeiEditor.applyAgentPatch(\(json(patch)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("applyAgentPatch threw \(error.localizedDescription)")
                return
            }
            self.requestSnapshot { markdownSnapshot in
                let markdown = markdownSnapshot.markdown
                if !markdown.contains("Agent 整理建议") || !markdown.contains("补充一条可写回的整理建议") {
                    self.fail("Agent patch was not serialized back to markdown")
                    return
                }
                self.validateCommandInsertion()
            }
        }
    }

    private func validateCommandInsertion() {
        let snippet = "\n$$\n\\frac{x}{y}\n$$\n"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("insertMarkdown command threw \(error.localizedDescription)")
                return
            }
            self.requestSnapshot { markdownSnapshot in
                let markdown = markdownSnapshot.markdown
                if !markdown.contains("\\frac{x}{y}") || !markdown.contains("$$") {
                    self.fail("insertMarkdown command did not serialize block math correctly")
                    return
                }
                self.validateCursorMarkerInsertion()
            }
        }
    }

    private func validateCursorMarkerInsertion() {
        let snippet = "\n> [!note] 标题\n>\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}\n"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("insertMarkdown cursor marker command threw \(error.localizedDescription)")
                return
            }
            let script = """
            (() => ({
              markdown: window.WeiBeiEditor.getMarkdown(),
              selectedText: window.WeiBeiEditor.selectedTextForCheck()
            }))()
            """
            self.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after cursor marker insert threw \(error.localizedDescription)")
                    return
                }
                guard let result = value as? [String: Any],
                      let markdown = result["markdown"] as? String,
                      let selectedText = result["selectedText"] as? String else {
                    self.fail("cursor marker inserted markdown did not return text")
                    return
                }
                if markdown.contains("{{WEIBEI_CURSOR}}")
                    || markdown.contains("{{WEIBEI_SELECT_START}}")
                    || markdown.contains("{{WEIBEI_SELECT_END}}") {
                    self.fail("insertMarkdown cursor marker leaked into saved markdown")
                    return
                }
                if !markdown.contains("> [!note] 标题\n>\n> 内容") {
                    self.fail("insertMarkdown cursor marker command did not keep the callout: \(markdown)")
                    return
                }
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines) != "内容" {
                    self.fail("insertMarkdown cursor marker did not select the editable placeholder")
                    return
                }
                self.validateInlineFormulaCursorMarkerInsertion()
            }
        }
    }

    private func validateInlineFormulaCursorMarkerInsertion() {
        let snippet = "${{WEIBEI_SELECT_START}}x_i = \\frac{a}{b}{{WEIBEI_SELECT_END}}$"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("inline formula marker command threw \(error.localizedDescription)")
                return
            }
            let script = """
            (() => ({
              markdown: window.WeiBeiEditor.getMarkdown(),
              selectedText: window.WeiBeiEditor.selectedTextForCheck()
            }))()
            """
            self.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after inline formula marker insert threw \(error.localizedDescription)")
                    return
                }
                guard let result = value as? [String: Any],
                      let markdown = result["markdown"] as? String,
                      let selectedText = result["selectedText"] as? String else {
                    self.fail("inline formula marker inserted markdown did not return text")
                    return
                }
                if markdown.contains("{{WEIBEI_SELECT_START}}")
                    || markdown.contains("{{WEIBEI_SELECT_END}}") {
                    self.fail("inline formula marker leaked into saved markdown")
                    return
                }
                if !markdown.contains("\\frac{a}{b}") || !markdown.contains("$") {
                    self.fail("inline formula marker command did not keep formula markdown: \(markdown)")
                    return
                }
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines) != "x_i = \\frac{a}{b}" {
                    self.fail("inline formula marker did not select the editable formula")
                    return
                }
                self.validateWritingRoundTrips()
            }
        }
    }

    private func validateWritingRoundTrips() {
        let script = """
        (() => {
          const editor = window.WeiBeiEditor;
          editor.setDocumentID('writing-round-trips');
          editor.setMarkdown('上段');
          editor.selectDocumentEndForCheck();
          for (let index = 0; index < 4; index += 1) editor.pressKeyForCheck('Enter');
          editor.typeTextForCheck('下段');
          const paragraphsBefore = document.querySelectorAll('.ProseMirror > p').length;
          const markdown = editor.getMarkdown();
          editor.setMarkdown(markdown);
          const paragraphsAfter = document.querySelectorAll('.ProseMirror > p').length;
          if (paragraphsBefore !== 5 || paragraphsAfter !== paragraphsBefore) {
            throw new Error('blank writing lines changed after snapshot reload: ' + JSON.stringify({ paragraphsBefore, paragraphsAfter, markdown }));
          }

          editor.setMarkdown('公式切换');
          if (!editor.selectFirstTextForCheck('公式切换') || !editor.executeSelectionCommand('inlineMath')) {
            throw new Error('first formula conversion failed');
          }
          if (!editor.executeSelectionCommand('inlineMath') || editor.getMarkdown().trim() !== '公式切换') {
            throw new Error('second formula click did not restore the original text: ' + editor.getMarkdown());
          }
          editor.setMarkdown('甲乙丙');
          if (!editor.selectFirstTextForCheck('乙') || !editor.executeSelectionCommand('font', 'literary')) {
            throw new Error('selected font command failed');
          }
          const selectedFontMarkdown = editor.getMarkdown().trim();
          if (selectedFontMarkdown !== '甲<span data-weibei-font="literary">乙</span>丙') {
            throw new Error('selected font changed the wrong text: ' + selectedFontMarkdown);
          }
          editor.setMarkdown(selectedFontMarkdown);
          if (document.querySelector('.ProseMirror [data-weibei-font="literary"]')?.textContent !== '乙'
              || editor.getMarkdown().trim() !== selectedFontMarkdown) {
            throw new Error('selected font did not survive reload');
          }

          editor.setMarkdown('/songti');
          editor.openSlashMenuForCheck();
          if (!editor.executeSlashCommandForCheck('fontSerif') || !editor.typeTextForCheck('后续')) {
            throw new Error('slash font command failed');
          }
          const slashFontMarkdown = editor.getMarkdown().trim();
          if (slashFontMarkdown !== '<span data-weibei-font="serif">后续</span>') {
            throw new Error('slash font did not apply to following input: ' + slashFontMarkdown);
          }
          editor.setMarkdown(slashFontMarkdown);
          if (document.querySelector('.ProseMirror [data-weibei-font="serif"]')?.textContent !== '后续') {
            throw new Error('slash font did not survive reload');
          }
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("writing round-trip check failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            self.validateMathNodeViews()
        }
    }

    private func validateMathNodeViews() {
        let interactionMarkdown = "行内 $x^2$\n\n$$\ny^2\n$$\n\n坏公式 $\\frac{$"
        let moneyMarkdown = "金额 $5、$10–$20、\\$5，公式 $x^2$。"
        let invalidFormula = "\\frac{"
        let fixedFormula = "\\frac{1}{2}"
        let script = """
        (() => {
          const editor = window.WeiBeiEditor;
          const fail = (message) => { throw new Error(message); };
          const key = (element, name, options = {}) => element.dispatchEvent(new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true, ...options }));
          const sourceHidden = (node) => node.classList.contains('weibei-math-adjacent')
            || getComputedStyle(node.querySelector('.weibei-math-source')).display === 'none';
          const visible = (node) => { const style = getComputedStyle(node); const rect = node.getBoundingClientRect(); return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && rect.width > 0 && rect.height > 0; };

          editor.setDocumentID('math-node-interactions');
          editor.setMarkdown(\(json(interactionMarkdown)));
          let inline = document.querySelector('.weibei-math-inline[data-value="x^2"]');
          let block = document.querySelector('.weibei-math-block[data-value="y^2"]');
          let invalid = Array.from(document.querySelectorAll('.weibei-math-inline')).find((node) => node.dataset.value === \(json(invalidFormula)));
          if (!inline?.querySelector('.weibei-math-preview > .katex') || !block?.querySelector('.weibei-math-preview > .katex-display')) fail('valid inline or block formula preview missing');
          if (![inline, block, invalid].every((node) => node && visible(node) && sourceHidden(node))) fail('formula source was visible by default or its container was hidden');
          if (!invalid?.classList.contains('weibei-math-invalid') || invalid.querySelector('.katex-error') || invalid.querySelector('.weibei-math-preview')?.textContent !== \(json(invalidFormula))) fail('invalid formula did not preserve its original source without katex-error');

          inline.querySelector('.weibei-math-preview').click();
          let input = inline.querySelector('.weibei-math-source');
          if (!inline.classList.contains('weibei-math-editing') || document.activeElement !== input || getComputedStyle(input).display === 'none') fail('click did not open inline formula editing');
          input.value = 'x^3'; input.dispatchEvent(new Event('input', { bubbles: true })); key(input, 'Enter');
          if (!editor.getMarkdown().includes('$x^3$') || inline.classList.contains('weibei-math-editing')) fail('inline Enter did not save the formula');

          key(invalid, 'Enter');
          input = invalid.querySelector('.weibei-math-source');
          if (document.activeElement !== input) fail('Enter did not open formula editing');
          input.value = \(json(fixedFormula)); input.dispatchEvent(new Event('input', { bubbles: true })); key(input, 'Enter');
          if (invalid.classList.contains('weibei-math-invalid') || !invalid.querySelector('.weibei-math-preview > .katex') || !editor.getMarkdown().includes(\(json(fixedFormula)))) fail('correcting an invalid formula did not restore its preview');

          key(block, 'Enter');
          input = block.querySelector('.weibei-math-source');
          input.value = 'y^3'; input.dispatchEvent(new Event('input', { bubbles: true })); key(input, 'Enter', { metaKey: true });
          if (!editor.getMarkdown().includes('y^3') || block.classList.contains('weibei-math-editing')) fail('block Command-Enter did not save the formula');
          block.querySelector('.weibei-math-preview').click(); input = block.querySelector('.weibei-math-source'); input.value = 'y^4'; input.dispatchEvent(new Event('input', { bubbles: true })); input.dispatchEvent(new Event('blur'));
          if (!editor.getMarkdown().includes('y^4')) fail('block blur did not save the formula');
          inline.querySelector('.weibei-math-preview').click(); input = inline.querySelector('.weibei-math-source'); input.value = 'x^4'; input.dispatchEvent(new Event('input', { bubbles: true })); key(input, 'Escape');
          if (!editor.getMarkdown().includes('$x^4$')) fail('Escape did not save the formula');
          const savedFormulas = editor.getMarkdown(); editor.setMarkdown(savedFormulas);
          if (!editor.getMarkdown().includes('$x^4$') || !editor.getMarkdown().includes('y^4') || !document.querySelector('.weibei-math-inline[data-value="x^4"]') || !document.querySelector('.weibei-math-block[data-value="y^4"]')) fail('formula edits did not survive serialization and reload');

          editor.setDocumentID('math-render-scope');
          editor.setMarkdown('first $a^2$ and second $b^2$');
          const formulas = Array.from(document.querySelectorAll('.weibei-math-inline'));
          const untouchedPreview = formulas[1]?.querySelector('.weibei-math-preview');
          const untouchedHTML = untouchedPreview?.innerHTML;
          editor.resetCheckMetrics();
          formulas[0]?.querySelector('.weibei-math-preview')?.click(); input = formulas[0]?.querySelector('.weibei-math-source'); input.value = 'a^3'; input.dispatchEvent(new Event('input', { bubbles: true })); key(input, 'Enter');
          const editedMetrics = editor.getCheckMetrics();
          if (editedMetrics.katexRenders < 1 || formulas[1]?.querySelector('.weibei-math-preview') !== untouchedPreview || untouchedPreview?.innerHTML !== untouchedHTML) fail('editing one formula rerendered an untouched formula');
          editor.setMarkdown('ordinary paragraph without formulas'); editor.resetCheckMetrics(); editor.typeTextForCheck(' plus text');
          if (editor.getCheckMetrics().katexRenders !== 0) fail('ordinary paragraph editing rendered KaTeX');

          editor.setDocumentID('math-money-boundaries'); editor.setMarkdown(\(json(moneyMarkdown)));
          const moneyNodes = Array.from(document.querySelectorAll('.weibei-math-node'));
          if (moneyNodes.length !== 1 || moneyNodes[0].dataset.value !== 'x^2') fail('currency or escaped dollars became formula nodes');

          editor.setDocumentID('math-typed'); editor.setMarkdown(''); editor.insertMarkdown(\(json("\n\n{{WEIBEI_CURSOR}}")));
          if (!editor.typeTextForCheck('$A^*$') || !editor.getMarkdown().includes('$A^*$') || !document.querySelector('.weibei-math-inline[data-value="A^*"]')) fail('typed inline formula did not become a formula node');
          if (!editor.typeTextForCheck('后') || !editor.getMarkdown().includes('$A^*$后')) fail('typing after an inline formula did not continue to its right');

          editor.setDocumentID('math-slash-inline'); editor.setMarkdown('/'); editor.openSlashMenuForCheck(); editor.executeSlashCommandForCheck('inlineMath');
          if (!document.querySelector('.weibei-math-inline[data-value="x"]') || !editor.getMarkdown().includes('$x$')) fail('Slash inline formula command did not insert a formula');
          editor.setDocumentID('math-slash-block'); editor.setMarkdown('/'); editor.openSlashMenuForCheck(); editor.executeSlashCommandForCheck('blockMath');
          if (!document.querySelector('.weibei-math-block[data-value="x"]') || !editor.getMarkdown().includes('$$')) fail('Slash block formula command did not insert a formula');
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("formula NodeView interaction check failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            self.validateWritingExperience()
        }
    }

    private func validateWritingExperience() {
        let script = """
        (() => {
          const editor = window.WeiBeiEditor;
          editor.setDocumentID('writing-experience');
          editor.setMarkdown('删除线目标 链接目标');
          editor.selectFirstTextForCheck('删除线目标');
          const strike = editor.executeSelectionCommand('strike')
            && editor.getMarkdown().includes('~~删除线目标~~');
          editor.selectFirstTextForCheck('链接目标');
          const linkShortcut = editor.pressKeyForCheck('k', { metaKey: true });
          return { strike, linkShortcut };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["strike"] as? Bool == true,
                  result["linkShortcut"] as? Bool == true,
                  self.linkEditorRequests == 1 else {
                self.fail("writing experience check failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            self.validateWorkPackageEStructures()
        }
    }

    private func validateWorkPackageEStructures() {
        let ordinaryMarkdown = "ordinary alpha\n\nordinary beta"
        let imageMarkdown = "![failed alt](missing.png)\n\n![success alt](data:image/svg+xml;base64,PHN2Zy8+)"
        let mermaidMarkdown = "```mermaid\ngraph TD\nA --> B\n```\n\nafter"
        let script = """
        (() => {
          const editor = window.WeiBeiEditor;
          editor.setDocumentID('work-package-e-metrics');
          editor.setMarkdown(\(json(ordinaryMarkdown)));
          editor.resetCheckMetrics();
          for (let index = 0; index < 10; index += 1) {
            if (!editor.selectFirstTextForCheck('ordinary') || !editor.selectDocumentEndForCheck()) throw new Error('selection helpers unavailable');
          }
          const selectionMetrics = editor.getCheckMetrics();
          editor.resetCheckMetrics();
          if (!editor.typeTextForCheck('x')) throw new Error('ordinary input helper unavailable');
          const inputMetrics = editor.getCheckMetrics();

          editor.setDocumentID('work-package-e-images');
          editor.setMarkdown(\(json(imageMarkdown)));
          const failed = document.querySelector('img[alt="failed alt"]');
          const success = document.querySelector('img[alt="success alt"]');
          if (!failed || !success) throw new Error('image NodeViews missing');
          const failedIdentity = { node: failed, src: failed.getAttribute('src'), alt: failed.alt };
          const successIdentity = { node: success, src: success.getAttribute('src'), alt: success.alt };
          failed.dispatchEvent(new Event('error'));
          success.dispatchEvent(new Event('load'));
          const select = (node) => {
            const rect = node.getBoundingClientRect();
            const options = { bubbles: true, cancelable: true, button: 0, clientX: rect.left + Math.max(1, rect.width / 2), clientY: rect.top + Math.max(1, rect.height / 2) };
            node.dispatchEvent(new MouseEvent('mousedown', options));
            node.dispatchEvent(new MouseEvent('mouseup', options));
            node.dispatchEvent(new MouseEvent('click', options));
            return node.classList.contains('ProseMirror-selectednode');
          };
          const failedSelectable = select(failed);
          const successSelectable = select(success);
          const imagesStable = failed === failedIdentity.node && success === successIdentity.node
            && failed.getAttribute('src') === failedIdentity.src && success.getAttribute('src') === successIdentity.src
            && failed.alt === failedIdentity.alt && success.alt === successIdentity.alt;

          editor.setDocumentID('work-package-e-mermaid');
          editor.setMarkdown(\(json(mermaidMarkdown)));
          document.querySelector('.ProseMirror')?.dispatchEvent(new FocusEvent('focus'));
          if (!editor.selectFirstCodeBlockEndForCheck()) throw new Error('Mermaid selection helper unavailable');
          window.WeiBeiMermaidPreviewForE = document.querySelector('.weibei-mermaid-render');
          window.WeiBeiMermaidHTMLForE = window.WeiBeiMermaidPreviewForE?.innerHTML || '';
          editor.resetCheckMetrics();
          if (!editor.typeTextForCheck('x')) throw new Error('Mermaid typing helper unavailable');
          window.WeiBeiMermaidBeforeForE = new Promise((resolve) => window.setTimeout(() => resolve({
            sameDOM: document.querySelector('.weibei-mermaid-render') === window.WeiBeiMermaidPreviewForE,
            sameHTML: window.WeiBeiMermaidPreviewForE?.innerHTML === window.WeiBeiMermaidHTMLForE,
            renders: window.WeiBeiEditor.getCheckMetrics().mermaidRenders
          }), 150));
          return {
            selectionDecorationNodes: selectionMetrics.decorationNodes,
            inputImageScans: inputMetrics.imageScans,
            inputCodeTokenizations: inputMetrics.codeTokenizations,
            inputKatexRenders: inputMetrics.katexRenders,
            inputMermaidRenders: inputMetrics.mermaidRenders,
            imagesStable,
            failedSelectable,
            successSelectable,
            mermaidPreviewExists: Boolean(window.WeiBeiMermaidPreviewForE),
            mermaidDOMReused: document.querySelector('.weibei-mermaid-render') === window.WeiBeiMermaidPreviewForE
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["selectionDecorationNodes"] as? Int == 0,
                  result["inputImageScans"] as? Int == 0,
                  result["inputCodeTokenizations"] as? Int == 0,
                  result["inputKatexRenders"] as? Int == 0,
                  result["inputMermaidRenders"] as? Int == 0,
                  result["imagesStable"] as? Bool == true,
                  result["failedSelectable"] as? Bool == true,
                  result["successSelectable"] as? Bool == true,
                  result["mermaidPreviewExists"] as? Bool == true,
                  result["mermaidDOMReused"] as? Bool == true else {
                self.fail("work package E structural metrics or image identity failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.validateMermaidDebounceBeforeDeadline()
            }
        }
    }

    private func validateMermaidDebounceBeforeDeadline() {
        webView.callAsyncJavaScript(
            "return await window.WeiBeiMermaidBeforeForE;",
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            guard case let .success(value) = result,
                  let snapshot = value as? [String: Any],
                  snapshot["sameDOM"] as? Bool == true,
                  snapshot["sameHTML"] as? Bool == true,
                  snapshot["renders"] as? Int == 0 else {
                self.fail("focused Mermaid preview updated before its 300ms debounce: \(String(describing: result))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.validateMermaidDebounceAfterDeadline()
            }
        }
    }

    private func validateMermaidDebounceAfterDeadline() {
        webView.evaluateJavaScript("""
        ({
          sameDOM: document.querySelector('.weibei-mermaid-render') === window.WeiBeiMermaidPreviewForE,
          changedHTML: window.WeiBeiMermaidPreviewForE?.innerHTML !== window.WeiBeiMermaidHTMLForE,
          renders: window.WeiBeiEditor.getCheckMetrics().mermaidRenders
        })
        """) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["sameDOM"] as? Bool == true,
                  result["changedHTML"] as? Bool == true,
                  (result["renders"] as? Int ?? 0) >= 1 else {
                self.fail("focused Mermaid preview did not update in place after its 300ms debounce: \(String(describing: value))")
                return
            }
            self.validateOutlineInitialEvent()
        }
    }

    private func validateOutlineInitialEvent() {
        let documentID = "work-package-e-outline"
        outlineEvents.removeAll { $0.documentID == documentID }
        webView.evaluateJavaScript("""
        window.WeiBeiEditor.setDocumentID(\(json(documentID)));
        window.WeiBeiEditor.setMarkdown('# Alpha\\n\\nbody');
        """) { [weak self] _, error in
            guard let self else { return }
            guard error == nil else {
                self.fail("outline initial document failed: \(String(describing: error))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let events = self.outlineEvents.filter { $0.documentID == documentID }
                guard events.count == 1,
                      let item = events[0].items.first,
                      events[0].items.count == 1,
                      item["title"] as? String == "Alpha",
                      item["level"] as? Int == 1,
                      item["index"] as? Int == 0 else {
                    self.fail("outline initial event was not emitted exactly once with the right payload: \(events)")
                    return
                }
                self.validateOutlineBodyChange(documentID: documentID)
            }
        }
    }

    private func validateOutlineBodyChange(documentID: String) {
        outlineEvents.removeAll { $0.documentID == documentID }
        webView.evaluateJavaScript("""
        if (!window.WeiBeiEditor.selectFirstTextForCheck('body') || !window.WeiBeiEditor.typeTextForCheck('!')) {
          throw new Error('outline body edit helper unavailable');
        }
        """) { [weak self] _, error in
            guard let self else { return }
            guard error == nil else {
                self.fail("outline ordinary body change failed: \(String(describing: error))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let events = self.outlineEvents.filter { $0.documentID == documentID }
                guard events.isEmpty else {
                    self.fail("ordinary body change emitted outlineChanged: \(events)")
                    return
                }
                self.validateOutlineTitleChange(documentID: documentID)
            }
        }
    }

    private func validateOutlineTitleChange(documentID: String) {
        outlineEvents.removeAll { $0.documentID == documentID }
        webView.evaluateJavaScript("""
        if (!window.WeiBeiEditor.selectFirstTextForCheck('Alpha')) throw new Error('missing outline heading');
        window.WeiBeiEditor.replaceSelection('Beta');
        """) { [weak self] _, error in
            guard let self else { return }
            guard error == nil else {
                self.fail("outline title change failed: \(String(describing: error))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let events = self.outlineEvents.filter { $0.documentID == documentID }
                guard events.count == 1,
                      events[0].items.count == 1,
                      events[0].items[0]["title"] as? String == "Beta",
                      events[0].items[0]["level"] as? Int == 1 else {
                    self.fail("heading text change did not emit one accurate outline payload: \(events)")
                    return
                }
                self.validateOutlineLevelChange(documentID: documentID)
            }
        }
    }

    private func validateOutlineLevelChange(documentID: String) {
        outlineEvents.removeAll { $0.documentID == documentID }
        webView.evaluateJavaScript("window.WeiBeiEditor.setMarkdown('## Beta\\n\\nbody!')") { [weak self] _, error in
            guard let self else { return }
            guard error == nil else {
                self.fail("outline level change failed: \(String(describing: error))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let events = self.outlineEvents.filter { $0.documentID == documentID }
                guard events.count == 1,
                      events[0].items.count == 1,
                      events[0].items[0]["title"] as? String == "Beta",
                      events[0].items[0]["level"] as? Int == 2 else {
                    self.fail("heading level change did not emit one accurate outline payload: \(events)")
                    return
                }
                self.validateTypedHtmlBreak()
            }
        }
    }

    private func validateTypedHtmlBreak() {
        let script = """
        window.WeiBeiEditor.insertMarkdown("\\n\\n{{WEIBEI_CURSOR}}");
        if (!window.WeiBeiEditor.typeTextForCheck('手动换行第一行<br />第二行')) {
          throw new Error('typeTextForCheck unavailable');
        }
        window.WeiBeiEditor.getMarkdown();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed HTML break check threw \(error.localizedDescription)")
                return
            }
            guard let markdown = value as? String else {
                self.fail("typed HTML break check did not return markdown")
                return
            }
            guard let range = markdown.range(of: "手动换行第一行") else {
                self.fail("typed HTML break text did not serialize")
                return
            }
            let suffix = String(markdown[range.upperBound...])
            if !suffix.hasPrefix("  \n第二行")
                && !suffix.hasPrefix("  \n> 第二行")
                && !suffix.hasPrefix("\\\n第二行")
                && !suffix.hasPrefix("\\\n> 第二行")
                && !suffix.hasPrefix("\n第二行")
                && !suffix.hasPrefix("\n> 第二行") {
                self.fail("typed HTML break did not become a Markdown hard break: \(markdown)")
                return
            }
            if markdown.contains("手动换行第一行<br") {
                self.fail("typed HTML break leaked raw HTML syntax into saved markdown")
                return
            }
            self.validateTypedMarkdownShortcuts()
        }
    }

    private func validateTypedMarkdownShortcuts() {
        let script = """
        (() => {
        const cases = [
          ['## 现场标题', 'h2', '## 现场标题', '现场标题'],
          ['- 现场条目', 'li', '现场条目', '现场条目'],
          ['- [ ] 现场待办', 'li[data-item-type="task"], li', '现场待办', '现场待办'],
          ['**现场加粗**', 'strong', '**现场加粗**', '现场加粗'],
          ['~~现场删除~~', 's, del', '~~现场删除~~', '现场删除'],
          ['==现场高亮==', '.weibei-highlight', '==现场高亮==', '现场高亮'],
          ['[[现场概念|显示名]]', '.weibei-wikilink[data-wikilink-target="现场概念"]', '[[现场概念|显示名]]', '显示名']
        ];
        for (const [typed, selector, expectedMarkdown, visibleText] of cases) {
          window.WeiBeiEditor.setMarkdown('# 输入语法验收\\n');
          window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
          if (!window.WeiBeiEditor.typeTextForCheck(typed)) {
            return { ok: false, reason: 'typeTextForCheck unavailable for ' + typed };
          }
          const markdown = window.WeiBeiEditor.getMarkdown();
          const node = document.querySelector(selector);
          if (!markdown.includes(expectedMarkdown) || !node || !node.textContent.includes(visibleText)) {
            return { ok: false, reason: 'typed Markdown shortcut did not render in place: ' + typed, markdown, html: document.querySelector('.ProseMirror')?.innerHTML || '' };
          }
        }
        return { ok: true, markdown: window.WeiBeiEditor.getMarkdown() };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed Markdown shortcut check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("typed Markdown shortcut check did not return result")
                return
            }
            if result["ok"] as? Bool != true {
                self.fail("typed Markdown shortcut check failed: \(result)")
                return
            }
            guard let markdown = result["markdown"] as? String, markdown.contains("[[现场概念|显示名]]") else {
                self.fail("typed Markdown shortcut check did not finish: \(result)")
                return
            }
            self.validateBlockEnterExit()
        }
    }

    private func validateBlockEnterExit() {
        let script = """
        (() => {
        try {
        const cases = [
          ['\\n\\n- 项目{{WEIBEI_CURSOR}}', '退出无序列表', ['- 项目', '* 项目', '+ 项目'], '\\n\\n退出无序列表'],
          ['\\n\\n- \u{200B}{{WEIBEI_CURSOR}}', '退出视觉空白无序列表', [], '\\n\\n退出视觉空白无序列表'],
          ['\\n\\n1. 项目{{WEIBEI_CURSOR}}', '退出有序列表', ['1. 项目'], '\\n\\n退出有序列表'],
          ['\\n\\n- [ ] 待办{{WEIBEI_CURSOR}}', '退出任务列表', ['- [ ] 待办', '* [ ] 待办', '+ [ ] 待办'], '\\n\\n退出任务列表'],
          ['\\n\\n> 引用{{WEIBEI_CURSOR}}', '退出引用', ['> 引用'], '\\n\\n退出引用'],
          ['\\n\\n> [!note] 标题\\n>\\n> 内容{{WEIBEI_CURSOR}}', '退出 Callout', ['> 内容'], '\\n\\n退出 Callout']
        ];
        for (const [markdown, text, expectedBeforeOptions, expectedAfter] of cases) {
          window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
          window.WeiBeiEditor.insertMarkdown(markdown);
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for first Enter');
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for second Enter');
          }
          if (!window.WeiBeiEditor.typeTextForCheck(text)) {
            throw new Error('typeTextForCheck unavailable after list exit');
          }
          const current = window.WeiBeiEditor.getMarkdown();
          if ((expectedBeforeOptions.length > 0 && !expectedBeforeOptions.some((expectedBefore) => current.includes(expectedBefore))) || !current.includes(expectedAfter)) {
            throw new Error('empty block Enter did not create a normal paragraph after the block: ' + text + '\\n' + current);
          }
          if (current.includes('\\u200B')) {
            throw new Error('empty block Enter left invisible list placeholder in markdown: ' + text + '\\n' + current);
          }
          if (current.includes('\\n- ' + text)
              || current.includes('\\n* ' + text)
              || current.includes('\\n+ ' + text)
              || current.includes('\\n1. ' + text)
              || current.includes('\\n2. ' + text)
              || current.includes('\\n- [ ] ' + text)
              || current.includes('\\n> ' + text)) {
            throw new Error('empty block Enter kept following text in the block: ' + text + '\\n' + current);
          }
        }
        const typedListCases = [
          ['- 手写项目', '手写退出无序列表', ['- 手写项目', '* 手写项目', '+ 手写项目'], ['\\n- 手写退出无序列表', '\\n* 手写退出无序列表', '\\n+ 手写退出无序列表']],
          ['1. 手写项目', '手写退出有序列表', ['1. 手写项目'], ['\\n1. 手写退出有序列表', '\\n2. 手写退出有序列表']],
          ['- [ ] 手写待办', '手写退出任务列表', ['- [ ] 手写待办', '* [ ] 手写待办', '+ [ ] 手写待办'], ['\\n- [ ] 手写退出任务列表', '\\n* [ ] 手写退出任务列表', '\\n+ [ ] 手写退出任务列表']]
        ];
        for (const [typed, after, expectedMarkers, forbiddenMarkers] of typedListCases) {
          window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
          window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
          if (!window.WeiBeiEditor.typeTextForCheck(typed)) {
            throw new Error('typeTextForCheck unavailable for typed list: ' + typed);
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for typed list first Enter: ' + typed);
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for typed list second Enter: ' + typed);
          }
          if (!window.WeiBeiEditor.typeTextForCheck(after)) {
            throw new Error('typeTextForCheck unavailable after typed list exit: ' + typed);
          }
          const typedMarkdown = window.WeiBeiEditor.getMarkdown();
          if (!expectedMarkers.some((marker) => typedMarkdown.includes(marker))
              || !typedMarkdown.includes('\\n\\n' + after)
              || forbiddenMarkers.some((marker) => typedMarkdown.includes(marker))) {
            throw new Error('typed list Enter did not exit to a normal paragraph: ' + typed + '\\n' + typedMarkdown);
          }
          if (Array.from(document.querySelectorAll('.ProseMirror li')).some((item) => item.textContent.includes(after))) {
            throw new Error('typed list exit kept following text inside a list item: ' + typed + '\\n' + document.querySelector('.ProseMirror')?.innerHTML);
          }
        }
        window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
        window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
        if (!window.WeiBeiEditor.typeTextForCheck('- ')) {
          throw new Error('typeTextForCheck unavailable for empty bullet shortcut');
        }
        if (!document.querySelector('.ProseMirror li')) {
          throw new Error('empty bullet shortcut did not create a real list item');
        }
        if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
          throw new Error('pressKeyForCheck unavailable for empty bullet exit');
        }
        if (!window.WeiBeiEditor.typeTextForCheck('空项目退出列表')) {
          throw new Error('typeTextForCheck unavailable after empty bullet exit');
        }
        const emptyShortcutMarkdown = window.WeiBeiEditor.getMarkdown();
        if (!emptyShortcutMarkdown.includes('\\n\\n空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n- 空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n* 空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n+ 空项目退出列表')
            || Array.from(document.querySelectorAll('.ProseMirror li')).some((item) => item.textContent.includes('空项目退出列表'))) {
          throw new Error('empty bullet shortcut Enter did not exit to a normal paragraph\\n' + emptyShortcutMarkdown + '\\n' + document.querySelector('.ProseMirror')?.innerHTML);
        }
        return { ok: true, markdown: window.WeiBeiEditor.getMarkdown() };
        } catch (error) {
          return { ok: false, reason: String(error?.message || error), stack: String(error?.stack || '') };
        }
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("list Enter exit check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("list Enter exit check did not return result")
                return
            }
            if let ok = result["ok"] as? Bool, ok == false {
                self.fail("list Enter exit check failed: \(result)")
                return
            }
            guard let markdown = result["markdown"] as? String else {
                self.fail("list Enter exit check did not return markdown: \(result)")
                return
            }
            if !markdown.contains("空项目退出列表") {
                self.fail("block Enter exit check did not finish all isolated cases: \(markdown)")
                return
            }
            self.validateSlashCommands()
        }
    }

    private func validateSlashCommands() {
        let triggerScript = """
        window.WeiBeiEditor.setMarkdown('');
        window.WeiBeiEditor.insertMarkdown('{{WEIBEI_CURSOR}}');
        window.WeiBeiEditor.typeTextForCheck('/');
        """
        webView.evaluateJavaScript(triggerScript) { [weak self] _, error in
            guard let self else { return }
            guard error == nil else { self.fail("automatic slash trigger setup failed: \(error!.localizedDescription)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.validateAutomaticSlashMenu()
            }
        }
    }

    private func validateAutomaticSlashMenu() {
        let script = """
        (() => {
          const menu = document.querySelector('.weibei-slash-menu');
          const rect = menu?.getBoundingClientRect();
          const readGlassMenu = (theme) => {
            window.WeiBeiEditor.setTheme(theme);
            const style = menu && getComputedStyle(menu);
            const active = menu?.querySelector('.weibei-slash-command.is-active > .weibei-slash-command-button');
            const activeStyle = active && getComputedStyle(active);
            const backgroundValues = ((style?.backgroundColor || '').match(/[0-9.]+/g) || []).map(Number);
            return {
              dataset: document.documentElement.dataset.weibeiGlass === theme,
              translucent: backgroundValues.length === 4 && backgroundValues[3] > 0 && backgroundValues[3] < 1,
              blur: (style?.backdropFilter || style?.webkitBackdropFilter || '').includes('10px'),
              ink: style?.color || '',
              accent: activeStyle?.color || '',
              shadow: style?.boxShadow || '',
              surface: backgroundValues
            };
          };
          const dark = readGlassMenu('glassDark');
          const light = readGlassMenu('glassLight');
          const mist = readGlassMenu('glassMist');
          const slate = readGlassMenu('glassSlate');
          const surfaceMatches = (values, red, green, blue, alpha) =>
            values.length === 4 && values[0] === red && values[1] === green && values[2] === blue && Math.abs(values[3] - alpha) < 0.001;
          const glassResult = {
            show: menu?.dataset.show === 'true',
            position: menu ? getComputedStyle(menu).position : '',
            visible: !!rect && rect.width > 0 && rect.height > 0 && rect.left >= 0 && rect.top >= 0 && rect.right <= innerWidth && rect.bottom <= innerHeight,
            darkTheme: dark.dataset,
            lightTheme: light.dataset,
            mistTheme: mist.dataset,
            slateTheme: slate.dataset,
            darkPalette: dark.ink === 'rgb(232, 239, 249)' && dark.accent === 'rgb(235, 87, 70)',
            lightPalette: light.ink === 'rgb(23, 29, 38)' && light.accent === 'rgb(156, 40, 29)',
            mistPalette: mist.ink === 'rgb(37, 35, 31)' && mist.accent === 'rgb(138, 47, 36)'
              && surfaceMatches(mist.surface, 244, 249, 255, .72),
            slatePalette: slate.ink === 'rgb(210, 214, 220)' && slate.accent === 'rgb(176, 64, 52)'
              && surfaceMatches(slate.surface, 27, 33, 43, .66),
            glassSurface: dark.translucent && light.translucent && mist.translucent && slate.translucent,
            glassBlur: dark.blur && light.blur && mist.blur && slate.blur,
            distinctShadows: dark.shadow !== light.shadow
          };
          window.WeiBeiEditor.setTheme('paper');
          return glassResult;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let state = value as? [String: Any],
                  state["show"] as? Bool == true,
                  state["position"] as? String == "absolute",
                  state["visible"] as? Bool == true,
                  state["darkTheme"] as? Bool == true,
                  state["lightTheme"] as? Bool == true,
                  state["mistTheme"] as? Bool == true,
                  state["slateTheme"] as? Bool == true,
                  state["darkPalette"] as? Bool == true,
                  state["lightPalette"] as? Bool == true,
                  state["mistPalette"] as? Bool == true,
                  state["slatePalette"] as? Bool == true,
                  state["glassSurface"] as? Bool == true,
                  state["glassBlur"] as? Bool == true,
                  state["distinctShadows"] as? Bool == true else {
                self.fail("automatic slash menu was not visible in the viewport: \(String(describing: error)); \(String(describing: value))")
                return
            }
            self.validateSlashCommandContents()
        }
    }

    private func validateSlashCommandContents() {
        let script = """
        (() => {
          const open = (text) => { window.WeiBeiEditor.setMarkdown(text); return window.WeiBeiEditor.openSlashMenuForCheck(); };
          if (!open('/')) throw new Error('slash menu did not open');
          if (!open('\\u200B/')) throw new Error('slash menu did not open from a blank-line placeholder');
          let state = window.WeiBeiEditor.slashStateForCheck();
          if (state.commands.length !== 24 || state.groups.join('|') !== '结构|列表|内容|丰富内容|字体') throw new Error('slash commands or groups invalid: ' + JSON.stringify(state));
          for (const [query, expected] of [['/h2', '二级标题'], ['/liujibiaoti', '六级标题'], ['/dmk', '代码块'], ['/yxlb', '有序列表'], ['/bijilianjie', '笔记链接'], ['/jiaozhu', '脚注'], ['/代码块', '代码块'], ['/songti', '字体：Songti SC']]) { open(query); state = window.WeiBeiEditor.slashStateForCheck(); if (state.commands.length !== 1 || state.commands[0] !== expected) throw new Error('alias failed: ' + query + JSON.stringify(state)); }
          for (const query of ['/code block', '/ordered list']) { if (open(query)) throw new Error('space alias matched: ' + query); }
          if (!open('前文/h2')) throw new Error('slash menu did not open after existing text');
          window.WeiBeiEditor.executeSlashCommandForCheck('heading2'); window.WeiBeiEditor.typeTextForCheck('标题');
          if (window.WeiBeiEditor.getMarkdown() !== '前文\\n\\n## 标题\\n') throw new Error('slash block command changed surrounding text: ' + JSON.stringify(window.WeiBeiEditor.getMarkdown()));
          open('前文/'); window.WeiBeiEditor.executeSlashCommandForCheck('inlineMath');
          if (window.WeiBeiEditor.getMarkdown() !== '前文$x$\\n') throw new Error('slash inline command changed surrounding text: ' + JSON.stringify(window.WeiBeiEditor.getMarkdown()));
          open('/'); window.WeiBeiEditor.pressKeyForCheck('ArrowDown'); state = window.WeiBeiEditor.slashStateForCheck(); if (state.activeDescendant !== 'weibei-slash-command-heading2' || !state.announcement.includes('二级标题')) throw new Error('accessibility did not update: ' + JSON.stringify(state));
          const menu = document.querySelector('.weibei-slash-menu'); menu.style.maxHeight = '90px'; menu.style.scrollBehavior = 'auto'; open('/'); for (let index = 0; index < 12; index += 1) window.WeiBeiEditor.pressKeyForCheck('ArrowDown'); if (menu.scrollTop <= 0) throw new Error('arrow navigation did not scroll the slash menu'); menu.style.maxHeight = '';
          window.WeiBeiEditor.pressKeyForCheck('Escape'); if (!window.WeiBeiEditor.getMarkdown().includes('/')) throw new Error('escape removed slash text');
          open('/h1'); window.WeiBeiEditor.executeSlashCommandForCheck('heading1'); window.WeiBeiEditor.typeTextForCheck('一级标题'); window.WeiBeiEditor.pressKeyForCheck('Enter'); window.WeiBeiEditor.typeTextForCheck('/h2'); window.WeiBeiEditor.openSlashMenuForCheck(); window.WeiBeiEditor.executeSlashCommandForCheck('heading2'); window.WeiBeiEditor.typeTextForCheck('二级标题'); window.WeiBeiEditor.pressKeyForCheck('Enter'); window.WeiBeiEditor.typeTextForCheck('/'); window.WeiBeiEditor.openSlashMenuForCheck();
          const headingMarkdown = window.WeiBeiEditor.getMarkdown(); const editorSelection = window.WeiBeiEditor.selectionForCheck(); const domSelection = window.getSelection(); const rootSelectionBackground = getComputedStyle(document.querySelector('.ProseMirror'), '::selection').backgroundColor; const selectionSwatch = document.createElement('span'); selectionSwatch.style.color = getComputedStyle(document.documentElement).getPropertyValue('--selection').trim(); document.body.appendChild(selectionSwatch); const expectedSelectionBackground = getComputedStyle(selectionSwatch).color; selectionSwatch.remove();
          if (headingMarkdown !== '# 一级标题\\n\\n## 二级标题\\n\\n/\\n' || editorSelection.from !== editorSelection.to || !domSelection?.isCollapsed || rootSelectionBackground !== expectedSelectionBackground) throw new Error('heading typing or root selection highlight is invalid: ' + JSON.stringify({ headingMarkdown, editorSelection, domSelectionCollapsed: domSelection?.isCollapsed, rootSelectionBackground, expectedSelectionBackground }));
          window.WeiBeiEditor.setDocumentID('slash-table-menu'); open('/table');
          const tableButton = document.querySelector('#weibei-slash-command-table .weibei-slash-command-button');
          if (!tableButton || document.querySelector('.weibei-slash-table-panel')) throw new Error('table submenu opened without an activation');
          tableButton.dispatchEvent(new MouseEvent('pointermove', { bubbles: true })); tableButton.click();
          window.WeiBeiEditor.pressKeyForCheck('ArrowDown'); window.WeiBeiEditor.pressKeyForCheck('Tab'); state = window.WeiBeiEditor.slashStateForCheck();
          if (state.tableOpen || document.querySelector('.weibei-slash-table-panel')) throw new Error('stationary pointer, click, ArrowDown, or Tab opened the table submenu: ' + JSON.stringify(state));
          window.WeiBeiEditor.pressKeyForCheck('ArrowRight'); state = window.WeiBeiEditor.slashStateForCheck();
          let tablePanel = document.querySelector('.weibei-slash-table-panel'); const tableSteppers = Array.from(tablePanel?.querySelectorAll('.weibei-slash-stepper') || []); const menuRect = menu.getBoundingClientRect(); let panelRect = tablePanel?.getBoundingClientRect();
          if (!state.tableOpen || !tablePanel || tableSteppers.length !== 2 || !panelRect) throw new Error('ArrowRight did not open the table submenu');
          if ((state.tableSide === 'right' && panelRect.left < menuRect.right) || (state.tableSide === 'left' && panelRect.right > menuRect.left)) throw new Error('table submenu overlaps its primary menu: ' + JSON.stringify({ side: state.tableSide, menuRect, panelRect }));
          const rowChildren = Array.from(tableSteppers[0].children).map((element) => element.tagName); const rowInput = tableSteppers[0].querySelector('input');
          if (rowChildren.join('|') !== 'SPAN|BUTTON|INPUT|BUTTON' || !rowInput || Math.abs(tableSteppers[0].getBoundingClientRect().width - (tablePanel.clientWidth - 16)) > 1) throw new Error('table dimension row layout invalid: ' + JSON.stringify({ rowChildren, rowWidth: tableSteppers[0].getBoundingClientRect().width, panelWidth: tablePanel.clientWidth }));
          rowInput.value = '5'; rowInput.dispatchEvent(new Event('input', { bubbles: true })); state = window.WeiBeiEditor.slashStateForCheck(); if (state.rows !== 5) throw new Error('editable row count did not update: ' + JSON.stringify(state));
          const originalMenuLeft = menu.style.left; menu.style.left = `${innerWidth - menu.offsetWidth - 8}px`; window.WeiBeiEditor.renderSlashMenuForCheck(); tablePanel = document.querySelector('.weibei-slash-table-panel'); panelRect = tablePanel?.getBoundingClientRect(); const rightMenuRect = menu.getBoundingClientRect();
          if (tablePanel?.dataset.side !== 'left' || !panelRect || panelRect.right > rightMenuRect.left) throw new Error('table submenu did not flip to the left: ' + JSON.stringify({ side: tablePanel?.dataset.side, rightMenuRect, panelRect }));
          menu.style.left = originalMenuLeft; window.WeiBeiEditor.renderSlashMenuForCheck();
          window.WeiBeiEditor.setDocumentID('slash-table-hover'); open('/table'); const hoverButton = document.querySelector('#weibei-slash-command-table .weibei-slash-command-button'); const hoverEvent = new Event('pointermove', { bubbles: true }); Object.defineProperties(hoverEvent, { movementX: { value: 1 }, movementY: { value: 0 } }); hoverButton?.dispatchEvent(hoverEvent); state = window.WeiBeiEditor.slashStateForCheck(); if (!state.tableOpen) throw new Error('real pointer movement did not open the table submenu');
          window.WeiBeiEditor.executeSlashCommandForCheck('table');
          return { markdown: window.WeiBeiEditor.getMarkdown(), state: window.WeiBeiEditor.slashStateForCheck() };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, let result = value as? [String: Any], let markdown = result["markdown"] as? String, markdown.contains("|") else { self.fail("slash command check failed: \(String(describing: error)); \(String(describing: value))"); return }
            self.validateMotionStableMenus()
        }
    }

    /// Motion rework guards: slash menu rows keep DOM identity across pointer
    /// motion, the table submenu keeps input focus across arrow-key changes,
    /// reduce-motion reaches the page, and the folded callout wrapper survives
    /// a read-mode toggle round trip without touching the Markdown.
    private func validateMotionStableMenus() {
        let script = """
        (() => {
          const open = (text) => { window.WeiBeiEditor.setMarkdown(text); return window.WeiBeiEditor.openSlashMenuForCheck(); };
          // 1. DOM identity: pointer motion must not rebuild the command rows.
          if (!open('/')) throw new Error('slash menu did not open for identity check');
          const menu = document.querySelector('.weibei-slash-menu');
          const rows = Array.from(menu.querySelectorAll('.weibei-slash-command-button'));
          if (rows.length < 4) throw new Error('slash rows missing for identity check');
          const probe = rows[1];
          probe.dataset.domIdentityProbe = '1';
          const hoverMove = (element) => { const event = new Event('pointermove', { bubbles: true }); Object.defineProperties(event, { movementX: { value: 2 }, movementY: { value: 0 } }); element.dispatchEvent(event); };
          hoverMove(rows[3]);
          if (!document.contains(probe) || probe.dataset.domIdentityProbe !== '1') throw new Error('pointer motion rebuilt slash rows');
          if (probe.closest('.weibei-slash-command')?.classList.contains('is-active')) throw new Error('active row did not move off the probed row');
          if (!rows[3].closest('.weibei-slash-command')?.classList.contains('is-active')) throw new Error('pointer motion did not update the active row');
          const ariaDescendant = menu.getAttribute('aria-activedescendant') || '';
          if (rows[3].parentElement && ariaDescendant !== rows[3].parentElement.id) throw new Error('aria-activedescendant did not follow the pointer: ' + ariaDescendant);

          // 2. Table submenu: one instance, stepper clicks keep input focus and
          //    always read live values (no stale captures from build time).
          window.WeiBeiEditor.setDocumentID('motion-table-focus'); open('/table');
          window.WeiBeiEditor.pressKeyForCheck('ArrowRight');
          const panel = document.querySelector('.weibei-slash-table-panel');
          if (!panel) throw new Error('table submenu did not open');
          panel.dataset.identityProbe = '1';
          const rowsStepper = panel.querySelectorAll('.weibei-slash-stepper')[0];
          const rowsInput = rowsStepper.querySelector('input');
          const increment = rowsStepper.querySelectorAll('button')[1];
          rowsInput.focus();
          increment.click();
          if (document.querySelector('.weibei-slash-table-panel') !== panel || panel.dataset.identityProbe !== '1') throw new Error('table submenu was rebuilt by a stepper click');
          if (document.activeElement !== rowsInput) throw new Error('stepper click stole the table input focus');
          if (window.WeiBeiEditor.slashStateForCheck().rows !== 4) throw new Error('stepper click did not read the live row value');
          increment.click();
          if (window.WeiBeiEditor.slashStateForCheck().rows !== 5) throw new Error('stale handler captured the build-time value');
          window.WeiBeiEditor.pressKeyForCheck('Escape');

          // 3. Reduce-motion boolean reaches the page and gates CSS motion.
          window.WeiBeiEditor.setReduceMotion(true);
          if (document.documentElement.dataset.weibeiReduceMotion !== 'true') throw new Error('reduce-motion did not reach the document');
          if (getComputedStyle(menu).transitionDuration !== '0s') throw new Error('reduce-motion did not disable menu transitions: ' + getComputedStyle(menu).transitionDuration);
          window.WeiBeiEditor.setReduceMotion(false);
          if (document.documentElement.dataset.weibeiReduceMotion !== 'false') throw new Error('reduce-motion could not be cleared');

          // 4. Folded callout: wrapper present, click toggles open state, Markdown intact.
          window.WeiBeiEditor.setDocumentID('motion-callout');
          window.WeiBeiEditor.setEditable(false);
          window.WeiBeiEditor.setMarkdown('> [!note]- 折叠标题\\n>\\n> 正文第一行\\n> 正文第二行');
          const callout = document.querySelector('blockquote.weibei-callout[data-callout-fold="-"]');
          const collapse = callout?.querySelector('.weibei-callout-collapse');
          const content = collapse?.querySelector('.weibei-callout-content');
          if (!callout || !collapse || !content) throw new Error('callout collapse wrapper missing: ' + JSON.stringify({
            callouts: Array.from(document.querySelectorAll('blockquote.weibei-callout')).map((node) => ({ fold: node.getAttribute('data-callout-fold'), cls: node.className, children: Array.from(node.children).map((child) => child.className) })),
            editable: document.body.dataset.editable
          }));
          const closedRows = getComputedStyle(collapse).gridTemplateRows;
          callout.click();
          if (!callout.classList.contains('weibei-callout-open')) throw new Error('click did not open the folded callout');
          const openRows = getComputedStyle(collapse).gridTemplateRows;
          if (closedRows === openRows) throw new Error('collapse grid rows did not change on toggle: ' + closedRows + ' / ' + openRows);
          callout.click();
          if (callout.classList.contains('weibei-callout-open')) throw new Error('click did not re-fold the callout');
          window.WeiBeiEditor.setEditable(true);
          const markdown = window.WeiBeiEditor.getMarkdown();
          if (!markdown.includes('[!note]-') || !markdown.includes('正文第二行')) throw new Error('callout round trip polluted the Markdown: ' + JSON.stringify(markdown));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("motion-stable menus check failed: \(String(describing: error)); \(String(describing: value))")
                return
            }
            self.validateIMECompositionBridge()
        }
    }

    /// Verifies that transient IME snapshots never round-trip through SwiftUI.
    private func validateIMECompositionBridge() {
        let initialSnapshotCount = snapshotCount
        let script = """
        (() => {
          window.WeiBeiEditor.setDocumentID('ime-composition'); window.WeiBeiEditor.setMarkdown('/h1'); window.WeiBeiEditor.openSlashMenuForCheck(); window.WeiBeiEditor.executeSlashCommandForCheck('heading1');
          const root = document.querySelector('.ProseMirror'); root.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true })); window.WeiBeiEditor.typeTextForCheck('中文标题');
          return { childCount: root.children.length };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil else { self.fail("IME composition setup failed: \(error!.localizedDescription)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard self.snapshotCount == initialSnapshotCount,
                      self.currentDocumentID == "ime-composition",
                      self.isDirty else {
                    self.fail("IME transient content crossed the snapshot bridge: \(String(describing: value))")
                    return
                }
                self.webView.evaluateJavaScript("window.WeiBeiEditor.compositionStateForCheck()") { stateValue, stateError in
                    guard stateError == nil,
                          let state = stateValue as? [String: Any],
                          state["start"] as? String != nil,
                          state["composing"] as? Bool == true else {
                        self.fail("IME composition state was not retained: \(String(describing: stateError)); \(String(describing: stateValue))")
                        return
                    }
                    self.webView.evaluateJavaScript("const heading = document.querySelector('.ProseMirror h1'); for (let index = 0; index < 3; index += 1) heading.appendChild(document.createElement('br')); document.querySelector('.ProseMirror').dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '中文标题' }));") { _, compositionError in
                        guard compositionError == nil else { self.fail("IME composition end failed: \(compositionError!.localizedDescription)"); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.webView.evaluateJavaScript("({ childCount: document.querySelector('.ProseMirror').children.length, breakCount: document.querySelectorAll('.ProseMirror h1 br').length, composition: window.WeiBeiEditor.compositionStateForCheck() })") { finalValue, finalError in
                            guard finalError == nil,
                                  let result = finalValue as? [String: Any],
                                  result["childCount"] as? Int == 1,
                                  result["breakCount"] as? Int == 0 else {
                                self.fail("IME final DOM was not normalized: \(String(describing: finalError)); \(String(describing: finalValue))")
                                return
                            }
                            self.requestSnapshot { snapshot in
                                guard snapshot.documentID == "ime-composition",
                                      snapshot.markdown == "# 中文标题\n" else {
                                    self.fail("IME final snapshot was incorrect: \(snapshot.markdown.debugDescription)")
                                    return
                                }
                                self.validateIMEQuoteComposition()
                            }
                        }
                    }
                    }
                }
            }
        }
    }

    /// Verifies that IME submission removes WebKit line-break artifacts inside a new quote.
    private func validateIMEQuoteComposition() {
        let initialSnapshotCount = snapshotCount
        let setupScript = """
        (() => {
          window.WeiBeiEditor.setDocumentID('ime-quote'); window.WeiBeiEditor.setMarkdown('/quote'); window.WeiBeiEditor.openSlashMenuForCheck(); window.WeiBeiEditor.executeSlashCommandForCheck('quote');
          const root = document.querySelector('.ProseMirror'); window.WeiBeiIMEQuoteInitialHeight = document.querySelector('.ProseMirror blockquote').getBoundingClientRect().height; root.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true })); window.WeiBeiEditor.typeTextForCheck('引用内容');
          return document.querySelector('.ProseMirror blockquote')?.textContent || '';
        })();
        """
        webView.evaluateJavaScript(setupScript) { [weak self] value, error in
            guard let self else { return }
            guard error == nil else { self.fail("IME quote setup failed: \(error!.localizedDescription)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard self.snapshotCount == initialSnapshotCount,
                      self.currentDocumentID == "ime-quote",
                      self.isDirty else {
                    self.fail("IME quote transient content crossed the snapshot bridge: \(String(describing: value))")
                    return
                }
                let completeScript = "const quote = document.querySelector('.ProseMirror blockquote'); const paragraph = quote.querySelector('p'); const marker = paragraph.querySelector('.ProseMirror-safari-ime-span'); if (!marker) throw new Error('missing Safari IME composition marker'); const beforeBreakHeight = quote.getBoundingClientRect().height; for (let index = 0; index < 3; index += 1) paragraph.appendChild(document.createElement('br')); const composingHeight = quote.getBoundingClientRect().height; if (composingHeight > window.WeiBeiIMEQuoteInitialHeight + 1) throw new Error('IME line breaks changed quote height: ' + window.WeiBeiIMEQuoteInitialHeight + ' -> ' + beforeBreakHeight + ' -> ' + composingHeight + '; html=' + paragraph.innerHTML + '; displays=' + Array.from(paragraph.querySelectorAll('br')).map((node) => getComputedStyle(node).display).join(',')); document.querySelector('.ProseMirror').dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '引用内容' }));"
                self.webView.evaluateJavaScript(completeScript) { _, completionError in
                    guard completionError == nil else { self.fail("IME quote completion failed: \(String(describing: completionError))"); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.webView.evaluateJavaScript("({ breakCount: document.querySelectorAll('.ProseMirror blockquote p br').length })") { finalValue, finalError in
                            guard finalError == nil,
                                  let result = finalValue as? [String: Any],
                                  result["breakCount"] as? Int == 0 else {
                                self.fail("IME quote line breaks were not normalized: \(String(describing: finalError)); \(String(describing: finalValue))")
                                return
                            }
                            self.requestSnapshot { snapshot in
                                guard snapshot.documentID == "ime-quote",
                                      snapshot.markdown == "> 引用内容\n" else {
                                    self.fail("IME quote final snapshot was incorrect: \(snapshot.markdown.debugDescription)")
                                    return
                                }
                                self.validateSlashImageLifecycle()
                            }
                        }
                    }
                }
            }
        }
    }

    private func validateSlashImageLifecycle() {
        let script = """
        (() => {
          window.WeiBeiEditor.setDocumentID('slash-image-a'); window.WeiBeiEditor.setMarkdown('/image'); window.WeiBeiEditor.openSlashMenuForCheck(); window.WeiBeiEditor.executeSlashCommandForCheck('image');
          const id = window.WeiBeiEditor.pendingImagePickerIDsForCheck()[0]; if (!id) throw new Error('missing picker request');
          window.WeiBeiEditor.resolveImagePicker(id, '.weibei-assets/example.png', 'example');
          const inserted = window.WeiBeiEditor.getMarkdown(); window.WeiBeiEditor.undoForCheck(); const undone = window.WeiBeiEditor.getMarkdown();
          window.WeiBeiEditor.setMarkdown('/image'); window.WeiBeiEditor.openSlashMenuForCheck(); window.WeiBeiEditor.executeSlashCommandForCheck('image'); const stale = window.WeiBeiEditor.pendingImagePickerIDsForCheck()[0]; window.WeiBeiEditor.setDocumentID('slash-image-b'); window.WeiBeiEditor.setMarkdown('/image'); window.WeiBeiEditor.cancelImagePicker(stale);
          if (!inserted.includes('.weibei-assets/example.png') || !undone.includes('/image') || !window.WeiBeiEditor.getMarkdown().includes('/image')) throw new Error('image lifecycle invalid');
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true, self.imagePickerRequests >= 2 else { self.fail("slash image lifecycle failed: \(String(describing: error)); requests=\(self.imagePickerRequests)"); return }
            self.validateSlashAfterInlineImage()
        }
    }

    /// Verifies that an inline image does not block Slash insertion or get replaced by it.
    private func validateSlashAfterInlineImage() {
        let script = """
        (() => {
          window.WeiBeiEditor.setDocumentID('slash-image-inline');
          window.WeiBeiEditor.setMarkdown('![icon](assets/weibei.svg) /');
          if (!window.WeiBeiEditor.openSlashMenuForCheck()) throw new Error('slash menu did not open after an inline image + /');
          const before = window.WeiBeiEditor.getMarkdown();
          if (!before.includes('![icon](assets/weibei.svg)')) throw new Error('image reference missing before command attempt: ' + before);
          window.WeiBeiEditor.executeSlashCommandForCheck('quote');
          const after = window.WeiBeiEditor.getMarkdown();
          if (!after.includes('![icon](assets/weibei.svg)') || !after.includes('>')) throw new Error('command insertion lost the image: ' + JSON.stringify({ before, after }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else { self.fail("slash after inline image failed: \(String(describing: error)); \(String(describing: value))"); return }
            self.validateSlashCodeBlockTypingStability()
        }
    }

    private func validateSlashCodeBlockTypingStability() {
        let script = """
        (() => {
          window.WeiBeiEditor.setDocumentID('list-tab'); window.WeiBeiEditor.setMarkdown('* 甲\\n* 乙'); window.WeiBeiEditor.selectDocumentEndForCheck(); window.WeiBeiEditor.pressKeyForCheck('Tab'); const bulletListTab = window.WeiBeiEditor.getMarkdown();
          window.WeiBeiEditor.setMarkdown('1. 甲\\n2. 乙'); window.WeiBeiEditor.selectDocumentEndForCheck(); window.WeiBeiEditor.pressKeyForCheck('Tab'); const orderedListTab = window.WeiBeiEditor.getMarkdown();
          if (!bulletListTab.includes('  * 乙') || !orderedListTab.includes('   1. 乙')) throw new Error('list Tab indentation diverged: ' + JSON.stringify({ bulletListTab, orderedListTab }));
          window.WeiBeiEditor.setDocumentID('slash-code-typing'); window.WeiBeiEditor.setMarkdown('/code'); window.WeiBeiEditor.openSlashMenuForCheck(); window.WeiBeiEditor.executeSlashCommandForCheck('code');
          const pre = document.querySelector('.ProseMirror pre'); const input = pre?.querySelector('.weibei-code-language-input'); const code = pre?.querySelector('code'); const initialHeight = pre?.getBoundingClientRect().height;
          if (!pre || !input || !code || input.parentElement !== pre || code.contains(input) || getComputedStyle(code).tabSize !== '4') throw new Error('code NodeView shell or tab size is invalid');
          let previous = window.WeiBeiEditor.selectionForCheck().from;
          for (const character of ['a', 'b', 'c']) {
            if (!window.WeiBeiEditor.typeTextForCheck(character)) throw new Error('cannot type code character');
            const selection = window.WeiBeiEditor.selectionForCheck(); const markdown = window.WeiBeiEditor.getMarkdown();
            if (!markdown.includes('```\\n' + ['a', 'ab', 'abc'][character.charCodeAt(0) - 97] + '\\n```') || selection.from !== previous + 1 || input !== pre.querySelector('.weibei-code-language-input') || document.activeElement !== document.querySelector('.ProseMirror') || pre.getBoundingClientRect().height !== initialHeight || code.querySelectorAll('br.ProseMirror-trailingBreak').length > 1) throw new Error('code typing became unstable: ' + markdown);
            previous = selection.from;
          }
          input.value = 'rust'; input.dispatchEvent(new Event('change', { bubbles: true }));
          if (!window.WeiBeiEditor.getMarkdown().includes('```rust\\nabc\\n```')) throw new Error('code language did not update through NodeView');
          window.WeiBeiEditor.undoForCheck(); if (window.WeiBeiEditor.getMarkdown().includes('```rust')) throw new Error('undo did not revert code language');
          window.WeiBeiEditor.setDocumentID('code-tab'); window.WeiBeiEditor.setMarkdown('```swift\\nlet value =\\n```\\n\\nafter'); window.WeiBeiEditor.selectFirstCodeBlockEndForCheck(); const editorElement = document.querySelector('.ProseMirror'); if (editorElement?.getAttribute('autocapitalize') !== 'none') throw new Error('code block did not disable autocapitalize'); window.WeiBeiEditor.pressKeyForCheck('Tab'); window.WeiBeiEditor.typeTextForCheck('1'); const tabMarkdown = window.WeiBeiEditor.getMarkdown(); if (!tabMarkdown.includes('let value =\\t1') || document.activeElement !== editorElement) throw new Error('Tab did not insert code indentation: ' + JSON.stringify({ tabMarkdown, activeElement: document.activeElement?.className || document.activeElement?.tagName })); window.WeiBeiEditor.selectDocumentEndForCheck(); if (editorElement?.getAttribute('autocapitalize') === 'none') throw new Error('autocapitalize remained disabled outside code block');
          window.WeiBeiEditor.setDocumentID('slash-mermaid-default'); window.WeiBeiEditor.setMarkdown('/mermaid'); window.WeiBeiEditor.openSlashMenuForCheck(); const mermaidButton = document.querySelector('#weibei-slash-command-mermaid .weibei-slash-command-button'); mermaidButton?.focus(); mermaidButton?.click();
          const mermaidSource = 'graph TD\\n\tA --> B'; const mermaidSelection = window.WeiBeiEditor.selectionForCheck(); const mermaidMarkdown = window.WeiBeiEditor.getMarkdown();
          if (mermaidMarkdown !== '```mermaid\\n' + mermaidSource + '\\n```\\n' || mermaidSelection.parent !== 'code_block' || mermaidSelection.parentOffset !== mermaidSource.length || document.activeElement !== document.querySelector('.ProseMirror')) throw new Error('Mermaid slash default or initial focus invalid: ' + JSON.stringify({ mermaidMarkdown, mermaidSelection, activeElement: document.activeElement?.className || document.activeElement?.tagName }));
          const defaultMermaidPre = document.querySelector('.weibei-mermaid-block'); const defaultMermaidCode = defaultMermaidPre?.querySelector('code'); const defaultMermaidPreview = document.querySelector('.weibei-mermaid-render'); const initialMermaidSourceHeight = defaultMermaidCode?.getBoundingClientRect().height || 0; if (!defaultMermaidPre || !defaultMermaidCode || !defaultMermaidPreview || defaultMermaidPre.contains(defaultMermaidPreview) || defaultMermaidPreview.parentElement !== editorElement) throw new Error('Mermaid preview remained inside editable source');
          window.WeiBeiEditor.typeTextForCheck('\\n'); const firstEnterHeight = defaultMermaidCode.getBoundingClientRect().height; const firstEnterSelection = window.WeiBeiEditor.selectionForCheck(); if (defaultMermaidCode.textContent !== mermaidSource + '\\n' || firstEnterSelection.parentOffset !== mermaidSource.length + 1 || firstEnterHeight <= initialMermaidSourceHeight || !defaultMermaidCode.querySelector('br.ProseMirror-trailingBreak') || document.querySelector('.weibei-mermaid-render') !== defaultMermaidPreview) throw new Error('first Mermaid Enter was not immediately visible: ' + JSON.stringify({ source: defaultMermaidCode.textContent, firstEnterSelection, initialMermaidSourceHeight, firstEnterHeight }));
          window.WeiBeiEditor.typeTextForCheck('\\n'); const secondEnterHeight = defaultMermaidCode.getBoundingClientRect().height; if (defaultMermaidCode.textContent !== mermaidSource + '\\n\\n' || secondEnterHeight <= firstEnterHeight) throw new Error('second Mermaid Enter did not add exactly the next source line'); window.WeiBeiEditor.pressKeyForCheck('Tab'); const tabbedMermaidHeight = defaultMermaidCode.getBoundingClientRect().height; const tabbedMermaidMarkdown = window.WeiBeiEditor.getMarkdown(); if (defaultMermaidCode.textContent !== mermaidSource + '\\n\\n\\t' || tabbedMermaidHeight !== secondEnterHeight || tabbedMermaidMarkdown !== '```mermaid\\n' + mermaidSource + '\\n\\n\\t\\n```\\n' || document.querySelector('.weibei-mermaid-render') !== defaultMermaidPreview) throw new Error('Mermaid Tab revealed deferred blank lines: ' + JSON.stringify({ source: defaultMermaidCode.textContent, tabbedMermaidMarkdown, firstEnterHeight, secondEnterHeight, tabbedMermaidHeight }));
          window.WeiBeiEditor.setMarkdown('```mermaid\\ngraph TD\\n```\\n\\nafter'); window.WeiBeiEditor.selectFirstCodeBlockEndForCheck(); const previewBeforeTyping = document.querySelector('.weibei-mermaid-render'); if (!window.WeiBeiEditor.typeTextForCheck('x') || !window.WeiBeiEditor.getMarkdown().includes('graph TDx')) throw new Error('Mermaid NodeView did not accept text');
          const previewDuringTyping = document.querySelector('.weibei-mermaid-render'); if (!previewBeforeTyping || previewDuringTyping !== previewBeforeTyping) throw new Error('Mermaid preview rerendered while source retained focus');
          document.querySelector('.ProseMirror')?.dispatchEvent(new FocusEvent('blur')); document.querySelector('.weibei-code-language-input')?.focus(); const previewAfterBlur = document.querySelector('.weibei-mermaid-render'); if (!previewAfterBlur || previewAfterBlur === previewDuringTyping) throw new Error('Mermaid preview did not rerender after source focus left');
          document.querySelector('.ProseMirror')?.dispatchEvent(new FocusEvent('focus')); if (!window.WeiBeiEditor.typeTextForCheck('y')) throw new Error('Mermaid source could not regain focus'); const previewDuringSecondEdit = document.querySelector('.weibei-mermaid-render'); if (previewDuringSecondEdit !== previewAfterBlur) throw new Error('Mermaid preview rerendered during the second edit');
          window.WeiBeiEditor.selectDocumentEndForCheck(); const previewAfterBlockExit = document.querySelector('.weibei-mermaid-render'); const selectionAfterBlockExit = window.WeiBeiEditor.selectionForCheck(); if (!previewAfterBlockExit || previewAfterBlockExit === previewDuringSecondEdit || selectionAfterBlockExit.parent === 'code_block') throw new Error('Mermaid preview did not rerender after selection left its source block: ' + JSON.stringify({ hasPreview: !!previewAfterBlockExit, samePreview: previewAfterBlockExit === previewDuringSecondEdit, selectionAfterBlockExit }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else { self.fail("slash code typing stability failed: \(String(describing: error))"); return }
            self.validateCodeLanguageDocumentIsolation()
        }
    }

    private func validateCodeLanguageDocumentIsolation() {
        let script = """
        (() => {
          window.WeiBeiEditor.setDocumentID('note-a'); window.WeiBeiEditor.setMarkdown('```swift\\nlet value = 1\\n```');
          const oldInput = document.querySelector('.weibei-code-language-input'); if (!oldInput) throw new Error('missing code language input'); oldInput.value = 'rust';
          window.WeiBeiEditor.setDocumentID('note-b'); window.WeiBeiEditor.setMarkdown('```swift\\nlet value = 2\\n```');
          oldInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); oldInput.dispatchEvent(new Event('blur', { bubbles: true }));
          const newInput = document.querySelector('.weibei-code-language-input'); const codeBlock = document.querySelector('.ProseMirror pre[data-language]'); const markdown = window.WeiBeiEditor.getMarkdown(); window.WeiBeiEditor.setEditable(false);
          const readonly = document.querySelector('.weibei-code-language-input'); const readonlyOK = readonly?.readOnly && readonly?.tabIndex === -1 && readonly?.getAttribute('aria-readonly') === 'true'; window.WeiBeiEditor.setEditable(true);
          if (markdown.includes('rust') || oldInput === newInput || !readonlyOK || getComputedStyle(codeBlock, '::before').content !== 'none') throw new Error('code language document isolation failed: ' + JSON.stringify({ markdown, sameInput: oldInput === newInput, readonlyOK, input: !!newInput, pseudoContent: getComputedStyle(codeBlock, '::before').content }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else { self.fail("code language isolation failed: \(String(describing: error))"); return }
            self.validateMermaidResourceRegressions()
        }
    }

    private func validateMermaidResourceRegressions() {
        let markdown = """
        ```mermaid
        xychart
          x-axis 1 --> 1
          line [1, 2]
        ```

        ```mermaid
        radar-beta
          axis a, b
          curve c {1, 1}
          ticks 1000000000
        ```
        """
        webView.evaluateJavaScript("""
        window.WeiBeiEditor.setDocumentID('mermaid-resource-regressions');
        window.WeiBeiEditor.setMarkdown(\(json(markdown)));
        """) { [weak self] _, error in
            guard let self else { return }
            guard error == nil else {
                self.fail("Mermaid resource regression setup failed: \(String(describing: error))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.webView.evaluateJavaScript("""
                ({
                  alive: !!document.querySelector('.ProseMirror'),
                  blocks: document.querySelectorAll('.weibei-mermaid-block').length,
                  markdown: window.WeiBeiEditor.getMarkdown()
                })
                """) { [weak self] value, error in
                    guard let self else { return }
                    guard error == nil,
                          let result = value as? [String: Any],
                          result["alive"] as? Bool == true,
                          (result["blocks"] as? Int ?? 0) == 2,
                          (result["markdown"] as? String)?
                            .trimmingCharacters(in: .newlines)
                            == markdown.trimmingCharacters(in: .newlines) else {
                        self.fail("patched Mermaid inputs destabilized the editor: \(String(describing: value)); error=\(String(describing: error))")
                        return
                    }
                    self.validateTextScaleSync()
                }
            }
        }
    }

    /// The Swift host pushes the app-wide text tier through
    /// `window.WeiBeiEditor.setTextScale`; the page must translate it into the
    /// `--weibei-text-scale` variable and a proportional `.ProseMirror` font.
    private func validateTextScaleSync() {
        webView.evaluateJavaScript("""
        (() => {
          const editor = document.querySelector('.ProseMirror');
          if (!editor) return { ok: false, detail: 'missing editor surface' };
          const before = parseFloat(getComputedStyle(editor).fontSize);
          window.WeiBeiEditor.setTextScale(1.5);
          const applied = document.documentElement.style.getPropertyValue('--weibei-text-scale');
          const after = parseFloat(getComputedStyle(editor).fontSize);
          window.WeiBeiEditor.setTextScale(1);
          const restored = parseFloat(getComputedStyle(editor).fontSize);
          const ratio = before > 0 ? after / before : 0;
          return {
            ok: applied === '1.5' && ratio > 1.45 && ratio < 1.55 && Math.abs(restored - before) <= 0.5,
            applied: applied,
            before: before,
            after: after,
            ratio: ratio,
          };
        })();
        """) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("text-scale check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any], result["ok"] as? Bool == true else {
                self.fail("text-scale sync did not resize editor copy: \(String(describing: value))")
                return
            }
            self.validateExternalMarkdownAcknowledgement()
        }
    }

    private func validateExternalMarkdownAcknowledgement() {
        let documentID = "note-switch-target"
        let markdown = "# 切换后的笔记\n\n"
        let generation = currentDocumentGeneration + 1
        let command: [String: Any] = [
            "protocolVersion": 2,
            "commandID": "web-editor-check-load",
            "documentID": documentID,
            "documentGeneration": generation,
            "type": "loadDocument",
            "payload": ["markdown": markdown],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let encoded = String(data: data, encoding: .utf8) else {
            fail("could not encode V2 loadDocument command")
            return
        }
        webView.evaluateJavaScript("window.WeiBeiEditor.dispatchCommand(\(encoded))") { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("V2 loadDocument was rejected: \(String(describing: error))")
                return
            }
            guard self.currentDocumentID == documentID,
                  self.currentDocumentGeneration == generation,
                  !self.isDirty else {
                self.fail("loadDocument did not publish a clean V2 session")
                return
            }
                self.requestSnapshot { snapshot in
                guard snapshot.documentID == documentID,
                      snapshot.documentGeneration == generation,
                      snapshot.markdown.trimmingCharacters(in: .newlines)
                        == markdown.trimmingCharacters(in: .newlines) else {
                    self.fail("loadDocument snapshot did not match the switched document: \(snapshot.markdown.debugDescription)")
                    return
                }
                self.validateIdempotentContentCommandRetry()
            }
        }
    }

    /// Same commandID already applied in the page, receipt lost, retry must not insert again.
    private func validateIdempotentContentCommandRetry() {
        let marker = "幂等插入标记"
        let command: [String: Any] = [
            "protocolVersion": 2,
            "commandID": "web-editor-check-idempotent-insert",
            "documentID": currentDocumentID,
            "documentGeneration": currentDocumentGeneration,
            "type": "insertStructuredBlock",
            "payload": ["markdown": "\n\n\(marker)\n"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let encoded = String(data: data, encoding: .utf8) else {
            fail("could not encode idempotent insert command")
            return
        }
        webView.evaluateJavaScript("window.WeiBeiEditor.dispatchCommand(\(encoded))") { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("idempotent insert command was rejected: \(String(describing: error))")
                return
            }
            self.requestSnapshot { first in
                let firstCount = first.markdown.components(separatedBy: marker).count - 1
                guard firstCount == 1 else {
                    self.fail("idempotent insert did not land once: \(first.markdown.debugDescription)")
                    return
                }
                self.webView.evaluateJavaScript("window.WeiBeiEditor.dispatchCommand(\(encoded))") { value, error in
                    guard error == nil, value as? Bool == true else {
                        self.fail("idempotent retry was rejected: \(String(describing: error))")
                        return
                    }
                    self.requestSnapshot { second in
                        let secondCount = second.markdown.components(separatedBy: marker).count - 1
                        guard secondCount == 1 else {
                            self.fail("lost-receipt retry duplicated inserted body: \(second.markdown.debugDescription)")
                            return
                        }
                        self.isDone = true
                    }
                }
            }
        }
    }

    private func validate(_ markdown: String) {
        let checks = [
            ("table", "| 能力"),
            ("escaped table wikilink", "[[货币理论\\|理论别名]]"),
            ("task unchecked", "[ ] todo"),
            ("task checked", "[x] done"),
            ("strikethrough", "~~删除线~~"),
            ("highlight", "==重点高亮=="),
            ("alias wikilink", "[[货币理论|理论别名]]"),
            ("heading wikilink", "[[货币理论#利率]]"),
            ("block wikilink", "[[货币理论#^rate-block]]"),
            ("block id", "^rate-block"),
            ("embed image", "![[assets/weibei.svg|100]]"),
            ("embed note", "![[货币理论#利率]]"),
            ("footnote", "[^1]: 这是脚注内容。"),
            ("inline footnote", "^[行内脚注内容]"),
            ("callout", "> [!note]- 可编辑标题"),
            ("inline math", "E = mc^2"),
            ("star inline math", "A^*"),
            ("normal dollar", "$5 不应该被误伤"),
            ("plugin-rendered inline math", "$text^*$"),
            ("matrix math", "\\begin{bmatrix}"),
            ("fraction math", "\\frac{a_1}{b^2}"),
            ("mermaid", "```mermaid"),
            ("comment", "%%这是一条只在写作时弱显示的注释%%"),
            ("block comment", "%%\n这是一段块注释\n跨行也应该弱显示\n%%"),
            ("tag", "#nested/tag"),
            ("frontmatter", "course: 货币金融学"),
            ("quoted code block", "> \\#quoted-code \\$5 \\[!note] <br />"),
            ("code fence", "```swift"),
            ("inline html break code", "`<br />`"),
            ("double backtick html break code", "``内部 ` <br />``"),
            ("inline code markdown syntax", "`[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />`"),
            ("inline code escaped syntax", "`\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]`"),
            ("escaped backtick prose syntax", "转义反引号 \\` 后面的 [[转义双链]] #escaped-tag $5"),
            ("code block html break", "<span>保留<br />源码</span>"),
            ("code block escaped syntax", "\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]"),
            ("image size", "![魏碑测试图|100x80](assets/weibei.svg)"),
            ("remote image", "![远程测试图](https://example.com/weibei.png)")
        ]
        for (name, fragment) in checks {
            if !markdown.contains(fragment) {
                fail("missing \(name): \(fragment)\n--- markdown ---\n\(markdown)")
                return
            }
        }
        guard let htmlBreakRange = markdown.range(of: "HTML 换行第一行") else {
            fail("missing html break prefix\n--- markdown ---\n\(markdown)")
            return
        }
        let htmlBreakSuffix = String(markdown[htmlBreakRange.upperBound...])
        if !htmlBreakSuffix.hasPrefix("  \n第二行") && !htmlBreakSuffix.hasPrefix("\\\n第二行") && !htmlBreakSuffix.hasPrefix("\n第二行") {
            fail("HTML break was swallowed instead of becoming a Markdown hard break\n--- markdown ---\n\(markdown)")
            return
        }
        if markdown.contains("HTML 换行第一行第二行") || markdown.contains("HTML 换行第一行<br") {
            fail("HTML break serialized as joined text or raw HTML\n--- markdown ---\n\(markdown)")
            return
        }
    }

    private func fail(_ message: String) {
        failure = message
        isDone = true
    }
}

private let finalizedAgentMarkdown = """
# 完成态回答

第一段保留自己的段落边界，并且包含 **重点**。

## 要点

- 第一项
- 第二项

| 能力 | 状态 |
| --- | --- |
| 段落 | 分开 |
| 表格 | 可读 |

```swift
let greeting = "你好，Markdown"
print(greeting)
```

```mermaid
flowchart LR
A[用户贴网址] --> B[魏碑读取]
B --> C[解析网页内容]
C --> D[形成回答]
D --> E[回答中附来源]
```

中文与 English mixed text should wrap naturally.

[外部链接](https://example.com/weibei-link-check)

\((1...120).map { "超长回答第 \($0) 段：重开后仍须使用同一套块级 Markdown 渲染。" }.joined(separator: "\n\n"))
"""

/// The Chat uses this exact read-only compact editor for finalized assistant turns.
/// Booting it from a complete string also covers reopening a persisted message.
private final class FinalizedAgentMarkdownHarness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private enum Phase: Equatable {
        case initial
        case externalLink
        case delayedGrowth
        case sameBucketResize
        case crossBucketResize
        case shortBlock
    }

    private let webView: WKWebView
    private var phase: Phase = .initial
    private var didReceiveEditorReady = false
    private var didValidateDOM = false
    private var didMeasureHeight = false
    private var didCancelExternalLink = false
    private var didPreserveBodyAfterExternalLink = false
    private var didMeasureDelayedGrowth = false
    private var didMeasureSameBucketResize = false
    private var didMeasureCrossBucketResize = false
    private var didMeasureShortBlock = false
    private var didStartFinalizedStream = false
    private var finalizedStreamHeightReports = 0
    private var measuredHeight: Double = 0
    private var initialReportedWidth: Double?
    private var sameBucketReportedWidth: Double?
    private var crossBucketReportedWidth: Double?
    private var finishReportedHeight: Double = 0
    private var delayedGrowthHeight: Double = 0
    private var shortBlockHeight: Double = 0
    private var isDone = false
    private var failure: String?

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: """
            window.initialMarkdown = \(json(finalizedAgentMarkdown));
            window.weiBeiDocumentID = "finalized-agent-markdown-check";
            window.weiBeiMarkdownEditable = false;
            window.weiBeiMarkdownCompactPreview = true;
            window.weiBeiTheme = "paper";
            window.weiBeiInterfaceLanguage = "zh";
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 680, height: 720), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        for name in ["editorReady", "contentHeightChanged", "finalizedStreaming", "editorFailure"] {
            controller.add(self, name: name)
        }
    }

    func run() {
        let indexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        let timeout = Date().addingTimeInterval(30)
        while !isDone && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if let failure {
            fputs("web-editor-check failed: \(failure)\n", stderr)
            exit(1)
        }
        expect(
            isDone,
            "finalized agent Markdown did not become ready "
                + "(dom=\(didValidateDOM), measured=\(didMeasureHeight), "
                + "externalLink=\(didCancelExternalLink && didPreserveBodyAfterExternalLink), "
                + "delayedGrowth=\(didMeasureDelayedGrowth), "
                + "sameBucket=\(didMeasureSameBucketResize), crossBucket=\(didMeasureCrossBucketResize), "
                + "short=\(didMeasureShortBlock), height=\(measuredHeight), shortHeight=\(shortBlockHeight))"
        )
        print(
            "Finalized Agent Markdown measurements passed: "
                + "initialWidth=\(initialReportedWidth ?? 0), "
                + "sameBucketWidth=\(sameBucketReportedWidth ?? 0), "
                + "crossBucketWidth=\(crossBucketReportedWidth ?? 0), "
                + "longHeight=\(measuredHeight), delayedGrowthHeight=\(delayedGrowthHeight), "
                + "shortHeight=\(shortBlockHeight)"
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }
        guard phase == .externalLink,
              navigationAction.request.url?.absoluteString == "https://example.com/weibei-link-check" else {
            fail("unexpected finalized Agent Markdown link navigation: \(navigationAction.request.url?.absoluteString ?? "nil")")
            decisionHandler(.cancel)
            return
        }
        didCancelExternalLink = true
        decisionHandler(.cancel)
        DispatchQueue.main.async { [weak self] in
            self?.validateBodyAfterCancelledExternalLink()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "editorReady":
            didReceiveEditorReady = true
            validateCompleteLoad(until: Date().addingTimeInterval(3))
        case "contentHeightChanged":
            guard didReceiveEditorReady else {
                fail("finalized agent Markdown reported height before editorReady")
                return
            }
            guard let height = (message.body as? [String: Any])?["height"] as? Double else {
                fail("finalized agent Markdown reported no height")
                return
            }
            if didStartFinalizedStream {
                finalizedStreamHeightReports += 1
            }
            handleMeasurement(height: height, width: Double(webView.frame.width))
        case "finalizedStreaming":
            guard didStartFinalizedStream,
                  let height = (message.body as? [String: Any])?["height"] as? Double,
                  height > 0 else {
                fail("finalized Agent Markdown reported no finalized height")
                return
            }
            finishReportedHeight = height
            validateDOM(until: Date().addingTimeInterval(14))
        case "editorFailure":
            fail("finalized agent Markdown renderer failed: \(message.body)")
        default:
            break
        }
    }

    private func validateCompleteLoad(until deadline: Date) {
        webView.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('.ProseMirror');
          return {
            ok: Boolean(root
              && root.querySelector('h1')
              && root.querySelectorAll('table tr').length >= 3
              && root.textContent.includes('超长回答第 120 段')),
            mermaidSvg: root?.querySelectorAll('.weibei-mermaid-render svg').length || 0,
            mermaidError: root?.querySelector('.weibei-mermaid-error')?.textContent || ''
          };
        })();
        """) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["ok"] as? Bool == true else {
                self.fail("complete finalized Agent Markdown did not reopen: \(String(describing: value))")
                return
            }
            if !(result["mermaidError"] as? String ?? "").isEmpty {
                self.fail("reopened finalized Agent Mermaid failed: \(String(describing: result["mermaidError"]))")
                return
            }
            guard result["mermaidSvg"] as? Int == 1 else {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateCompleteLoad(until: deadline)
                    }
                    return
                }
                self.fail("reopened finalized Agent Mermaid did not render")
                return
            }
            self.installFinalizedMarkdownStream()
        }
    }

    private func installFinalizedMarkdownStream() {
        didStartFinalizedStream = true
        let prefixScript = """
        (() => {
          const markdown = \(json(finalizedAgentMarkdown));
          const mermaidStart = markdown.indexOf('```mermaid');
          window.WeiBeiEditor.setMarkdown('');
          window.WeiBeiEditor.updateStreamingMarkdown(markdown.slice(0, mermaidStart + 20));
          return true;
        })();
        """
        webView.evaluateJavaScript(prefixScript) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.fail("finalized Agent Markdown stream could not start")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.webView.evaluateJavaScript("""
                (() => {
                  const markdown = \(json(finalizedAgentMarkdown));
                  const mermaidStart = markdown.indexOf('```mermaid');
                  window.WeiBeiEditor.updateStreamingMarkdown(markdown.slice(0, mermaidStart + 35));
                })();
                """) { _, error in
                    guard error == nil else {
                        self.fail("finalized Agent Markdown stream could not update")
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.finishFinalizedMarkdownStream()
                    }
                }
            }
        }
    }

    private func finishFinalizedMarkdownStream() {
        webView.evaluateJavaScript("""
        (() => {
          return window.WeiBeiEditor.finishStreamingMarkdown(\(json(finalizedAgentMarkdown))) === true;
        })();
        """) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  value as? Bool == true else {
                self.fail("finalized Agent Markdown stream could not finish")
                return
            }
            // `finalizedStreaming` arrives only after the final body and the
            // authoritative final height have landed.
        }
    }

    private func validateDOM(until deadline: Date) {
        let script = """
        (() => {
          const root = document.querySelector('.ProseMirror');
          if (!root) return { ok: false, reason: 'missing ProseMirror root' };
          const code = root.querySelector('pre code')?.textContent || '';
          const mermaidSource = root.querySelector('.weibei-mermaid-block');
          const measuredNodes = [
            document.querySelector('#editor'),
            document.querySelector('.milkdown'),
            root
          ].filter(Boolean);
          const height = Math.ceil(Math.max(...measuredNodes.map((node) =>
            Math.max(node.scrollHeight || 0, node.offsetHeight || 0, node.clientHeight || 0)
          )));
          return {
            ok: root.querySelectorAll('h1').length === 1
              && root.querySelectorAll('h2').length === 1
              && root.querySelectorAll('li').length >= 2
              && root.querySelectorAll('table tr').length >= 3
              && code.includes('let greeting')
              && root.textContent.includes('第一段保留自己的段落边界')
              && root.textContent.includes('中文与 English mixed text')
              && root.textContent.includes('超长回答第 120 段'),
            paragraphCount: root.querySelectorAll('p').length,
            listItemCount: root.querySelectorAll('li').length,
            tableRowCount: root.querySelectorAll('table tr').length,
            mermaidSvg: root.querySelectorAll('.weibei-mermaid-render svg').length,
            mermaidError: root.querySelector('.weibei-mermaid-error')?.textContent || '',
            mermaidSourceVisible: Boolean(mermaidSource && getComputedStyle(mermaidSource).display !== 'none' && mermaidSource.getBoundingClientRect().height > 0),
            reportedHeight: Number(window.WeiBeiCompactPreviewHeight || 0),
            height,
            code
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("finalized agent Markdown DOM check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("finalized agent Markdown DOM check returned no result")
                return
            }
            // The completion tail now types out at the streaming cadence, so
            // polls can land mid-reveal: structural checks retry to the
            // deadline instead of failing on an intermediate document.
            if result["ok"] as? Bool != true {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateDOM(until: deadline)
                    }
                    return
                }
                self.fail("finalized agent Markdown lost block structure: \(String(describing: value))")
                return
            }
            if !(result["mermaidError"] as? String ?? "").isEmpty {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateDOM(until: deadline)
                    }
                    return
                }
                self.fail("finalized Agent Mermaid failed: \(String(describing: result["mermaidError"]))")
                return
            }
            guard result["mermaidSvg"] as? Int == 1 else {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateDOM(until: deadline)
                    }
                    return
                }
                self.fail("finalized Agent Mermaid did not render: \(result)")
                return
            }
            guard result["mermaidSourceVisible"] as? Bool == false else {
                self.fail("finalized Agent Mermaid exposed source instead of the rendered diagram")
                return
            }
            guard let reportedHeight = (result["reportedHeight"] as? NSNumber)?.doubleValue,
                  let actualHeight = (result["height"] as? NSNumber)?.doubleValue,
                  reportedHeight + 1 >= self.finishReportedHeight,
                  reportedHeight + 1 >= actualHeight else {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateDOM(until: deadline)
                    }
                    return
                }
                self.fail("finalized Agent Markdown height clipped content: finish=\(self.finishReportedHeight), result=\(result)")
                return
            }
            guard self.finalizedStreamHeightReports <= 20 else {
                self.fail("finalized Agent Mermaid caused a height-report storm: \(self.finalizedStreamHeightReports)")
                return
            }
            self.didValidateDOM = true
            self.advanceFromInitialIfReady()
        }
    }

    private func handleMeasurement(height: Double, width: Double?) {
        switch phase {
        case .initial:
            measuredHeight = max(measuredHeight, height)
            didMeasureHeight = height > 1_500
            if initialReportedWidth == nil {
                initialReportedWidth = width
            }
            advanceFromInitialIfReady()
        case .externalLink:
            break
        case .delayedGrowth:
            guard height >= measuredHeight + 100 else { return }
            delayedGrowthHeight = height
            didMeasureDelayedGrowth = true
            phase = .sameBucketResize
            DispatchQueue.main.async { [weak self] in
                self?.webView.setFrameSize(CGSize(width: 679, height: 720))
            }
        case .sameBucketResize:
            guard let width,
                  let initialReportedWidth,
                  abs(width - initialReportedWidth) >= 0.5 else { return }
            didMeasureSameBucketResize = true
            sameBucketReportedWidth = width
            phase = .crossBucketResize
            DispatchQueue.main.async { [weak self] in
                self?.webView.setFrameSize(CGSize(width: 620, height: 720))
            }
        case .crossBucketResize:
            guard let width,
                  let sameBucketReportedWidth,
                  abs(width - sameBucketReportedWidth) >= 20 else { return }
            didMeasureCrossBucketResize = true
            crossBucketReportedWidth = width
            phase = .shortBlock
            webView.evaluateJavaScript("window.WeiBeiEditor.setMarkdown('> 短引用')") { [weak self] _, error in
                if let error {
                    self?.fail("short finalized block could not be installed: \(error.localizedDescription)")
                }
            }
        case .shortBlock:
            guard height > 0 else { return }
            validateShortBlock(measuredHeight: height)
        }
    }

    private func advanceFromInitialIfReady() {
        guard phase == .initial, didValidateDOM && didMeasureHeight else { return }
        phase = .externalLink
        webView.evaluateJavaScript("""
        document.querySelector('a[href="https://example.com/weibei-link-check"]')?.click()
        """) { [weak self] _, error in
            if let error {
                self?.fail("finalized Agent Markdown external-link click failed: \(error.localizedDescription)")
            }
        }
    }

    private func validateBodyAfterCancelledExternalLink() {
        webView.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('.ProseMirror');
          return Boolean(root
            && root.textContent.includes('超长回答第 120 段')
            && location.href.startsWith('file:'));
        })();
        """) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                fail("cancelled external link replaced finalized Agent Markdown")
                return
            }
            didPreserveBodyAfterExternalLink = true
            beginDelayedGrowthCheck()
        }
    }

    private func beginDelayedGrowthCheck() {
        phase = .delayedGrowth
        webView.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('.ProseMirror');
          if (!root) return false;
          const lateBlock = document.createElement('div');
          lateBlock.id = 'weibei-delayed-growth-check';
          lateBlock.style.height = '240px';
          lateBlock.textContent = '延迟加载的图片或图表占位';
          root.appendChild(lateBlock);
          return true;
        })();
        """) { [weak self] value, error in
            if error != nil || value as? Bool != true {
                self?.fail("could not simulate delayed finalized Markdown growth")
            }
        }
    }

    private func validateShortBlock(measuredHeight: Double) {
        webView.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('.ProseMirror');
          return Boolean(root?.querySelector('blockquote')
            && root.textContent.trim() === '短引用');
        })();
        """) { [weak self] value, error in
            guard let self else { return }
            if error != nil || value as? Bool != true {
                // A delayed report from the previous long document can race the
                // replacement. Ignore it and wait for the short block's report.
                return
            }
            shortBlockHeight = measuredHeight
            didMeasureShortBlock = measuredHeight > 0
            isDone = didMeasureSameBucketResize
                && didMeasureCrossBucketResize
                && didMeasureShortBlock
        }
    }

    private func fail(_ message: String) {
        failure = message
        isDone = true
    }
}

private func verifyAgentChatMarkdownSourceContract() {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let chatPath = root.appendingPathComponent("Sources/WeiBei/Views/NotesAgentView.swift")
    let richMarkdownPath = root.appendingPathComponent(
        "Sources/WeiBei/Views/RichMarkdownEditorView.swift"
    )
    let webEditorPath = root.appendingPathComponent(
        "Sources/WeiBei/WebEditor/src/editor.ts"
    )
    guard let chat = try? String(contentsOf: chatPath, encoding: .utf8),
          let richMarkdown = try? String(contentsOf: richMarkdownPath, encoding: .utf8),
          let webEditor = try? String(contentsOf: webEditorPath, encoding: .utf8) else {
        expect(false, "could not read finalized Agent Markdown source contract")
        return
    }

    // Native answer layout and view identity are checked on the actual NSTextView.
    // Tombstone: streaming used to set allowsHitTesting(ready && !isStreaming),
    // so already-blue source/http links could not be clicked until the reply
    // finished. Keep hit-testing aligned with the visible WebView surface.
    expect(
        !chat.contains(".allowsHitTesting(finalizedRendererReady && !isStreaming)"),
        "streaming Agent Markdown must keep already-rendered source links clickable"
    )
    expect(
        richMarkdown.contains("navigationAction.navigationType == .linkActivated")
            && richMarkdown.contains("isSamePageFragment(targetURL, currentURL: webView.url)")
            && richMarkdown.contains("scheme == \"http\" || scheme == \"https\" || scheme == \"mailto\"")
            && richMarkdown.contains("NSWorkspace.shared.open(targetURL)")
            && richMarkdown.contains("decisionHandler(.cancel)"),
        "Markdown external links must open natively without replacing the current editor/answer"
    )
    expect(
        !richMarkdown.contains("{ paced: true }")
            && !webEditor.contains("pacedTailTimer")
            && !webEditor.contains("PACED_TAIL_")
            && !webEditor.contains("options?.paced")
            && webEditor.contains("if (document.hidden || isEditorReduceMotion())"),
        "Agent Markdown must not reintroduce a second web content pacer"
    )
}

final class UTF8HTMLFixtureSchemeHandler: NSObject, WKURLSchemeHandler {
    var rootDirectory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let rootDirectory,
              let requestURL = urlSchemeTask.request.url,
              requestURL.host == "fixture" else {
            urlSchemeTask.didFailWithError(NSError(domain: "WeiBei.HTMLFixture", code: 1))
            return
        }
        let fileURL = requestURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(rootDirectory) { $0.appendingPathComponent(String($1)) }
        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "WeiBei.HTMLFixture", code: 2))
            return
        }
        let mimeType = fileURL.pathExtension == "css" ? "text/css" : "image/svg+xml"
        urlSchemeTask.didReceive(URLResponse(
            url: requestURL,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        ))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class UTF8HTMLReaderHarness: NSObject, WKNavigationDelegate {
    private let resourceSchemeHandler: UTF8HTMLFixtureSchemeHandler
    private let webView: WKWebView
    private var isDone = false
    private var failure: String?
    private var expectedLoadStarted = false
    private let expectedHTML = Data("""
    <!doctype html>
    <link rel="stylesheet" href="reader.css">
    <h1>利率基础</h1>
    <p>名义利率与实际利率。</p>
    <img id="relative-image" src="marker.svg" alt="同目录图片">
    """.utf8)

    override init() {
        let resourceSchemeHandler = UTF8HTMLFixtureSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(resourceSchemeHandler, forURLScheme: "weibeihtmlfixture")
        self.resourceSchemeHandler = resourceSchemeHandler
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        super.init()
        webView.navigationDelegate = self
    }

    func run() {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-html-reader-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        do {
            try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
            try Data("body { color: rgb(12, 34, 56); }".utf8)
                .write(to: fixtureRoot.appendingPathComponent("reader.css"), options: .atomic)
            try Data("""
            <svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">
              <rect width="2" height="2" fill="#9f3b2f"/>
            </svg>
            """.utf8).write(to: fixtureRoot.appendingPathComponent("marker.svg"), options: .atomic)
        } catch {
            expect(false, "could not create UTF-8 HTML reader fixture: \(error.localizedDescription)")
        }
        resourceSchemeHandler.rootDirectory = fixtureRoot

        let staleHTML = Data(("<h1>旧文稿</h1>" + String(repeating: "旧", count: 100_000)).utf8)
        webView.load(staleHTML, mimeType: "text/html", characterEncodingName: "utf-8", baseURL: fixtureRoot)

        let timeout = Date().addingTimeInterval(5)
        while !isDone && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        expect(failure == nil, failure ?? "")
        expect(isDone, "UTF-8 HTML reader fixture did not finish")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !expectedLoadStarted else { return }
        expectedLoadStarted = true
        webView.stopLoading()
        guard webView.load(
            expectedHTML,
            mimeType: "text/html",
            characterEncodingName: "utf-8",
            baseURL: URL(string: "weibeihtmlfixture://fixture/")!
        ) != nil else {
            failure = "UTF-8 HTML reader fixture could not start"
            isDone = true
            return
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard expectedLoadStarted else { return }
        validateLoadedHTML(until: Date().addingTimeInterval(3))
    }

    private func validateLoadedHTML(until deadline: Date) {
        webView.evaluateJavaScript("""
        (() => {
          const image = document.getElementById('relative-image');
          return {
            text: document.body.innerText,
            color: getComputedStyle(document.body).color,
            imageWidth: image?.naturalWidth || 0
          };
        })();
        """) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, let result = value as? [String: Any] else {
                if Date() >= deadline {
                    failure = "UTF-8 HTML reader JavaScript failed: \(String(describing: error))"
                    isDone = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateLoadedHTML(until: deadline)
                    }
                }
                return
            }
            guard let text = result["text"] as? String,
                  text.contains("利率基础"),
                  text.contains("名义利率与实际利率"),
                  !text.contains("旧文稿") else {
                if Date() >= deadline {
                    failure = "UTF-8 HTML or stale-navigation cancellation failed: \(String(describing: value)); error=\(String(describing: error))"
                    isDone = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.validateLoadedHTML(until: deadline)
                    }
                }
                return
            }
            if result["color"] as? String == "rgb(12, 34, 56)",
               result["imageWidth"] as? Int == 2 {
                isDone = true
                return
            }
            if Date() >= deadline {
                failure = "same-directory HTML resources did not load: \(String(describing: value))"
                isDone = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.validateLoadedHTML(until: deadline)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let navigationError = error as NSError
        if navigationError.domain == NSURLErrorDomain, navigationError.code == NSURLErrorCancelled { return }
        failure = error.localizedDescription
        isDone = true
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let navigationError = error as NSError
        if navigationError.domain == NSURLErrorDomain, navigationError.code == NSURLErrorCancelled { return }
        failure = error.localizedDescription
        isDone = true
    }
}

private struct BenchmarkMetrics: Codable {
    let transactions: Int
    let fullSerializations: Int
    let bridgeMessages: Int
    let bridgeBytes: Int
    let decorationNodes: Int
    let decorationCacheHits: Int
    let katexRenders: Int
    let mermaidRenders: Int
    let imageScans: Int
    let imageNodeUpdates: Int
    let codeTokenizations: Int
    let outlineReports: Int
    let fullBridgeMessages: Int
}

private struct BenchmarkPreparationState: Codable {
    let readyMetrics: BenchmarkMetrics
}

private struct BenchmarkActionState: Codable {
    let inputMetrics: BenchmarkMetrics
    let documentGeneration: Int
    let revision: Int
    let loadedRuntimes: [String]
}

private struct BenchmarkTimings: Codable {
    let samplesMilliseconds: [Double]
    let minimumMilliseconds: Double
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double

    init(samples: [Double]) {
        let sorted = samples.sorted()
        samplesMilliseconds = samples
        minimumMilliseconds = sorted.first ?? 0
        medianMilliseconds = sorted[sorted.count / 2]
        p95Milliseconds = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        maximumMilliseconds = sorted.last ?? 0
    }
}

private struct BenchmarkFixtureResult: Codable {
    let fixture: String
    let bytes: Int
    let characters: Int
    let readyMilliseconds: Double
    let snapshotBytes: Int
    let snapshotCharacters: Int
    let snapshotTimings: BenchmarkTimings
    let inputToNextFrameTimings: BenchmarkTimings
    let readyMetrics: BenchmarkMetrics
    let metrics: BenchmarkMetrics
}

private struct BenchmarkReport: Codable {
    let inputCharacters: Int
    let selectionChanges: Int
    let snapshots: Int
    let fixtures: [BenchmarkFixtureResult]
}

private enum BenchmarkError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

private final class EditorBenchmarkHarness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let input = String(repeating: "基", count: 100)
    static let snapshotCount = 7

    private let fixture: String
    private let markdown: String
    private let webView: WKWebView
    private let panel: NSPanel
    private var loadStarted = 0.0
    private var readyMilliseconds = 0.0
    private var readyMetrics: BenchmarkMetrics?
    private var inputRevision = 0
    private var documentGeneration = 0
    private var snapshotSamples: [Double] = []
    private var inputToNextFrameSamples: [Double] = []
    private var snapshotMarkdown: String?
    private var pendingSnapshotRequestID: String?
    private var pendingSnapshotStarted = 0.0
    private var completion: ((Result<BenchmarkFixtureResult, Error>) -> Void)?

    init(fixture: String, markdown: String) {
        self.fixture = fixture
        self.markdown = markdown
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: """
        document.documentElement.setAttribute("writingsuggestions", "false");
        window.initialMarkdown = \(json(markdown));
        window.weiBeiDocumentID = \(json(fixture));
        window.weiBeiMarkdownEditable = true;
        window.weiBeiEditorCheckMode = true;
        window.weiBeiLocalImageScheme = "weibeiimage";
        window.weiBeiMarkdownBaseURL = \(json(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/WeiBei/Resources/Editor/").absoluteString));
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        panel = NSPanel(
            contentRect: NSRect(x: 16, y: 16, width: 120, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .floating
        panel.contentView?.addSubview(webView)
        for name in [
            "editorReady", "dirtyChanged", "snapshotReady", "selectionChanged", "askAgentWithSelection",
            "wikiLinkActivated", "sourceReferenceActivated", "editorFailure",
            "imageAttachmentRequested", "imagePickerRequested", "contentHeightChanged",
            "activeHeadingChanged", "compactPreviewWheel", "appShortcut", "selectionAskMark",
            "benchmarkFrame"
        ] {
            controller.add(self, name: name)
        }
        webView.navigationDelegate = self
    }

    func run(completion: @escaping (Result<BenchmarkFixtureResult, Error>) -> Void) {
        self.completion = completion
        panel.orderFrontRegardless()
        let indexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        loadStarted = ProcessInfo.processInfo.systemUptime
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.completion != nil else { return }
            self.finish(.failure(BenchmarkError.failed("\(self.fixture): editor benchmark timed out")))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "editorReady":
            guard (message.body as? [String: Any])?["documentID"] as? String == fixture else {
                finish(.failure(BenchmarkError.failed("\(fixture): editorReady returned the wrong document")))
                return
            }
            readyMilliseconds = (ProcessInfo.processInfo.systemUptime - loadStarted) * 1_000
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.beginActions() }
        case "editorFailure":
            finish(.failure(BenchmarkError.failed("\(fixture): editor reported a failure: \(message.body)")))
        case "dirtyChanged":
            guard let body = message.body as? [String: Any],
                  body["protocolVersion"] as? Int == 2,
                  body["documentID"] as? String == fixture,
                  body["documentGeneration"] as? Int == documentGeneration || documentGeneration == 0,
                  body["revision"] as? Int != nil,
                  body["dirty"] as? Bool != nil else {
                finish(.failure(BenchmarkError.failed("\(fixture): dirtyChanged did not contain a V2 session")))
                return
            }
        case "snapshotReady":
            receiveSnapshot(message.body)
        case "benchmarkFrame":
            receiveInputFrame(message.body)
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(BenchmarkError.failed("\(fixture): navigation failed: \(error.localizedDescription)")))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(BenchmarkError.failed("\(fixture): navigation failed: \(error.localizedDescription)")))
    }

    private func beginActions() {
        let script = """
        (() => {
        const editor = window.WeiBeiEditor;
        if (typeof editor?.getCheckMetrics !== 'function' || typeof editor?.resetCheckMetrics !== 'function') {
          throw new Error('editor check metrics API is unavailable');
        }
        const readyMetrics = editor.getCheckMetrics();
        editor.resetCheckMetrics();
        if (!editor.selectDocumentEndForCheck()) throw new Error('benchmark selection helper is unavailable');
        return JSON.stringify({ readyMetrics });
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let raw = value as? String,
                  let data = raw.data(using: .utf8),
                  let state = try? JSONDecoder().decode(BenchmarkPreparationState.self, from: data) else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): benchmark setup failed: \(String(describing: error))")))
                return
            }
            self.readyMetrics = state.readyMetrics
            self.webView.evaluateJavaScript("requestAnimationFrame(() => window.webkit.messageHandlers.benchmarkFrame.postMessage(-1)); true") { [weak self] value, error in
                guard let self else { return }
                guard error == nil, value as? Bool == true else {
                    self.finish(.failure(BenchmarkError.failed("\(self.fixture): benchmark frame warmup failed")))
                    return
                }
            }
        }
    }

    private func measureInputCharacter(at index: Int) {
        guard index < Self.input.count else {
            finishActions()
            return
        }
        let script = """
        (() => {
          const started = performance.now();
          if (!window.WeiBeiEditor.typeTextForCheck(\(json(String(Self.input[Self.input.startIndex]))))) return false;
          requestAnimationFrame(() => window.webkit.messageHandlers.benchmarkFrame.postMessage(performance.now() - started));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): benchmark input failed: \(String(describing: error))")))
                return
            }
        }
    }

    private func receiveInputFrame(_ value: Any) {
        if (value as? NSNumber)?.doubleValue == -1 {
            measureInputCharacter(at: 0)
            return
        }
        guard inputToNextFrameSamples.count < Self.input.count,
              let milliseconds = (value as? NSNumber)?.doubleValue,
              milliseconds.isFinite,
              milliseconds > 0 else {
            finish(.failure(BenchmarkError.failed("\(fixture): input-to-next-frame sample was invalid")))
            return
        }
        inputToNextFrameSamples.append(milliseconds)
        measureInputCharacter(at: inputToNextFrameSamples.count)
    }

    private func finishActions() {
        let script = """
        (() => {
        const editor = window.WeiBeiEditor;
        for (let index = 0; index < 10; index += 1) {
          if (!editor.selectFirstTextForCheck('基基') || !editor.selectDocumentEndForCheck()) {
            throw new Error('benchmark selection helpers are unavailable');
          }
        }
        const inputMetrics = editor.getCheckMetrics();
        const session = editor.getBridgeSessionForCheck();
        return JSON.stringify({
          inputMetrics,
          documentGeneration: session.documentGeneration,
          revision: session.revision,
          loadedRuntimes: Array.from(document.scripts)
            .map((script) => script.src.split('/').pop())
            .filter((name) => name?.endsWith('-runtime.js')),
        });
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let raw = value as? String,
                  let data = raw.data(using: .utf8),
                  let state = try? JSONDecoder().decode(BenchmarkActionState.self, from: data) else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): benchmark actions failed: \(String(describing: error))")))
                return
            }
            guard self.inputToNextFrameSamples.count == Self.input.count else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): input-to-next-frame samples were incomplete")))
                return
            }
            guard state.inputMetrics.fullSerializations == 0,
                  state.inputMetrics.fullBridgeMessages == 0 else {
                self.finish(.failure(BenchmarkError.failed(
                    "\(self.fixture): ordinary input serialized or bridged full Markdown: serializations=\(state.inputMetrics.fullSerializations), messages=\(state.inputMetrics.fullBridgeMessages)"
                )))
                return
            }
            guard state.inputMetrics.imageScans == 0,
                  state.inputMetrics.imageNodeUpdates == 0,
                  state.inputMetrics.codeTokenizations == 0,
                  state.inputMetrics.katexRenders == 0,
                  state.inputMetrics.mermaidRenders == 0 else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): ordinary input rerendered unrelated content")))
                return
            }
            if !state.loadedRuntimes.isEmpty {
                self.finish(.failure(BenchmarkError.failed(
                    "\(self.fixture): loaded unrelated runtimes: \(state.loadedRuntimes)"
                )))
                return
            }
            self.inputRevision = state.revision
            self.documentGeneration = state.documentGeneration
            self.measureSnapshot()
        }
    }

    private func measureSnapshot() {
        let requestID = "benchmark-\(snapshotSamples.count + 1)"
        pendingSnapshotRequestID = requestID
        pendingSnapshotStarted = ProcessInfo.processInfo.systemUptime
        let command: [String: Any] = [
            "protocolVersion": 2,
            "commandID": "benchmark-command-\(snapshotSamples.count + 1)",
            "requestID": requestID,
            "documentID": fixture,
            "documentGeneration": documentGeneration,
            "minimumRevision": inputRevision,
            "type": "requestSnapshot",
            "payload": [:],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let encoded = String(data: data, encoding: .utf8) else {
            finish(.failure(BenchmarkError.failed("\(fixture): could not encode snapshot command")))
            return
        }
        webView.evaluateJavaScript("window.WeiBeiEditor.dispatchCommand(\(encoded))") { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): V2 snapshot command failed: \(String(describing: error))")))
                return
            }
        }
    }

    private func receiveSnapshot(_ value: Any) {
        guard let body = value as? [String: Any],
              body["protocolVersion"] as? Int == 2,
              body["documentID"] as? String == fixture,
              body["documentGeneration"] as? Int == documentGeneration,
              let revision = body["revision"] as? Int,
              revision >= inputRevision,
              let requestID = body["requestID"] as? String,
              requestID == pendingSnapshotRequestID,
              let markdown = body["markdown"] as? String else {
            finish(.failure(BenchmarkError.failed("\(fixture): snapshotReady did not match the V2 request")))
            return
        }
        pendingSnapshotRequestID = nil
        if let previous = snapshotMarkdown, previous != markdown {
            finish(.failure(BenchmarkError.failed("\(fixture): repeated snapshots were not stable")))
            return
        }
        snapshotMarkdown = markdown
        snapshotSamples.append((ProcessInfo.processInfo.systemUptime - pendingSnapshotStarted) * 1_000)
        if snapshotSamples.count < Self.snapshotCount {
            measureSnapshot()
        } else {
            readFinalMetrics()
        }
    }

    private func readFinalMetrics() {
        webView.evaluateJavaScript("JSON.stringify(window.WeiBeiEditor.getCheckMetrics())") { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let raw = value as? String,
                  let data = raw.data(using: .utf8),
                  let metrics = try? JSONDecoder().decode(BenchmarkMetrics.self, from: data),
                  let readyMetrics = self.readyMetrics,
                  let snapshotMarkdown = self.snapshotMarkdown else {
                self.finish(.failure(BenchmarkError.failed("\(self.fixture): metrics collection failed: \(String(describing: error))")))
                return
            }
            guard metrics.fullSerializations == Self.snapshotCount,
                  metrics.fullBridgeMessages == Self.snapshotCount else {
                self.finish(.failure(BenchmarkError.failed(
                    "\(self.fixture): explicit snapshot counts were wrong: serializations=\(metrics.fullSerializations), messages=\(metrics.fullBridgeMessages)"
                )))
                return
            }
            self.finish(.success(BenchmarkFixtureResult(
                fixture: self.fixture,
                bytes: self.markdown.utf8.count,
                characters: self.markdown.count,
                readyMilliseconds: self.readyMilliseconds,
                snapshotBytes: snapshotMarkdown.utf8.count,
                snapshotCharacters: snapshotMarkdown.count,
                snapshotTimings: BenchmarkTimings(samples: self.snapshotSamples),
                inputToNextFrameTimings: BenchmarkTimings(samples: self.inputToNextFrameSamples),
                readyMetrics: readyMetrics,
                metrics: metrics
            )))
        }
    }

    private func finish(_ result: Result<BenchmarkFixtureResult, Error>) {
        guard let completion else { return }
        self.completion = nil
        panel.orderOut(nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        completion(result)
    }
}

private func runBenchmarks(completion: @escaping (Result<String, Error>) -> Void) {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fixtureRoot = root.appendingPathComponent("Tests/Fixtures/Writing", isDirectory: true)
    let fixtureNames = ["chinese-long.md", "plain-100k.md", "table-30x20.md"]

    var results: [BenchmarkFixtureResult] = []
    var activeHarness: EditorBenchmarkHarness?
    func runFixture(at index: Int) {
        guard index < fixtureNames.count else {
            do {
                let report = BenchmarkReport(
                    inputCharacters: EditorBenchmarkHarness.input.count,
                    selectionChanges: 20,
                    snapshots: EditorBenchmarkHarness.snapshotCount,
                    fixtures: results
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                completion(.success(String(decoding: try encoder.encode(report), as: UTF8.self)))
            } catch {
                completion(.failure(error))
            }
            return
        }
        let relativePath = fixtureNames[index]
        do {
            let markdown = try String(
                contentsOf: fixtureRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            activeHarness = EditorBenchmarkHarness(fixture: relativePath, markdown: markdown)
            activeHarness?.run { result in
                activeHarness = nil
                switch result {
                case let .success(value):
                    results.append(value)
                    runFixture(at: index + 1)
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    runFixture(at: 0)
}

let benchmarkMode = CommandLine.arguments.dropFirst().contains("--benchmark")
if benchmarkMode {
    NSApplication.shared.setActivationPolicy(.accessory)
    DispatchQueue.main.async {
        runBenchmarks { result in
            switch result {
            case let .success(report):
                print(report)
                fflush(stdout)
                exit(0)
            case let .failure(error):
                fputs("web-editor-benchmark failed: \(error.localizedDescription)\n", stderr)
                fflush(stderr)
                exit(1)
            }
        }
    }
    NSApplication.shared.run()
    exit(1)
}
NSApplication.shared.setActivationPolicy(.prohibited)
if ProcessInfo.processInfo.environment["WEIBEI_HTML_READER_SELF_CHECK_ONLY"] == "1" {
    UTF8HTMLReaderHarness().run()
    print("WeiBei HTML reader check passed")
    exit(0)
}
verifyAgentChatMarkdownSourceContract()
UTF8HTMLReaderHarness().run()
EditorHarness().run()
FinalizedAgentMarkdownHarness().run()
print("WeiBei web editor check passed")
