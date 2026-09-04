# flexibility_requirement_service.jl — 系统灵活性需求计算

requirement_source(::NetLoadRequirementInput) = FLEXIBILITY_REQUIREMENT_NET_LOAD
requirement_source(::AgcScheduleRequirementInput) = FLEXIBILITY_REQUIREMENT_AGC_SCHEDULE
requirement_source(::UserDefinedRequirementInput) = FLEXIBILITY_REQUIREMENT_USER_DEFINED

function _build_system_flexibility_requirement_results(
    context::SystemFlexibilityRequirementContext,
    source::String,
    upward_requirement::Real,
    downward_requirement::Real;
    reference_power::Union{Nothing,Real}=nothing,
    target_power::Union{Nothing,Real}=nothing,
)
    return SystemFlexibilityRequirementResult[
        SystemFlexibilityRequirementResult(
            context;
            direction=FLEXIBILITY_UP,
            requirement_source=source,
            requirement=upward_requirement,
            reference_power=reference_power,
            target_power=target_power,
        ),
        SystemFlexibilityRequirementResult(
            context;
            direction=FLEXIBILITY_DOWN,
            requirement_source=source,
            requirement=downward_requirement,
            reference_power=reference_power,
            target_power=target_power,
        ),
    ]
end

"""
    calculate_system_flexibility_requirement(context, input)

统一的系统灵活性需求计算入口。一次调用只接受一种需求输入，避免净负荷、
AGC/计划功率和用户给定目标在没有明确物理含义时重复相加。
"""
function calculate_system_flexibility_requirement(
    context::SystemFlexibilityRequirementContext,
    input::NetLoadRequirementInput,
)
    current_net_load_kw =
        input.current_rigid_load_kw + input.current_flexible_load_kw -
        input.current_wind_available_power_kw - input.current_pv_available_power_kw
    next_net_load_kw =
        input.next_rigid_load_kw + input.next_flexible_load_kw -
        input.next_wind_available_power_kw - input.next_pv_available_power_kw
    net_load_change_kw = next_net_load_kw - current_net_load_kw

    return _build_system_flexibility_requirement_results(
        context,
        requirement_source(input),
        max(0.0, net_load_change_kw),
        max(0.0, -net_load_change_kw);
        reference_power=current_net_load_kw,
        target_power=next_net_load_kw,
    )
end

function calculate_system_flexibility_requirement(
    context::SystemFlexibilityRequirementContext,
    input::AgcScheduleRequirementInput,
)
    target_deviation_kw = input.target_poi_power_kw - input.baseline_poi_power_kw
    return _build_system_flexibility_requirement_results(
        context,
        requirement_source(input),
        max(0.0, target_deviation_kw),
        max(0.0, -target_deviation_kw);
        reference_power=input.baseline_poi_power_kw,
        target_power=input.target_poi_power_kw,
    )
end

function calculate_system_flexibility_requirement(
    context::SystemFlexibilityRequirementContext,
    input::UserDefinedRequirementInput,
)
    return _build_system_flexibility_requirement_results(
        context,
        requirement_source(input),
        input.upward_requirement_kw,
        input.downward_requirement_kw,
    )
end
