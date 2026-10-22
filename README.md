# 聆乐（LingYue）— iOS 本地音乐播放器

一款**以本地播放为主、架构上预留在线流媒体扩展点**的 iOS 音乐 App（SwiftUI 原生实现）。

- **本地播放**：从“文件”App 导入音频（mp3 / m4a / flac / wav / aiff 等），自动读取标题、歌手、专辑、封面、时长。
- **完整播放体验**：播放队列、上一首/下一首、随机、三种循环、进度拖动、音量、锁屏与控制中心 Now Playing 和远程控制、后台播放。
- **曲库组织**：歌曲 / 专辑 / 歌手三种视图、播放列表（可建、可加歌、可移除）、本地搜索。
- **预留在线**：通过 `MusicSource` 协议抽象音乐来源，以后接入在线流媒体无需改动播放器与界面（见下）。

---

## 目录结构

```
LingYue/
├── project.yml                     # XcodeGen 工程定义（生成 .xcodeproj）
├── .github/workflows/build-ipa.yml # GitHub Actions 云编译出 IPA
├── prototype/index.html            # 交互式设计原型（双击即可在浏览器打开）
├── scripts/make_icon.py            # App 图标生成脚本（PIL）
└── LingYue/                        # SwiftUI 源码
    ├── LingYueApp.swift
    ├── Models/       Song / Playlist / AlbumGroup / MusicSource(协议)
    ├── Services/     LocalLibrarySource / LibraryStore / PlayerManager / NowPlayingCenter
    ├── Views/        RootTabView / Library / Album / Playlist / Search / NowPlaying / MiniPlayer / Settings
    └── Assets.xcassets/
```

---

## 一、先看设计原型

直接双击打开 `prototype/index.html`，浏览器里即可交互试玩：

- 点击歌曲 → 底部出现迷你播放条
- 点击迷你播放条 → 打开全屏播放页
- 切换 歌曲/专辑/歌手、播放列表、搜索、设置 标签
- 播放页可切 播放/暂停、上一首/下一首、随机、循环

---

## 二、编译（Windows 没有 Xcode，用云编译）

### 方案 A：GitHub Actions 云编译（推荐，Windows 即可）

1. 把本目录推到你的 GitHub 仓库（默认 `main` 分支）。
2. 进入仓库 **Actions** → **Build LingYue IPA** → **Run workflow**（push 也会自动触发）。
3. 构建完成后在 Artifacts 下载 `LingYue-ipa.zip`，解压得到 **`LingYue.ipa`**。

> 工作流会用 GitHub 的 macOS 机器跑 XcodeGen 生成工程、编译出未签名的 `.ipa`，无需本机任何 macOS 环境。

### 方案 B：本机 Mac 编译

有 Mac 时可直接在 Xcode 中打开：

```bash
brew install xcodegen      # 若未装
cd LingYue
xcodegen generate          # 生成 LingYue.xcodeproj
open LingYue.xcodeproj     # 在 Xcode 中选真机签名运行/导出 IPA
```

> `.xcodeproj` 已加入 `.gitignore`，用 `project.yml` 重新生成即可，保证工程一致性。

---

## 三、用 Sideloadly 安装到 iPhone

你的电脑是 Windows + 已连 iPhone，流程如下（Sideloadly 会用你的 Apple ID 签名，**免费账号 7 天需重签**）：

1. 下载安装 [Sideloadly](https://sideloadly.io/)（你当前为 v0.71.1）。
2. iPhone 保持 USB 连接，确认 Sideloadly 左侧显示 `iPhone (...) @USB`。
3. 把上一步得到的 **`LingYue.ipa`** 拖进 Sideloadly 的 IPA 图标区域。
4. 填入你的 Apple ID（如 `a1023163347@gmail.com`）——勾选 **Advanced Options** 里 **"Bundle ID"** 可自定义（默认 `com.lingyue.app`，免费账号也够用）。
5. 点击 **Start**，按提示在 iPhone 上「设置 → 通用 → VPN 与设备管理」信任你的开发者证书。
6. 回到桌面打开 **聆乐**。

> 免费开发者账号签名的 App 有效期 **7 天**，过期后用 Sideloadly 重新点一次 Start 即可续签。
> 若要在多台设备上使用或长期免重签，可改用付费开发者账号或签名服务。

---

## 四、导入音乐到 App

1. 先在 iPhone 的「文件」App 里把 mp3/m4a/flac 等放到任意位置（如“我的 iPhone”）。
2. 打开聆乐 → 音乐库 → 右上角 **导入**。
3. 在文件选择器中多选音频，确认后自动拷入沙盒并读取元数据与封面。
4. 也可把整个文件夹放进「文件」App，App 启动时会自动扫描。

---

## 五、预留在线流媒体的扩展方式

`MusicSource` 协议就是扩展点（`LingYue/Models/MusicSource.swift`）：

```swift
protocol MusicSource {
    var kind: MusicSourceKind { get }
    func fetchSongs() async throws -> [Song]
    func resolveURL(for song: Song) -> URL   // 本地=文件URL，在线=播放地址
}
```

以后接在线源时，新增一个实现即可：

```swift
struct StreamingSource: MusicSource {
    var kind: MusicSourceKind = .streaming
    func fetchSongs() async throws -> [Song] { /* 拉取云端曲库 */ }
    func resolveURL(for song: Song) -> URL { URL(string: "https://cdn.xxx/\(song.id).m3u8")! }
}
```

然后在 `LingYueApp.swift` 里把 `LocalLibrarySource()` 换成 `StreamingSource()`，
播放器（基于 AVPlayer）、曲库、界面全部复用，无需改动。

---

## 六、注意事项

- 部署目标 **iOS 17.0+**（你的是 iPhone 18.7.10，满足）。
- 后台播放需在 `project.yml` 的 `info` 中已声明 `UIBackgroundModes: [audio]`，生成 Info.plist 时自动带上。
- 锁屏封面 / 远程控制基于 `MediaPlayer` 框架，已实现。
- 应用名显示为「聆乐」，Bundle ID 默认 `com.lingyue.app`，可在 `project.yml` 里修改后重新生成工程。
