# 来源、验证工具与样例

本库自身采用根目录MIT LICENSE。按公开格式独立实现MoonBit核心，
不绑定或复制segyio的C/Python实现；Node宿主只处理文件、参数和编译桥接。

| 外部来源 | 角色 | 许可证或使用边界 |
|---|---|---|
| [SEG-Y rev2.0规范](https://seg.org/wp-content/uploads/2025/11/seg_y_rev2_0_mar2017.pdf) | 字段、样本编码与结构约束 | 仅链接，不分发规范全文 |
| [segyio](https://github.com/equinor/segyio) | 1.9.14 独立文件读写验证 | 发行包声明LGPL-3.0-or-later；仅开发工具，不随源码包分发 |
| [NumPy](https://github.com/numpy/numpy/blob/main/LICENSE.txt) | 2.5.3 独立数值参考 | BSD-3-Clause |

2026-09-22核对上游项目许可证声明和本机1.9.14发行包METADATA；版本见tools/requirements.txt。
这里不把验证依赖的许可证改成MIT，也不声称表格替代依赖发行包完整许可。
将来若分发包含这些库的环境，需要另行处理其许可、版权及源码提供等要求。

CP037表与Python标准编码器逐字节核对；SEG-Y样例由examples/create.json
及验证脚本合成，不下载/分发油田、商业勘探或上游测试数据。
时间与坐标为合成字段，不代表真实采集设备或坐标系认证。
evidence仅保存检查与环境/散列结果；AI辅助开发保留真实作者。

QC示例/阈值与verify-quality.py的二进制样本亦为合成，非真实设备合格指标。
独立参考为struct/segyio生成器和NumPy矩统计；整道排除、共享明细额度与报告状态为本项目接口契约，详见QUALITY.md。
