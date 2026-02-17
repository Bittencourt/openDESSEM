# Feature Request: Parse FCF Cuts Binary Files (cortdeco.rv2, mapcut.rv2)

## Summary

Add support for parsing FCF (Future Cost Function) Benders cuts from binary files `cortdeco.rv2` and `mapcut.rv2`. These files contain the NEWAVE-derived cuts that represent the marginal water values for hydro plants in DESSEM optimization.

## Background

The FCF is essential for hydrothermal optimization as it represents the future cost of water usage (opportunity cost). Currently, the `infofcf.dat` file only contains metadata (MAPFCF, FCFFIX records), not the actual FCF cut data.

The actual FCF cuts come from NEWAVE in binary format:
- `cortdeco.rv2` - FCF cuts for DESSEM
- `mapcut.rv2` - Cut mapping/indexing

## Reference Implementation

The **inewave** project (https://github.com/rjmalves/inewave) successfully parses NEWAVE's `cortes.dat` binary file using NumPy's `frombuffer()`. The same format is used in DESSEM's FCF cut files.

Key files from inewave:
- `inewave/newave/modelos/cortes.py` - Binary parsing logic
- `inewave/newave/cortes.py` - Public API

## Binary Format Specification

### Record Structure (based on inewave implementation)

```python
# From inewave/newave/modelos/cortes.py
# Record size: typically 1664 bytes (configurable)
# Structure per cut:

# Integer part: 4 × Int32 = 16 bytes
- indice_corte          # Cut index (linked list pointer)
- iteracao_construcao   # Construction iteration
- indice_forward        # Forward index  
- iteracao_desativacao  # Deactivation iteration

# Float part: N × Float64 = 8N bytes
- rhs                   # Independent term
- pi_varm_uhe{N}        # Volume coefficients (water values)
- pi_qafl_uhe{N}_lag{L} # Inflow coefficients
- pi_gnl_sbm{S}_pat{P}_lag{L} # GNL thermal coefficients
```

### Reading Pattern (from inewave)

```python
def __le_e_atribui_int(self, file: IO, destino: np.ndarray, tamanho: int, indice: int):
    destino[indice, :] = np.frombuffer(
        file.read(tamanho * 4),
        dtype=np.int32,
        count=tamanho,
    )

def __le_e_atribui_float(self, file: IO, destino: np.ndarray, tamanho: int, indice: int):
    destino[indice, :] = np.frombuffer(
        file.read(tamanho * 8),
        dtype=np.float64,
        count=tamanho,
    )
```

### Key Implementation Details

1. **Storage**: `STORAGE = "BINARY"`
2. **Record size**: Variable, typically 1664 bytes (passed as parameter)
3. **Linked list structure**: Cuts point to previous cuts via `indice_corte`
4. **Type sizes**: Int32 = 4 bytes, Float64 = 8 bytes
5. **Little-endian**: Standard for x86/x64

## Proposed Julia Implementation

### 1. Data Structures

```julia
"""
    FCFCut

Single Benders cut from the Future Cost Function.

# Fields
- `indice_corte::Int32`: Cut index (1-based after conversion)
- `iteracao_construcao::Int32`: Construction iteration
- `indice_forward::Int32`: Forward index
- `iteracao_desativacao::Int32`: Deactivation iteration
- `rhs::Float64`: Independent term
- `coeficientes::Vector{Float64}`: Cut coefficients (water values, etc.)
"""
struct FCFCut
    indice_corte::Int32
    iteracao_construcao::Int32
    indice_forward::Int32
    iteracao_desativacao::Int32
    rhs::Float64
    coeficientes::Vector{Float64}
end

"""
    FCFCutsData

Container for all FCF cuts from a binary file.

# Fields
- `cortes::Vector{FCFCut}`: All parsed cuts
- `tamanho_registro::Int`: Record size in bytes
- `numero_total_cortes::Int`: Total number of cuts
- `codigos_rees::Vector{Int}`: REE codes (if aggregated)
- `codigos_uhes::Vector{Int}`: UHE codes (if individualized)
"""
struct FCFCutsData
    cortes::Vector{FCFCut}
    tamanho_registro::Int
    numero_total_cortes::Int
    codigos_rees::Vector{Int}
    codigos_uhes::Vector{Int}
    codigos_submercados::Vector{Int}
    ordem_maxima_parp::Int
    numero_patamares_carga::Int
    lag_maximo_gnl::Int
end
```

### 2. Binary Parsing Function

```julia
"""
    parse_cortdeco(filepath::String; kwargs...) -> FCFCutsData

Parse FCF cuts from binary cortdeco.rv2 file.

# Arguments
- `filepath::String`: Path to cortdeco.rv2 file
- `tamanho_registro::Int=1664`: Record size in bytes
- `indice_ultimo_corte::Int=1`: Index of last cut (starting point)
- `numero_total_cortes::Int=10000`: Maximum cuts to read
- `codigos_rees::Vector{Int}=Int[]`: REE codes for aggregated mode
- `codigos_uhes::Vector{Int}=Int[]`: UHE codes for individualized mode
- `codigos_submercados::Vector{Int}=[1,2,3,4]`: Submarket codes
- `ordem_maxima_parp::Int=12`: Maximum PAR(p) order
- `numero_patamares_carga::Int=3`: Number of load levels
- `lag_maximo_gnl::Int=2`: Maximum GNL lag

# Returns
- `FCFCutsData`: Container with all parsed cuts

# Example
```julia
cuts = parse_cortdeco("cortdeco.rv2",
    tamanho_registro=1664,
    codigos_uhes=[1, 2, 4, 6, 7, 8, 9, 10, 11, 12]
)
println("Number of cuts: ", length(cuts.cortes))
```
"""
function parse_cortdeco(
    filepath::String;
    tamanho_registro::Int=1664,
    indice_ultimo_corte::Int=1,
    numero_total_cortes::Int=10000,
    codigos_rees::Vector{Int}=Int[],
    codigos_uhes::Vector{Int}=Int[],
    codigos_submercados::Vector{Int}=[1, 2, 3, 4],
    ordem_maxima_parp::Int=12,
    numero_patamares_carga::Int=3,
    lag_maximo_gnl::Int=2,
)
    # Calculate number of coefficients based on record size
    # Header: 4 integers × 4 bytes = 16 bytes
    # Remaining: (tamanho_registro - 16) / 8 floats
    bytes_header = 16
    numero_coeficientes = (tamanho_registro - bytes_header) ÷ 8
    
    # Pre-allocate arrays
    tabela_int = zeros(Int32, numero_total_cortes, 4)
    tabela_float = zeros(Float64, numero_total_cortes, numero_coeficientes)
    
    cortes = FCFCut[]
    
    open(filepath, "r") do io
        # Read first cut
        indice_proximo = indice_ultimo_corte
        cortes_lidos = 0
        
        while indice_proximo != 0 && cortes_lidos < numero_total_cortes
            # Seek to cut position
            offset = (indice_proximo - 1) * tamanho_registro
            seek(io, offset)
            
            # Read integer header (4 × Int32)
            int_data = read(io, 4 * 4)
            int_values = reinterpret(Int32, int_data)
            
            indice_corte = int_values[1]
            iteracao_construcao = int_values[2]
            indice_forward = int_values[3]
            iteracao_desativacao = int_values[4]
            
            # Read float coefficients
            float_data = read(io, numero_coeficientes * 8)
            float_values = reinterpret(Float64, float_data)
            
            rhs = float_values[1]
            coeficientes = float_values[2:end]
            
            # Create cut
            cut = FCFCut(
                cortes_lidos + 1,  # Convert to 1-based index
                iteracao_construcao,
                indice_forward,
                iteracao_desativacao,
                rhs,
                collect(coeficientes)
            )
            push!(cortes, cut)
            
            # Next cut index (stored as previous cut index in file)
            indice_proximo = indice_corte
            cortes_lidos += 1
        end
    end
    
    return FCFCutsData(
        cortes,
        tamanho_registro,
        length(cortes),
        codigos_rees,
        codigos_uhes,
        codigos_submercados,
        ordem_maxima_parp,
        numero_patamares_carga,
        lag_maximo_gnl
    )
end
```

### 3. Water Value Lookup

```julia
"""
    get_water_value(cuts::FCFCutsData, uhe_code::Int, storage::Float64) -> Float64

Get interpolated water value for a hydro plant at given storage.

Uses the FCF cuts to compute the marginal water value:
    α >= rhs + Σ(πᵢ * variableᵢ)

# Arguments
- `cuts::FCFCutsData`: FCF cuts container
- `uhe_code::Int`: Hydro plant code
- `storage::Float64`: Current storage (hm³)

# Returns
- `Float64`: Water value (R\$/hm³)

# Example
```julia
cuts = parse_cortdeco("cortdeco.rv2", codigos_uhes=[1,2,4,6])
wv = get_water_value(cuts, 6, 5000.0)  # FURNAS at 5000 hm³
```
"""
function get_water_value(cuts::FCFCutsData, uhe_code::Int, storage::Float64)
    # Find coefficient index for this UHE
    uhe_idx = findfirst(==(uhe_code), cuts.codigos_uhes)
    
    if uhe_idx === nothing
        error("UHE code $uhe_code not found in FCF cuts")
    end
    
    # Coefficient position: after RHS
    # pi_varm_uhe{N} starts at index 2
    coef_idx = 1 + uhe_idx
    
    # Average water value across all cuts
    total_wv = 0.0
    for cut in cuts.cortes
        if coef_idx <= length(cut.coeficientes)
            total_wv += cut.coeficientes[coef_idx]
        end
    end
    
    return total_wv / length(cuts.cortes)
end
```

### 4. Alternative: Direct Record Reading (Simpler)

```julia
"""
    FCFCutRecord

Raw binary record matching FORTRAN unformatted layout.
Use this for direct reading without coefficient interpretation.
"""
struct FCFCutRecord
    # Header (16 bytes)
    indice_proximo::Int32        # Index of previous cut (linked list)
    iteracao_construcao::Int32   # Construction iteration
    indice_forward::Int32        # Forward index
    iteracao_desativacao::Int32  # Deactivation iteration
    
    # Coefficients (variable size, typically 206 Float64 = 1648 bytes)
    rhs::Float64                 # Independent term
    coeficientes::NTuple{205, Float64}  # All coefficients
end

# Verify size matches expected
# @assert sizeof(FCFCutRecord) == 1664 "Record size mismatch!"

function parse_cortdeco_simple(filepath::String; tamanho_registro::Int=1664)
    num_coef = (tamanho_registro - 16) ÷ 8 - 1  # Subtract 1 for RHS
    
    records = FCFCutRecord[]
    
    open(filepath, "r") do io
        while !eof(io)
            try
                # Read header
                indice_proximo = read(io, Int32)
                iteracao_construcao = read(io, Int32)
                indice_forward = read(io, Int32)
                iteracao_desativacao = read(io, Int32)
                
                # Read RHS
                rhs = read(io, Float64)
                
                # Read coefficients
                coeficientes = ntuple(_ -> read(io, Float64), num_coef)
                
                push!(records, FCFCutRecord(
                    indice_proximo,
                    iteracao_construcao,
                    indice_forward,
                    iteracao_desativacao,
                    rhs,
                    coeficientes
                ))
            catch e
                if e isa EOFError
                    break
                end
                rethrow()
            end
        end
    end
    
    return records
end
```

## Testing

```julia
@testset "FCF Cuts Binary Parser" begin
    # Test with sample file
    cuts_path = "docs/Sample/DS_ONS_102025_RV2D11/cortdeco.rv2"
    
    if isfile(cuts_path)
        cuts = parse_cortdeco(cuts_path)
        
        @test !isempty(cuts.cortes)
        @test cuts.tamanho_registro == 1664
        
        # Check first cut has valid data
        first_cut = cuts.cortes[1]
        @test isfinite(first_cut.rhs)
        @test !isempty(first_cut.coeficientes)
        
        # Test water value lookup
        if !isempty(cuts.codigos_uhes)
            wv = get_water_value(cuts, cuts.codigos_uhes[1], 1000.0)
            @test isfinite(wv)
        end
    end
end
```

## Integration with Existing Code

The new parsers should integrate with:

1. **`DessemCase`** - Add `cortes::Union{FCFCutsData, Nothing}` field
2. **FCF loading** - Update `parse_infofcf_dat()` to also load binary cuts
3. **API** - Add `get_cortes()` function

## Files to Modify/Add

```
src/
├── parser/
│   ├── cortdeco.jl      # NEW: Binary FCF cuts parser
│   └── mapcut.jl        # NEW: Cut mapping parser (if different format)
├── types.jl             # Add FCFCut, FCFCutsData structs
└── api.jl               # Add parse_cortdeco(), get_water_value()
```

## References

- **inewave cortes.py**: https://github.com/rjmalves/inewave/blob/main/inewave/newave/modelos/cortes.py
- **inewave cortes API**: https://github.com/rjmalves/inewave/blob/main/inewave/newave/cortes.py
- **cfinterface binary reading**: https://github.com/rjmalves/cfinterface
- **DESSEM manual**: CEPEL documentation

## Related Issues

- `infofcf.dat` parsing (#XX) - Metadata only, needs binary cuts for full FCF support
- HIDR binary parsing (#XX) - Similar pattern, already implemented

## Priority

**Medium** - The FCF cuts are essential for accurate water valuation in hydrothermal optimization, but many use cases can work with:
1. Default/estimated water values
2. Post-solve analysis using `PDO_ECO_FCFCORTES` (text output)
3. External FCF processing

## Questions

1. What is the exact record size for DESSEM's `cortdeco.rv2`? (1664 is typical for NEWAVE)
2. Is `mapcut.rv2` needed or does `cortdeco.rv2` contain all necessary data?
3. Are there sample files with known cut values for validation?
4. Should we also support `PDO_ECO_FCFCORTES` text output parsing?

---

**Labels**: enhancement, parser, binary-format, FCF
**Assignees**: @Bittencourt
