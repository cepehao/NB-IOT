module NBIoTSim

include("Types.jl")
include("TrafficModels.jl")
include("TrafficGenerator.jl")
include("Analytics.jl")
include("Metrics.jl")
include("EventQueue.jl")
include("NPRACHSimulator.jl")
include("MatlabBridge.jl")

# Types.jl
export TrafficKind, Periodic, Poisson, Burst, Emergency, Downlink
export DeviceState, Idle, WaitingForOccasion, Transmitting, Backoff, RASuccess, Dropped, DataTransmission, Done
export TrafficConfig, NPRACHConfig, CellConfig, validate_nprach_config, validate_cell_config
export Device, ArrivalEvent, NPRACHOccasionEvent, BackoffExpiryEvent, DTDepartureEvent
export TrafficStream, DTPool, SimMetrics, SimState

# TrafficModels.jl (Модуль 1 — математика)
export sample_activation_model1, sample_activation_model2
export generate_periodic_device_stream, generate_poisson_arrivals, generate_downlink_arrivals

# TrafficGenerator.jl (Модуль 1 — точка входа)
export build_traffic_stream, merge_streams, compute_active_devices, estimate_intensity

# Analytics.jl (верификация Модуля 2)
export p_collision_exact, expected_success_exact, expected_used_preambles_exact, expected_collided_preambles_exact
export throughput_slotted_aloha, p_empty_poisson, p_collision_poisson, erlang_b

# Metrics.jl
export record_occasion_result!, record_dt_snapshot!

# EventQueue.jl / NPRACHSimulator.jl (Модуль 2)
export create_sim_state, run_simulation, step!, push_event!, pop_event!
export next_occasion_time, select_preamble, assign_preambles, resolve_occasion, schedule_backoff
export try_seize_dt!, release_dt!, dt_utilization
export process!

# MatlabBridge.jl (задел под Модуль 3)
export to_mxstruct

end # module NBIoTSim
