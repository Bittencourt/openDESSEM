---
phase: quick-001
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - examples/ons_data_example.jl
autonomous: true

must_haves:
  truths:
    - "Nodal LMPs can be calculated from PWF network topology"
    - "Results display shows bus-level prices alongside submarket PLDs"
  artifacts:
    - path: "examples/ons_data_example.jl"
      contains: "solve_dc_opf_nodal_lmps"
  key_links:
    - from: "examples/ons_data_example.jl"
      to: "parse_pwf_file"
      via: "Integration module"
---

<objective>
Add an optional nodal pricing section to `examples/ons_data_example.jl` that demonstrates PowerModels DC-OPF for bus-level locational marginal prices using PWF network topology.

Purpose: Demonstrate full nodal pricing capability alongside the existing submarket PLD calculation.
Output: Updated example with optional nodal LMP section that can be enabled when PowerModels is available.
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md

# Existing Infrastructure (already implemented)
- `src/integration/pwf_parser.jl`: `parse_pwf_file()` parses ANAREDE .pwf files
- `src/integration/Integration.jl`: `pwf_to_entities()` converts PWF to Bus/ACLine entities
- `src/integration/powermodels_adapter.jl`: `convert_to_powermodel()` creates PowerModels dict
- `src/integration/Integration.jl`: `solve_dc_opf_nodal_lmps()` extracts nodal LMPs

# Sample Data
PWF files available in `docs/Sample/DS_ONS_102025_RV2D11/`:
- `leve.pwf` (light load case)
- `media.pwf` (medium load case)
- `sab10h.pwf`, `sab19h.pwf` (Saturday cases)
</context>

<tasks>

<task type="auto">
  <name>Add nodal pricing section after PLD display</name>
  <files>examples/ons_data_example.jl</files>
  <action>
After the existing PLD display section (around line 673, after the submarket PLD output), add a new optional section for nodal pricing:

