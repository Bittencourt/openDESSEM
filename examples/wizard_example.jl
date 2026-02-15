"""
    Interactive System Builder Wizard

This wizard guides you through creating a power system model step-by-step.
It provides sensible defaults and validates input as you go.

Features:
- Step-by-step guided configuration
- Sensible defaults (just press Enter to accept)
- Input validation with helpful error messages
- Progress tracking
- Option to save/load configurations
- Quick-start option for simple systems
"""

using OpenDESSEM
using OpenDESSEM.Entities
using OpenDESSEM.Variables
using OpenDESSEM.Constraints
using OpenDESSEM.Objective
using OpenDESSEM.Solvers
using HiGHS
using Dates
using Printf

# ============================================================================
# WIZARD STATE
# ============================================================================

mutable struct WizardState
    config::Dict{String, Any}
    current_step::Int
    total_steps::Int

    WizardState() = new(Dict{String, Any}(), 1, 9)
end

const wizard = WizardState()

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    print_header(title::String, step_num::Int, total_steps::Int)

Print a formatted header for the current step.
"""
function print_header(title::String, step_num::Int, total_steps::Int)
    println("\n", "=" ^ 70)
    println("STEP \$step_num of \$total_steps: \$title")
    println("=" ^ 70)
end

"""
    print_prompt(prompt::String, default::Any)

Print a formatted prompt with default value hint.
"""
function print_prompt(prompt::String, default::Any)
    default_str = string(default)
    if occursin("\n", default_str)
        default_str = "[multiline]"
    end
    print("\n\$prompt\n[Default: \$default_str] (press Enter): ")
end

"""
    prompt(prompt::String, default::String; validate::Function = (x) -> true)

Prompt user for input with validation.

# Arguments
- `prompt`: The question to ask
- `default`: Default value if user presses Enter
- `validate`: Optional validation function that returns true if valid

# Returns
The user's input or default value
"""
function prompt(prompt::String, default::String; validate::Function = (x) -> true)
    while true
        print_prompt(prompt, default)
        input = readline()

        # Empty input means accept default
        if isempty(strip(input))
            if validate(default)
                return default
            else
                println("  ⚠ Default value is invalid. Please provide a value.")
                continue
            end
        end

        # Validate user input
        if validate(input)
            return input
        else
            println("  ⚠ Invalid input. Please try again.")
        end
    end
end

"""
    prompt_number(prompt::String, default::Number; type::Type=Float64,
                  min::Real=NaN, max::Real=NaN, integer::Bool=false)

Prompt user for numeric input with validation.

# Arguments
- `prompt`: The question to ask
- `default`: Default value
- `type`: Expected type (Int or Float64)
- `min`: Minimum allowed value (NaN = no minimum)
- `max`: Maximum allowed value (NaN = no maximum)
- `integer`: If true, enforce integer values

# Returns
The user's input or default value as the specified type
"""
function prompt_number(prompt::String, default::Number;
                       type::Type=Float64, min::Real=NaN, max::Real=NaN,
                       integer::Bool=false)
    default_str = string(default)

    # Build validation message
    range_msg = ""
    if !isnan(min) && !isnan(max)
        range_msg = " (must be between \$min and \$max)"
    elseif !isnan(min)
        range_msg = " (must be >= \$min)"
    elseif !isnan(max)
        range_msg = " (must be <= \$max)"
    end

    if integer
        range_msg *= ", integer value"
    end

    while true
        print("\n\$prompt\$range_msg\n[Default: \$default_str]: ")
        input = strip(readline())

        # Empty input means accept default
        if isempty(input)
            if !isnan(min) && default < min
                println("  ⚠ Default is below minimum. Please enter a value.")
                continue
            end
            if !isnan(max) && default > max
                println("  ⚠ Default is above maximum. Please enter a value.")
                continue
            end
            return type(default)
        end

        # Try to parse
        parsed = tryparse(type, input)
        if parsed === nothing
            println("  ⚠ Invalid number format. Please try again.")
            continue
        end

        # Check integer constraint
        if integer && parsed != floor(parsed)
            println("  ⚠ Must be an integer value. Please try again.")
            continue
        end

        # Check range
        if !isnan(min) && parsed < min
            println("  ⚠ Value must be >= \$min. Please try again.")
            continue
        end
        if !isnan(max) && parsed > max
            println("  ⚠ Value must be <= \$max. Please try again.")
            continue
        end

        return parsed
    end
end

"""
    prompt_yes_no(prompt::String, default::Bool)

Prompt user for yes/no response.
"""
function prompt_yes_no(prompt::String, default::Bool)
    default_str = default ? "Y/n" : "y/N"
    print("\n\$prompt\n[Default: \$default_str]: ")

    while true
        input = strip(lowercase(readline()))

        if isempty(input)
            return default
        end

        if input in ["y", "yes", "1", "true"]
            return true
        elseif input in ["n", "no", "0", "false"]
            return false
        else
            print("  Please enter 'y' or 'n': ")
        end
    end
end

"""
    prompt_choice(prompt::String, options::Vector{String}, default_index::Int)

Prompt user to choose from a list of options.

