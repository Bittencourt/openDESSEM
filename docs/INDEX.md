# OpenDESSEM Documentation Index

Welcome to the OpenDESSEM documentation. This index provides a organized overview of all documentation resources.

## Quick Start

- **[README.md](../README.md)** - Project overview, quick start, and installation
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Essential commands and workflows

## Core Documentation

### Architecture & Design

- **[01_DETAILED_TECHNICAL_PLAN.md](01_DETAILED_TECHNICAL_PLAN.md)** - Complete technical architecture
- **[ARCHITECTURAL_DECISION.md](ARCHITECTURAL_DECISION.md)** - Key architectural decisions and rationale
- **[DESSEM_Planning_Document.md](DESSEM_Planning_Document.md)** - Original planning and problem definition

### System Components

- **[constraint_system_guide.md](constraint_system_guide.md)** - Constraint builder system documentation
- **[VALIDATION_FRAMEWORK_DESIGN.md](VALIDATION_FRAMEWORK_DESIGN.md)** - Validation and testing framework

### Integration

- **[POWERMODELS_COMPATIBILITY_ANALYSIS.md](POWERMODELS_COMPATIBILITY_ANALYSIS.md)** - PowerModels.jl integration analysis
- **[HYDROPOWERMODELS_INTEGRATION.md](HYDROPOWERMODELS_INTEGRATION.md)** - HydroPowerModels.jl integration
- **[PWF_INTEGRATION.md](PWF_INTEGRATION.md)** - PWF file format integration

### Quality & Assessment

- **[CRITICAL_ASSESSMENT.md](CRITICAL_ASSESSMENT.md)** - Critical evaluation of implementation
- **[CRITICAL_EVALUATION.md](CRITICAL_EVALUATION.md)** - Code quality assessment

## Development Guides

- **[.claude/CLAUDE.md](../.claude/CLAUDE.md)** - Development guidelines, TDD practices, code style
- **[AGENTS.md](../AGENTS.md)** - AI agent development guidelines (overlaps with CLAUDE.md)

## Examples

- **[examples/README.md](../examples/README.md)** - Examples overview
- **[examples/WIZARD_README.md](../examples/WIZARD_README.md)** - Interactive wizard guide
- **[examples/docs/WIZARD_INDEX.md](../examples/docs/WIZARD_INDEX.md)** - Wizard documentation index
- **[examples/docs/WIZARD_FLOWCHART.md](../examples/docs/WIZARD_FLOWCHART.md)** - Wizard flowcharts
- **[examples/docs/WIZARD_IMPLEMENTATION_SUMMARY.md](../examples/docs/WIZARD_IMPLEMENTATION_SUMMARY.md)** - Wizard implementation details

## Historical Documentation

### Task Summaries

- **[tasks/TASK-006-IMPLEMENTATION-SUMMARY.md](tasks/TASK-006-IMPLEMENTATION-SUMMARY.md)** - Constraint builder implementation
- **[tasks/TASK-006-COMMIT-CHECKLIST.md](tasks/TASK-006-COMMIT-CHECKLIST.md)** - Task 006 commit checklist

### Maintenance Records

- **[maintenance/MARKET_ENTITY_FIX_SUMMARY.md](maintenance/MARKET_ENTITY_FIX_SUMMARY.md)** - Market entity validation fixes

## Sample Data Documentation

- **[Sample/ONS_NETWORK_FILES.md](Sample/ONS_NETWORK_FILES.md)** - ONS network file descriptions
- **[Sample/ONS_VALIDATION.md](Sample/ONS_VALIDATION.md)** - ONS data validation
- **[Sample/SAMPLE_VALIDATION.md](Sample/SAMPLE_VALIDATION.md)** - Sample data validation
- **[Sample/NETWORK_QUICK_REFERENCE.md](Sample/NETWORK_QUICK_REFERENCE.md)** - Network data quick reference
- **[Sample/ENTITY_COMPATIBILITY_ANALYSIS.md](Sample/ENTITY_COMPATIBILITY_ANALYSIS.md)** - Entity compatibility analysis

## Documentation by Audience

### For New Users

1. Start with [README.md](../README.md) for project overview
2. Review [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for essential commands
3. Try [examples/WIZARD_README.md](../examples/WIZARD_README.md) for interactive system building
4. Read [DESSEM_Planning_Document.md](DESSEM_Planning_Document.md) for background

### For Developers

1. Read [.claude/CLAUDE.md](../.claude/CLAUDE.md) for development guidelines
2. Study [01_DETAILED_TECHNICAL_PLAN.md](01_DETAILED_TECHNICAL_PLAN.md) for architecture
3. Review [constraint_system_guide.md](constraint_system_guide.md) for constraint development
4. Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for commands and workflows

### For AI Agents

1. Primary: [AGENTS.md](../AGENTS.md) - Comprehensive agent guidelines
2. Detailed rules: [.claude/CLAUDE.md](../.claude/CLAUDE.md) - TDD, commit conventions
3. Architecture: [01_DETAILED_TECHNICAL_PLAN.md](01_DETAILED_TECHNICAL_PLAN.md)

### For Researchers

1. [DESSEM_Planning_Document.md](DESSEM_Planning_Document.md) - Problem formulation
2. [ARCHITECTURAL_DECISION.md](ARCHITECTURAL_DECISION.md) - Design rationale
3. [POWERMODELS_COMPATIBILITY_ANALYSIS.md](POWERMODELS_COMPATIBILITY_ANALYSIS.md) - Integration analysis
4. [VALIDATION_FRAMEWORK_DESIGN.md](VALIDATION_FRAMEWORK_DESIGN.md) - Validation approach

## Documentation Standards

All documentation follows these standards:

- **Format**: Markdown with GitHub-flavored extensions
- **Code examples**: Julia code blocks with syntax highlighting
- **Structure**: Clear headings, bullet points, tables
- **Links**: Relative links within documentation
- **Date format**: YYYY-MM-DD
- **Updates**: Documentation updated with code changes

## Recent Updates

- **2026-02-15**: Reorganized documentation structure, moved wizard docs to examples/docs/, task docs to docs/tasks/, maintenance docs to docs/maintenance/
- **2026-01-07**: Added AGENTS.md for AI agent guidelines
- **2026-01-05**: Completed TASK-006 constraint builder system
- **2025-01-05**: Updated status in CLAUDE.md and AGENTS.md

## Contributing to Documentation

When adding or updating documentation:

1. **Update this index** if adding new documents
2. **Follow the structure** - place docs in appropriate directories
3. **Use relative links** for cross-references
4. **Include examples** in technical documentation
5. **Date your changes** in document headers

## Need Help?

- **General questions**: See [README.md](../README.md)
- **Development help**: See [.claude/CLAUDE.md](../.claude/CLAUDE.md)
- **Examples**: See [examples/](../examples/)
- **Issues**: [GitHub Issues](https://github.com/your-org/openDESSEM/issues)

---

**Last Updated**: 2026-02-15
**Maintainer**: OpenDESSEM Development Team
