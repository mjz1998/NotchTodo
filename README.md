# NotchTodo

把 ClickUp 待办事项放进 MacBook 的刘海里：鼠标移到刘海即可查看、勾选完成、改名、切换状态、新建和删除任务。

> 无刘海的 Mac / 外接显示器会在菜单栏正中显示。

## 安装

1. 到 [Releases](https://github.com/mjz1998/NotchTodo/releases/latest) 下载 `NotchTodo.zip`，解压后把 `NotchTodo.app` 拖到「应用程序」。
2. 由于应用未经 Apple 公证，首次打开会被拦截，任选一种方式放行：
   - **系统设置 → 隐私与安全性**，在底部找到 NotchTodo，点「仍要打开」；或
   - 在终端执行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/NotchTodo.app
     ```
3. 打开后刘海会自动展开设置页，粘贴你的 ClickUp API Key 即可。

**系统要求：** macOS 13 及以上，Apple 芯片和 Intel 均可。

## 获取 ClickUp API Key

ClickUp → 左下角头像 → **Settings → Apps → API Token → Generate**，复制 `pk_` 开头的字符串。

Key 只保存在你本机的「钥匙串」中，应用只与 `api.clickup.com` 通信，不会上传到任何其他地方。

## 使用

| 操作 | 方式 |
|---|---|
| 展开 / 收起 | 鼠标移到刘海 / 移开 |
| 完成任务 | 点左侧圆圈 |
| 改名 | 双击任务名，回车保存，Esc 取消 |
| 切换状态 | 点右侧状态标签 |
| 新建任务 | 顶部输入框输入后回车 |
| 在 ClickUp 打开 / 删除 | 右键任务 |
| 固定展开 | 📌 按钮 |
| 设置 / 退出 | ⚙️ 按钮 |

只显示**分配给你的未关闭任务**，每 60 秒自动刷新。新建任务默认放进设置里填写的 List ID 对应清单（List ID 是清单网址中 `/li/` 后面的数字）。

**开机自启：** 系统设置 → 通用 → 登录项与扩展 → 「登录时打开」点 + 添加 NotchTodo。

## 从源码构建

需要 Xcode 15 及以上：

```bash
git clone https://github.com/mjz1998/NotchTodo.git
cd NotchTodo
swift run            # 直接运行
./build_app.sh       # 打包为 NotchTodo.app
```