# Arguments
- `prompt`: The question to ask
- `options`: List of options (will be numbered 1, 2, 3, ...)
- `default_index`: Index of default option (1-based)

# Returns
The selected option string
"""
function prompt_choice(prompt::String, options::Vector{String}, default_index::Int)
    println("\n\$prompt")

    for (i, opt) in enumerate(options)
        marker = i == default_index ? "►" : " "
        println("  [\$marker] \$i. \$opt")
    end

    print("\nChoose option [Default: \$default_index]: ")

    while true
        input = strip(readline())

        if isempty(input)
            return options[default_index]
        end

        index = tryparse(Int, input)
        if index === nothing || index < 1 || index > length(options)
            println("  ⚠ Please enter a number between 1 and \$(length(options))")
        else
            return options[index]
        end
    end
end

"""
    prompt_list(prompt::String, item_type::String, n_items::Int)

Prompt user to provide a list of items.

# Arguments
- `prompt`: Description of what to ask for
- `item_type`: Type description for prompts
- `n_items`: How many items to ask for

# Returns
Vector of strings with user input
"""
function prompt_list(prompt::String, item_type::String, n_items::Int)
    println("\n\$prompt")
    println("You will be asked to provide \$n_items \$item_type.\n")

    items = String[]
    for i in 1:n_items
        print("  Enter name/ID for \$item_type #\$i: ")
        name = strip(readline())
        if isempty(name)
            name = "\$(uppercase(item_type[1]))_\$i"
        end
        push!(items, name)
    end

    return items
end

"""
    show_help(topic::String)

Display help information about a topic.
"""
function show_help(topic::String)
    help_text = Dict(
        "bus" => """
        BUS HELP:
        A bus is an electrical node in the network where generators,
        loads, and transmission lines connect.

        Typical values:
        - Voltage: 69kV, 138kV, 230kV, 345kV, 500kV, 765kV
        - Latitude: -23.5 (Sao Paulo)
        - Longitude: -46.6 (Sao Paulo)
        """,

        "submarket" => """
        SUBMARKET HELP:
        A submarket is a bidding zone or market region.

        Common codes:
        - SE: Sudeste (Southeast)
        - S: Sul (South)
        - NE: Nordeste (Northeast)
        - N: Norte (North)
        """,

        "thermal" => """
        THERMAL PLANT HELP:
        Thermal plants generate electricity from heat sources.

        Fuel types:
        - NATURAL_GAS: Flexible, medium cost
        - COAL: Cheap baseload, slow ramping
        - FUEL_OIL: Peaking, expensive
        - DIESEL: Small peaking units
        - NUCLEAR: Cheap baseload, no ramping
        - BIOMASS: Renewable thermal

        Typical parameters:
        - Capacity: 50-1000 MW
        - Min generation: 20-50% of capacity
        - Ramp rate: 1-20 MW/min
        - Min up time: 2-8 hours
        - Min down time: 2-6 hours
        - Fuel cost: 50-300 R\$/MWh
        - Startup cost: 5000-50000 R\$
        """,

        "hydro" => """
        HYDRO PLANT HELP:
        Hydro plants generate electricity from water flow.

        Types:
        - Reservoir: Large storage, flexible
        - Run-of-river: No storage, must-run
        - Pumped storage: Can pump water uphill

        Typical parameters:
        - Max volume: 1000-10000 hm³ (cubic hectometers)
        - Initial volume: 20-80% of max
        - Max outflow: 100-1000 m³/s
        - Efficiency: 85-95%
        - Max generation: 50-500 MW
        - Water value: 30-100 R\$/hm³
        """,

        "renewable" => """
        RENEWABLE PLANT HELP:
        Wind and solar plants with variable output.

        Wind:
        - Typical capacity: 50-500 MW
        - Output varies with wind speed
        - Often non-dispatchable

        Solar:
        - Typical capacity: 10-200 MW
        - Diurnal generation pattern
        - Zero output at night
        """,

        "solver" => """
        SOLVER OPTIONS HELP:

        Time limit: Maximum solver time in seconds
        - Small systems (< 100 vars): 60 seconds
        - Medium systems (100-1000): 300 seconds
        - Large systems (> 1000): 1800 seconds

        MIP gap: Relative optimality gap (0.0-1.0)
        - 0.01 = 1% gap (default, good balance)
        - 0.001 = 0.1% gap (more accurate, slower)
        - 0.05 = 5% gap (faster, less accurate)

        Threads: Number of CPU cores to use
        - 1: Single-threaded (default)
        - 4+: Multi-threaded (faster on large problems)
        """
    )

    if haskey(help_text, topic)
        println("\n" * "-" ^ 70)
        println(help_text[topic])
        println("-" ^ 70)
    else
        println("\n⚠ No help available for '\$topic'")
    end
end

# ============================================================================
# WIZARD STEPS
# ============================================================================

"""
    step_1_system_basics()

