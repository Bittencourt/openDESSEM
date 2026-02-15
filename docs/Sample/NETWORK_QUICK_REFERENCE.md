# Network Files Summary - Quick Reference

## Question: Do ONS files include network data?

**Answer**: ✅ **YES** - ONS sample includes comprehensive electrical network data.

## Quick Comparison

| Feature | ONS Sample | CCEE Sample |
|---------|------------|-------------|
| **Directory** | `DS_ONS_102025_RV2D11` | `DS_CCEE_102025_SEMREDE_RV0D28` |
| **Network** | ✅ Full network (day 11) | ❌ No network (SEMREDE) |
| **Network Flag** | `1` in TM records | `0` in TM records |
| **Network Files** | 56 files (4 PWF + 48 AFP + others) | 0 files |
| **Time Resolution** | Half-hourly (48 stages) | Aggregated periods |
| **Use Case** | Operational dispatch | Market clearing |

## Files Defining Network in ONS Sample

### 1. Primary Topology: `entdados.dat`
- Network configuration (RD, RIVAR records)
- Subsystems (5 total: SE, S, NE, N, FC)
- Energy reservoirs (12 total)
- Time discretization with `network_flag=1` for day 11

### 2. Network Index: `desselet.dat`
- Links 48 time stages to network files
- 4 base cases: leve.pwf, media.pwf, sab10h.pwf, sab19h.pwf
- 48 patterns: pat01.afp through pat48.afp

### 3. Electrical Topology: PWF Files (Anarede format)
- `leve.pwf` - Light load base case (~39k lines)
- `media.pwf` - Medium load base case
- `sab10h.pwf` - Saturday 10am case
- `sab19h.pwf` - Saturday 7pm case

**Contains**: Buses, transmission lines, impedances, voltage limits

### 4. Time-Varying Constraints: AFP Files (Anarede format)
- `pat01.afp` through `pat48.afp` (~1.9k lines each)
- Security constraints (transmission limits)
- Network modifications for each half-hour
- Generation participation factors

## Parser Status

| Component | Implementation | Location | Notes |
|-----------|----------------|----------|-------|
| **entdados.dat** | ✅ Complete | `src/parser/entdados.jl` | High-level network topology |
| **desselet.dat** | ❌ Not implemented | Need to create | **IDESSEM parses this** |
| **PWF files** | ⚠️ Not needed | Anarede format | **IDESSEM does NOT parse** |
| **AFP files** | ⚠️ Not needed | Anarede format | **IDESSEM does NOT parse** |

**Key Finding**: IDESSEM (reference implementation) **only parses desselet.dat**, treating PWF/AFP files as opaque references. See `docs/parsers/IDESSEM_DESSELET_ANALYSIS.md` for details.

## Network Flag Logic

From `entdados.dat`:

```
TM  11    0   0      0.5     1     LEVE   # Day 11: network_flag=1 → Use PWF/AFP
TM  11    0  30      0.5     1     LEVE   # Half-hourly with network
...
TM  12    0   0       21      0            # Day 12: network_flag=0 → No network
```

**Interpretation**:
- `network_flag=1` → Detailed network simulation (use desselet.dat + PWF/AFP)
- `network_flag=0` → Simplified dispatch (no network constraints)

## Next Steps

1. ✅ **Done**: Analyzed ONS network files structure
2. 🔲 **TODO**: Implement `desselet.dat` parser
3. 🔲 **TODO**: Document Anarede PWF/AFP format (reference only)
4. 🔲 **TODO**: Add ONS network integration tests

## Full Documentation

See **`docs/Sample/ONS_NETWORK_FILES.md`** for complete analysis with:
- Detailed file structure
- Example data from each file type
- Network data flow diagram
- Parser recommendations
- Testing strategies

---

**Key Takeaway**: ONS sample uses layered network definition with high-level topology in `entdados.dat` (parseable) and detailed electrical network in Anarede PWF/AFP files (consumed directly by DESSEM solver).
