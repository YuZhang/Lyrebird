# Lyrebird（琴鸟）

Lyrebird 是一款原生 macOS Apple Music 录音工具。它通过 Core Audio Process Tap 获取 Apple Music 解码后的音频，自动识别当前歌曲、按曲目分轨，并将音频、封面和歌曲元数据保存为独立文件。

## 主要功能

- 自动识别歌曲名、歌手、专辑和封面。
- 自动分轨，只保存判定为完整的录音。
- 支持 ALAC 无损输出（24-bit）和 AAC（256 kbps）。
- 支持 44.1、48、88.2、96、176.4、192 kHz 输出采样率，实际结果取决于播放链路。
- 按“歌手 - 歌名”命名文件，重名时自动追加序号。
- 已有歌曲自动跳过，删除文件后会重新检查目录。
- 暂停播放时暂停写入，恢复同一首歌后续写原文件，不记录暂停空白。
- 支持采样率延迟识别、必要时自动回到开头重录。
- 菜单栏驻留，显示录制状态，关闭主窗口后仍可继续使用。
- 集中设置窗口、录音日志、权限与采集诊断。

## 系统要求

- macOS 13 或更高版本。
- 推荐使用 macOS 14.2 或更高版本，以使用 Core Audio Process Tap。
- Apple Music App。
- Xcode 或 Swift 命令行工具链，支持 Swift 5.9。
- 高解析录制需要相应的音源、网络缓冲和输出设备支持；USB DAC 可能需要单独设置输出格式。

旧版 macOS 可回退到 ScreenCaptureKit 音频捕获，但其行为与 Process Tap 不完全相同。

## 构建与安装

在项目根目录执行：

```bash
chmod +x setup_local_signing.sh build_app.sh
./setup_local_signing.sh
./build_app.sh
ditto dist/Lyrebird.app /Applications/Lyrebird.app
open /Applications/Lyrebird.app
```

构建产物：

- `dist/Lyrebird.app`
- `dist/Lyrebird.zip`

`setup_local_signing.sh` 会创建本地签名身份。使用固定的本地签名有助于升级应用后保留系统授权。`Signing/` 中的钥匙串、证书和密码不纳入 Git 版本控制；如果该目录不存在，构建脚本会退回到临时签名。

## 权限

根据系统和采集方式，首次使用时可能需要：

1. **自动化权限**：读取 Apple Music 当前歌曲、播放位置、时长和采样率，并控制播放、暂停及回卷。
2. **屏幕与系统音频录制权限**：用于 ScreenCaptureKit 回退路径，不保存屏幕画面。
3. **系统音频采集权限**：用于 Core Audio Process Tap。

如果授权后仍提示权限不足，请使用 Cmd＋Q 完全退出应用，再重新打开。也可在设置窗口运行“采集诊断”。

## 使用方法

1. 在“设置”中选择保存目录、编码格式和录制模式。
2. 点击录制按钮。即使 Apple Music 尚未播放，应用也会等待播放。
3. 自动模式下，应用识别歌曲后创建文件，并在歌曲完整结束时保存。
4. 播放中暂停只会暂停写入；恢复同一首歌后继续录制。
5. 切歌、停止播放或手动停止时，未达到完整条件的文件会被丢弃。
6. 点击菜单栏小鸟图标，可在主窗口关闭后继续打开录音面板。

### 高解析重录

“高解析重录”默认关闭，避免打断正常听歌。开启后，如果同一首歌的源采样率从较低值提升到高解析格式，应用会删除尚未完成的低采样率录音，并自动回到开头重录一次。

如果歌曲开始时采样率暂时未知，应用会等待有效信息；确认过晚时，也可能自动回到开头，避免生成错误格式或残缺文件。

### 音频 MIDI 设置

高解析录制不仅取决于编码设置，还取决于整条输出链路。可在 macOS“音频 MIDI 设置”中选择实际输出设备并设置其格式，例如 96,000 Hz 或 192,000 Hz。

如果输出设备只支持 48 kHz，生成更高采样率的文件也不会增加原始音频细节。

## 测试

运行全部单元测试：

```bash
swift test
```

当前测试覆盖编码、元数据、文件命名、去重、录制完整性、暂停相关时间处理、设置持久化和滚动文字等。

应用还提供真机诊断入口：

```bash
/Applications/Lyrebird.app/Contents/MacOS/Lyrebird \
  --run-automatic-format-probe \
  --diagnostic-output /tmp/lyrebird-format.txt

/Applications/Lyrebird.app/Contents/MacOS/Lyrebird \
  --run-viewmodel-pause-probe \
  --diagnostic-output /tmp/lyrebird-pause.txt

/Applications/Lyrebird.app/Contents/MacOS/Lyrebird \
  --run-output-directory-probe \
  --diagnostic-output /tmp/lyrebird-directory.txt

/Applications/Lyrebird.app/Contents/MacOS/Lyrebird \
  --run-waiting-probe \
  --diagnostic-output /tmp/lyrebird-waiting.txt
```

诊断会使用 Apple Music 播放、暂停或回卷，并在结束后暂停播放。请使用独立测试目录，避免与正式录音混淆。

## 项目结构

```text
Package.swift                     Swift Package 配置
Sources/MusicTrackRecorder/       应用、录音引擎、Apple Music 自动化和界面
Tests/MusicTrackRecorderTests/    单元测试
Resources/                        应用配置和图标资源
build_app.sh                      构建、签名和打包脚本
setup_local_signing.sh            本地签名配置脚本
generate_icon.py                  应用图标生成脚本
generate_menubar_icons.py         菜单栏小鸟帧图生成脚本
diagnostics/                      本地诊断产物（不纳入 Git）
dist/                             构建产物（不纳入 Git）
Signing/                          本地签名材料（不纳入 Git）
```

## 音质与格式说明

- 录制的是 Apple Music **解码后的音频流**，不是对原始商店文件的直接复制。
- ALAC 输出位深为 24-bit；这不代表源文件一定是 24-bit，也不保证 bit-perfect。
- AAC 是有损编码，界面显示其码率而不是固定 PCM 位深。
- 提高输出采样率或位深不会凭空增加音源细节。
- Apple Music 可能先使用较低格式快速起播，待网络和设备条件就绪后再切换到高解析格式。

## 使用边界

请仅在适用法律、版权要求及 Apple Music 服务条款允许的范围内使用本工具。不要用于未经授权的复制、分发或规避版权管理。
