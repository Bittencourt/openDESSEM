# ONS Network Files Analysis

## Overview

**Answer**: YES, the ONS files include comprehensive network topology and electrical network data. 

The ONS sample (`DS_ONS_102025_RV2D11`) includes full network simulation capabilities for day 11 (October 11, 2025) with half-hourly resolution, then simplified representation for days 12-17.

## Key Differences: ONS vs CCEE

| Feature | ONS Sample | CCEE Sample |
|---------|------------|-------------|
| **Network Flag** | `1` (network enabled) for day 11 | `0` (no network) |
| **PWF Files** | ✅ 4 base case files | ❌ None |
| **AFP Files** | ✅ 48 pattern files (half-hourly) | ❌ None |
| **Time Resolution** | Half-hourly (0.5h) for day 11 | Aggregated periods |
| **Use Case** | Full network simulation (ONS operational) | Simplified dispatch (CCEE market) |
| **Directory Suffix** | No suffix | `_SEMREDE` (without network) |

## Files Defining Network Topology

### 1. **entdados.dat** - Main Topology File
Location: `docs/Sample/DS_ONS_102025_RV2D11/entdados.dat`
Size: 5,399 lines

**Network Configuration Records**:
```
RD  1    800  0 1                    # Network options: slack=1, max_circuits=800, format=1
RIVAR  999     4                     # Variation restrictions: entity=999, var_type=4
```

**Time Discretization with Network Flag**:
```
TM  11    0   0      0.5     1     LEVE    # Day 11: network_flag=1, 0.5h, LEVE pattern
TM  11    0  30      0.5     1     LEVE    # Half-hourly intervals
...
TM  11   23  30      0.5     1     LEVE    # 48 half-hourly periods for day 11

TM  12    0   0       21       0              # Days 12-17: network_flag=0 (simplified)
```

**Subsystems (5 total)**:
```
SIST    1 SE  0 SUDESTE       # Southeast/Central-West
SIST    2 S   0 SUL           # South
SIST    3 NE  0 NORDESTE      # Northeast
SIST    4 N   0 NORTE         # North
SIST    5 FC  0 FICTICIOCONS  # Fictitious consumers
```

**Energy Reservoirs (12 total)**:
```
REE    1  1 SUDESTE           # REE 1: Sudeste
REE    2  1 PARANA            # REE 2: Paraná
REE    3  1 PARANAIBA         # REE 3: Paranaíba
...
```

**Hydro Plants with Initial Volumes**:
```
UH  ANGRA 1     1     0.0     0.0     0.0  
UH  FUNIL-GRA   1     0.0     0.0     0.0  
UH  ITUMBIARA   1    15.8   100.0    19.6  
...
```

### 2. **desselet.dat** - Electrical Network Data
Location: `docs/Sample/DS_ONS_102025_RV2D11/desselet.dat`
Size: 60 lines

**Purpose**: Links time stages to base cases and pattern modifications

**Base Cases (4 load patterns)**:
```
1    leve          leve.pwf      # Light load base case
2    sab10h        sab10h.pwf    # Saturday 10am base case
3    sab19h        sab19h.pwf    # Saturday 7pm base case
4    media         media.pwf     # Medium load base case
```

**Pattern Modifications (48 half-hourly stages for day 11)**:
```
01 Estagio01    20251011  0  0  0.5      1 pat01.afp  # 00:00-00:30, uses base 1 (leve)
02 Estagio02    20251011  0 30  0.5      1 pat02.afp  # 00:30-01:00, uses base 1
...
15 Estagio15    20251011  7  0  0.5      2 pat15.afp  # 07:00-07:30, uses base 2 (sab10h)
...
35 Estagio35    20251011 17  0  0.5      3 pat35.afp  # 17:00-17:30, uses base 3 (sab19h)
...
45 Estagio45    20251011 22  0  0.5      4 pat45.afp  # 22:00-22:30, uses base 4 (media)
48 Estagio48    20251011 23 30  0.5      4 pat48.afp  # 23:30-00:00, uses base 4
```

