# 数据与参考

项目代码MIT。`examples/public/usgs-06c01-first300.seg` 是 US Geological Survey Data Series259公开数据06c01.seg的前300道，按上游元数据public domain提供并保留USGS署名。源字节范围和校验值见同目录SOURCE.json，原始采集不是本项目原创。当前源站HTTP403和节选缓存来源如实记录在docs/PUBLIC-USGS.md。

SEG-Y是已有行业格式。segyio1.9.14（LGPL-3.0）只作为独立验证工具安装，项目核心与Node宿主不链接、复制或在运行时调用segyio。NumPy/struct验证的是具体字节和数值，不产生行业认证。参考工具许可证由其上游发布物提供。
