# USGS公开道集节选与有出处的QC任务

本轮使用 USGS Data Series259 的 `06c01.seg` 前300道，来源是2006年路易斯安那近海数字Chirp调查。官方[数据说明](https://pubs.usgs.gov/ds/259/html/download.html)和[元数据](https://pubs.usgs.gov/ds/259/html/metadata.html)描述4-byte integer、25kHz采样和三个采集通道，并披露间歇零道问题。项目只定位原始振幅为零的道，不能仅据零值判断某一具体故障原因。

## 来源完整性与许可

随例子保存的是**明确截取的完整道边界前缀**，不是整个调查文件：原字节半开范围 `[0,975600)`，3600字节头+300×(240字节道头+750×4字节样本)。SHA-256 `bcaafd0f7e6d416a0552ab265cce2330810c3242c6ba265ee21fbdc39349b604`。全部字节保持不变，头中仍保留非标准版本字；没有补齐或造出缺少的后半文件。

该节选由先前下载到的8,073,216字节缓存前部提取，独立Python struct逐道检查所选范围全部完整。该较长缓存本身中途截断，未用于完整文件验收。9月27日重新请求源站（Range和普通GET）均返回HTTP403，故没有“新鲜整文件下载成功”的说法。`examples/public/SOURCE.json`保留两者长度、哈希和来源限制。附带小节选使本地复现不再依赖这次不可访问的源站。

上游元数据许可为public domain并请求署名USGS；此处保留 U.S. Geological Survey / Data Series259 及源URL，不将采集或原数据声明为本项目原创。项目代码MIT与公共数据来源分别说明。

## 可复现任务

```sh
moon build --target js --release
node examples/run-public-qc.mjs work/usgs-qc
```

输出目录须不存在。report.json/ issues.csv/manifest.json包含300道、225000样本的QC，按原始`trace_in_record`字段分成0/1/2三组各100道；36道为零振幅，保留原始道索引、道头和样本字节偏移。原样本没有删除、修改或自动判为设备坏道。CSV只列问题详情，必须与JSON报告一起读取，不能单凭空CSV推断整体合格。

也可运行 `node tools/segy.mjs qc examples/public/usgs-06c01-first300.seg examples/public/quality.json`。有发现时正常输出并退出3；格式/IO失败退出2。不提供阈值时不擅自判断削波。

## 显式兼容与默认拒绝

此文件在零基3500位置存`00 01`，与标准rev1.0的`01 00`不同。默认decode/parse_header仍拒绝。新增`legacy_revision_one=true`只允许在大端、没有rev2 sentinel、版本word恰好0x0001时，把后续布局明确按rev1解释；不接受其它未知版本。解释假设不表示文件满足标准。

FileHeader保留`raw_revision_word`与`assumed_legacy_revision_one`；JSON inspect/validate及QC的`format_assumptions`展示该假设。copy字节完全不变；select/window/convert继续保留该版本字和标志，重新以默认严格方式读取仍会拒绝，不会暗中修复文件或扩大兼容范围。validate检查所选解释下的结构和数值，不是标准合规认证。

## 独立检查

```sh
python -m pip install -r tools/requirements.txt
python tools/verify-public-usgs.py --evidence work/usgs-reference.json
```

Python struct/NumPy从原始大端int32独立读取225000个整数；MoonBit CSV逐值一致。segyio1.9.14另核对全部300道和转换选择输出，但其1.x接口暴露float32，不能把它当完整int32精度的唯一真值。总体/分组均值、RMS、标准差、36条零道及源偏移分别比较；默认拒绝、截断、未知版本及详情截断仍保持严格语义。报告只覆盖此节选，不能推广为全部USGS调查或所有厂商SEG-Y的通过证明。