```julia
# ============================================================================
# STEP 6: Optional Nodal Pricing with PWF Network (if PowerModels available)
# ============================================================================

println("\n" * "=" ^ 70)
println("NODAL PRICING (OPTIONAL)")
println("=" ^ 70)

# Check if PowerModels is available
has_powermodels = try
    using PowerModels
    @info "✓ PowerModels is available for nodal pricing"
    true
catch e
    @info "PowerModels not found - skipping nodal pricing section"
    false
end

if has_powermodels && has_highs && result.has_values
    try
        # Path to PWF network file (leve.pwf = light load case)
        pwf_path = joinpath(ons_data_path, "leve.pwf")
        
        if !isfile(pwf_path)
            @warn "PWF file not found: $pwf_path"
            println("  Skipping nodal pricing - no PWF network file")
        else
            println("\nLoading PWF network topology...")
            println("  File: leve.pwf")
            
            # Parse PWF file
            pwf_network = OpenDESSEM.Integration.parse_pwf_file(pwf_path)
            @printf("  Loaded: %d buses, %d branches\n", 
                length(pwf_network.buses), length(pwf_network.branches))
            
            # Convert to OpenDESSEM entities
            pwf_buses, pwf_lines = OpenDESSEM.Integration.pwf_to_entities(pwf_network)
            @printf("  Converted: %d buses, %d AC lines\n", 
                length(pwf_buses), length(pwf_lines))
            
            # Get generator dispatch from solved model (first period)
            # Map to PowerModels generators at their buses
            pm_gens = OpenDESSEM.Entities.ThermalPlant[]
            for plant in system.thermal_plants[1:min(10, end)]  # Limit for demo
                push!(pm_gens, plant)
            end
            
            # Convert to PowerModels format
            # Use period 1 dispatch as snapshot
            pm_data = OpenDESSEM.Integration.convert_to_powermodel(;
                buses = pwf_buses,
                lines = pwf_lines,
                thermals = pm_gens,
                base_mva = 100.0
            )
            
            # Validate conversion
            if !OpenDESSEM.Integration.validate_powermodel_conversion(pm_data)
                @warn "PowerModels validation failed"
            else
                println("\nSolving DC-OPF for nodal LMPs...")
                
                # Solve DC-OPF and extract nodal LMPs
                nodal_result = OpenDESSEM.Integration.solve_dc_opf_nodal_lmps(
                    pm_data, HiGHS.Optimizer)
                
                if nodal_result["status"] == "OPTIMAL" || nodal_result["status"] == "LOCALLY_SOLVED"
                    nodal_lmps = nodal_result["nodal_lmps"]
                    
                    println("\nNodal LMPs (sample buses):")
                    println("  " * "-"^60)
                    
                    # Show top 10 buses by LMP
                    sorted_lmps = sort(collect(nodal_lmps); by = x -> x[2], rev = true)
                    for (i, (bus_id, lmp)) in enumerate(sorted_lmps[1:min(10, end)])
                        # Find bus name if available
                        bus_idx = parse(Int, bus_id)
                        bus_name = bus_idx <= length(pwf_buses) ? pwf_buses[bus_idx].name : "Bus $bus_id"
                        @printf("  %2d. %-30s %8.2f R$/MWh\n", i, bus_name, lmp)
                    end
                    
                    # Summary statistics
                    lmp_values = collect(values(nodal_lmps))
                    println("\nLMP Statistics:")
                    @printf("  Buses with LMP: %d\n", length(lmp_values))
                    @printf("  Average LMP:    %.2f R$/MWh\n", mean(lmp_values))
                    @printf("  Min LMP:        %.2f R$/MWh\n", minimum(lmp_values))
                    @printf("  Max LMP:        %.2f R$/MWh\n", maximum(lmp_values))
                    @printf("  Std Dev:        %.2f R$/MWh\n", std(lmp_values))
                    
                    println("\nComparison with Submarket PLDs:")
                    println("  Nodal pricing shows congestion costs within submarkets")
                    println("  Submarket PLDs = uniform price per submarket")
                    println("  Nodal LMPs = location-specific prices including losses")
                else
                    @warn "DC-OPF did not converge" status=nodal_result["status"]
                end
            end
        end
    catch e
        @warn "Nodal pricing section failed" error=e
        println("  Continuing with example...")
    end
elseif !has_powermodels
    println("\nPowerModels.jl not installed - skipping nodal pricing.")
    println("To enable nodal pricing:")
    println("  using Pkg")
    println("  Pkg.add(\"PowerModels\")")
elseif !result.has_values
    println("\nNo feasible solution available - skipping nodal pricing.")
end
```

Key implementation notes:
1. Place this AFTER the existing PLD section (around line 673, before the "Cost Breakdown" section)
2. Use `try/catch` to make it gracefully optional - failures don't break the example
3. Limit generators to first 10 for demo purposes (full system may be slow)
4. Add `using Statistics: std` to imports at top if not already present
5. Reference PowerModels via qualified path since it's optional
</action>
  <verify>
grep -q "solve_dc_opf_nodal_lmps" examples/ons_data_example.jl && echo "Nodal LMP function call found"
grep -q "NODAL PRICING" examples/ons_data_example.jl && echo "Section header found"
  </verify>
  <done>
- Nodal pricing section added to ons_data_example.jl
- Section is optional (graceful fallback if PowerModels unavailable)
- Displays sample bus LMPs with comparison to submarket PLDs
  </done>
</task>

</tasks>

<verification>
- `grep -c "solve_dc_opf_nodal_lmps" examples/ons_data_example.jl` returns count >= 1
- Section does not break existing functionality (wrapped in try/catch)
- PowerModels import is optional (not required at top level)
</verification>

<success_criteria>
- Example file contains nodal pricing section after PLD display
- Section uses existing infrastructure (parse_pwf_file, pwf_to_entities, solve_dc_opf_nodal_lmps)
- Fails gracefully when PowerModels not installed
- Demonstrates comparison between submarket PLDs and nodal LMPs
</success_criteria>

<output>
After completion, the updated example will demonstrate both pricing methods:
1. Submarket PLDs (existing)
2. Nodal LMPs from PWF network (new optional section)
</output>
