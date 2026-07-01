# LookAway

LookAway 是一个原生 macOS 菜单栏护眼提醒工具。它会在菜单栏显示当前倒计时，用轻量的视觉提醒让你把目光从屏幕移开一会儿。

默认节奏是 `20-20-20`：专注 20 分钟，休息 20 秒。你也可以切换到番茄钟、深度专注，或者保存自己的自定义节奏。
<img width="333" height="447" alt="image" src="https://github.com/user-attachments/assets/3e50fe55-8efa-41d7-97a2-5670c9830248" />
<img width="357" height="206" alt="image" src="https://github.com/user-attachments/assets/419c8e00-5608-4906-99b7-2f7df9788c61" />


## 功能

- 常驻 macOS 菜单栏，只显示倒计时
- 点击菜单栏可快速暂停、重置、跳到休息、打开设置或退出
- 支持 `20-20-20`、`番茄钟 25/5`、`深度专注 50/10` 和自定义节奏
- 自定义节奏可以命名，并在下次打开时保留
- 可设置专注和休息的时、分、秒
- 菜单栏倒计时支持完整和简约两种显示方式
- 休息提醒支持轻唤卡片（强提醒）和眨眼渐暗（弱提醒）两种样式
- 休息阶段使用正向计时，展示已经休息了多久
- 统计今日专注时长和今日休息时长
- 支持开机自启动
- 进度满后弹出休息提醒窗口

## 构建

```bash
cd LookAway
./build.sh
```

构建产物：

- `build/LookAway.app`
- `dist/LookAway.dmg`

## 运行

双击 `build/LookAway.app`，或把 DMG 里的 App 拖到 Applications 后运行。

因为这是本地未签名应用，首次打开时 macOS 可能会提示安全限制。可以在 Finder 里右键 App，选择“打开”。

## 说明

开机自启动使用用户级 `LaunchAgent` 实现。勾选后会写入：

```text
~/Library/LaunchAgents/local.lookaway.menubar.login.plist
```

取消勾选并保存后会删除这个文件。
