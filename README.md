# NotchTodo —— 刘海里的 ClickUp 待办

## 环境
- macOS 13+（带刘海的 MacBook 效果最佳；无刘海屏幕会在菜单栏正中模拟一个）
- Xcode 15+ 或 Command Line Tools（`xcode-select --install`）

## 运行
```bash
cd NotchTodo
swift run                 # 快速试用
./build_app.sh            # 打包为 NotchTodo.app
mv NotchTodo.app /Applications/ && open /Applications/NotchTodo.app
```
开机自启：系统设置 → 通用 → 登录项 → 添加 NotchTodo.app

## 首次使用
启动后刘海会自动展开设置页，粘贴 ClickUp API Key（`pk_` 开头）→ 保存。
Key 仅存放在本机「钥匙串」，不会写入任何文件。

## 操作
| 操作 | 方式 |
|---|---|
| 展开 / 收起 | 鼠标移到刘海 / 移开 |
| 完成 / 取消完成 | 点左侧圆圈 |
| 改名 | 双击任务名，回车保存，Esc 取消 |
| 改状态 | 点右侧状态标签 |
| 新建 | 顶部输入框回车 |
| 打开 / 删除 | 右键任务 |
| 固定展开 | 📌 按钮 |

只显示**分配给你的未关闭任务**（含子任务），每 60 秒自动刷新。