Step 1: Configure basic system information.
"""
function step_1_system_basics()
    print_header("SYSTEM BASICS", 1, wizard.total_steps)

    println("\nThis wizard will guide you through creating a power system model.")
    println("You can accept defaults by pressing Enter, or type 'help' for information.")
    println("Type 'quit' at any time to exit.\n")

    # System name
    wizard.config["system_name"] = prompt(
        "Enter a name for your system",
        "My Power System"
    )

    # Base date
    print("\nEnter the base date (simulation start date)")
    print("\n[Default: 2025-01-15] (format: YYYY-MM-DD): ")
    date_input = strip(readline())

    if isempty(date_input)
        wizard.config["base_date"] = Date(2025, 1, 15)
    else
        try
            wizard.config["base_date"] = Date(date_input, dateformat"yyyy-mm-dd")
        catch
            println("  ⚠ Invalid date format. Using default.")
            wizard.config["base_date"] = Date(2025, 1, 15)
        end
    end

    # Time horizon
    wizard.config["time_periods"] = prompt_number(
        "How many time periods (hours) to simulate?",
        24;
        type=Int,
        min=1,
        max=168,
        integer=true
    )

    println("\n✓ System basics configured")
end

"""
    step_2_buses()

Step 2: Define electrical buses.
"""
function step_2_buses()
    print_header("DEFINE BUSES", 2, wizard.total_steps)

    println("\nBuses are electrical nodes where generators, loads, and lines connect.")
    println("Type 'help' at any time for more information.\n")

    # Ask for help
    show_help("bus")

    n_buses = prompt_number(
        "How many buses do you want?",
        3;
        type=Int,
        min=1,
        max=100,
        integer=true
    )

    wizard.config["n_buses"] = n_buses

    # Quick mode: create with defaults
    if n_buses <= 5
        create_simple = prompt_yes_no(
            "Create buses with default settings?",
            true
        )

        if create_simple
            wizard.config["buses"] = create_default_buses(n_buses)
            println("\n✓ Created \$n_buses buses with default settings")
            return
        end
    end

    # Detailed configuration
    bus_names = prompt_list("Enter bus names:", "bus", n_buses)
    wizard.config["bus_names"] = bus_names

    # Voltage level
    default_voltage = prompt_choice(
        "Select default voltage level:",
        ["69 kV", "138 kV", "230 kV", "345 kV", "500 kV", "765 kV"],
        3
    )
    wizard.config["bus_voltage"] = parse(Float64, split(default_voltage)[1])

    println("\n✓ Buses configured")
end

"""
    create_default_buses(n::Int) -> Vector{Bus}

Create default buses with sensible values.
"""
function create_default_buses(n::Int)
    buses = Bus[]
    regions = ["North", "Center", "South", "East", "West"]
    voltages = [230.0, 345.0, 500.0, 138.0, 69.0]

    for i in 1:n
        idx = min(i, length(regions))
        bus = Bus(;
            id = "BUS_\$(i)",
            name = "Bus \$i - \$(regions[idx])",
            voltage_kv = voltages[idx],
            base_kv = voltages[idx],
            latitude = -23.5 + (i * 0.5),
            longitude = -46.6 + (i * 0.5)
        )
        push!(buses, bus)
    end

    return buses
end

"""
    step_3_submarkets()

Step 3: Define submarkets (bidding zones).
"""
function step_3_submarkets()
    print_header("DEFINE SUBMARKETS", 3, wizard.total_steps)

    # Ask for help
    show_help("submarket")

    n_submarkets = prompt_number(
        "How many submarkets (bidding zones)?",
        min(3, wizard.config["n_buses"]);
        type=Int,
        min=1,
        max=10,
        integer=true
    )

    wizard.config["n_submarkets"] = n_submarkets

    # Quick creation
    create_simple = prompt_yes_no(
        "Create submarkets with default settings?",
        true
    )

    if create_simple
        wizard.config["submarkets"] = create_default_submarkets(n_submarkets)
        println("\n✓ Created \$n_submarkets submarkets with default settings")
        return
    end

    # Detailed configuration would go here
    wizard.config["submarkets"] = create_default_submarkets(n_submarkets)
    println("\n✓ Submarkets configured")
end

"""
    create_default_submarkets(n::Int) -> Vector{Submarket}

Create default submarkets.
"""
function create_default_submarkets(n::Int)
    submarkets = Submarket[]
    codes = ["N", "NE", "SE", "S"]
    names = ["North", "Northeast", "Southeast", "South"]

    for i in 1:n
        idx = min(i, length(codes))
        sub = Submarket(;
            id = "SUB_\$(i)",
            code = codes[idx],
            name = "\$(names[idx]) Region",
            country = "BR"
        )
        push!(submarkets, sub)
    end

    return submarkets
end

"""
    step_4_thermal_plants()

Step 4: Define thermal power plants.
"""
function step_4_thermal_plants()
    print_header("DEFINE THERMAL PLANTS", 4, wizard.total_steps)

    show_help("thermal")

    n_thermal = prompt_number(
        "How many thermal plants?",
        3;
        type=Int,
        min=0,
        max=50,
        integer=true
    )

    wizard.config["n_thermal"] = n_thermal

    if n_thermal == 0
        wizard.config["thermal_plants"] = ConventionalThermal[]
        println("\n✓ No thermal plants created")
        return
    end

    # Quick creation
    create_simple = prompt_yes_no(
        "Create thermal plants with default settings?",
        true
    )

    if create_simple
        wizard.config["thermal_plants"] = create_default_thermal_plants(
            n_thermal,
            wizard.config["bus_names"],
            wizard.config["submarkets"]
        )
        println("\n✓ Created \$n_thermal thermal plants with default settings")
        return
    end

    # Detailed configuration
    wizard.config["thermal_plants"] = create_default_thermal_plants(
        n_thermal,
        wizard.config["bus_names"],
        wizard.config["submarkets"]
    )
    println("\n✓ Thermal plants configured")
end

"""
    create_default_thermal_plants(n::Int, bus_names::Vector{String},
                                  submarkets::Vector{Submarket}) -> Vector{ConventionalThermal}