### 3. **PWF Files** - Anarede Power Flow Base Cases
Location: `docs/Sample/DS_ONS_102025_RV2D11/*.pwf`
Format: Anarede (Brazilian power flow software)
Files: `leve.pwf`, `media.pwf`, `sab10h.pwf`, `sab19h.pwf`
Size: ~39,000 lines each

**Purpose**: Define electrical network topology for different load levels

**Structure**:
```
TITU
ONS PDPM Outubro 2025 - LEVE                 # Title: October 2025 - Light load

DAGR                                          # Area/Subsystem definitions
  6 SUBMERCADOS DO SIN                        # 6 markets in National Interconnected System
  1   SUDESTE/CENTRO-OESTE                    # Market 1: Southeast/Central-West
  2   SUL                                     # Market 2: South
  3   NORDESTE                                # Market 3: Northeast
  4   NORTE                                   # Market 4: North

DBAR                                          # Bus data (network nodes)
(Num)OETGb(   nome   )Gl( V)( A)( Pg)( Qg)( Qn)( Qm)(Bc  )( Pl)( Ql)( Sh)Are(Vf)M...
   10 L1 VANGRA1UNE001 5 981-235     -74.9   0.   0.    # Bus 10: Angra 1 generator
   11 L1 VANGRA2UNE001 5 972-235     -246.   0.   0.    # Bus 11: Angra 2 generator
   12 L1 VLCBARRUHE002 5 971-240     -198.   0.   0.    # Bus 12: L.C. Barreto hydro
   ...
```

**Contains**:
- **DBAR**: Bus definitions (voltage, generation, load, reactive power)
- **DLIN**: Transmission line data
- **DOPC**: Calculation options
- **DCTE**: Constants and convergence parameters
- Complete electrical network topology with impedances, limits, and control settings

### 4. **AFP Files** - Anarede Pattern Files
Location: `docs/Sample/DS_ONS_102025_RV2D11/pat*.afp`
Format: Anarede modification files
Count: 48 files (pat01.afp through pat48.afp)
Size: ~1,900 lines each

**Purpose**: Modify base cases for each half-hourly stage with:
- **RESP**: Electrical restrictions (security constraints)
- **DREF**: Network element modifications (line flows, generation limits)

**Example from pat01.afp**:
```
DREF MUDA                                              # Modify reference data
RESP      1     -99999      2000                       # Restriction 1: limit 2000 MW
# Formula: F(ASS-LON1) + 0.55*F(ASS-LON2) < 2000 MW
      1027  556 2       -0.55                          # Line 1027->556 circuit 2, factor -0.55
      1027  556 1       -1.00                          # Line 1027->556 circuit 1, factor -1.00

RESP      2      -2078      2078                       # Restriction 2: ±2078 MW
# Formula: F(Luziania-Rio das Eguas) < 2078 MW
      3050 6442 1        1.00                          # Line 3050->6442 circuit 1, factor 1.00
```

**Defines**:
- Security constraints (transmission limits considering contingencies)
- Generation participation factors
- Network element status (in-service, out-of-service)
- Load modifications for each time stage

### 5. **Additional Network Files**

| File | Purpose | Size |
|------|---------|------|
| `pdo_somflux.dat` | Network flow summaries (post-processing) | 24,585 lines |
| `pdo_cmobar.dat` | Marginal costs by bus (nodal prices) | 16,977 lines |
| `areacont.dat` | Control area definitions | 9 lines |
| `respotele.dat` | Reserve and potential data | 1,117 lines |
| `indelet.dat` | Electrical indices | 17 lines |

## Network Data Flow

```
1. entdados.dat defines:
   ├─ Network flag: TM records with network_flag=1 for day 11
   ├─ Network options: RD record (slack, circuits, format)
   ├─ Subsystems: SIST records (SE, S, NE, N, FC)
   ├─ Energy reservoirs: REE records
   └─ Hydro plants: UH records with initial conditions

2. desselet.dat links:
   ├─ Base cases: 4 PWF files for different load patterns
   └─ Time stages: 48 AFP files for half-hourly modifications

3. PWF files (Anarede format) contain:
   ├─ Complete electrical network topology
   ├─ Bus data (voltage, generation, load)
   ├─ Transmission line data (impedance, limits)
   └─ Base case power flow solution

4. AFP files (Anarede modifications) contain:
   ├─ Security constraints (RESP records)
   ├─ Network modifications for each time stage
   └─ Generation and load adjustments
```

