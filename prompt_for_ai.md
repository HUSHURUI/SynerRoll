# 仿真计算功能 - 问题说明与修改需求

## 一、背景

这是一个能源系统优化平台，有前端（Nuxt/Vue）和后端（Julia）。

**项目结构**：
- `backend/src/main.jl` - Julia 后端，负责解析项目 JSON 并生成 component.json 和 connection.json
- 前端通过 `/api/parse` POST 接口调用后端

---

## 二、已完成的修改（正确）

### layerConfigs 字段重命名

**目标**：将 layerConfigs 里的 `techParams` 改为 `paras`，`economicParams` 改为 `costs`

**修改后的代码**（main.jl 约 273-284 行）：
```julia
raw_layer_configs = get(business, "layerConfigs", Dict{String, Any}())
layer_configs = Dict{String, Any}()
for (layer_id, layer_data) in raw_layer_configs
    layer_configs[layer_id] = Dict{String, Any}(
        "layerId" => get(layer_data, "layerId", layer_id),
        "status" => get(layer_data, "status", "stand_alone"),
        "paras" => get(layer_data, "techParams", Dict{String, Any}()),        # ← 重命名
        "costs" => get(layer_data, "economicParams", Dict{String, Any}()),     # ← 重命名
        "constraints" => get(layer_data, "constraints", Dict{String, Any}()),
        "objectives" => get(layer_data, "objectives", Dict{String, Any}())
    )
end
```

---

## 三、待确认/修改的问题

### 问题 1：component.json 生成逻辑

**现状（可能有问题）**：
当前代码在 main.jl 约 471-477 行：
```julia
components = ComponentRecord[]
for node in nodes
    if !is_bus_node(node)
        comp = parse_non_bus_node(node)
        push!(components, comp)
    end
end
```

**疑问**：这个逻辑看起来只处理非总线节点，请确认：
- component.json 是否应该只包含非总线类节点（如 WT、PV、GRID 等）？
- 还是说应该包含所有节点包括总线节点？

---

### 问题 2：connection.json 生成逻辑（核心问题）

**期望的 connection.json 格式**：

```json
[
    {
        "busLabel": "电总线",
        "variables": ["E_WT_out_风机", "E_PV_out_光伏", "E_GRID_in_电网"]
    },
    {
        "busLabel": "热总线",
        "variables": ["Q_HT_out_锅炉"]
    },
    {
        "busLabel": "",
        "variables": ["E_GRID_out_电网", "E_LOAD_in_负荷"]
    }
]
```

**格式说明**：
- 如果 `busLabel` 为空字符串，表示这是一条普通二元连线（两个非总线节点之间的连接）
- 如果 `busLabel` 有值，表示这是总线连接，所有连接到这个总线的非总线节点变量都放在同一个 `variables` 数组里

**总线连接的变量名格式**：`{介质前缀}_{组件类型}_{方向}_{节点名称}`
- 介质前缀：electric→E, thermal→Q, gas→G, hydrogen→H, material→M, general→X
- 方向：out（出）/ in（入）
- 示例：E_WT_out_风机、Q_HT_in_锅炉、E_GRID_in_电网

**普通连线的变量名格式**：只有两个变量 [源变量, 目标变量]
- 示例：["E_GRID_out_电网", "E_LOAD_in_负荷"]

---

### 问题 3：当前 parse_bus_connections 函数的问题

当前 main.jl 约 311-415 行的 `parse_bus_connections` 函数逻辑可能存在问题：

1. **是否正确处理了总线侧和非总线侧的 handle 前缀？**
   - handle ID 格式可能包含 `bus-` 前缀（如 `bus-src`、`bus-tgt`）
   - 需要正确区分 `bus-` 前缀来判断方向

2. **是否正确生成了 variables 数组？**
   - 总线连接时，应该收集所有连接到同一个总线的非总线节点的变量名
   - 普通连线时，只有两个变量 [source_var, target_var]

3. **是否正确避免了重复处理同一条边？**

---

## 四、数据结构参考

### 节点数据结构（简化）

```json
{
  "id": "node-123",
  "categoryKey": "bus",           // "bus" 表示总线节点，其他为普通组件
  "data": {
    "componentKey": "",           // 总线节点为空
    "label": "电总线",
    "business": {
      "componentKey": "",
      "componentName": "电总线",
      "layerConfigs": { ... }
    },
    "portConfig": {               // 总线节点的端口配置
      "src1": { "medium": "electric" },
      "tgt1": { "medium": "electric" }
    }
  }
}
```

### 连线数据结构（简化）

```json
{
  "id": "edge-1",
  "source": "bus-node-id",        // 源节点 ID
  "target": "wt-node-id",         // 目标节点 ID
  "sourceHandle": "src1",         // 源端口（可能带 bus- 前缀）
  "targetHandle": "tgt1",         // 目标端口（可能带 bus- 前缀）
  "data": {
    "medium": "electric"          // 连线介质类型
  }
}
```

---

## 五、修改要求

请帮我修改 `backend/src/main.jl` 中的：

1. **component.json 生成逻辑**（如果有问题的话）
2. **connection.json 生成逻辑** - 特别是 `parse_bus_connections` 函数，确保：
   - 正确处理 handle ID 中的 `bus-` 前缀
   - 正确判断方向（总线是源→out，总线是目标→in）
   - 正确分组：同一个总线的所有非总线节点变量放在一条记录里
   - 正确处理普通二元连线（busLabel 为空）

---

## 六、其他辅助函数（可能有用）

```julia
# 判断节点是否为总线
is_bus_node(node) = get(node, "categoryKey", "") == "bus"

# 判断 handle 是否为总线侧（包含 bus- 前缀）
is_handle_at_bus_side(handle_id::String) = occursin("bus-", handle_id)

# 去掉 handle 后缀（-src, -tgt）
function strip_handle_suffix(handle_id::String)::String
    handle_id = replace(handle_id, "-src" => "")
    handle_id = replace(handle_id, "-tgt" => "")
    return handle_id
end

# 去掉 handle 的 bus- 前缀
function strip_bus_handle_suffix(handle_id::String)::String
    handle_id = replace(handle_id, "bus-" => "")
    return handle_id
end

# 生成变量名
function build_variable_name(component_key::String, component_name::String, medium::String, direction::Symbol)::String
    prefix = get_medium_prefix(medium)  # electric→E, thermal→Q 等
    dir_str = direction == :out ? "out" : "in"
    return "$(prefix)_$(component_key)_$(dir_str)_$(component_name)"
end
```
