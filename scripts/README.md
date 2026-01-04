# OpenDESSEM Development Scripts

This directory contains utility scripts to support the development workflow defined in `.claude/claude.md`.

## Available Scripts

### 1. `clean_before_commit.sh`

**Purpose**: Removes temporary and auxiliary files before git commit.

**Usage**:
```bash
# Make executable (first time only)
chmod +x scripts/clean_before_commit.sh

# Run cleanup
./scripts/clean_before_commit.sh
```

**What it cleans**:
- Log files (`*.log`)
- Editor backup files (`*~`, `*.swp`, `*.bak`, `*.tmp`)
- OS-specific files (`.DS_Store`, `Thumbs.db`)
- Julia artifacts (`*.jl.c`, `*.jl.*.bc`)
- Python cache (`__pycache__/`)
- Test artifacts (`*.cov`, coverage files)
- IDE directories (`.idea/`, etc.)

**Output**:
- Color-coded summary of cleaned files
- Warning if any temp files remain
- Current git status
- Next steps for committing

### 2. `pre_commit_check.jl`

**Purpose**: Comprehensive pre-commit verification following TDD and development rules.

**Usage**:
```bash
# Run all checks
julia scripts/pre_commit_check.jl
```

**Checks performed**:
1. ✅ **Julia Version** - Verifies Julia ≥ 1.8
2. ✅ **Temporary Files** - Scans for temp files (*.log, *~, *.swp, etc.)
3. ✅ **Test Suite** - Runs full test suite via `test/runtests.jl`
4. ✅ **Git Status** - Checks for uncommitted changes
5. ✅ **Documentation** - Validates documentation build scripts
6. ✅ **Code Formatting** - Verifies all Julia files are formatted with JuliaFormatter
7. ✅ **Project.toml** - Validates project configuration

**Exit codes**:
- `0`: All checks passed - safe to commit
- `1`: Some checks failed - fix before committing
- `6`: Julia version too old

**Features**:
- Cross-platform compatible (Windows, Linux, macOS)
- Color-coded terminal output
- Graceful handling of missing dependencies
- Clear error messages and next steps

**Integration with git hooks** (optional):
```bash
# Install as pre-commit hook (optional)
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
julia scripts/pre_commit_check.jl
exit $?
EOF

chmod +x .git/hooks/pre-commit
```

---

## Development Workflow

### Step-by-Step Process

#### 1. Before Making Changes
```bash
# Ensure clean state
git status

# Pull latest changes
git pull origin develop
```

#### 2. Write Code (TDD)
```bash
# Write test first
# test/unit/test_my_feature.jl

# Implement feature
# src/my_feature.jl

# Run tests continuously
julia --project=test test/runtests.jl
```

#### 3. Before Committing
```bash
# Step 1: Clean temporary files
./scripts/clean_before_commit.sh

# Step 2: Run all checks
julia scripts/pre_commit_check.jl

# Step 3: If all checks pass, review changes
git diff
git diff --staged

# Step 4: Commit
git add <files>
git commit -m "feat(scope): description"
```

#### 4. After Committing
```bash
# Push to remote
git push origin feature/your-feature

# Or create pull request
gh pr create --title "Add feature" --body "Description"
```

---

## Customization

### Adding New Checks to `pre_commit_check.jl`

Edit `pre_commit_check.jl` and add a new check function:

```julia
function check_my_custom_check()
    print_header("Check: My Custom Check")

    # Your logic here
    if condition_met
        print_success("Check passed")
        return true
    else
        print_error("Check failed")
        return false
    end
end
```

Then add to the `checks` array in `main()`:

```julia
checks = [
    # ... existing checks ...
    ("My Custom Check", check_my_custom_check)
]
```

### Adding New Cleanup Patterns to `clean_before_commit.sh`

Edit `clean_before_commit.sh` and add to the appropriate section:

```bash
# =====================================================
# My Custom Files
# =====================================================
clean_files "*.myext" "my custom files"
```

---

## Troubleshooting

### Script Not Executable (Linux/Mac)

```bash
chmod +x scripts/clean_before_commit.sh
```

### Julia Not in PATH

Use full path to Julia executable:

```bash
/full/path/to/julia scripts/pre_commit_check.jl
```

### Tests Failing

Run tests with verbose output to see what's failing:

```bash
julia --project=test test/runtests.jl
```

### Documentation Build Failing

Check documentation dependencies:

```bash
cd docs
julia --project=.
julia> instantiate()
julia> make()
```

---

## Continuous Integration

These scripts are designed to work with CI/CD pipelines:

### GitHub Actions Example

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Set up Julia
        uses: julia-actions/setup-julia@v1
        with:
          version: '1.10'

      - name: Run pre-commit checks
        run: julia scripts/pre_commit_check.jl
```

---

## Additional Resources

- **Development Guidelines**: See `.claude/claude.md`
- **Testing Guide**: See `test/README.md`
- **Documentation**: See `docs/guide.md`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | 2025-01-04 | Enhanced pre_commit_check.jl with cross-platform support and better error handling |
| 1.0 | 2025-01-03 | Initial scripts created |

---

**Last Updated**: 2025-01-03
**Maintainer**: OpenDESSEM Development Team
