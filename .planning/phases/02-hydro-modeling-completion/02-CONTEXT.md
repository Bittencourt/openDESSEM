# Phase 2: Hydro Modeling Completion - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Enable hydro plants to operate with realistic cascade topology and inflow data. This phase loads hydrological inflows from DESSEM files, builds cascade topology (DAG with cycle detection), implements water travel time delays, and applies correct unit conversions. The objective function (Phase 1) already values water — this phase makes the water balance constraints realistic.

**Success Criteria (from ROADMAP):**
1. Inflows load from vazaolateral.csv instead of hardcoded zeros
2. Cascade water delays work correctly (upstream outflows reach downstream after travel time)
3. Cascade topology utility detects circular dependencies and computes plant depths
4. Water balance constraints use correct unit conversions (m³/s to hm³ with 0.0036 factor)

</domain>

<decisions>
## Implementation Decisions

### Cascade Topology Edge Cases

**Headwater plants (no upstream):**
- Treat inflow as exogenous data from vazaolateral.csv
- These plants have no upstream water balance term — only natural inflow
- Do not require an upstream source; this is the normal case for rivers originating in mountains

**Orphan plants (no downstream):**
- Outflow exits the modeled system (goes to ocean, unmodeled reservoir, etc.)
- This is NOT an error condition — just record the outflow
- No warning needed for plants without downstream_plant_id

**Multiple upstreams merging:**
- Track inflows by upstream ID: `inflow[t] = sum(upstream_outflow[t - delay] for each upstream)`
- Keep separate terms per upstream for debugging and transparency
- Each upstream may have different travel time delays

**Terminal plant identification:**
- Infer from topology: if `downstream_plant_id` is `nothing` or empty, plant is terminal
- Do NOT add an explicit `is_terminal` field to ReservoirHydro
- Terminal status is derived, not stored

### Cycle Detection Behavior

**When to detect cycles:**
- At ElectricitySystem construction time (fail fast)
- Do not wait until constraint building — catch data errors early

**Cycle response:**
- Throw ArgumentError immediately
- Cycles are data errors that must be fixed in the input data
- No automatic cycle-breaking attempted

**Error message format:**
- Include full cycle path: `"Circular cascade detected: H001 → H002 → H003 → H001"`
- List all plant IDs in the cycle with arrow notation

**Unknown downstream references:**
- If `downstream_plant_id` points to a plant not in the system: log warning, treat as terminal
- Do NOT throw error — allows partial system definitions during development

### OpenCode's Discretion

- Exact DAG traversal algorithm (DFS, topological sort, etc.)
- How to compute plant depths (distance from headwater)
- Whether to cache topology results or recompute
- Internal data structure for cascade graph

</decisions>

<specifics>
## Specific Ideas

- Follow existing patterns from `hydro_water_balance.jl` constraint builder
- The cascade delay logic is already commented out at lines 224-228 — uncomment and complete
- Unit conversion factor 0.0036 = (60 seconds × 60 minutes) / 1,000,000 for m³/s to hm³ per hour

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-hydro-modeling-completion*
*Context gathered: 2026-02-15*
