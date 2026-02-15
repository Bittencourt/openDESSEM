# OpenDESSEM Documentation

This directory contains the core documentation for the OpenDESSEM project.

## Navigation

📋 **[INDEX.md](INDEX.md)** - Complete documentation index and navigation guide

## Quick Access

### For Getting Started
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Commands, workflows, and quick tips
- [DESSEM_Planning_Document.md](DESSEM_Planning_Document.md) - Background and problem definition

### For Development
- [../.claude/CLAUDE.md](../.claude/CLAUDE.md) - Development guidelines (TDD, commit conventions, code style)
- [01_DETAILED_TECHNICAL_PLAN.md](01_DETAILED_TECHNICAL_PLAN.md) - Technical architecture
- [constraint_system_guide.md](constraint_system_guide.md) - Constraint development guide

### For Architecture Understanding
- [ARCHITECTURAL_DECISION.md](ARCHITECTURAL_DECISION.md) - Design decisions and rationale
- [POWERMODELS_COMPATIBILITY_ANALYSIS.md](POWERMODELS_COMPATIBILITY_ANALYSIS.md) - PowerModels.jl integration
- [VALIDATION_FRAMEWORK_DESIGN.md](VALIDATION_FRAMEWORK_DESIGN.md) - Testing and validation

## Directory Structure

```
docs/
├── INDEX.md                          # Documentation index
├── README.md                         # This file
├── QUICK_REFERENCE.md                # Quick commands and workflows
│
├── Core Documentation
│   ├── 01_DETAILED_TECHNICAL_PLAN.md
│   ├── ARCHITECTURAL_DECISION.md
│   ├── DESSEM_Planning_Document.md
│   └── constraint_system_guide.md
│
├── Integration Guides
│   ├── POWERMODELS_COMPATIBILITY_ANALYSIS.md
│   ├── HYDROPOWERMODELS_INTEGRATION.md
│   └── PWF_INTEGRATION.md
│
├── Quality & Validation
│   ├── CRITICAL_ASSESSMENT.md
│   ├── CRITICAL_EVALUATION.md
│   └── VALIDATION_FRAMEWORK_DESIGN.md
│
├── Sample Data
│   └── Sample/
│       ├── ONS_NETWORK_FILES.md
│       ├── ONS_VALIDATION.md
│       └── SAMPLE_VALIDATION.md
│
├── Historical Records
│   ├── tasks/                        # Implementation task summaries
│   └── maintenance/                  # Maintenance and fix records
│
└── See also
    ├── ../examples/docs/             # Example and wizard documentation
    ├── ../.claude/CLAUDE.md          # Core development guidelines
    └── ../AGENTS.md                  # AI agent guidelines
```

## Documentation Standards

All documentation in this project follows:

- **Markdown format** with GitHub-flavored extensions
- **Clear structure** with hierarchical headings
- **Code examples** in Julia with syntax highlighting
- **Relative links** for navigation
- **Regular updates** synchronized with code changes

## Finding What You Need

### I want to...

- **Learn about the project** → Start with [DESSEM_Planning_Document.md](DESSEM_Planning_Document.md)
- **Understand the architecture** → Read [01_DETAILED_TECHNICAL_PLAN.md](01_DETAILED_TECHNICAL_PLAN.md)
- **Start developing** → Follow [../.claude/CLAUDE.md](../.claude/CLAUDE.md)
- **Add constraints** → Study [constraint_system_guide.md](constraint_system_guide.md)
- **Use the CLI wizard** → See [../examples/WIZARD_README.md](../examples/WIZARD_README.md)
- **Run tests** → Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
- **Integrate with PowerModels** → Read [POWERMODELS_COMPATIBILITY_ANALYSIS.md](POWERMODELS_COMPATIBILITY_ANALYSIS.md)

## Contributing to Documentation

When updating documentation:

1. **Keep INDEX.md current** - Update the index when adding new documents
2. **Follow the structure** - Place documents in appropriate directories
3. **Use relative links** - Ensure links work in both GitHub and local viewing
4. **Include examples** - Add code examples for technical content
5. **Date your updates** - Include update date in document footer

## Need Help?

- **Documentation questions**: Open an issue with "docs:" prefix
- **General help**: See [../README.md](../README.md)
- **Development help**: See [../.claude/CLAUDE.md](../.claude/CLAUDE.md)

---

**Last Updated**: 2026-02-15
