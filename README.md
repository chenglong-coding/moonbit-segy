# MoonSEGY

评审/首次使用请先看[实际任务、替代方案与可运行证据](REVIEW.md)：读入SEG-Y，扫描头与道索引，按道集分组检查振幅/非有限值/分析范围，输出带原始道号与字节位置的问题清单，再由调用方筛选或导出。

MoonBit 原生 SEG-Y 文件交换、道筛选和原始振幅质量检查库。面向反射地震记录与道集数据，不是 miniSEED/SAC 工具、反演程序或地球物理结论生成器。头、样本编解码、索引、变换与分析全部在 MoonBit；Node 只负责文件和 CLI 参数。

`localreview/segy` 是尚未发布的本地模块。MIT；AI 辅助开发并保留真实作者。本地完成不等于远程 CI、注册表发布或正式比赛验收。原范围见 [SCOPE](docs/SCOPE.md)，实测边界见 [TESTING](docs/TESTING.md)。

## 本轮公开道集与兼容边界

已用USGS DS259的明确300道节选验证225000个原始int32样本、36条零道和三个通道分组。新增显式旧版版本字兼容选项；默认严格拒绝，开启后在报告保留解释假设，原字节不变。[PUBLIC-USGS](docs/PUBLIC-USGS.md)说明来源节选、源站当前HTTP403、公开许可与可离线复现流程。此方向作为旧IRC的替代候选，尚无正式仓库或获准换题结论。

## 支持能力

- 常用 rev0、rev1.0、受限 rev2.0；大/小端识别；ASCII 和 EBCDIC CP037；计数或 EndText 结束的扩展文本块。
- IBM32、IEEE32/64、有符号8/16/24/32/64位样本。int64 保持整数和原字节，不先变成 Double。
- 标准240字节道头，定长/变长扫描索引、原字节复制、未知普通头字节保留；受限 rev2 固定道支持扩展计数/采样间隔。
- 坐标/高程/时间标量，明确角度单位下的 DMS 解码；道选择、头值筛选、道集分组、样本窗口和样本码转换。
- 原始或显式权重振幅统计、RMS、总体标准差、死道/用户阈值裁剪检查；CSV、脚本无关 SVG 波形。
- 全道集/指定原始道号的QC：按头字段分组，原始字节位置、非有限/整数范围/权重问题定位，完整汇总与限额问题明细；JSON/CSV。

## 快速运行

需要 MoonBit 与 Node.js 24。当前固定工具链见`.moonbit-version`；0.2.0检查见docs/TESTING.md，旧0.1.0日志不当作当前版本结论。核心运行不需要 Python/segyio。

```sh
moon check --target all
moon test --target js
moon test --target wasm-gc
moon build --target js --release
node tools/segy.mjs create examples/create.json demo.sgy
node tools/segy.mjs validate demo.sgy
node tools/segy.mjs stats demo.sgy examples/stats.json
node tools/segy.mjs groups demo.sgy examples/groups.json
node tools/segy.mjs select demo.sgy examples/select.json selected.sgy
node tools/segy.mjs window demo.sgy examples/window.json window.sgy
node tools/segy.mjs csv demo.sgy examples/select.json samples.csv
node tools/segy.mjs svg demo.sgy examples/trace.json trace.svg
node tools/segy.mjs qc demo.sgy examples/quality.json
moon run examples/quality_check --target js
```

示例生成三道合成数据，包含两个同道集波形和一条零幅度道。输出必须是新路径，不覆盖既有文件；错误写 stderr、退出码2。SVG 必须显式选道，超过20000样本请先窗口，不用未经说明的降采样隐藏细节。
`qc` 示例故意包含零幅度道和阈值问题，正常输出报告后退出3；这不是命令崩溃。`qc`/`qc-csv` 无发现退出0，参数/结构/IO错误退出2。纯MoonBit示例正常退出并打印发现结果，可用JS/Wasm-GC运行。
单样本道使用可见圆点表示（包括零值），不虚构时间跨度；多样本道保持逐点折线。

普通命令形式为 `COMMAND INPUT [OPTIONS.json] [OUTPUT]`，选项是 **JSON 文件**；`create OPTIONS.json OUTPUT` 例外。读取报告默认打印 JSON，CSV/SVG 打印文本；二进制操作必须给 OUTPUT。

| 命令 | 选项/行为 |
|---|---|
| inspect / validate | 结构信息 / 另外遍历样本拒绝非有限 IEEE 值 |
| trace | `trace`，可选 `first`、`count`（每次最多100000）；含时间和头字段 |
| stats | `trace`，可选 `dead_threshold`、`clip_threshold`、`weighted` |
| groups / find | `field` / 再加 `minimum`、`maximum`，原始有符号字段闭区间 |
| coordinate | `trace`、`field`；可选 `degrees:true` 将显式角度单位转十进制度 |
| copy / select / filter | 精确复制 / `traces` / `field`、`minimum`、`maximum` |
| window / convert | `first`、`count` / `sample_code` |
| csv / svg | `traces` 数组 / `trace` |
| qc / qc-csv | 可选 `traces`、`group_by`、`dead_threshold`、`clip_threshold`、`weighted`、`max_details`、`max_groups`；见 [QC指南](docs/QUALITY.md) |

可用原始字段名：sequence_line、sequence_file、field_record、trace_in_record、source_point、ensemble、trace_in_ensemble、identification、offset、receiver_elevation、source_elevation、source_depth、elevation_scalar、coordinate_scalar、source_x/y、group_x/y、coordinate_units、delay_ms、weighting；rev1/2另有 cdp_x/y、inline、crossline、shotpoint、shotpoint_scalar、time_scalar。未列字段仍保留原字节，但不解释其语义。

