"""
    Test suite for market entity types

Tests for Submarket and Load entities following TDD principles.
"""

using OpenDESSEM
using Test

@testset "Market Entity Tests" begin

    @testset "Submarket - Constructor" begin
        @testset "Valid submarket" begin
            sm = Submarket(;
                id = "SM_001",
                name = "Southeast",
                code = "SE",
                country = "Brazil",
                description = "Southeast submarket",
            )

            @test sm.id == "SM_001"
            @test sm.name == "Southeast"
            @test sm.code == "SE"
            @test sm.country == "Brazil"
            @test sm.description == "Southeast submarket"
            @test sm isa MarketEntity
            @test sm isa PhysicalEntity
        end

        @testset "Submarket with empty description" begin
            sm = Submarket(;
                id = "SM_002",
                name = "Northeast",
                code = "NE",
                country = "Brazil",
            )

            @test sm.description == ""  # Default
            @test sm.metadata !== nothing
        end

        @testset "Submarket with long description" begin
            sm = Submarket(;
                id = "SM_003",
                name = "South",
                code = "SU",
                country = "Brazil",
                description = "Southern region including Rio Grande do Sul and Santa Catarina",
            )

            @test length(sm.description) > 50
        end
    end

    @testset "Submarket - Validation" begin
        @testset "Invalid code length" begin
            @test_throws ArgumentError Submarket(;
                id = "SM_001",
                name = "Invalid Code",
                code = "X",  # Too short (min 2)
                country = "Brazil",
            )

            @test_throws ArgumentError Submarket(;
                id = "SM_001",
                name = "Invalid Code",
                code = "ABCDE",  # Too long (max 4)
                country = "Brazil",
            )
        end

        @testset "Invalid country" begin
            @test_throws ArgumentError Submarket(;
                id = "SM_001",
                name = "Invalid Country",
                code = "SE",
                country = "X",  # Too short
            )
        end

        @testset "Invalid ID format" begin
            @test_throws ArgumentError Submarket(;
                id = "",  # Empty string
                name = "Invalid ID",
                code = "SE",
                country = "Brazil",
            )
        end
    end

    @testset "Load - Constructor" begin
        @testset "Valid load with submarket_id" begin
            load = Load(;
                id = "LOAD_001",
                name = "Southeast Load",
                submarket_id = "SE",
                base_mw = 50000.0,
                load_profile = ones(168),
                is_elastic = false,
            )

            @test load.id == "LOAD_001"
            @test load.name == "Southeast Load"
            @test load.submarket_id == "SE"
            @test load.bus_id === nothing
            @test load.base_mw == 50000.0
            @test length(load.load_profile) == 168
            @test load.is_elastic == false
            @test load.elasticity == -0.1
            @test load isa MarketEntity
            @test load isa PhysicalEntity
        end

        @testset "Valid load with bus_id" begin
            load = Load(;
                id = "LOAD_002",
                name = "Bus Load",
                submarket_id = nothing,
                bus_id = "B_001",
                base_mw = 1000.0,
                load_profile = [1.0, 0.9, 0.8],
                is_elastic = false,
            )

            @test load.submarket_id === nothing
            @test load.bus_id == "B_001"
            @test length(load.load_profile) == 3
        end

        @testset "Elastic load" begin
            load = Load(;
                id = "LOAD_003",
                name = "Elastic Load",
                submarket_id = "SE",
                base_mw = 30000.0,
                load_profile = ones(24),
                is_elastic = true,
                elasticity = -0.2,
            )

            @test load.is_elastic == true
            @test load.elasticity == -0.2
        end

        @testset "Load with varying profile" begin
            profile = collect(0.6:0.1:1.4)  # 0.6 to 1.4
            load = Load(;
                id = "LOAD_004",
                name = "Variable Load",
                submarket_id = "NE",
                base_mw = 20000.0,
                load_profile = profile,
            )

            @test load.load_profile[1] == 0.6
            @test load.load_profile[end] == 1.4
            @test length(load.load_profile) == 9
        end

        @testset "Default values" begin
            load = Load(;
                id = "LOAD_005",
                name = "Default Load",
                submarket_id = "SU",
                base_mw = 15000.0,
                load_profile = ones(24),
            )

            @test load.is_elastic == false  # Default
            @test load.elasticity == -0.1  # Default
            @test load.bus_id === nothing  # Default
            @test load.metadata !== nothing
        end
    end

    @testset "Load - Validation" begin
        @testset "Missing submarket_id and bus_id" begin
            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "No Location",
                submarket_id = nothing,
                bus_id = nothing,
                base_mw = 10000.0,
                load_profile = ones(24),
            )
        end

        @testset "Invalid base_mw" begin
            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Zero Base",
                submarket_id = "SE",
                base_mw = 0.0,
                load_profile = ones(24),
            )

            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Negative Base",
                submarket_id = "SE",
                base_mw = -10000.0,
                load_profile = ones(24),
            )
        end

        @testset "Empty load profile" begin
            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Empty Profile",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = Float64[],
            )
        end

        @testset "Negative values in profile" begin
            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Negative Profile",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = [1.0, 0.9, -0.1],
            )
        end

        @testset "Invalid elasticity for elastic load" begin
            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Positive Elasticity",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = ones(24),
                is_elastic = true,
                elasticity = 0.1,  # Must be negative
            )

            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Zero Elasticity",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = ones(24),
                is_elastic = true,
                elasticity = 0.0,  # Must be negative
            )
        end

        @testset "Invalid submarket_id format" begin
            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Short Submarket",
                submarket_id = "X",  # Too short (min 2)
                base_mw = 10000.0,
                load_profile = ones(24),
            )

            @test_throws ArgumentError Load(;
                id = "LOAD_001",
                name = "Long Submarket",
                submarket_id = "ABCDE",  # Too long (max 4)
                base_mw = 10000.0,
                load_profile = ones(24),
            )
        end
    end

    @testset "MarketEntity - Type Hierarchy" begin
        @testset "Submarket type hierarchy" begin
            sm = Submarket(; id = "SM_001", name = "Test", code = "T1", country = "Brazil")

            @test sm isa MarketEntity
            @test sm isa PhysicalEntity
            @test sm isa AbstractEntity
            @test MarketEntity <: PhysicalEntity
            @test PhysicalEntity <: AbstractEntity
        end

        @testset "Load type hierarchy" begin
            load = Load(;
                id = "LOAD_001",
                name = "Test Load",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = ones(24),
            )

            @test load isa MarketEntity
            @test load isa PhysicalEntity
            @test load isa AbstractEntity
        end
    end

    @testset "BilateralContract - Constructor" begin
        @testset "Valid bilateral contract" begin
            contract = BilateralContract(;
                id = "BC_001",
                seller_id = "SELLER_001",
                buyer_id = "BUYER_001",
                energy_mwh = 1000.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
                end_date = DateTime(2024, 12, 31),
            )

            @test contract.id == "BC_001"
            @test contract.seller_id == "SELLER_001"
            @test contract.buyer_id == "BUYER_001"
            @test contract.energy_mwh == 1000.0
            @test contract.price_rsj_per_mwh == 150.0
            @test contract.start_date == DateTime(2024, 1, 1)
            @test contract.end_date == DateTime(2024, 12, 31)
            @test contract isa MarketEntity
            @test contract isa PhysicalEntity
        end

        @testset "Contract with default values" begin
            contract = BilateralContract(;
                id = "BC_002",
                seller_id = "SELLER_002",
                buyer_id = "BUYER_002",
                energy_mwh = 500.0,
                price_rsj_per_mwh = 200.0,
                start_date = DateTime(2024, 6, 1),
            )

            @test contract.end_date === nothing
            @test contract.metadata !== nothing
        end

        @testset "Contract with zero energy (valid)" begin
            contract = BilateralContract(;
                id = "BC_003",
                seller_id = "SELLER_001",
                buyer_id = "BUYER_001",
                energy_mwh = 0.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
            )

            @test contract.energy_mwh == 0.0
        end

        @testset "Contract with large energy" begin
            contract = BilateralContract(;
                id = "BC_004",
                seller_id = "SELLER_001",
                buyer_id = "BUYER_001",
                energy_mwh = 100000.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
            )

            @test contract.energy_mwh == 100000.0
        end
    end

    @testset "BilateralContract - Validation" begin
        @testset "Seller and buyer must be different" begin
            @test_throws ArgumentError BilateralContract(;
                id = "BC_001",
                seller_id = "AGENT_001",
                buyer_id = "AGENT_001",  # Same as seller
                energy_mwh = 1000.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
            )
        end

        @testset "Negative energy not allowed" begin
            @test_throws ArgumentError BilateralContract(;
                id = "BC_001",
                seller_id = "SELLER_001",
                buyer_id = "BUYER_001",
                energy_mwh = -1000.0,  # Negative
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
            )
        end

        @testset "Negative price not allowed" begin
            @test_throws ArgumentError BilateralContract(;
                id = "BC_001",
                seller_id = "SELLER_001",
                buyer_id = "BUYER_001",
                energy_mwh = 1000.0,
                price_rsj_per_mwh = -150.0,  # Negative
                start_date = DateTime(2024, 1, 1),
            )
        end

        @testset "Empty seller_id" begin
            @test_throws ArgumentError BilateralContract(;
                id = "BC_001",
                seller_id = "",  # Empty
                buyer_id = "BUYER_001",
                energy_mwh = 1000.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
            )
        end

        @testset "Empty buyer_id" begin
            @test_throws ArgumentError BilateralContract(;
                id = "BC_001",
                seller_id = "SELLER_001",
                buyer_id = "",  # Empty
                energy_mwh = 1000.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 1, 1),
            )
        end

        @testset "End date before start date" begin
            @test_throws ArgumentError BilateralContract(;
                id = "BC_001",
                seller_id = "SELLER_001",
                buyer_id = "BUYER_001",
                energy_mwh = 1000.0,
                price_rsj_per_mwh = 150.0,
                start_date = DateTime(2024, 12, 31),
                end_date = DateTime(2024, 1, 1),  # Before start
            )
        end
    end

    @testset "MarketEntity - Edge Cases" begin
        @testset "Single period load profile" begin
            load = Load(;
                id = "LOAD_001",
                name = "Single Period",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = [1.0],
            )

            @test length(load.load_profile) == 1
        end

        @testset "Very elastic load" begin
            load = Load(;
                id = "LOAD_001",
                name = "High Elasticity",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = ones(24),
                is_elastic = true,
                elasticity = -0.5,  # Very elastic
            )

            @test load.elasticity == -0.5
            @test load.is_elastic == true
        end

        @testset "Large load profile" begin
            # 1 week of hourly data
            profile = ones(168)
            load = Load(;
                id = "LOAD_001",
                name = "Weekly Profile",
                submarket_id = "SE",
                base_mw = 50000.0,
                load_profile = profile,
            )

            @test length(load.load_profile) == 168
        end

        @testset "Small profile values" begin
            load = Load(;
                id = "LOAD_001",
                name = "Small Multipliers",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = [0.1, 0.2, 0.3],
            )

            @test load.load_profile == [0.1, 0.2, 0.3]
        end

        @testset "Large profile values" begin
            load = Load(;
                id = "LOAD_001",
                name = "Large Multipliers",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = [1.5, 2.0, 2.5],
            )

            @test load.load_profile == [1.5, 2.0, 2.5]
        end

        @testset "Zero in profile (valid)" begin
            load = Load(;
                id = "LOAD_001",
                name = "Zero Period",
                submarket_id = "SE",
                base_mw = 10000.0,
                load_profile = [1.0, 0.0, 1.0],
            )

            @test load.load_profile[2] == 0.0
        end

        @testset "Large base demand" begin
            load = Load(;
                id = "LOAD_001",
                name = "Mega Load",
                submarket_id = "SE",
                base_mw = 100000.0,  # 100 GW
                load_profile = ones(24),
            )

            @test load.base_mw == 100000.0
        end
    end

end