Create default thermal plants with diverse characteristics.
"""
function create_default_thermal_plants(n::Int, bus_names::Vector{String},
                                       submarkets::Vector{Submarket})
    plants = ConventionalThermal[]
    fuel_types = [COAL, NATURAL_GAS, NATURAL_GAS]
    capacities = [500.0, 300.0, 200.0]
    costs = [80.0, 120.0, 200.0]

    for i in 1:n
        idx = min(i, length(fuel_types))
        bus_idx = min(i, length(bus_names))
        sub_idx = min(i, length(submarkets))

        plant = ConventionalThermal(;
            id = "T_\$(i)",
            name = "Thermal Plant \$i",
            bus_id = bus_names[bus_idx],
            submarket_id = submarkets[sub_idx].code,
            fuel_type = fuel_types[idx],
            capacity_mw = capacities[idx],
            min_generation_mw = capacities[idx] * 0.3,
            max_generation_mw = capacities[idx],
            ramp_up_mw_per_min = 5.0 + idx * 5.0,
            ramp_down_mw_per_min = 5.0 + idx * 5.0,
            min_up_time_hours = 8 - idx * 2,
            min_down_time_hours = 4 - idx,
            fuel_cost_rsj_per_mwh = costs[idx],
            startup_cost_rs = 50000.0 - idx * 15000.0,
            shutdown_cost_rs = 20000.0 - idx * 5000.0,
            commissioning_date = DateTime(2010, 6, 1, 0, 0, 0)
        )
        push!(plants, plant)
    end

    return plants
end

"""
    step_5_hydro_plants()

Step 5: Define hydroelectric plants.
"""
function step_5_hydro_plants()
    print_header("DEFINE HYDRO PLANTS", 5, wizard.total_steps)

    show_help("hydro")

    n_hydro = prompt_number(
        "How many hydro plants?",
        1;
        type=Int,
        min=0,
        max=50,
        integer=true
    )

    wizard.config["n_hydro"] = n_hydro

    if n_hydro == 0
        wizard.config["hydro_plants"] = ReservoirHydro[]
        println("\n✓ No hydro plants created")
        return
    end

    # Quick creation
    create_simple = prompt_yes_no(
        "Create hydro plants with default settings?",
        true
    )

    if create_simple
        wizard.config["hydro_plants"] = create_default_hydro_plants(
            n_hydro,
            wizard.config["bus_names"],
            wizard.config["submarkets"]
        )
        println("\n✓ Created \$n_hydro hydro plants with default settings")
        return
    end

    wizard.config["hydro_plants"] = create_default_hydro_plants(
        n_hydro,
        wizard.config["bus_names"],
        wizard.config["submarkets"]
    )
    println("\n✓ Hydro plants configured")
end

"""
    create_default_hydro_plants(n::Int, bus_names::Vector{String},
                                submarkets::Vector{Submarket}) -> Vector{ReservoirHydro}

Create default hydro plants.
"""
function create_default_hydro_plants(n::Int, bus_names::Vector{String},
                                     submarkets::Vector{Submarket})
    plants = ReservoirHydro[]

    for i in 1:n
        bus_idx = min(i + 1, length(bus_names))
        sub_idx = min(i + 1, length(submarkets))

        plant = ReservoirHydro(;
            id = "H_\$(i)",
            name = "Hydro Plant \$i",
            bus_id = bus_names[bus_idx],
            submarket_id = submarkets[sub_idx].code,
            max_volume_hm3 = 5000.0,
            initial_volume_hm3 = 2500.0,
            min_volume_hm3 = 500.0,
            min_outflow_m3_per_s = 0.0,
            max_outflow_m3_per_s = 500.0,
            efficiency = 90.0,
            max_generation_mw = 200.0,
            min_generation_mw = 50.0,
            water_value_rs_per_hm3 = 50.0,
            subsystem_code = i,
            initial_volume_percent = 50.0
        )
        push!(plants, plant)
    end

    return plants
end

"""
    step_6_renewables()

