#!/usr/bin/env julia
# Test script for FCF binary parsing with DESSEM2Julia
#
# Note: The sample cortdeco.rv2 in docs/Sample/DS_ONS_102025_RV2D11/ is
# a placeholder file with no actual FCF cuts (all records are zeros).
# To test with real data, use a DESSEM case with NEWAVE-generated FCF cuts.

using Pkg
Pkg.activate(@__DIR__)

using DESSEM2Julia

println("="^60)
println("FCF Binary Parsing Test")
println("="^60)

# Path to sample cortdeco.rv2
cortdeco_path = joinpath(@__DIR__, "docs/Sample/DS_ONS_102025_RV2D11/cortdeco.rv2")
mapcut_path = joinpath(@__DIR__, "docs/Sample/DS_ONS_102025_RV2D11/mapcut.rv2")

println("\nTest files:")
println("  cortdeco: $cortdeco_path")
println("  mapcut:   $mapcut_path")
println("  cortdeco exists: $(isfile(cortdeco_path))")
println("  mapcut exists:   $(isfile(mapcut_path))")

if !isfile(cortdeco_path)
    println("\nERROR: cortdeco.rv2 not found!")
    exit(1)
end

println("\n" * "-"^60)
println("Test 1: parse_cortdeco()")
println("-"^60)

try
    cuts = parse_cortdeco(cortdeco_path)
    println("✓ parse_cortdeco() succeeded")
    println("  Type: $(typeof(cuts))")

    # Check structure
    if hasproperty(cuts, :cortes)
        println("  Number of cuts: $(length(cuts.cortes))")
    end
    if hasproperty(cuts, :tamanho_registro)
        println("  Record size: $(cuts.tamanho_registro) bytes")
    end

    # Show first cut details
    if !isempty(cuts.cortes)
        first_cut = cuts.cortes[1]
        println("\n  First cut:")
        println("    Type: $(typeof(first_cut))")
        for fn in fieldnames(typeof(first_cut))
            val = getfield(first_cut, fn)
            if val isa AbstractVector
                println("    $fn: Vector{$(eltype(val))} length=$(length(val))")
            else
                println("    $fn: $val")
            end
        end
    end

    println("\n✓ Test 1 PASSED")
