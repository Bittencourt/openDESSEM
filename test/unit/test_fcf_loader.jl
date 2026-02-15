"""
    Test suite for FCF (Future Cost Function) curve loader.

Tests FCF curve data structures, parsing, and water value interpolation.
"""

using Test
using Dates

# Include the FCF loader module
include("../../src/data/loaders/fcf_loader.jl")

using .FCFCurveLoader

@testset "FCF Loader Tests" begin

    @testset "FCFCurve Struct" begin
        @testset "Valid construction" begin
            curve = FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 5,
                storage_breakpoints = [0.0, 100.0, 500.0, 1000.0, 2000.0],
                water_values = [200.0, 150.0, 100.0, 50.0, 20.0],
            )

            @test curve.plant_id == "H_SE_001"
            @test curve.num_pieces == 5
            @test length(curve.storage_breakpoints) == 5
            @test length(curve.water_values) == 5
            @test curve.storage_breakpoints == [0.0, 100.0, 500.0, 1000.0, 2000.0]
            @test curve.water_values == [200.0, 150.0, 100.0, 50.0, 20.0]
        end

        @testset "Validation rejects mismatched array lengths" begin
            # num_pieces doesn't match storage_breakpoints length
            @test_throws ArgumentError FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0],
                water_values = [200.0, 150.0, 100.0],
            )

            # num_pieces doesn't match water_values length
            @test_throws ArgumentError FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 500.0],
                water_values = [200.0, 150.0],
            )
        end

        @testset "Validation rejects empty plant_id" begin
            @test_throws ArgumentError FCFCurve(;
                plant_id = "",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 500.0],
                water_values = [200.0, 150.0, 100.0],
            )

            @test_throws ArgumentError FCFCurve(;
                plant_id = "   ",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 500.0],
                water_values = [200.0, 150.0, 100.0],
            )
        end

        @testset "Validation rejects insufficient breakpoints" begin
            @test_throws ArgumentError FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 1,
                storage_breakpoints = [100.0],
                water_values = [150.0],
            )
        end

        @testset "Validation rejects negative storage" begin
            @test_throws ArgumentError FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [-10.0, 100.0, 500.0],
                water_values = [200.0, 150.0, 100.0],
            )
        end

        @testset "Validation rejects negative water values" begin
            @test_throws ArgumentError FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 500.0],
                water_values = [200.0, -50.0, 100.0],
            )
        end

        @testset "Validation rejects unsorted breakpoints" begin
            @test_throws ArgumentError FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [100.0, 0.0, 500.0],
                water_values = [150.0, 200.0, 100.0],
            )
        end

        @testset "Allows identical storage breakpoints" begin
            # Edge case: consecutive breakpoints can be equal
            @test_nowarn FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 100.0],
                water_values = [200.0, 150.0, 140.0],
            )
        end
    end

    @testset "FCFCurveData Container" begin
        @testset "Valid construction" begin
            curve = FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 500.0],
                water_values = [200.0, 150.0, 100.0],
            )

            curves = Dict("H_SE_001" => curve)
            fcf_data = FCFCurveData(;
                curves = curves,
                study_date = Date(2025, 10, 1),
                num_periods = 168,
                source_file = "test.dat",
            )

            @test length(fcf_data.curves) == 1
            @test haskey(fcf_data.curves, "H_SE_001")
            @test fcf_data.study_date == Date(2025, 10, 1)
            @test fcf_data.num_periods == 168
            @test fcf_data.source_file == "test.dat"
        end

        @testset "Default values" begin
            fcf_data = FCFCurveData()

            @test isempty(fcf_data.curves)
            @test fcf_data.study_date == Date(2025, 1, 1)
            @test fcf_data.num_periods == 168
            @test fcf_data.source_file == ""
        end

        @testset "Validation rejects invalid num_periods" begin
            @test_throws ArgumentError FCFCurveData(; num_periods = 0)
            @test_throws ArgumentError FCFCurveData(; num_periods = -1)
        end

        @testset "Add and retrieve curves" begin
            fcf_data = FCFCurveData()

            curve1 = FCFCurve(;
                plant_id = "H_SE_001",
                num_pieces = 3,
                storage_breakpoints = [0.0, 100.0, 500.0],
                water_values = [200.0, 150.0, 100.0],
            )

            curve2 = FCFCurve(;
                plant_id = "H_SE_002",
                num_pieces = 4,
                storage_breakpoints = [0.0, 200.0, 400.0, 600.0],
                water_values = [180.0, 140.0, 100.0, 60.0],
            )

            fcf_data = FCFCurveData(; curves = Dict("H_SE_001" => curve1, "H_SE_002" => curve2))

            @test has_fcf_curve(fcf_data, "H_SE_001")
            @test has_fcf_curve(fcf_data, "H_SE_002")
            @test !has_fcf_curve(fcf_data, "H_SE_003")
            @test length(fcf_data.curves) == 2
        end
    end

    @testset "Water Value Interpolation" begin
        # Create a simple 3-point curve for testing
        curve = FCFCurve(;
            plant_id = "H_SE_001",
            num_pieces = 3,
            storage_breakpoints = [0.0, 100.0, 500.0],
            water_values = [200.0, 150.0, 100.0],
        )

        @testset "Interpolation at breakpoints" begin
            @test interpolate_water_value(curve, 0.0) == 200.0
            @test interpolate_water_value(curve, 100.0) == 150.0
            @test interpolate_water_value(curve, 500.0) == 100.0
        end

        @testset "Linear interpolation between breakpoints" begin
            # At 50 hm³ (midpoint between 0 and 100)
            @test interpolate_water_value(curve, 50.0) == 175.0

            # At 300 hm³ (midpoint between 100 and 500)
            @test interpolate_water_value(curve, 300.0) == 125.0

            # At 250 hm³ (25% from 100 to 500)
            @test interpolate_water_value(curve, 250.0) == 137.5
        end

        @testset "Clamping for extrapolation below min" begin
            @test interpolate_water_value(curve, -10.0) == 200.0
            @test interpolate_water_value(curve, -100.0) == 200.0
        end

        @testset "Clamping for extrapolation above max" begin
            @test interpolate_water_value(curve, 600.0) == 100.0
            @test interpolate_water_value(curve, 1000.0) == 100.0
        end
    end

    @testset "get_water_value Function" begin
        curve1 = FCFCurve(;
            plant_id = "H_SE_001",
            num_pieces = 3,
            storage_breakpoints = [0.0, 100.0, 500.0],
            water_values = [200.0, 150.0, 100.0],
        )

        curve2 = FCFCurve(;
            plant_id = "H_NE_001",
            num_pieces = 2,
            storage_breakpoints = [0.0, 300.0],
            water_values = [180.0, 120.0],
        )

        fcf_data = FCFCurveData(;
            curves = Dict("H_SE_001" => curve1, "H_NE_001" => curve2),
        )

        @testset "Get water value for existing plant" begin
            @test get_water_value(fcf_data, "H_SE_001", 0.0) == 200.0
            @test get_water_value(fcf_data, "H_SE_001", 50.0) == 175.0
            @test get_water_value(fcf_data, "H_SE_001", 300.0) == 125.0
            @test get_water_value(fcf_data, "H_NE_001", 150.0) == 150.0
        end

        @testset "Throws for non-existent plant" begin
            @test_throws ArgumentError get_water_value(fcf_data, "H_XX_999", 100.0)
        end
    end

    @testset "Helper Functions" begin
        curve1 = FCFCurve(;
            plant_id = "H_SE_001",
            num_pieces = 3,
            storage_breakpoints = [0.0, 100.0, 500.0],
            water_values = [200.0, 150.0, 100.0],
        )

        curve2 = FCFCurve(;
            plant_id = "H_NE_001",
            num_pieces = 2,
            storage_breakpoints = [0.0, 300.0],
            water_values = [180.0, 120.0],
        )

        fcf_data = FCFCurveData(;
            curves = Dict("H_SE_001" => curve1, "H_NE_001" => curve2),
        )

        @testset "has_fcf_curve" begin
            @test has_fcf_curve(fcf_data, "H_SE_001") == true
            @test has_fcf_curve(fcf_data, "H_NE_001") == true
            @test has_fcf_curve(fcf_data, "H_XX_999") == false
        end

        @testset "get_plant_ids" begin
            plant_ids = get_plant_ids(fcf_data)
            @test length(plant_ids) == 2
            @test "H_SE_001" in plant_ids
            @test "H_NE_001" in plant_ids
            # Should be sorted
            @test plant_ids == sort(plant_ids)
        end
    end

    @testset "Parser - parse_fcf_line" begin
        @testset "Valid FCF line" begin
            # Format: posto num_pieces s1 v1 s2 v2 ...
            line = "1 3 0.0 200.0 100.0 150.0 500.0 100.0"
            curve = parse_fcf_line(line, 1)

            @test curve !== nothing
            @test curve.plant_id == "H_XX_001"
            @test curve.num_pieces == 3
            @test curve.storage_breakpoints == [0.0, 100.0, 500.0]
            @test curve.water_values == [200.0, 150.0, 100.0]
        end

        @testset "Valid FCF line with extra spaces" begin
            line = "  42   2   0.0   180.0   300.0   120.0  "
            curve = parse_fcf_line(line, 1)

            @test curve !== nothing
            @test curve.plant_id == "H_XX_042"
            @test curve.num_pieces == 2
        end

        @testset "Valid FCF line with comma delimiter" begin
            line = "5,4,0.0,200.0,100.0,150.0,300.0,120.0,500.0,100.0"
            curve = parse_fcf_line(line, 1)

            @test curve !== nothing
            @test curve.num_pieces == 4
        end

        @testset "Returns nothing for insufficient data" begin
            # Only 4 values, need at least 6
            @test parse_fcf_line("1 2 0.0 100.0", 1) === nothing
            @test parse_fcf_line("1", 1) === nothing
        end

        @testset "Returns nothing for empty or comment lines" begin
            @test parse_fcf_line("", 1) === nothing
            @test parse_fcf_line("   ", 1) === nothing
            @test parse_fcf_line("& this is a comment", 1) === nothing
            @test parse_fcf_line("# this is a comment", 1) === nothing
        end

        @testset "Returns nothing for malformed data" begin
            # Non-numeric posto
            @test parse_fcf_line("ABC 3 0.0 200.0 100.0 150.0 500.0 100.0", 1) === nothing
            # Invalid num_pieces
            @test parse_fcf_line("1 XYZ 0.0 200.0 100.0 150.0 500.0 100.0", 1) === nothing
        end
    end

    @testset "Parser - Integration" begin
        @testset "Parse sample FCF data" begin
            # Create a temporary FCF file for testing
            temp_file = tempname() * ".dat"
            fcf_content = """
            & INFOFCF - FCF Curve Data
            # Comments are ignored
            1 3 0.0 200.0 100.0 150.0 500.0 100.0
            2 4 0.0 180.0 50.0 160.0 100.0 140.0 200.0 120.0
            156 2 0.0 220.0 800.0 100.0
            """
            write(temp_file, fcf_content)

            try
                fcf_data = parse_infofcf_file(temp_file)

                @test length(fcf_data.curves) == 3
                @test haskey(fcf_data.curves, "H_XX_001")
                @test haskey(fcf_data.curves, "H_XX_002")
                @test haskey(fcf_data.curves, "H_XX_156")

                # Verify curve 1
                curve1 = fcf_data.curves["H_XX_001"]
                @test curve1.num_pieces == 3
                @test curve1.water_values == [200.0, 150.0, 100.0]

                # Verify curve 156
                curve156 = fcf_data.curves["H_XX_156"]
                @test curve156.num_pieces == 2
                @test interpolate_water_value(curve156, 400.0) == 160.0

            finally
                rm(temp_file, force = true)
            end
        end

        @testset "Handle missing file" begin
            @test_throws ArgumentError parse_infofcf_file("/nonexistent/path/infofcf.dat")
        end
    end

    @testset "load_fcf_curves" begin
        @testset "Throws for non-existent directory" begin
            @test_throws ArgumentError load_fcf_curves("/nonexistent/directory/")
        end

        @testset "Throws for directory without FCF file" begin
            temp_dir = mktempdir()
            try
                @test_throws ArgumentError load_fcf_curves(temp_dir)
            finally
                rm(temp_dir, recursive = true, force = true)
            end
        end

        @testset "Loads from infofcf.dat" begin
            temp_dir = mktempdir()
            temp_file = joinpath(temp_dir, "infofcf.dat")
            fcf_content = "1 2 0.0 200.0 500.0 100.0"
            write(temp_file, fcf_content)

            try
                fcf_data = load_fcf_curves(temp_dir)
                @test length(fcf_data.curves) == 1
                @test fcf_data.source_file == temp_file
            finally
                rm(temp_dir, recursive = true, force = true)
            end
        end

        @testset "Loads from uppercase INFOFCF.DAT" begin
            temp_dir = mktempdir()
            temp_file = joinpath(temp_dir, "INFOFCF.DAT")
            fcf_content = "1 2 0.0 200.0 500.0 100.0"
            write(temp_file, fcf_content)

            try
                fcf_data = load_fcf_curves(temp_dir)
                @test length(fcf_data.curves) == 1
            finally
                rm(temp_dir, recursive = true, force = true)
            end
        end

        @testset "Loads from fcf.dat alternative" begin
            temp_dir = mktempdir()
            temp_file = joinpath(temp_dir, "fcf.dat")
            fcf_content = "1 2 0.0 200.0 500.0 100.0"
            write(temp_file, fcf_content)

            try
                fcf_data = load_fcf_curves(temp_dir)
                @test length(fcf_data.curves) == 1
            finally
                rm(temp_dir, recursive = true, force = true)
            end
        end
    end

    @testset "load_fcf_curves_with_mapping" begin
        temp_dir = mktempdir()
        temp_file = joinpath(temp_dir, "infofcf.dat")
        fcf_content = "1 2 0.0 200.0 500.0 100.0\n156 3 0.0 220.0 400.0 160.0 800.0 100.0"
        write(temp_file, fcf_content)

        plant_id_map = Dict(1 => "H_SE_001", 156 => "H_SU_156")

        try
            fcf_data = load_fcf_curves_with_mapping(temp_dir, plant_id_map)

            @test haskey(fcf_data.curves, "H_SE_001")
            @test haskey(fcf_data.curves, "H_SU_156")
            @test !haskey(fcf_data.curves, "H_XX_001")

            # Verify mapped curve data is preserved
            @test fcf_data.curves["H_SE_001"].num_pieces == 2
            @test fcf_data.curves["H_SU_156"].num_pieces == 3

        finally
            rm(temp_dir, recursive = true, force = true)
        end
    end

    @testset "Edge Cases" begin
        @testset "Empty FCF file" begin
            temp_file = tempname() * ".dat"
            write(temp_file, "")

            try
                fcf_data = parse_infofcf_file(temp_file)
                @test isempty(fcf_data.curves)
            finally
                rm(temp_file, force = true)
            end
        end

        @testset "FCF file with only comments" begin
            temp_file = tempname() * ".dat"
            fcf_content = """
            & Header comment
            # Another comment
            
            & More comments
            """
            write(temp_file, fcf_content)

            try
                fcf_data = parse_infofcf_file(temp_file)
                @test isempty(fcf_data.curves)
            finally
                rm(temp_file, force = true)
            end
        end

        @testset "Large number of pieces" begin
            # Test with 10 pieces
            storage = [0.0, 50.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0]
            values = [200.0, 190.0, 180.0, 160.0, 140.0, 120.0, 100.0, 80.0, 60.0, 40.0]
            curve = FCFCurve(;
                plant_id = "H_LARGE",
                num_pieces = 10,
                storage_breakpoints = storage,
                water_values = values,
            )

            @test curve.num_pieces == 10
            @test interpolate_water_value(curve, 150.0) == 170.0
        end

        @testset "Very small water values" begin
            curve = FCFCurve(;
                plant_id = "H_SMALL",
                num_pieces = 2,
                storage_breakpoints = [0.0, 1000.0],
                water_values = [0.01, 0.001],
            )

            @test interpolate_water_value(curve, 500.0) ≈ 0.0055
        end
    end
end