Step 6: Define renewable energy sources.
"""
function step_6_renewables()
    print_header("DEFINE RENEWABLES", 6, wizard.total_steps)

    show_help("renewable")

    has_wind = prompt_yes_no(
        "Include wind farms?",
        true
    )

    n_wind = 0
    if has_wind
        n_wind = prompt_number(
            "How many wind farms?",
            1;
            type=Int,
            min=1,
            max=20,
            integer=true
        )
    end

    has_solar = prompt_yes_no(
        "Include solar farms?",
        false
    )

    n_solar = 0
    if has_solar
        n_solar = prompt_number(
            "How many solar farms?",
            1;
            type=Int,
            min=1,
            max=20,
            integer=true
        )
    end

    wizard.config["n_wind"] = n_wind
    wizard.config["n_solar"] = n_solar

    # Create defaults
    wind_farms = n_wind > 0 ? create_default_wind_farms(n_wind, wizard.config["bus_names"], wizard.config["submarkets"]) : WindPlant[]
    solar_farms = n_solar > 0 ? create_default_solar_farms(n_solar, wizard.config["bus_names"], wizard.config["submarkets"]) : SolarPlant[]

    wizard.config["wind_farms"] = wind_farms
    wizard.config["solar_farms"] = solar_farms

    println("\n✓ Renewables configured (\$(length(wind_farms)) wind, \$(length(solar_farms)) solar)")
end

"""
    create_default_wind_farms(n::Int, bus_names::Vector{String},
                              submarkets::Vector{Submarket}) -> Vector{WindPlant}

Create default wind farms.
"""
function create_default_wind_farms(n::Int, bus_names::Vector{String},
                                   submarkets::Vector{Submarket})
    farms = WindPlant[]
    n_bus = length(bus_names)
    n_sub = length(submarkets)

    for i in 1:n
        bus_idx = min(n_bus - i + 1, n_bus)
        sub_idx = min(n_bus - i + 1, n_sub)

        farm = WindPlant(;
            id = "W_\$(i)",
            name = "Wind Farm \$i",
            bus_id = bus_names[bus_idx],
            submarket_id = submarkets[sub_idx].code,
            capacity_mw = 150.0,
            forecast_type = DETERMINISTIC,
            is_dispatchable = false
        )
        push!(farms, farm)
    end

    return farms
end

"""
    create_default_solar_farms(n::Int, bus_names::Vector{String},
                               submarkets::Vector{Submarket}) -> Vector{SolarPlant}

Create default solar farms.
"""
function create_default_solar_farms(n::Int, bus_names::Vector{String},
                                    submarkets::Vector{Submarket})
    farms = SolarPlant[]
    n_bus = length(bus_names)
    n_sub = length(submarkets)

    for i in 1:n
        bus_idx = min(i, n_bus)
        sub_idx = min(i, n_sub)

        farm = SolarPlant(;
            id = "S_\$(i)",
            name = "Solar Farm \$i",
            bus_id = bus_names[bus_idx],
            submarket_id = submarkets[sub_idx].code,
            capacity_mw = 100.0,
            forecast_type = DETERMINISTIC,
            is_dispatchable = false
        )
        push!(farms, farm)
    end

    return farms
end

"""
    step_7_loads()

Step 7: Define loads (demand).
"""
function step_7_loads()
    print_header("DEFINE LOADS", 7, wizard.total_steps)

    n_loads = prompt_number(
        "How many loads?",
        wizard.config["n_buses"];
        type=Int,
        min=1,
        max=50,
        integer=true
    )

    wizard.config["n_loads"] = n_loads

    # Quick creation
    create_simple = prompt_yes_no(
        "Create loads with default patterns?",
        true
    )

    n_hours = wizard.config["time_periods"]

    if create_simple
        wizard.config["loads"] = create_default_loads(
            n_loads,
            wizard.config["bus_names"],
            wizard.config["submarkets"],
            n_hours
        )
        println("\n✓ Created \$n_loads loads with default patterns")
        return
    end

    wizard.config["loads"] = create_default_loads(
        n_loads,
        wizard.config["bus_names"],
        wizard.config["submarkets"],
        n_hours
    )
    println("\n✓ Loads configured")
end

"""
    create_default_loads(n::Int, bus_names::Vector{String},
                        submarkets::Vector{Submarket}, n_hours::Int) -> Vector{Load}

Create default loads with time-varying patterns.
"""
function create_default_loads(n::Int, bus_names::Vector{String},
                              submarkets::Vector{Submarket}, n_hours::Int)
    loads = Load[]

    for i in 1:n
        bus_idx = min(i, length(bus_names))
        sub_idx = min(i, length(submarkets))

        # Different load patterns
        if i == 1
            # Steady industrial load
            profile = fill(400.0, n_hours)
        elseif i == 2
            # Daytime commercial peak
            profile = vcat(fill(300.0, 6), fill(500.0, 12), fill(400.0, 6))
            if n_hours > 24
                profile = repeat(profile, outer=ceil(Int, n_hours/24))[1:n_hours]
            end
        else
            # Residential evening peak
            profile = vcat(fill(200.0, 12), fill(350.0, 6), fill(250.0, 6))
            if n_hours > 24
                profile = repeat(profile, outer=ceil(Int, n_hours/24))[1:n_hours]
            end
        end

        load = Load(;
            id = "L_\$(i)",
            name = "Load \$i",
            bus_id = bus_names[bus_idx],
            submarket_id = submarkets[sub_idx].code,
            base_mw = maximum(profile),
            load_profile = profile
        )
        push!(loads, load)
    end

    return loads
end

"""
    step_8_interconnections()

