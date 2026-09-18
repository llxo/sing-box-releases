# sing-box releases

[上游](https://github.com/reF1nd/sing-box)，移除了 provider 的 `tag/` 前缀，自动构建 `reF1nd-stable` 和 `reF1nd-testing` 分支的最新版本。

每个 Release 包含三个构建产物：

| 构建产物 | 平台 | 内容 |
| --- | --- | --- |
| [`SFA-<version>-arm64-v8a.apk`](https://github.com/reF1nd/sing-box-releases/releases) | Android arm64 | Sing-Box Android 客户端安装包（APK） |
| [`sing-box-<version>-android-arm64.zip`](https://github.com/reF1nd/sing-box-releases/releases) | Android arm64 | `sing-box` 命令行核心和 `LICENSE`（启用 eBPF） |
| [`sing-box-<version>-windows-amd64.zip`](https://github.com/reF1nd/sing-box-releases/releases) | Windows amd64 | `sing-box.exe`、`libcronet.dll` 和 `LICENSE` |
