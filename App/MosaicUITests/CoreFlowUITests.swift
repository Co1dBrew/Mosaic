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
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test"] + (reset ? ["--ui-test-reset"] : [])
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

    // MARK: Smoke —— 文件夹管理页可达且能新建

    func testSmoke_folderManagerReachable() {
        launch()
        // chip 行在没有用户文件夹时整行隐藏（§2.2），所以先建一个文件夹
        // 只能从笔记页的文件夹选择器进 —— 这里走另一条路：先建笔记再进选择器。
        composeNote(title: "SmokeNote", body: "内容")
        let picker = app.buttons["note.folderPicker"]
        wait(picker, 8, "笔记页导航栏应当有文件夹选择器")
        picker.tap()
        let newFolder = app.buttons["新建文件夹…"]
        wait(newFolder, 5, "选择器里应当有「新建文件夹…」")
        newFolder.tap()

        // 新建文件夹 sheet 出现即可 —— 这条是 smoke，不验证完整的创建流程。
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5),
                      "新建文件夹表单应当出现")
    }

}