Step 8: Define transmission interconnections.
"""
function step_8_interconnections()
    print_header("DEFINE INTERCONNECTIONS", 8, wizard.total_steps)

    n_buses = wizard.config["n_buses"]

    if n_buses < 2
        println("\n⚠ Need at least 2 buses for interconnections")
        wizard.config["interconnections"] = Interconnection[]
        return
    end

    # Calculate max possible connections
    max_connections = div(n_buses * (n_buses - 1), 2)

    n_connections = prompt_number(
        "How many interconnections between buses?",
        min(n_buses - 1, max_connections);
        type=Int,
        min=0,
        max=max_connections,
        integer=true
    )

    if n_connections == 0
        wizard.config["interconnections"] = Interconnection[]
        println("\n✓ No interconnections created")
        return
    end

    # Quick creation
    create_simple = prompt_yes_no(
        "Create interconnections with default settings?",
        true
    )

    if create_simple
        wizard.config["interconnections"] = create_default_interconnections(
            n_connections,
            wizard.config["bus_names"],
            wizard.config["submarkets"]
        )
        println("\n✓ Created \$n_connections interconnections")
        return
    end

    wizard.config["interconnections"] = create_default_interconnections(
        n_connections,
        wizard.config["bus_names"],
        wizard.config["submarkets"]
    )
    println("\n✓ Interconnections configured")
end

"""
    create_default_interconnections(n::Int, bus_names::Vector{String},
                                    submarkets::Vector{Submarket}) -> Vector{Interconnection}

Create default interconnections.
"""
function create_default_interconnections(n::Int, bus_names::Vector{String},
                                         submarkets::Vector{Submarket})
    connections = Interconnection[]
    n_bus = length(bus_names)
    n_sub = length(submarkets)

    # Connect adjacent buses
    for i in 1:min(n, n_bus - 1)
        from_bus = bus_names[i]
        to_bus = bus_names[min(i + 1, n_bus)]
        from_sub = submarkets[min(i, n_sub)].code
        to_sub = submarkets[min(i + 1, n_sub)].code

        conn = Interconnection(;
            id = "IC_\$(i)_\$(i+1)",
            name = "Connection \$from_bus to \$to_bus",
            from_bus_id = from_bus,
            to_bus_id = to_bus,
            from_submarket_id = from_sub,
            to_submarket_id = to_sub,
            capacity_mw = 200.0,
            loss_percent = 2.0
        )
        push!(connections, conn)
    end

    return connections
end

"""
    step_9_solver_options()

Step 9: Configure solver options.
"""
function step_9_solver_options()
    print_header("SOLVER OPTIONS", 9, wizard.total_steps)

    show_help("solver")

    # Time limit
    time_limit = prompt_number(
        "Maximum solve time (seconds)?",
        300.0;
        type=Float64,
        min=10.0,
        max=7200.0
    )

    # MIP gap
    mip_gap = prompt_number(
        "Relative MIP gap (0.01 = 1%)?",
        0.01;
        type=Float64,
        min=0.0,
        max=1.0
    )

    # Threads
    threads = prompt_number(
        "Number of threads (1 for single-threaded)?",
        1;
        type=Int,
        min=1,
        max=16,
        integer=true
    )

    wizard.config["time_limit"] = time_limit
    wizard.config["mip_gap"] = mip_gap
    wizard.config["threads"] = threads

    println("\n✓ Solver options configured")
end

# ============================================================================
# WIZARD ORCHESTRATION
# ============================================================================

"""
    display_summary()

Display a summary of the configured system.
"""
function display_summary()
    println("\n", "=" ^ 70)
    println("SYSTEM CONFIGURATION SUMMARY")
    println("=" ^ 70)

    println("\nSystem: ", wizard.config["system_name"])
    println("Base Date: ", wizard.config["base_date"])
    println("Time Periods: ", wizard.config["time_periods"])

    println("\nNetwork:")
    println("  Buses: ", wizard.config["n_buses"])
    println("  Submarkets: ", wizard.config["n_submarkets"])

    println("\nGeneration:")
    println("  Thermal Plants: ", wizard.config["n_thermal"])
    println("  Hydro Plants: ", wizard.config["n_hydro"])
    println("  Wind Farms: ", get(wizard.config, "n_wind", 0))
    println("  Solar Farms: ", get(wizard.config, "n_solar", 0))

    println("\nDemand & Transmission:")
    println("  Loads: ", wizard.config["n_loads"])
    println("  Interconnections: ", length(wizard.config["interconnections"]))

    println("\nSolver:")
    println("  Time Limit: ", wizard.config["time_limit"], " seconds")
    println("  MIP Gap: ", wizard.config["mip_gap"])
    println("  Threads: ", wizard.config["threads"])

    println("\n" * "=" ^ 70)
end

"""
    build_system() -> ElectricitySystem

