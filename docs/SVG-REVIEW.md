# SVG 图形输出核查

2026-09-22，Windows 11，Codex 内置 Chromium 浏览器。六类合成输入通过真实 `tools/segy.mjs create` / `svg` 路径生成，再在浏览器中打开；无真实采集或个人数据。

## 发现与修复

旧输出只含一个顶点的 polyline，XML 合法但没有可绘制线段。单个正值、负值和零值都只显示灰色零线，实际样本不可见。旧测试只确认 `<polyline` 存在或 XML 可解析，未覆盖视觉结果。

单样本现在增加半径4的蓝色圆点，与原采样时间位置和归一化纵坐标一致；不延伸一段不存在的时间或补造第二个采样。多样本仍输出原逐点折线。

## 实查范围

| 输入 | 浏览器结果 |
|---|---|
| `[0,1,2,1,0,-1,-2,-1,0]` | 正峰、负谷及端点正常 |
| 五个零值 | 可见蓝色水平波形 |
| 单个 `4` / `-4` / `0` | 分别为零线上方、下方、线上可见点 |
| `[-1e300,0,1e300]`，IEEE64 | 坐标有限，正常跨越零线 |

[修复前上半屏](../evidence/svg-browser/before-top.png) / [下半屏](../evidence/svg-browser/before-bottom.png)，
[修复后上半屏](../evidence/svg-browser/after-top.png) / [下半屏](../evidence/svg-browser/after-bottom.png)。
截图及输入/输出散列见 [机器记录](../evidence/svg-review-20260922.json)。截图是实际浏览器结果，不是自行绘制的预览。

## 回归与复现

`moon test operations_test.mbt --target js --filter '*single positive*'` 在修复前失败；修复后全库 JS/Wasm-GC 各13组通过。
`python tools/verify-reference.py` 增加独立XML几何断言：样本数、有限坐标、单点可见半径和正负位置、`t=0..0`，共332场景1171项；CLI16项仍通过。

可将 `examples/create.json` 中一条道改为 `{"samples":[4]}`，保留文件其他必需字段，再按 README 的 create/svg 命令写到新输出路径，用浏览器打开 SVG。

这只是六类合成样本的本机视觉核验，不代表所有浏览器、极小屏幕、所有仪器文件或正式赛事验收。没有增加脚本、网络请求、诊断解释或数据插值；未更改公共API。
