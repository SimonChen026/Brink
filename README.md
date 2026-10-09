# 绝境 Brink

一个 macOS 上的生存决策游戏。十场根据真实灾难改编的绝境：雪山空难、海上漂流、矿井透水、地震废墟、沙漠迷途、荒岛、南极越冬、洪水、冻雨封路、原始森林迷途，外加一个终章和新手教程。其他幸存者由大模型扮演（DeepSeek、Kimi、GLM、通义千问、豆包、OpenAI、Claude 等，也可以接任何兼容 OpenAI 接口的服务）。你可以亲自下场，也可以开着上帝视角看它们为了活下去互相较量。

*A survival decision game for macOS (Chinese and English). Ten scenarios based on real disasters, an hour-by-hour physiological simulation, a 3D scene for each, and AI models playing the other survivors.*

## 特点

- 每回合系统给出一个局面，所有人表态、分工、夜里私下行动（私聊、偷吃、动议）。
- 投票以外，还要互相照应：分口粮给孩子或快撑不住的人，冷的夜里挨着谁睡，户外的活结伴去；有人崩溃了，得有人陪他一天才能缓过来。
- 难度可选：普通、困难（默认）、绝境。困难下救援来得更晚，人会被一天天耗干，还会一件接一件地出岔子：用基础人机模拟，几乎没有人能活着出去（通关率在一成以下）。封面右上角和对局顶栏里的“难度”按钮随时可以调。
- 体温、脱水、饥饿、疲劳、伤病逐小时计算，按真实的生理数据。
- 每个场景都有程序化生成的 3D 现场，跟着局面变化。
- 无尽模式：五个玩家一关接一关地闯，攒经验、考资格证，最后是大结局。
- 中英双语。没有配置 API key 也能玩：其他角色由离线的基础人机扮演。

## 安装

从 [Releases](https://github.com/SimonChen026/Brink/releases) 下载最新的 `Brink-<版本>.dmg`，打开后把 Brink 拖进“应用程序”。需要 macOS 14 或更新版本，Apple 芯片和 Intel 都可以。

这个版本没有经过 Apple 公证，第一次打开时 macOS 会拦一下。放行的方法：

- 右键点 Brink → 打开；
- 或者到“系统设置 → 隐私与安全性”点“仍要打开”。

## 从源代码编译

需要 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
xcodegen generate          # 生成 Brink.xcodeproj
./scripts/build_app.sh     # 编译到 dist/Brink.app
./scripts/make_dmg.sh      # 打包成 dist/Brink-<版本>.dmg
swift test                 # 单元测试
```

## API key 的安全

- key 只存在 macOS 钥匙串里（条目 “Brink — API keys”），只在这台 Mac 上可读，不会同步到 iCloud。
- 不会写进任何文件，界面、错误信息和对局记录里都会打码。
- 只通过 https 发给你选的服务商（发给本机的除外，比如 Ollama）。网络请求不留磁盘缓存，也不存 cookie。
- 游戏不收集任何数据。对局时，场景内容和你写的话会发给你配置的大模型服务商；对局记录只存在本机（`~/Library/Application Support/Brink/`）。

## 许可证

[MIT](LICENSE)