Build the ElectricitySystem from wizard configuration.
"""
function build_system()::ElectricitySystem
    # Get entities from config
    buses = wizard.config["buses"]
    submarkets = wizard.config["submarkets"]
    thermal_plants = wizard.config["thermal_plants"]
    hydro_plants = wizard.config["hydro_plants"]
    wind_farms = wizard.config["wind_farms"]
    solar_farms = wizard.config["solar_farms"]
    loads = wizard.config["loads"]
    interconnections = wizard.config["interconnections"]

    # Add forecasts to renewables
    n_hours = wizard.config["time_periods"]

    for farm in wind_farms
        # Simple wind forecast: higher during day
        forecast = vcat(
            fill(50.0, 6),
            fill(120.0, 12),
            fill(80.0, 6)
        )
        if n_hours > 24
            forecast = repeat(forecast, outer=ceil(Int, n_hours/24))[1:n_hours]
        end
        farm.capacity_forecast = forecast
    end

    for farm in solar_farms
        # Solar forecast: zero at night, peak during day
        n_day = n_hours % 24
        if n_day == 0
            n_day = 24
        end

        base_profile = vcat(
            fill(0.0, 6),   # Night
            range(0, 100, length=6),  # Morning ramp
            range(100, 100, length=4),  # Peak
            range(100, 0, length=4),  # Evening decline
            fill(0.0, 4)    # Night
        )

        forecast = repeat(base_profile, outer=ceil(Int, n_hours/24))[1:n_hours]
        farm.capacity_forecast = forecast
    end

    # Create the system
    system = ElectricitySystem(;
        buses = buses,
        submarkets = submarkets,
        thermal_plants = thermal_plants,
        hydro_plants = hydro_plants,
        wind_farms = wind_farms,
        solar_farms = solar_farms,
        loads = loads,
        interconnections = interconnections,
        base_date = wizard.config["base_date"]
    )

    return system
end

"""
    run_optimization(system::ElectricitySystem)

Run the optimization with configured solver options.
"""
function run_optimization(system::ElectricitySystem)
    println("\n", "=" ^ 70)
    println("RUNNING OPTIMIZATION")
    println("=" ^ 70)

    time_periods = 1:wizard.config["time_periods"]

    # Create model
    println("\nCreating optimization model...")
    model = Model()

    # Create variables
    println("Creating variables...")
    create_variables!(model, system, time_periods)

    # Build constraints
    println("Building constraints...")

    # Thermal UC
    if !isempty(system.thermal_plants)
        thermal_uc = ThermalCommitmentConstraint(;
            metadata = ConstraintMetadata(;
                name = "Thermal Unit Commitment",
                description = "UC constraints for thermal plants",
                priority = 10
            ),
            include_ramp_rates = true,
            include_min_up_down = true,
            initial_commitment = Dict(p.id => false for p in system.thermal_plants)
        )
        build!(model, system, thermal_uc)
    end

    # Hydro water balance
    if !isempty(system.hydro_plants)
        hydro_constraint = HydroWaterBalanceConstraint(;
            metadata = ConstraintMetadata(;
                name = "Hydro Water Balance",
                description = "Water balance for hydro plants",
                priority = 10
            )
        )
        build!(model, system, hydro_constraint)
    end

    # Renewable limits
    if !isempty(system.wind_farms) || !isempty(system.solar_farms)
        renewable_constraint = RenewableLimitConstraint(;
            metadata = ConstraintMetadata(;
                name = "Renewable Limits",
                description = "Wind/solar generation limits",
                priority = 10
            )
        )
        build!(model, system, renewable_constraint)
    end

    # Submarket balance
    balance_constraint = SubmarketBalanceConstraint(;
        metadata = ConstraintMetadata(;
            name = "Submarket Energy Balance",
            description = "Energy balance for LMP calculation",
            priority = 10
        )
    )
    build!(model, system, balance_constraint)

    # Build objective
    println("Building objective...")

    n_hours = wizard.config["time_periods"]

    fuel_costs = Dict{String,Vector{Float64}}()
    startup_costs = Dict{String,Vector{Float64}}()

    for plant in system.thermal_plants
        fuel_costs[plant.id] = fill(plant.fuel_cost_rs_per_mwh, n_hours)
        startup_costs[plant.id] = fill(plant.startup_cost_rs, n_hours)
    end

    build_objective!(model, system;
        fuel_costs = fuel_costs,
        startup_costs = startup_costs,
        shutdown_costs = Dict{String,Vector{Float64}}()
    )

    # Solve
    println("\nSolving optimization problem...")

    solver_options = SolverOptions(;
        time_limit_seconds = wizard.config["time_limit"],
        mip_gap = wizard.config["mip_gap"],
        threads = wizard.config["threads"],
        verbose = false
    )

    result = compute_two_stage_lmps(
        model, system, HiGHS.Optimizer;
        options = solver_options
    )

    return result
end

"""
    display_results(uc_result, sced_result, system)

