# 九宫格主键区增大

用户认可参考豆包的 B 版比例后，追加要求：中间打字区仍偏小，应进一步增大，而不是只放大字母。

实现：左右功能列为字母键宽度的 75%，中央三列优先；竖屏九宫格默认主键触控行高 52 pt（Apple 键帽约 51 pt），底行 44 pt。纵向布局间隙 5 pt，加上 Apple 键帽内缩后的视觉间距约 6 pt；横向间隙 6 pt。九宫格主体从 206 增到 215 pt，新增 9 pt 留给主键。横屏仍使用 143 pt，高度百分比继续生效。左侧标点新增随主题变化的细分隔线，四个常用标点及滚动查找其余标点的行为保持。

以参考截图的 430 pt 宽度计，中央键帽约 87 × 51 pt；参考图中豆包约 85 × 46 pt。此比较只说明同宽静态几何，不代表真机误触率或输入速度。

中英切换仍在空格右侧；英文、数字、符号、并击和自定义布局沿用既有几何。设置页预览复用新布局并同步其纵横比。应用标识、词库、用户配置和输入事件路径不变。

交付：1.2.0 (70) TrollStore IPA，源码 `281f85c8607165ae48b92c15e726a5fd37f51cca`。

用户在云端排队期间提出本机构建，随后使用本机 Xcode 27.0 (27A266a)、iOS 27 SDK 完成构建，最低部署版本仍为 iOS 17.0。本次验收依据为本机构建与测试；不声称远端 CI 通过。

验证：共享模块 90 项、打包 23 项、发布配置 5 项 / 22 断言通过；iOS 27 模拟器宿主执行 293 项，288 项通过、5 项沿既有条件跳过、0 失败。新增窄屏、正常竖屏、横屏及 100–130% 高度边界/重叠检查通过；实际宿主放大后的点击区域、语言切换后恢复、竖屏四个标点可见性通过。既有候选选择、直接标点、Buffer 与导入九键回归通过。

已查看实际 UIKit 宿主截图，竖屏中央键帽约 87 × 51 pt，窄屏和横屏主键区未出现重叠。截图位于 `.build/ios-trollstore/selected-evidence-build70-local/`；它们不含系统底部地球/麦克风安全区，不等同 iOS 17 第三方 App 内真机截图。

安装包：`.build/ios-trollstore/output/XSIME-1.2.0-70-TrollStore.ipa`。打包后重新解包验证 App / 扩展均为 1.2.0 (70)、最低 iOS 17.0、兼容标识与共享组权限保持不变、两者签名校验通过。SHA-256：`0139efdc9ae5318305b32ca68f4e6011db9f9655ac01162004fefc61c4c81498`。同目录保留 source、verification 和 sha256 记录，旧包保留。

[CI 40708996290](https://github.com/zhuxian89/xsime/actions/runs/40708996290) 等待 15 分钟后失败，job 从未执行任何步骤。GitHub 原因：`The job was not acquired by Runner of type hosted even after multiple attempts`，同时提示 macOS arm64 runner 容量不足。没有把它记录成源码或测试失败，也没有为等待机器而重试工作流。

本机构建环境可复用：CMake 4.1.2 安装在 `.build/ios-local/tools/`，依赖在 `Vendor/ios-build/`，原生库在 `Vendor/Rime.xcframework/`。命令只为当前进程设置 Xcode，不修改系统 `xcode-select`：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
PATH="$PWD/.build/ios-local/tools/bin:$PATH" platforms/ios/scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer platforms/ios/scripts/test-simulator.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project platforms/ios/RIMES.xcodeproj -scheme RIMES -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath platforms/ios/build/DeviceDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

本机日志位于 `.build/ios-local/`。标准构建脚本会生成 Xcode 工程和第三方声明，源记录注明这些生成输入；交付后已恢复其工作区差异，没有夹带无关生成文件改动。

iOS 17 真机手感待用户确认。