所有读命令可用 `endian:"big"/"little"`、`text_encoding:"ASCII"/"EBCDIC"` 显式覆盖。覆盖端序不能与识别到的 rev2 标志冲突。自动文本检测是可报歧义的启发式，不把所有 EBCDIC 变种都当 CP037。

## 库 API 与数据语义

根包为纯 MoonBit。公共签名见 [pkg.generated.mbti](pkg.generated.mbti)。`parse_header` / `decode` 读取，`make_header` / `make_trace` / `create` 新建。`Dataset` 提供 trace_index、trace、select、find_traces、groups、window、convert_samples、csv 等；`Trace` 提供 sample、field、scaled_field、coordinate_degrees、time_seconds、statistics、svg。

```moonbit
let dataset = @segy.decode(bytes)
let selected = dataset.select(dataset.find_traces("ensemble", 10, 20))
let windowed = selected.window(2, 100)
let output = windowed.encode()
```

调用方需处理可抛出的错误。道和样本索引从0开始，代码中的字节偏移从0开始，规范表从1开始。采样间隔单位微秒；延迟头字段是带时间标量的毫秒；CSV/time_seconds 为相对震源时间的秒，不猜测绝对日期/时区。

`encode()` 原样返回不可变字节；select/window 重算结构计数，保留其他采集元数据。select 更新 sequence_file，原始 sequence_line、记录/道集标识保留。window 对每道用同一样本索引区间，不把短道悄悄补零。改变起点若不能由**既有时间标量**精确表达，就报错，不同时破坏其他 lag/mute 时间字段。

原始振幅不是物理标定值。`weighted:true` 仅应用 `2^(-weighting)`，不自动应用传感器换能系数。标量坐标保持声明的米/英尺/角单位；不从数值猜 CRS。clipped_samples 只表示超过用户阈值，dead 只表示幅度阈值意义上的平坦零道，不等价于设备损坏诊断。

`Dataset::quality_check` 能报告并继续扫描不可分析样本。任何样本不可可靠分析时，该整道统计为显式null，不进入分组/全局振幅汇总，完整原因与样本计数保留；不偷偷算有效子集均值。合并统计按样本数量加权，不按每道平均值或时间长度加权。完整64位原值与文件保持不变。CLI道号/头字段/预算必须为精确整数，不接受小数截断。

## 精度与明确限制

- `Sample::Signed(Int64)` 保存完整64位整数；转 Double 分析保守拒绝绝对值超过2^53。CLI 的整数样本使用十进制字符串输出；新建JSON大整数也必须使用字符串。
- IBM32 写入规范化、最近舍入（中点远离零）；浮点下溢至零/溢出报错，IEEE64 原字节复制不损精度。Float→Integer 只接受精确整数，不隐式截断。
- 非有限 IEEE 样本可结构读取和原字节复制，`validate`、逐道统计、样本CSV、SVG拒绝；QC会报告并继续扫描，不修改原样本。不能因 inspect 成功声称数值有效。
- 文件最大256 MiB，1000000道，单道1000000样本，合计16000000样本，1024扩展文本块，CSV1000000行；这些是数据限额，不承诺恒定内存。
- 不支持额外240字节道头、头布局重映射、二进制用户 stanza、pair-swapped、tape label、data trailer、rev2.1、无符号/过时定点样本码。未知布局明确拒绝，普通未解释头字节可保留。
- 不提供任意原始头的跨端序/跨版本重写，因为未知字段无法安全重排。可新建两种端序，现有文件的选择、窗口和样本格式转换保持原端序/版本。
- rev2 宽计数/非整数间隔仅支持固定道；变长道须能由标准16位样本数/间隔表达。rev2 新建版本为独立 major/minor 字节，读取兼容旧 little-endian uint16 写法。

## 复现验证

```sh
moon fmt --check
moon info
node tools/check-cli.mjs
python -m pip install -r tools/requirements.txt
python tools/verify-reference.py
python tools/verify-quality.py
```

增强前基线为13组测试、CLI16项、独立332场景/1171项，保留在 [reference.json](evidence/reference.json)。当前QC增强的源码绑定与复查结果见 [quality-20260922.json](evidence/quality-20260922.json) 和 [TESTING](docs/TESTING.md)，不以旧散列证明新代码。segyio 1.9.14不支持24位码7，且不能替代变长道/rev2完整验证：这些用独立 struct/CP037参考，绝不标成 segyio 通过。CI 已配置三系统，远程未执行。
SVG 的六类合成样本已在本机真实 Chromium 浏览器中检查，发现并修复单样本不可见问题；见 [图形输出核查](docs/SVG-REVIEW.md)。

依据：[SEG-Y rev2.0 原始规范](https://seg.org/wp-content/uploads/2025/11/seg_y_rev2_0_mar2017.pdf)、[segyio](https://segyio.readthedocs.io/)。CP037 数据表与 Python 独立编码器全256字节互核，非 Python 包装实现。复用本批自有二进制读取设计，未复制第三方库核心。

验证工具许可证和合成样例来源见 [SOURCES](docs/SOURCES.md)。

初始查重见五项目选型记录；2026-09-22刷新 MoonBit+SEG-Y/注册表网页/GitLink 索引未命中同向项目，不是全球不存在的证明。已有 miniSEED/SAC 项目不是本库的 SEG-Y 交换工作流。
