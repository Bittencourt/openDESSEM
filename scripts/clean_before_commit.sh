#!/bin/bash
# =====================================================
# clean_before_commit.sh
# =====================================================
# Cleans temporary and auxiliary files before git commit
# Usage: ./scripts/clean_before_commit.sh
# =====================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}OpenDESSEM Pre-Commit Cleanup${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Counter for cleaned files
cleaned_count=0

# Function to clean files by pattern
clean_files() {
    local pattern=$1
    local description=$2

    if find . -name "$pattern" 2>/dev/null | grep -q .; then
        count=$(find . -name "$pattern" 2>/dev/null | wc -l)
        find . -name "$pattern" -delete 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Removed $count $description"
        cleaned_count=$((cleaned_count + count))
    fi
}

# Function to clean directories by pattern
clean_dirs() {
    local pattern=$1
    local description=$2

    if find . -type d -name "$pattern" 2>/dev/null | grep -q .; then
        find . -type d -name "$pattern" -exec rm -rf {} + 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Removed $description directories"
        ((cleaned_count++))
    fi
}

echo -e "${YELLOW}Cleaning temporary files...${NC}"
echo ""

# =====================================================
# Log files
# =====================================================
clean_files "*.log" "log files"

# =====================================================
# Editor backup files
# =====================================================
clean_files "*~" "editor backup files"
clean_files "*.swp" "Vim swap files"
clean_files "*.swo" "Vim swap files"
clean_files "*.swn" "Vim swap files"
clean_files "*.bak" "backup files"
clean_files "*.tmp" "temporary files"
clean_files "*.temp" "temporary files"

# =====================================================
# OS-specific files
# =====================================================
clean_files ".DS_Store" "macOS DS_Store files"
clean_files "Thumbs.db" "Windows thumbnail files"
clean_files "Desktop.ini" "Windows desktop files"

# =====================================================
# Julia artifacts
# =====================================================
clean_files "*.jl.c" "Julia C artifacts"
clean_files "*.jl.*.bc" "Julia LLVM bitcode"
clean_dirs ".revise" "Julia Revise directories"

# =====================================================
# Python cache (if using auxiliary Python scripts)
# =====================================================
clean_dirs "__pycache__" "Python cache directories"
clean_files "*.pyc" "Python bytecode files"

# =====================================================
# Test artifacts
# =====================================================
clean_files "*.cov" "coverage files"
clean_dirs "test/__outputs__" "test output directories"

# =====================================================
# IDE directories
# =====================================================
clean_dirs ".idea" "IDE directories"
clean_dirs "vscode-settings" "VSCode settings directories"

# =====================================================
# Remove Julia build artifacts (but keep deps.jl if it exists)
# =====================================================
if [ -f "deps/build.log" ]; then
    rm -f deps/build.log
    echo -e "${GREEN}✓${NC} Removed Julia build log"
    ((cleaned_count++))
fi

# =====================================================
# Check for remaining common temp files
# =====================================================
echo ""
echo -e "${YELLOW}Checking for remaining temporary files...${NC}"

# Count remaining temp files
remaining_logs=$(find . -name "*.log" 2>/dev/null | wc -l)
remaining_backup=$(find . -name "*~" -o -name "*.bak" -o -name "*.tmp" 2>/dev/null | wc -l)
remaining_os=$(find . -name ".DS_Store" -o -name "Thumbs.db" 2>/dev/null | wc -l)

if [ "$remaining_logs" -gt 0 ]; then
    echo -e "${RED}⚠ Warning: $remaining_logs log files remaining${NC}"
fi

if [ "$remaining_backup" -gt 0 ]; then
    echo -e "${RED}⚠ Warning: $remaining_backup backup/temp files remaining${NC}"
fi

if [ "$remaining_os" -gt 0 ]; then
    echo -e "${RED}⚠ Warning: $remaining_os OS-specific files remaining${NC}"
fi

# =====================================================
# Summary
# =====================================================
echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Cleanup Summary${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "Files cleaned: ${GREEN}$cleaned_count${NC}"

# =====================================================
# Git status
# =====================================================
echo ""
echo -e "${YELLOW}Current git status:${NC}"
git status --short

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review changes: ${GREEN}git diff${NC}"
echo "2. Run tests: ${GREEN}julia --project=test test/runtests.jl${NC}"
echo "3. Stage files: ${GREEN}git add <files>${NC}"
echo "4. Commit: ${GREEN}git commit -m 'type(scope): description'${NC}"
echo ""
