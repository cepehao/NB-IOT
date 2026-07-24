using Test
using NBIoTSim

@testset "NBIoTSim" begin
    include("test_traffic_models.jl")
    include("test_collision_analytics.jl")
    include("test_ra_state_machine.jl")
end