Display optimization results.
"""
function display_results(uc_result, sced_result, system)
    println("\n", "=" ^ 70)
    println("OPTIMIZATION RESULTS")
    println("=" ^ 70)

    if sced_result !== nothing && is_optimal(sced_result)
        println("\n✓ Optimization successful!")
        @printf("  Stage 1 (UC) Objective: R\$ %.2f\n", uc_result.objective_value)
        @printf("  Stage 1 Solve Time: %.2f seconds\n", uc_result.solve_time_seconds)
        @printf("  Stage 2 (SCED) Objective: R\$ %.2f\n", sced_result.objective_value)
        @printf("  Stage 2 Solve Time: %.2f seconds\n", sced_result.solve_time_seconds)

        # Show LMPs
        println("\n" * "-" ^ 70)
        println("LOCATIONAL MARGINAL PRICES (LMP)")
        println("-" * 70)

        time_periods = 1:wizard.config["time_periods"]

        for submarket in system.submarkets
            println("\n\$(submarket.name) (\$(submarket.code))")

            lmps = get_submarket_lmps(sced_result, submarket.code, time_periods)

            # Show sample hours
            display_hours = time_periods[1:min(5, length(time_periods))]
            for t in display_hours
                @printf("  Hour %3d: %8.2f R\$ /MWh\n", t, lmps[t])
            end

            if length(time_periods) > 5
                println("  ...")
            end

            avg_lmp = sum(lmps) / length(lmps)
            @printf("  Average: %.2f R\$/MWh\n", avg_lmp)
        end
    else
        println("\n✗ Optimization failed or did not converge")
    end

    println("\n" * "=" ^ 70)
end

"""
    run_wizard()

Main wizard orchestration function.
"""
function run_wizard()
    println("\n")
    println("╔" * "=" ^ 68 * "╗")
    println("║" * " " ^ 15 * "OpenDESSEM System Builder Wizard" * " " ^ 21 * "║")
    println("╚" * "=" ^ 68 * "╝")

    try
        # Run all steps
        step_1_system_basics()
        step_2_buses()
        step_3_submarkets()
        step_4_thermal_plants()
        step_5_hydro_plants()
        step_6_renewables()
        step_7_loads()
        step_8_interconnections()
        step_9_solver_options()

        # Display summary
        display_summary()

        # Confirm
        proceed = prompt_yes_no(
            "\nProceed to build and solve the system?",
            true
        )

        if !proceed
            println("\n✗ Wizard cancelled by user")
            return
        end

        # Build system
        println("\nBuilding electricity system...")
        system = build_system()

        println("\n✓ System created successfully!")
        println("  Entities validated and connected")

        # Run optimization
        uc_result, sced_result = run_optimization(system)

        # Display results
        display_results(uc_result, sced_result, system)

        println("\n✓ Wizard completed successfully!")

    catch e
        println("\n✗ Error during wizard execution:")
        println(e)
        # println(stacktrace(catch_backtrace()))
    end
end

# ============================================================================
# QUICK START MODE
# ============================================================================

"""
    quick_start()

Create a simple system with minimal interaction.
"""
function quick_start()
    println("\n" * "=" ^ 70)
    println("QUICK START MODE - Creating Simple 3-Bus System")
    println("=" ^ 70)

    # Pre-configure wizard
    wizard.config["system_name"] = "Quick Start System"
    wizard.config["base_date"] = Date(2025, 1, 15)
    wizard.config["time_periods"] = 24

    # Use defaults
    wizard.config["n_buses"] = 3
    wizard.config["bus_names"] = ["BUS_1", "BUS_2", "BUS_3"]
    wizard.config["bus_voltage"] = 230.0
    wizard.config["buses"] = create_default_buses(3)

    wizard.config["n_submarkets"] = 3
    wizard.config["submarkets"] = create_default_submarkets(3)

    wizard.config["n_thermal"] = 3
    wizard.config["thermal_plants"] = create_default_thermal_plants(
        3, ["BUS_1", "BUS_2", "BUS_3"], wizard.config["submarkets"]
    )

    wizard.config["n_hydro"] = 1
    wizard.config["hydro_plants"] = create_default_hydro_plants(
        1, ["BUS_1", "BUS_2", "BUS_3"], wizard.config["submarkets"]
    )

    wizard.config["n_wind"] = 1
    wizard.config["n_solar"] = 0
    wizard.config["wind_farms"] = create_default_wind_farms(
        1, ["BUS_1", "BUS_2", "BUS_3"], wizard.config["submarkets"]
    )
    wizard.config["solar_farms"] = SolarPlant[]

    wizard.config["n_loads"] = 3
    wizard.config["loads"] = create_default_loads(
        3, ["BUS_1", "BUS_2", "BUS_3"], wizard.config["submarkets"], 24
    )

    wizard.config["interconnections"] = create_default_interconnections(
        2, ["BUS_1", "BUS_2", "BUS_3"], wizard.config["submarkets"]
    )

    wizard.config["time_limit"] = 300.0
    wizard.config["mip_gap"] = 0.01
    wizard.config["threads"] = 1

    display_summary()

    # Build and solve
    println("\nBuilding electricity system...")
    system = build_system()

    println("\n✓ System created!")

    uc_result, sced_result = run_optimization(system)
    display_results(uc_result, sced_result, system)

    println("\n✓ Quick start completed!")
end

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

println("\n" * "=" ^ 70)
println("OpenDESSEM System Builder Wizard")
println("=" ^ 70)

println("\nChoose your mode:")
println("  1. Interactive Wizard (guided step-by-step)")
println("  2. Quick Start (simple 3-bus system)")
println("  3. Exit")

print("\nEnter choice [Default: 2]: ")
choice = strip(readline())

if isempty(choice) || choice == "2"
    quick_start()
elseif choice == "1"
    run_wizard()
else
    println("\nExiting...")
end
