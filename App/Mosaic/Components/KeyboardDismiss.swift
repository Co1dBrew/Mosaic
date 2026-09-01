import SwiftUI

/// # 设置页的键盘收起
///
/// ## 它修的是什么
///
/// 设置里的每一个输入框（Base URL / 模型名 / API Key / STT …）在输入完成后
/// **键盘不会消失**。表单是 `Form`，输入框下面还有 Toggle 和按钮，
/// 于是用户要么盲点被键盘挡住的区域，要么退出这一屏 —— 两种都不是「完成输入」。
///
/// ## 为什么不用 `UIApplication.endEditing`
///
/// 那是一句到处能调、也到处被调的全局命令：它绕过 SwiftUI 的焦点系统，
/// 于是 `@FocusState` 与真实焦点会不一致，而不一致的那一刻没有任何报错。
/// 更实际的问题是它**不可组合** —— 每个 View 各自复制一遍，
/// 下一个新增的输入框一定会漏。
///
/// 这里用 `@FocusState` 的枚举绑定：焦点是**一个值**，
/// 「收起键盘」就是把它置 `nil`。谁持有这个值、谁能改它，都是显式的。
///
/// ## 三条退出路径，覆盖所有键盘类型
///
/// | 路径 | 靠什么 | 覆盖 |
/// |---|---|---|
/// | 键盘上的「完成」 | `ToolbarItemGroup(placement: .keyboard)` | **全部**，包括 `numberPad` 这种没有 Return 键的 |
/// | 软键盘的 Return | `.submitLabel(.done)` + `.onSubmit` | 单行文本 / URL / 密码 |
/// | 滑动列表 | `.scrollDismissesKeyboard(.interactively)` | 用户想看被挡住的内容时的自然动作 |
///
/// 三条都保留，是因为它们对应三种**不同的用户意图**，不是同一件事的三种写法：
/// 点「完成」是「我填好了」，按 Return 是「这一项填好了」，
/// 滑动是「我想看下面」。少任何一条都会在某个具体场景里卡住。
///
/// ## 键盘收起 ≠ 取消输入
///
/// 这个修饰符**不碰数据**。设置项全部是即时保存（`SettingsStore` 直接写
/// `UserDefaults` / Keychain），收起键盘只改焦点。
/// 在这里顺手做一次「提交」或「回滚」都会改变既有的保存语义。
extension View {

    /// 给一屏表单装上完整的键盘收起行为。
    ///
    /// - Parameter focus: 这一屏的焦点绑定。置 `nil` = 收起键盘。
    func settingsKeyboardDismissal<Field: Hashable>(
        focus: FocusState<Field?>.Binding
    ) -> some View {
        modifier(SettingsKeyboardDismissal(focus: focus))
    }
}

private struct SettingsKeyboardDismissal<Field: Hashable>: ViewModifier {
    @FocusState.Binding var focus: Field?

    func body(content: Content) -> some View {
        content
            // 用户想看被键盘挡住的内容时，滑动就收起 —— iOS 的默认手感。
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // **只在有焦点时才挂这一组。**
                // 无条件挂的话，`ToolbarItemGroup(placement: .keyboard)` 在某些
                // iOS 版本上会给没有输入框的界面也留出一条空工具条。
                if focus != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { focus = nil }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("keyboard.done")
                    }
                }
            }
            // 离开这一屏时清焦点。不清的话，返回后再进来键盘会「记得」上次的焦点，
            // 表现为一进设置页键盘就自己弹出来。
            .onDisappear { focus = nil }
    }
}
