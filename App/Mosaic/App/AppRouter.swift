import SwiftUI
import Observation
import MosaicKit

/// # 导航路由（`UI_REDESIGN.md` v2 §1.1）
///
/// ## 为什么需要它
///
/// v2 的首页要能推四个目的地（笔记 / 搜索 / 设置 / 文件夹管理）。第一版给每个
/// 目的地挂了一个 `.navigationDestination(isPresented:)` / `(item:)`，**实测只有
/// 一部分生效**：同一个视图上挂多个 destination 修饰符时后挂的会盖住先挂的，
/// 表现是「点设置能进去、点笔记行没反应」，而且没有任何编译期或运行期警告。
///
/// 收敛成**一条路径 + 一个 `navigationDestination(for:)`**：路由是数据，
/// 目的地只有一处声明。附带的好处是 UI 测试可以直接断言路径，而不必靠找控件。
enum AppRoute: Hashable {
    /// 笔记页。`anchor` 只有从搜索结果进来时才有 —— 平时进笔记既不滚动也不高亮。
    case note(card: Card, anchor: SearchAnchor?)
    case search
    case settings
    case advancedSettings
    case folders
}

@Observable
@MainActor
final class AppRouter {
    var path: [AppRoute] = []

    func push(_ route: AppRoute) { path.append(route) }

    func popToRoot() { path.removeAll() }

    /// 当前栈深。UI 测试用它判断「有没有真的推进去」，
    /// 比在屏幕上找一个可能还没渲染完的控件稳。
    var depth: Int { path.count }
}
