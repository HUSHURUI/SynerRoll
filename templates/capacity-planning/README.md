# 容量规划风光荷历史数据模板

`electric-load-history-template.csv` 是可直接导入容量规划模块的风速、辐照度和电负荷示例模板：

- 覆盖 2026-01-01 至 2026-01-07，共 7 个完整自然日。
- 时间分辨率为 60 分钟，共 168 条记录。
- `timestamp` 使用 ISO 8601 本地时间。
- `electric_load_kw` 表示电负荷功率，单位为 kW。
- `wind_speed_m_s` 表示风速，单位为 m/s。
- `solar_irradiance_w_m2` 表示太阳辐照度，单位为 W/m²。

导入表单填写：

- 时区：`Asia/Shanghai`
- 分辨率：`60 分钟`
- 时间戳列：`timestamp`
- 电负荷对应的 CSV 数据列：`electric_load_kw`
- 风速对应的 CSV 数据列：`wind_speed_m_s`
- 辐照度对应的 CSV 数据列：`solar_irradiance_w_m2`
- 其他没有数据的边界不要勾选。

替换示例数值时必须保留表头；时间戳应严格递增，且每个自然日都应包含完整的 24 个点。
