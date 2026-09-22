# 全道集振幅质量核查

目标是定位可复查的问题或分析限制，不是自动删道、传感器认证或地质判断。直接扫描原Dataset，保留原道索引、文件偏移和头标识；不先select重编号，不改源字节。

## 真实文件工作流

```sh
moon build --target js --release
node tools/segy.mjs create examples/create.json demo.sgy
node tools/segy.mjs qc demo.sgy examples/quality.json report.json
node tools/segy.mjs qc-csv demo.sgy examples/quality.json problems.csv
moon run examples/quality_check --target js
moon run examples/quality_check --target wasm-gc
```

输出必须是新路径；配置为JSON文件，不是内联JSON。两个QC命令在示例上正常完成、写报告、返回3（存在发现），批处理应显式接受该状态，不能当作输入错误。0表示启用的检查没有发现；2表示配置、结构或IO错误，没有完成报告。

纯MoonBit示例无需Node文件宿主，展示两组数据、不同道长度和采样间隔、振幅零道及阈值问题；正常执行打印 `issues` 是预期结果。

## 公共API

```moonbit
let report = dataset.quality_check(
  traces=[4, 1, 2], group_by="ensemble",
  dead_threshold=0.0, clip_threshold=1.5, weighted=false,
  max_details=256, max_groups=65536,
)
let json = report.to_json().stringify()
let csv = report.issues_csv()
```

函数可抛错。省略traces扫描全部；提供时必须非空、唯一且在原Dataset范围内，保留调用方顺序。source_trace_count是原Dataset道数；summary.traces是选中道数，不能把部分核查说成全文件已查。

分组为单个受支持的**原始有符号头字段**，如ensemble、field_record、inline。按选中道中首次出现顺序排列；first_trace仍是原始道号。原值0保持0，不猜缺省含义。rev0未标准化字段（如inline）明确拒绝。不做二维网格分组、空间聚类、坐标单位推断或CRS转换。

## 检查含义

| flags | 语义 |
|---|---|
| nonfinite_samples | 原始IEEE NaN或±Inf；完整数量和第一个样本下标 |
| integer_range_samples | 整数绝对值大于2^53，超过保守Double分析范围；不代表文件非法，也不是说这些数全部不能精确表示 |
| negative_weighting | 仅weighted=true时权重为负；不支持该转换 |
| weighting_range | 可转换原值经权重计算后非有限或非零值变零；完整数量和第一处位置 |
| dead_amplitude | 整道可分析，所有绝对振幅≤dead_threshold；非零常数道不因标准差为0就被判死道 |
| clip_threshold | 整道可分析，有绝对振幅≥clip_threshold；阈值0禁用，不表示设备确实饱和 |
| header_dead | 原始identification为2；与振幅死道独立统计 |

阈值须有限非负，包含等号；两种振幅标志可以同时成立。未知顶层QC参数拒绝，防止拼错后静默关闭检查。

标准依据：[SEG-Y rev2.0表3和附录E](https://seg.org/wp-content/uploads/2025/11/seg_y_rev2_0_mar2017.pdf)。规范道头字节169–170的N对应乘 `2^-N`，字节29–30标识码2表示声明死道；代码字节偏移从0开始。只显式应用该权重，不解析或应用进一步的传感器换能/标定。不同道可能没有共同物理单位，组合统计仅为数值汇总。未启用weighted时，不因未使用的负权重拒绝原始振幅分析。

整数范围检查先于缩放，与Trace::amplitude一致，不以“缩小后能装入Double”为由丢精度；原值仍可精确复制、以十进制字符串导出。权重使用Double因子，极大N导致因子下溢时不作扩展精度补救，非零结果丢失记为weighting_range。

## 统计口径与缺失

- 每道完整扫描；任何样本不可分析或权重不支持，则statistics为显式null，**整道**不纳入组合统计。不是剔除坏样本后假装整道有效。
- summary/groups中的traces、samples、problem_traces和原因数量覆盖完整选择。analyzed_traces/analyzed_samples给实际参与统计数量，差值即整道排除范围。
- dead_traces、clipped_traces、clipped_samples只统计整道可分析的数据；header_dead_traces始终按头统计。原因可重叠，不能相加当作唯一问题道数。
- 非有限、整数范围、权重数值范围按样本计数；negative_weighting_traces按道计数。第一处位置为原道零起点样本号，不存在时为null，不是0或单元素数组。
- 所有参与道的样本等权合并，长道贡献更多；不是各道均值再平均，也不按采样间隔给时间权重。不重采样，不把不同间隔拼成单一时间轴。
- 最小/最大道长和采样间隔保留，便于识别异构记录。没有可分析道时组合statistics为null，不输出NaN JSON、不补零。
- 峰值归一化在线总体矩与合并公式避免直接平方巨大原值。总体标准差除以N；归一化矩的理论范围用于限制舍入漂移。仍是Double近似，不是任意精度或近乎相消数据的精度保证。

## 定位、预算与CSV

默认保留256条**问题道**，max_details可0..100000。达到预算后仍继续完整扫描、分组和计数，设置details_truncated；按选择顺序保留，不是严重度排名。详情含原道号、头/样本字节偏移、sequence_line/file、field_record、ensemble；头标识可能重复，可靠定位用trace和offset。

groups完整保留，默认最多65536组，max_groups可1..100000；超限报错而非静默丢组。沿用256MiB文件、1000000道、累计16000000样本等限额。按道在线计算，不为分析创建整个文件的Double副本；不承诺恒定进程内存。

CSV仅导出保留的问题道，不含完整组汇总。不能分析时均值/RMS留空且statistics_available=false，flags给原因。空CSV可能来自max_details=0，不能替代JSON总体结果或作为通过证明。报告从不自动删改问题道。

## 独立验证

tools/verify-quality.py用struct独立打包大小端、rev0/1/2、ASCII/CP037、整数/IEEE、变长道和坏样本；另用segyio生成IBM/IEEE固定道。NumPy独立拼接可分析的完整道，计算统计和分组，不调用本库stats作为真值。struct覆盖不冒充segyio支持。

比较区分JSON数字/null/数组/布尔/字段集合，覆盖全排除、整数分析边界、权重、定位、异构间隔、截断和真实退出码。普通统计rtol=3e-10/atol=1e-12；非零极小值使用零绝对容差；结构/计数精确比较。合成数据不是实测地震勘测认证。
