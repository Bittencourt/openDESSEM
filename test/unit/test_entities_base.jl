"""
    Tests for base entity types and validation utilities.

Tests AbstractEntity, EntityMetadata, and all validation functions.
"""

using Test
using OpenDESSEM.Entities
using Dates

@testset "Entity Validation Utilities" begin

    @testset "validate_id" begin
        @testset "Valid IDs" begin
            @test validate_id("T001") == "T001"
            @test validate_id("A1_B2") == "A1_B2"
            @test validate_id("plant-123") == "plant-123"
            @test validate_id("LONG_ID_12345") == "LONG_ID_12345"
        end

        @testset "Invalid IDs - Empty" begin
            @test_throws ArgumentError validate_id("")
        end

        @testset "Invalid IDs - Too Long" begin
            long_id = "A"^100
            @test_throws ArgumentError validate_id(long_id)
        end

        @testset "Invalid IDs - Special Characters" begin
            @test_throws ArgumentError validate_id("T 001")  # Space
            @test_throws ArgumentError validate_id("T@001")   # @ symbol
            @test_throws ArgumentError validate_id("T.001")   # Dot
        end

        @testset "Custom length limits" begin
            @test validate_id("AB"; min_length = 2) == "AB"
            @test_throws ArgumentError validate_id("A"; min_length = 2)

            @test validate_id("ABC"; max_length = 3) == "ABC"
            @test_throws ArgumentError validate_id("ABCD"; max_length = 3)
        end
    end

    @testset "validate_name" begin
        @testset "Valid names" begin
            @test validate_name("Plant A") == "Plant A"
            @test validate_name("  Plant B  ") == "Plant B"  # Strips whitespace
            @test validate_name("Hydro Plant São Paulo") == "Hydro Plant São Paulo"
        end

        @testset "Invalid names - Empty" begin
            @test_throws ArgumentError validate_name("")
            @test_throws ArgumentError validate_name("   ")  # Whitespace only
        end

        @testset "Invalid names - Too long" begin
            long_name = "A"^300
            @test_throws ArgumentError validate_name(long_name)
        end
    end

    @testset "validate_positive" begin
        @testset "Valid positive values" begin
            @test validate_positive(1.0) == 1.0
            @test validate_positive(0.001) == 0.001
            @test validate_positive(1000) == 1000
        end

        @testset "Invalid values - Zero" begin
            @test_throws ArgumentError validate_positive(0.0)
            @test_throws ArgumentError validate_positive(0.0, "capacity")
        end

        @testset "Invalid values - Negative" begin
            @test_throws ArgumentError validate_positive(-1.0)
            @test_throws ArgumentError validate_positive(-100.0, "generation")
        end

        @testset "Error messages include field name" begin
            try
                validate_positive(-5.0, "test_field")
                @test false  # Should not reach here
            catch e
                @test occursin("test_field", e.msg)
            end
        end
    end

    @testset "validate_non_negative" begin
        @testset "Valid non-negative values" begin
            @test validate_non_negative(0.0) == 0.0
            @test validate_non_negative(1.0) == 1.0
            @test validate_non_negative(1000) == 1000
        end

        @testset "Invalid values - Negative" begin
            @test_throws ArgumentError validate_non_negative(-0.001)
            @test_throws ArgumentError validate_non_negative(-1.0)
        end
    end

    @testset "validate_strictly_positive" begin
        @testset "Alias for validate_positive" begin
            @test validate_strictly_positive(5.0) == validate_positive(5.0)
            @test_throws ArgumentError validate_strictly_positive(0.0)
            @test_throws ArgumentError validate_strictly_positive(-1.0)
        end
    end

    @testset "validate_percentage" begin
        @testset "Valid percentages" begin
            @test validate_percentage(0.0) == 0.0
            @test validate_percentage(50.0) == 50.0
            @test validate_percentage(100.0) == 100.0
            @test validate_percentage(33.33) == 33.33
        end

        @testset "Invalid percentages - Below 0" begin
            @test_throws ArgumentError validate_percentage(-0.01)
            @test_throws ArgumentError validate_percentage(-10.0)
        end

        @testset "Invalid percentages - Above 100" begin
            @test_throws ArgumentError validate_percentage(100.01)
            @test_throws ArgumentError validate_percentage(150.0)
        end
    end

    @testset "validate_in_range" begin
        @testset "Valid values in range" begin
            @test validate_in_range(5.0, 0.0, 10.0) == 5.0
            @test validate_in_range(0.0, 0.0, 10.0) == 0.0
            @test validate_in_range(10.0, 0.0, 10.0) == 10.0
        end

        @testset "Invalid values - Below minimum" begin
            @test_throws ArgumentError validate_in_range(-1.0, 0.0, 10.0)
            @test_throws ArgumentError validate_in_range(5.0, 10.0, 20.0)
        end

        @testset "Invalid values - Above maximum" begin
            @test_throws ArgumentError validate_in_range(11.0, 0.0, 10.0)
            @test_throws ArgumentError validate_in_range(25.0, 10.0, 20.0)
        end

        @testset "Reversed range" begin
            @test validate_in_range(5.0, 10.0, 0.0) == 5.0  # Works with reversed bounds
        end
    end

    @testset "validate_min_leq_max" begin
        @testset "Valid relationships" begin
            @test validate_min_leq_max(0.0, 10.0) === nothing
            @test validate_min_leq_max(5.0, 5.0) === nothing
            @test validate_min_leq_max(-10.0, 10.0) === nothing
        end

        @testset "Invalid relationships" begin
            @test_throws ArgumentError validate_min_leq_max(10.0, 5.0)
            @test_throws ArgumentError validate_min_leq_max(100.0, 0.0)
        end

        @testset "Custom field names" begin
            try
                validate_min_leq_max(10.0, 5.0, "min_gen", "max_gen")
                @test false
            catch e
                @test occursin("min_gen", e.msg)
                @test occursin("max_gen", e.msg)
            end
        end
    end

    @testset "validate_one_of" begin
        @testset "Valid values" begin
            @test validate_one_of("coal", ["coal", "gas", "nuclear"]) == "coal"
            @test validate_one_of("gas", ["coal", "gas", "nuclear"]) == "gas"
            @test validate_one_of(2, [1, 2, 3]) == 2
        end

        @testset "Invalid values" begin
            @test_throws ArgumentError validate_one_of(
                "invalid",
                ["coal", "gas", "nuclear"],
            )
            @test_throws ArgumentError validate_one_of(5, [1, 2, 3])
        end
    end

    @testset "validate_unique_ids" begin
        @testset "Unique IDs - Valid" begin
            struct TestItem
                id::String
            end

            items = [TestItem("A"), TestItem("B"), TestItem("C")]
            @test validate_unique_ids(items) === nothing
        end

        @testset "Duplicate IDs - Invalid" begin
            struct TestItem2
                id::String
            end

            items = [
                TestItem2("A"),
                TestItem2("B"),
                TestItem2("A"),  # Duplicate
            ]
            @test_throws ValidationError validate_unique_ids(items)
        end

        @testset "Multiple duplicates" begin
            struct TestItem3
                id::String
            end

            items = [
                TestItem3("A"),
                TestItem3("B"),
                TestItem3("A"),  # Duplicate
                TestItem3("B"),   # Duplicate
            ]
            try
                validate_unique_ids(items)
                @test false
            catch e
                @test e.msg isa String
                @test occursin("A", e.msg)
                @test occursin("B", e.msg)
            end
        end
    end
