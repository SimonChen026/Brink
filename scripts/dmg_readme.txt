绝境 Brink — 安装说明

1. 把 Brink.app 拖进 Applications（应用程序）文件夹。

2. 第一次打开：这个版本没有经过 Apple 公证，macOS 会拦一下。
   · 在“应用程序”里右键 Brink → 打开 → 再点“打开”；
   · 如果没有“打开”按钮（macOS 15 以后）：先双击一次，再到 系统设置 → 隐私与安全性，
     在下面找到“仍要打开”；
   · 或者在终端里运行：xattr -dr com.apple.quarantine /Applications/Brink.app

3. API key：在 设置 → 大模型 里填。key 只存在本机的“钥匙串”里（项目名 “Brink — API keys”），
   不写进任何文件，显示和日志里都会打码，只通过 https 发给你选的服务商。
   更新到新版本后第一次用到 key 时，macOS 可能会问是否允许 Brink 读取钥匙串，点“始终允许”。
   不填 key 也能玩：其他角色由离线的基础人机扮演。

4. 你的数据：存档、对局记录、设置都在 ~/Library/Application Support/Brink/。
   对局时，场景内容和你写的话会发给你配置的大模型服务商；对局记录（包括私聊和日记）只存在本机。

5. 卸载：删除 Brink.app 和上面那个文件夹；在“钥匙串访问”里删掉 “Brink — API keys”。

需要 macOS 14 或更新版本，Apple 芯片或 Intel 都可以。

--------------------------------------------------------------------

Brink (绝境) — read me

1. Drag Brink.app into Applications.

2. First launch: this build isn't notarized by Apple, so macOS stops it once.
   · Right-click Brink in Applications → Open → Open;
   · if there's no Open button (macOS 15 and later): double-click it once, then go to
     System Settings → Privacy & Security and click "Open Anyway" near the bottom;
   · or run in Terminal: xattr -dr com.apple.quarantine /Applications/Brink.app

3. API keys: add them in Settings → AI models. Keys live only in this Mac's Keychain
   (item "Brink — API keys"), never in a file; they're masked on screen and in logs, and only
   sent over https to the provider you chose. After an update, macOS may ask whether Brink may
   use the Keychain item the first time a key is needed — choose "Always Allow".
   No keys? You can still play: offline basic bots play the other characters.

4. Your data: saves, game logs and settings are in ~/Library/Application Support/Brink/.
   During a game, the scenario text and what you write are sent to the AI providers you set up;
   game logs (whispers and diaries included) stay on this Mac.

5. To uninstall: delete Brink.app and that folder, and remove "Brink — API keys" in Keychain Access.

Requires macOS 14 or later, Apple silicon or Intel.