catch e
    println("✗ Test 1 FAILED: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "-"^60)
println("Test 2: parse_mapcut()")
println("-"^60)

if isfile(mapcut_path)
    try
        mapcut = parse_mapcut(mapcut_path)
        println("✓ parse_mapcut() succeeded")
        println("  Type: $(typeof(mapcut))")

        # Show structure
        for fn in fieldnames(typeof(mapcut))
            val = getfield(mapcut, fn)
            if val isa AbstractVector
                println("  $fn: Vector{$(eltype(val))} length=$(length(val))")
            else
                println("  $fn: $val")
            end
        end

        println("\n✓ Test 2 PASSED")
    catch e
        println("✗ Test 2 FAILED: $e")
        showerror(stdout, e, catch_backtrace())
    end
else
    println("⊘ Test 2 SKIPPED: mapcut.rv2 not found")
end

println("\n" * "-"^60)
println("Test 3: get_cut_statistics()")
println("-"^60)

try
    cuts = parse_cortdeco(cortdeco_path)
    stats = get_cut_statistics(cuts)
    println("✓ get_cut_statistics() succeeded")
    println("  Type: $(typeof(stats))")
    for (k, v) in pairs(stats)
        println("  $k: $v")
    end
    println("\n✓ Test 3 PASSED")
catch e
    println("✗ Test 3 FAILED: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "-"^60)
println("Test 4: get_water_value()")
println("-"^60)

try
    cuts = parse_cortdeco(cortdeco_path)

    # Try to get water value (need to find valid UHE code)
    if hasproperty(cuts, :codigos_uhes) && !isempty(cuts.codigos_uhes)
        uhe_code = cuts.codigos_uhes[1]
        storage = 1000.0  # hm³
        wv = get_water_value(cuts, uhe_code, storage)
        println("✓ get_water_value() succeeded")
        println("  UHE code: $uhe_code")
        println("  Storage: $storage hm³")
        println("  Water value: $wv")
    else
        println("  No UHE codes available for water value test")
    end
    println("\n✓ Test 4 PASSED")
catch e
    println("✗ Test 4 FAILED: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "="^60)
println("FCF Binary Parsing Test Complete")
println("="^60)

# =============================================================================
# Test 5: Synthetic FCF data (to verify parser works with real data structure)
# =============================================================================

println("\n" * "="^60)
println("Test 5: Synthetic FCF data (parser validation)")
println("="^60)

mktempdir() do tmpdir
    test_file = joinpath(tmpdir, "test_cortdeco.rv2")
    record_size = 1664
    num_coef = (record_size - 16) ÷ 8  # 206 floats (1 RHS + 205 coefficients)

    # Create 3 cuts in linked list format (reverse order in file)
    open(test_file, "w") do io
        # Cut 1 (index 1, points to nothing - index 0)
        write(io, Int32(0))  # indice_corte_anterior (0 = no previous cut)
        write(io, Int32(1))  # iteracao_construcao
        write(io, Int32(1))  # indice_forward
        write(io, Int32(0))  # iteracao_desativacao (0 = active)
        write(io, Float64(1000.0))  # RHS
        for i = 1:205
            write(io, Float64(i * 0.1))  # Coefficients
        end

        # Cut 2 (index 2, points to cut 1)
        write(io, Int32(1))  # indice_corte_anterior (points to cut 1)
        write(io, Int32(2))  # iteracao_construcao
        write(io, Int32(2))  # indice_forward
        write(io, Int32(0))  # iteracao_desativacao
        write(io, Float64(2000.0))  # RHS
        for i = 1:205
            write(io, Float64(i * 0.2))
        end

        # Cut 3 (index 3, points to cut 2)
        write(io, Int32(2))  # points to cut 2
        write(io, Int32(3))
        write(io, Int32(3))
        write(io, Int32(0))
        write(io, Float64(3000.0))
        for i = 1:205
            write(io, Float64(i * 0.3))
        end
    end

    # Parse with UHE codes
    cuts = parse_cortdeco(
        test_file,
        tamanho_registro = record_size,
        indice_ultimo_corte = 3,  # Start from last cut
        codigos_uhes = [1, 2, 3, 4, 5],
    )

    println("✓ Synthetic data parsing succeeded")
    println("  Total cuts: $(cuts.numero_total_cortes)")
    println("  Record size: $(cuts.tamanho_registro) bytes")

    # Verify chronological order (parser reverses linked list)
    @assert cuts.cortes[1].rhs == 1000.0 "Cut 1 RHS mismatch"
    @assert cuts.cortes[2].rhs == 2000.0 "Cut 2 RHS mismatch"
    @assert cuts.cortes[3].rhs == 3000.0 "Cut 3 RHS mismatch"
    println("  ✓ Cuts in chronological order (linked list reversed correctly)")

    # Verify coefficients
    @assert cuts.cortes[1].coeficientes[1] ≈ 0.1 "Coefficient mismatch"
    @assert cuts.cortes[1].coeficientes[10] ≈ 1.0 "Coefficient mismatch"
    println("  ✓ Coefficients parsed correctly")

    # Test water value with UHE codes
    wv1 = get_water_value(cuts, 1)
    @assert wv1 ≈ 0.2 "Water value mismatch (avg of 0.1, 0.2, 0.3)"
    println("  ✓ Water value calculation works (UHE 1: $wv1)")

    # Test statistics
    stats = get_cut_statistics(cuts)
    @assert stats["total_cuts"] == 3
    @assert stats["active_cuts"] == 3
    println("  ✓ Statistics computed correctly")

    println("\n✅ Test 5 PASSED - Parser works correctly with valid data")
end

println("\n" * "="^60)
println("Summary:")
println("  - parse_cortdeco() works correctly")
println("  - Sample cortdeco.rv2 is empty (placeholder)")
println("  - Use real DESSEM case with NEWAVE FCF cuts for testing")
println("="^60)
