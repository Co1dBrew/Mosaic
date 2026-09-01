import XCTest

/// # 核心流程 UI 测试（`DECISION_CONFIG: UI_TEST_SCOPE = CORE_E2E_AND_SMOKE`）
///
/// ## 写法约束（`UI_REDESIGN.md` §39）
///
/// - **只用 accessibility identifier 定位**，不用可见文案、不用坐标。
///   文案会改（改文案不该让测试变红），坐标会随字号与机型变。
/// - **不用固定 sleep**。等待一律走 `waitForExistence(timeout:)` ——
///   固定 sleep 要么太短（偶发失败）要么太长（每条用例都慢），两头不讨好。
/// - 每条用例自己建自己需要的数据。**用例之间不共享状态** ——
///   共享状态会让失败的用例顺序相关，排查成本翻倍。
///
/// ## 存储隔离
///
/// `--ui-test` 让 App 用一个独立的磁盘 store（不是 in-memory：Core Flow 2 要
/// 验证「重启后还在」，in-memory 一退出就没了，那条用例会永远通过）。
/// `--ui-test-reset` 在启动时清空它。
final class CoreFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: 工具

    @discardableResult
    private func launch(reset: Bool = true, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test"] + (reset ? ["--ui-test-reset"] : []) + extraArguments
        app.launch()
        self.app = app
        return app
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 8,
                      _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      message.isEmpty ? "\(element) 没有出现" : message, file: file, line: line)
    }

    /// 按 identifier 找元素，**不限定类型**。
    ///
    /// SwiftUI 把同一个修饰符渲染成什么类型并不稳定（`LabeledContent` 可能是
    /// `staticText` 也可能是 `other`，`EmptyStateView` 可能整块是 `other`）。
    /// 按类型查会得到「本地能过、换个 iOS 版本就红」的测试，
    /// 而它红的原因与产品行为无关。
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 按 identifier 前缀找**可点**的那一个。
    ///
    /// 优先在 `buttons` 里找：同一个 identifier 会同时出现在按钮和它的容器上，
    /// 而容器往往不可点。第一版取「第一个 isHittable 的任意元素」，
    /// 结果拿到容器，点下去什么都没发生 —— 用例失败的原因与产品无关。
    private func tappable(prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        // 顺序：button → cell → 任意。同一个 identifier 会同时挂在按钮、
        // 承载它的 cell 和更外层的容器上，而它们的可点性并不一致 ——
        // SwiftUI 把 `Button` 放进 `List` 时，可点的那个有时是 cell 不是 button。
        for query in [app.buttons.matching(predicate),
                      app.cells.matching(predicate),
                      app.descendants(matching: .any).matching(predicate)] {
            let all = query.allElementsBoundByIndex
            if let hit = all.first(where: { $0.isHittable }) { return hit }
            if let first = all.first { return first }
        }
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// 点一个元素。不可点时退回坐标点击。
    ///
    /// `isHittable == false` 不一定意味着「点不到」—— SwiftUI 里一个被
    /// `accessibilityElement(children: .combine)` 合并过的容器经常报 false，
    /// 但它的中心点确实落在可交互区域上。直接 `tap()` 那时会抛错。
    private func tapElement(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "要点的元素不存在", file: file, line: line)
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// 点一下，等目标出现；没出现就**再点一次**。
    ///
    /// 冷启动后的第一次点击有时会落在「界面已经画出来、但还没开始接受事件」的
    /// 窗口里 —— 元素查询看得见它，点下去却没有反应。这是 XCUITest 的已知行为，
    /// 不是产品缺陷。**只重试一次**：真正的产品缺陷不会因为多点一下就好。
    @discardableResult
    private func tapUntil(_ target: XCUIElement, tapping element: @autoclosure () -> XCUIElement,
                          timeout: TimeInterval = 8) -> Bool {
        tapElement(element())
        if target.waitForExistence(timeout: timeout) { return true }
        tapElement(element())
        return target.waitForExistence(timeout: timeout)
    }

    /// 在可滚动容器里向下找一个元素。
    ///
    /// SwiftUI 的 `Form` / `List` 是惰性的：**屏幕外的行根本不在无障碍树里**。
    /// 直接 `waitForExistence` 会在「元素存在但要滚动才看得到」时失败，
    /// 而那不是产品缺陷。
    @discardableResult
    private func scrollTo(_ identifier: String, maxSwipes: Int = 8) -> XCUIElement {
        let target = element(identifier)
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { return target }
            app.swipeUp()
        }
        return target
    }

    /// 从首页进搜索页并返回搜索框。
    ///
    /// 与 `openNewFolderSheet` 同一个理由：真机上「点了没反应」是常态而不是例外，
    /// 尤其在刚刚发生过一次大改动（比如删掉一个文件夹、整页从列表变成空状态）之后 ——
    /// 那一刻 SwiftUI 正在重建视图树，第一次点击会落进去。
    /// 用 `tapUntil` 而不是「等 8 秒再断言」：等更久只会让失败来得更慢。
    @discardableResult
    private func openSearch(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let button = app.buttons["notes.search"]
        wait(button, 8, "首页应当有搜索入口", file: file, line: line)
        let field = app.searchFields.firstMatch
        if !tapUntil(field, tapping: button, timeout: 8) {
            XCTFail("点搜索之后没有出现搜索框。当前界面：\n\(app.debugDescription)",
                    file: file, line: line)
        }
        field.tap()
        return field
    }

    /// 打开笔记页的文件夹选择器，并点进「新建文件夹…」。
    ///
    /// 单独抽出来是因为它在真机上**间歇性失败**：`picker.tap()` 打开的是一个
    /// Menu，`waitForExistence` 能看见「新建文件夹…」，但等到真的去点的时候
    /// 那一帧的元素已经失效（真机上菜单动画比模拟器慢）。
    /// 报错是 `No matches found`，看起来像功能没了 —— 其实只是慢了一拍。
    ///
    /// `tapUntil` 就是为这种情况准备的：点一下，等目标，没等到就**再点一次**。
    /// 只重试一次 —— 真正的产品缺陷不会因为多点一下就好。
    private func openNewFolderSheet(file: StaticString = #filePath, line: UInt = #line) {
        let picker = app.buttons["note.folderPicker"]
        wait(picker, 8, "笔记页导航栏应当有文件夹选择器", file: file, line: line)
        let nameField = app.textFields["folder.name"]
        let newFolder = app.buttons["新建文件夹…"]
        picker.tap()
        wait(newFolder, 6, "选择器里应当有「新建文件夹…」", file: file, line: line)
        if tapUntil(nameField, tapping: newFolder, timeout: 6) { return }
        // 菜单可能已经关掉了 —— 重开一次再点。
        picker.tap()
        wait(newFolder, 6, "重开选择器后应当仍有「新建文件夹…」", file: file, line: line)
        tapUntil(nameField, tapping: newFolder, timeout: 6)
        XCTAssertTrue(nameField.waitForExistence(timeout: 6),
                      "新建文件夹表单应当出现。当前界面：\n\(app.debugDescription)",
                      file: file, line: line)
    }

    /// 新建一条笔记并写入标题与一段正文，返回标题。
    ///
    /// 正文用**随机 token**：搜索用例要能证明「搜到的是这一条」，
    /// 而固定字符串在多次运行之间会互相干扰。
    @discardableResult
    private func composeNote(title: String, body: String) -> String {
        let compose = app.buttons["notes.compose"]
        wait(compose, 8, "首页的新建按钮应当存在")
        compose.tap()

        let titleField = app.textFields["note.title"]
        wait(titleField, 8, "笔记页应当有标题输入框")
        titleField.tap()
        titleField.typeText(title)

        // 末尾那个空文字块（§3.5「进入即可写」）。它是 UITextView，
        // 在 XCUITest 里是 textView 而不是 textField。
        let editor = app.textViews.firstMatch
        if editor.waitForExistence(timeout: 4) {
            editor.tap()
            editor.typeText(body)
        }
        return title
    }

    private func goBack() {
        // 返回按钮没有稳定 identifier（系统生成），用导航栏的第一个按钮。
        let back = app.navigationBars.buttons.element(boundBy: 0)
        wait(back, 5, "导航栏应当有返回按钮")
        back.tap()
    }

    /// 一路退回首页，**按结果判断而不是按次数**。
    ///
    /// 单独一个 `goBack()` 在搜索页上不够可靠：键盘起来的时候第一次点可能只是
    /// 清空输入框，人看不出区别，而下一步「首页应该有 chip 行」会以一个
    /// 完全不相关的理由失败（实测就是这么浪费掉一轮的）。
    /// 所以这里退到**看见首页的新建按钮**为止。
    private func returnToNoteList(maxTaps: Int = 3) {
        let home = app.buttons["notes.compose"]
        for _ in 0..<maxTaps {
            if home.waitForExistence(timeout: 3) { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }
        XCTAssertTrue(home.waitForExistence(timeout: 5),
                      "点了 \(maxTaps) 次返回仍然没回到首页。当前界面：\n\(app.debugDescription)")
    }

    // MARK: Core Flow 1 —— 新建 → 持久化 → 搜索 → 打开结果

    func testCoreFlow1_createSearchAndOpen() {
        launch()
        let token = "ZebraQuokka\(Int.random(in: 10_000...99_999))"
        composeNote(title: "会议纪要 \(token)", body: "本周确定了排期与分工 \(token)")
        goBack()

        // 回到首页后列表里应当有这条笔记。
        let list = app.collectionViews["notes.list"].exists
            ? app.collectionViews["notes.list"] : app.tables["notes.list"]
        wait(list, 8, "首页应当出现笔记列表")

        app.buttons["notes.search"].tap()
        let search = app.searchFields.firstMatch
        wait(search, 8, "搜索页应当有搜索框")
        search.tap()
        search.typeText(token)

        // 结果行的 identifier 带 noteID，所以用前缀匹配找到「某一条结果」。
        let anyResult = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'"))
            .firstMatch
        wait(anyResult, 12, "搜索应当返回刚创建的笔记")
        tapElement(tappable(prefix: "search.result."))

        // 打开的必须是**那一条** —— 标题里带着随机 token。
        let titleField = app.textFields["note.title"]
        wait(titleField, 8, "点结果应当进入笔记页")
        let value = (titleField.value as? String) ?? ""
        XCTAssertTrue(value.contains(token),
                      "打开的笔记标题应当含 \(token)，实际是「\(value)」")
    }

    // MARK: Core Flow 2 —— 编辑 → 重启 → 内容还在

    func testCoreFlow2_editSurvivesRestart() {
        launch()
        let token = "PersistTest\(Int.random(in: 10_000...99_999))"
        composeNote(title: token, body: "第一次写的内容")
        goBack()

        // **不 reset 地重启** —— 这条用例的全部意义就在这里。
        app.terminate()
        launch(reset: false)

        let anyRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'notes.rowTitle.'"))
            .firstMatch
        wait(anyRow, 12, "重启后首页应当仍然有那条笔记")

        let titleField = app.textFields["note.title"]
        if !tapUntil(titleField, tapping: tappable(prefix: "notes.rowTitle."), timeout: 8) {
            // 失败时把无障碍树打出来。没有它就只能靠猜「点到了什么」，
            // 而 UI 测试最贵的成本就是猜。
            XCTFail("点了笔记行之后没有进入笔记页。当前界面：\n\(app.debugDescription)")
            return
        }
        let value = (titleField.value as? String) ?? ""
        XCTAssertTrue(value.contains(token), "重启后标题应当还是「\(token)」，实际是「\(value)」")
    }

    // MARK: Core Flow 3 —— 删除之后搜不到

    func testCoreFlow3_deletedNoteIsNotSearchable() {
        launch()
        let token = "DeleteMe\(Int.random(in: 10_000...99_999))"
        composeNote(title: "临时笔记 \(token)", body: "这条马上会被删掉 \(token)")

        // 在笔记页的 `⋯` 菜单里删除（§3.3：低频动作的唯一收口）。
        app.buttons["note.more"].tap()
        let deleteItem = app.buttons["删除笔记"]
        wait(deleteItem, 5, "⋯ 菜单里应当有「删除笔记」")
        deleteItem.tap()
        let confirm = app.buttons["删除"]
        wait(confirm, 5, "删除应当有二次确认")
        confirm.tap()

        // 删除后回到首页，再搜索，必须搜不到。
        app.buttons["notes.search"].tap()
        let search = app.searchFields.firstMatch
        wait(search, 8)
        search.tap()
        search.typeText(token)

        let resultRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'"))
            .firstMatch
        // 给检索一点时间真的跑完（250ms 防抖 + 索引），再断言它**没有**结果。
        // 直接断言不存在会在还没跑完时误判通过。
        XCTAssertFalse(resultRow.waitForExistence(timeout: 8),
                       "已删除的笔记不应再出现在搜索结果里")
    }

    // MARK: Core Flow 4 —— 空状态

    func testCoreFlow4_emptyStateOnFirstLaunch() {
        launch()
        wait(element("notes.empty.all"), 12,
             "全新安装的首页应当显示空状态引导，而不是一片空白")
        // 空状态下新建入口必须仍然可达 —— 否则用户没有出路。
        XCTAssertTrue(app.buttons["notes.compose"].exists, "空状态下仍要能新建")
    }

    // MARK: Core Flow 5 —— 设置分层与 iCloud 状态不说谎

    func testCoreFlow5_settingsAdvancedAndHonestICloud() {
        launch()
        app.buttons["notes.settings"].tap()
        wait(element("settings.advanced"), 10, "设置第一屏应当有「高级」入口")

        // 第一屏**不**放低频项（v2 §6 的分层）。
        XCTAssertFalse(element("settings.search.keywordOnly").exists,
                       "搜索方式说明属于「高级」，不该在第一屏")

        element("settings.advanced").tap()

        // 搜索：`PRODUCTION_RETRIEVAL = KEYWORD` 之下，「智能搜索」那一整段
        // （Embedding 模型 / 维度 / Base URL / 云端同意开关）**不该出现** ——
        // 它们对搜索行为没有任何影响，而那个开关还要用户授权一次数据外发。
        // 与 iCloud 同一条原则：不给必然无效的开关。
        wait(element("settings.search.keywordOnly"), 10,
             "纯词法生产下高级页应当据实说明「搜索方式：关键词」")
        XCTAssertFalse(element("settings.cloudSearchConsent").exists,
                       "这一版不跑语义路，云端搜索同意开关不该存在 —— 那是个开了也没用的开关")

        // iCloud：这个构建没有 CloudKit 能力（entitlements 是空的），
        // 所以必须**不给开关**，而是明说不提供。它在高级页靠下，要滚过去。
        scrollTo("settings.icloud.unavailable")
        wait(element("settings.icloud.unavailable"), 8,
             "没有 CloudKit 能力时必须显示「此版本不提供」，而不是一个必然失败的开关")
        XCTAssertFalse(app.switches["启用 iCloud 同步"].exists,
                       "不可用时不该出现 iCloud 开关 —— 那是个陷阱")
    }

    // MARK: Core Flow 6 —— 删掉文件夹之后，里面的笔记也搜不到（D1 端到端）

    /// # 这条走的是 derived 数据最容易漏的那条路
    ///
    /// 删笔记有 cascade，删**文件夹**没有 —— derived 数据在另一个 container 里，
    /// 没有任何 cascade 能到达它。漏掉的后果不是「多占点磁盘」，
    /// 而是**已删除的笔记继续占 topK 名额**：搜索返回一条点进去是空的结果。
    ///
    /// 单测层面有 `DerivedCleanupTests` 守着，但那是在内核上验的。
    /// 这一条从用户的手指开始：建笔记 → 建文件夹 → 删文件夹 → 搜索。
    /// **它在真机上跑** —— 上一个只在真机上现形的缺陷是删笔记直接 crash。
    func testCoreFlow6_deletingAFolderAlsoRemovesItsNotesFromSearch() {
        launch()
        let token = "FolderPurge\(Int.random(in: 10_000...99_999))"
        composeNote(title: "归档笔记 \(token)", body: "这条笔记属于一个马上会被删掉的文件夹 \(token)")

        // 在笔记页把它放进一个新建的文件夹。
        openNewFolderSheet()

        // **按 identifier 定位，不用 `textFields.firstMatch`** —— 那会命中
        // sheet 背后笔记页的标题框（它存在但不可点），错误信息是
        // 「not hittable」，与真正的问题差得很远。
        let nameField = app.textFields["folder.name"]
        wait(nameField, 8, "新建文件夹表单应当有名称输入框")
        nameField.tap()
        nameField.typeText("Purge\(token)")
        let save = app.buttons["folder.save"]
        wait(save, 5, "新建文件夹表单应当有保存入口")
        save.tap()

        returnToNoteList()

        // 先确认**删之前搜得到** —— 否则下面那条断言可能只是因为它从来就没被索引。
        let search = openSearch()
        search.typeText(token)
        let hit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'"))
            .firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 12),
                      "前置：删文件夹之前这条笔记必须搜得到")
        returnToNoteList()

        // 进文件夹管理页，滑动删除那个文件夹（会连带删掉里面的笔记）。
        let manageChip = app.buttons["notes.chip.manage"]
        if !manageChip.waitForExistence(timeout: 8) {
            // chip 行只在**有用户文件夹**时出现（v2 §2.2）。找不到它通常意味着
            // 上面那个文件夹压根没建成，而不是 chip 行的问题 —— 把树打出来，
            // 否则只能靠猜。
            XCTFail("chip 行末尾应当有进管理页的 ⋯。当前界面：\n\(app.debugDescription)")
            return
        }
        manageChip.tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'folders.row.'"))
            .firstMatch
        wait(row, 8, "管理页应当列出刚建的文件夹")

        // 左滑露出删除。**滑的是 cell，不是行内容** —— `swipeActions` 挂在
        // `List` 的行上，滑行内容本身在部分 iOS 版本上不触发。
        let cell = app.cells.firstMatch.exists ? app.cells.firstMatch : row
        cell.swipeLeft()

        // 优先按 identifier 找；`swipeActions` 里的 Button 在部分 iOS 版本上
        // 拿不到 identifier，所以留一条按文案的退路（这一处文案是稳定的系统级动作词）。
        let byID = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'folders.delete.'"))
            .firstMatch
        let deleteButton = byID.waitForExistence(timeout: 3) ? byID : app.buttons["删除"].firstMatch
        if !deleteButton.waitForExistence(timeout: 5) {
            XCTFail("左滑应当露出删除。当前界面：\n\(app.debugDescription)")
            return
        }
        deleteButton.tap()
        // `.firstMatch`：alert 的按钮在无障碍树里会出现不止一处（alert 本身 +
        // 它的容器），直接用 query 会报 "Multiple matching elements found"。
        let confirm = app.buttons["folders.confirmDelete"].firstMatch
        wait(confirm, 5, "删除文件夹应当有二次确认")
        confirm.tap()

        returnToNoteList()

        // 再搜一次：不该再有结果。
        let search2 = openSearch()
        search2.typeText(token)
        let stale = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'"))
            .firstMatch
        // 给检索真的跑完的时间再断言「没有」—— 直接断言不存在会在还没跑完时误判通过。
        XCTAssertFalse(stale.waitForExistence(timeout: 10),
                       "删掉文件夹之后，里面的笔记不该还留在搜索结果里")
    }

    // MARK: Core Flow 7 —— 大字号 + 深色下，核心操作仍然够得着

    /// # 「视觉正常」这件事怎么才算测过
    ///
    /// 截图对比在这个阶段没有意义（没有基线，而且换一版 iOS 就全红）。
    /// 但**排版塌掉的可观察后果是稳定的**：控件被挤出屏幕、被别的东西盖住、
    /// 或者缩到点不着。所以这一条不比像素，只问一句 ——
    /// **在最大的无障碍字号 + 深色下，核心路径上的每个控件还点得着吗。**
    ///
    /// 它同时覆盖长标题与中英混排的换行：标题用的是一个又长又中英混排的串，
    /// 塌了的话下面那些控件就够不着了。
    ///
    /// 两个 launch argument 是 UIKit 的标准覆盖开关，不需要 App 侧配合。
    func testCoreFlow7_accessibilityTextSizeAndDarkModeKeepControlsReachable() {
        launch(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
            "-UIUserInterfaceStyle", "Dark"
        ])

        // 首页：三个入口都要在。空状态下尤其容易被大字号的引导文案顶下去。
        wait(app.buttons["notes.compose"], 12, "大字号下首页仍要有新建入口")
        XCTAssertTrue(app.buttons["notes.compose"].isHittable, "新建按钮要点得着，不能只是存在")
        XCTAssertTrue(app.buttons["notes.search"].isHittable, "搜索入口要点得着")
        XCTAssertTrue(app.buttons["notes.settings"].isHittable, "设置入口要点得着")

        // 长标题 + 中英混排：两种换行规则在同一行里。
        let token = "A11y\(Int.random(in: 10_000...99_999))"
        composeNote(title: "二〇二六年秋季学期 CS5330 Pattern Recognition 期末项目排期与分工 \(token)",
                    body: "会上确定了 milestone 与 deliverable 的时间点 \(token)")

        // 笔记页：导航栏三件套 + 底部插入工具条都要还在、还点得着。
        // 大字号最先压垮的就是这两条 —— 它们一个在顶一个在底。
        XCTAssertTrue(app.buttons["note.folderPicker"].isHittable, "大字号下文件夹选择器仍要点得着")
        XCTAssertTrue(app.buttons["note.more"].isHittable, "大字号下 ⋯ 仍要点得着")
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.isHittable, "长标题不该把输入框自己挤出屏幕")

        returnToNoteList()

        // 搜索：大字号下结果行仍然可达，落点仍然对。
        let search = openSearch()
        search.typeText(token)
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'"))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 12), "大字号下仍要搜得到")
        tapElement(tappable(prefix: "search.result."))
        wait(app.textFields["note.title"], 8, "大字号下点结果仍要能进笔记页")
    }

    // MARK: Core Flow 8 —— 设置页输入完成后键盘收起（R1）

    /// # 判据是「键盘真的不在了」，不是「状态变量为 nil」
    ///
    /// XCUITest 里判断键盘在不在，可靠的做法是看 `app.keyboards` ——
    /// 它反映的是**系统键盘窗口**，而不是 App 自己的焦点状态。
    /// 后者是 App 自己说的话，用它来验证 App 自己的行为等于什么都没验。
    ///
    /// 顺带验第二件事：**收起键盘 ≠ 取消输入。** 设置项是即时保存的，
    /// 点完「完成」之后值必须还在 —— 修键盘时改坏保存语义是很容易的。
    func testCoreFlow8_settingsKeyboardDismissesAfterEntry() {
        launch()
        app.buttons["notes.settings"].tap()
        wait(element("settings.advanced"), 10, "设置第一屏应当有「高级」入口")
        element("settings.advanced").tap()

        // 用「高级」页的模型名：**它在默认服务商下无条件存在**，
        // 不必先去动服务商 Picker（Picker 的展开方式随 iOS 版本变，
        // 用它当前置条件会让这条用例以一个与键盘无关的理由失败）。
        // 这一屏同时也是唯一带 `numberPad` 的一屏 —— 工具条正是为它存在的。
        let field = app.textFields["advanced.modelName"]
        wait(field, 10, "高级页应当有模型名输入框")
        field.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "点输入框应当弹出键盘")

        let typed = "kb\(Int.random(in: 10_000...99_999))"
        field.typeText(typed)

        // 「完成」：键盘工具条上的那个。它是唯一能覆盖所有键盘类型的退出路径
        // （`numberPad` 上没有 Return 键）。
        let done = app.buttons["keyboard.done"].firstMatch
        wait(done, 5, "键盘上方应当有「完成」")
        done.tap()

        // **键盘真的消失了。** `waitForNonExistence` 而不是 `!exists` ——
        // 收起是有动画的，立刻查会查到一个正在退场的键盘。
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 8),
                      "点「完成」之后键盘必须真的消失。当前界面：\n\(app.debugDescription)")

        // 值还在 —— **收起键盘 ≠ 取消输入**。设置项是即时保存的，
        // 修键盘时把保存语义改坏是很容易的，所以这一条必须一起断言。
        let value = (field.value as? String) ?? ""
        XCTAssertTrue(value.contains(typed),
                      "收起键盘不该丢掉刚输入的值，实际是「\(value)」")

        // 离开这一屏再回来，键盘不该自己弹出来（焦点在 onDisappear 被清掉）。
        goBack()
        wait(element("settings.advanced"), 8, "应当回到设置第一屏")
        element("settings.advanced").tap()
        wait(app.textFields["advanced.modelName"], 8, "应当再次进入高级页")
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 3),
                       "重新进入设置页时不该自动弹出键盘")
    }

    // MARK: Smoke —— 文件夹管理页可达且能新建

    func testSmoke_folderManagerReachable() {
        launch()
        // chip 行在没有用户文件夹时整行隐藏（§2.2），所以先建一个文件夹
        // 只能从笔记页的文件夹选择器进 —— 这里走另一条路：先建笔记再进选择器。
        composeNote(title: "SmokeNote", body: "内容")
        openNewFolderSheet()

        // 新建文件夹 sheet 出现即可 —— 这条是 smoke，不验证完整的创建流程。
        XCTAssertTrue(app.textFields["folder.name"].waitForExistence(timeout: 5),
                      "新建文件夹表单应当出现")
    }

}