## Network Flag Interpretation

From `entdados.dat`:

| Day | Network Flag | Meaning | Time Resolution |
|-----|--------------|---------|-----------------|
| 11 | `1` | Full network simulation | 48 half-hourly stages (0.5h each) |
| 12-17 | `0` | Simplified (no network) | Aggregated periods (3-21h each) |

**Why this matters**:
- Day 11 requires detailed network power flow calculations (using PWF/AFP files)
- Days 12-17 use simplified dispatch without network constraints
- This is typical for operational planning: detailed near-term, simplified long-term

## Parser Implementation Status

✅ **All network parsers already implemented** in `src/parser/entdados.jl`:

| Record Type | Parser Function | Status | Lines |
|-------------|-----------------|--------|-------|
| RD | `parse_rd()` | ✅ Complete | 1315+ |
| RIVAR | `parse_rivar()` | ✅ Complete | 1218+ |
| TM | `parse_tm()` | ✅ Complete | 51+ |
| SIST | `parse_sist()` | ✅ Complete | 96+ |
| REE | `parse_ree()` | ✅ Complete | 1152+ |
| IA | `parse_ia()` | ✅ Complete | 864+ |
| RI | `parse_ri()` | ✅ Complete | 956+ |
| GP | `parse_gp()` | ✅ Complete | 1121+ |

**Note**: PWF and AFP files (Anarede format) are **not currently parsed** by DESSEM2Julia. These are external network definition files processed by the DESSEM solver itself.

## Testing with ONS Data

To parse the ONS network data:

```julia
using DESSEM2Julia

# Parse main topology file
data = parse_entdados("docs/Sample/DS_ONS_102025_RV2D11/entdados.dat")

# Access network configuration
rd = data.rd  # Network options
rivar = data.rivar  # Variation restrictions
tm = data.tm  # Time discretization (check network_flag)
sist = data.sist  # Subsystems (5 total)
ree = data.ree  # Energy reservoirs (12 total)
uh = data.uh  # Hydro plants

# Check network flag for each day
for record in tm
    if record.network_flag == 1
        println("Day $(record.day) stage $(record.stage): NETWORK ENABLED")
        println("  Load pattern: $(record.load_level)")
        println("  Duration: $(record.duration) hours")
    end
end
```

## Recommendations

### For ONS Compatibility
1. ✅ **entdados.dat parser**: Already complete and tested
2. ⚠️ **desselet.dat parser**: **NOT YET IMPLEMENTED** - needed to link time stages to PWF/AFP files
3. ⚠️ **PWF parser**: Not needed (Anarede format, used directly by DESSEM solver)
4. ⚠️ **AFP parser**: Not needed (Anarede format, used directly by DESSEM solver)

### Next Steps
1. **Implement desselet.dat parser** to read base case and pattern file mappings
2. Add tests for ONS network data with `network_flag=1`
3. Document the Anarede file format (PWF/AFP) for users who need to understand network topology
4. Create examples showing how to identify which time stages have network enabled

## Summary

**Files defining network in ONS sample**:

1. **entdados.dat** - Primary topology (subsystems, reservoirs, network flags, options)
2. **desselet.dat** - Links time stages to network files
3. **leve.pwf, media.pwf, sab10h.pwf, sab19h.pwf** - Anarede base case network topology
4. **pat01.afp through pat48.afp** - Anarede modifications for each time stage

**Key insight**: ONS uses **layered network definition**:
- High-level topology in `entdados.dat` (parseable by DESSEM2Julia)
- Detailed electrical network in PWF/AFP files (Anarede format, consumed by DESSEM solver)
- `desselet.dat` acts as the bridge between them

The ONS sample is production-grade data used for actual operational dispatch planning with full AC power flow network modeling.