end

@testset "EntityMetadata" begin

    @testset "Constructor with defaults" begin
        metadata = EntityMetadata()

        @test metadata.created_at !== nothing
        @test metadata.updated_at !== nothing
        @test metadata.version == 1
        @test metadata.source == "unknown"
        @test isempty(metadata.tags)
        @test isempty(metadata.properties)
    end

    @testset "Constructor with custom values" begin
        now_time = Dates.now()
        metadata = EntityMetadata(
            created_at = now_time,
            updated_at = now_time,
            version = 2,
            source = "database",
            tags = ["verified", "2024"],
            properties = Dict("key1" => "value1"),
        )

        @test metadata.created_at == now_time
        @test metadata.updated_at == now_time
        @test metadata.version == 2
        @test metadata.source == "database"
        @test metadata.tags == ["verified", "2024"]
        @test metadata.properties["key1"] == "value1"
    end
end

@testset "Entity Helper Functions" begin

    # Define a test entity
    struct TestEntity <: AbstractEntity
        id::String
        name::String
        metadata::EntityMetadata
    end

    @testset "get_id" begin
        entity = TestEntity("TEST_001", "Test Entity", EntityMetadata())

        @test get_id(entity) == "TEST_001"
    end

    @testset "has_id" begin
        entity = TestEntity("TEST_001", "Test Entity", EntityMetadata())

        @test has_id(entity, "TEST_001") == true
        @test has_id(entity, "OTHER_001") == false
    end

    @testset "is_empty" begin
        entity = TestEntity("TEST_001", "Test Entity", EntityMetadata())

        @test is_empty(entity) == false
    end

    @testset "update_metadata" begin
        entity = TestEntity(
            "TEST_001",
            "Test Entity",
            EntityMetadata(
                created_at = DateTime("2024-01-01T12:00:00"),
                version = 1,
                source = "manual",
            ),
        )

        new_metadata =
            update_metadata(entity; updates = Dict{String,Any}("new_key" => "new_value"))

        @test new_metadata.created_at == DateTime("2024-01-01T12:00:00")
        @test new_metadata.updated_at > entity.metadata.created_at
        @test new_metadata.version == 2
        @test new_metadata.source == "manual"
        @test new_metadata.properties["new_key"] == "new_value"
    end

    @testset "add_tag" begin
        entity = TestEntity(
            "TEST_001",
            "Test Entity",
            EntityMetadata(version = 1, tags = ["existing"]),
        )

        new_metadata = add_tag(entity, "new_tag")

        @test "new_tag" in new_metadata.tags
        @test "existing" in new_metadata.tags
        @test new_metadata.version == 2

        # Adding existing tag returns same metadata
        same_metadata = add_tag(entity, "existing")
        @test same_metadata.tags == entity.metadata.tags
    end

    @testset "set_property" begin
        entity = TestEntity(
            "TEST_001",
            "Test Entity",
            EntityMetadata(version = 1, properties = Dict("old_key" => "old_value")),
        )

        new_metadata = set_property(entity, "new_key", "new_value")

        @test new_metadata.properties["new_key"] == "new_value"
        @test new_metadata.properties["old_key"] == "old_value"  # Original property preserved
        @test new_metadata.version == 2

        # Update existing property
        updated_metadata = set_property(entity, "old_key", "updated_value")
        @test updated_metadata.properties["old_key"] == "updated_value"
    end
end
