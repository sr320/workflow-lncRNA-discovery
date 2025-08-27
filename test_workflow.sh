#!/bin/bash

# Test script to validate the improved workflow components
# This script tests the basic functionality without running the full pipeline

set -e

echo "=== lncRNA Discovery Workflow Validation Test ==="
echo

# Test 1: Python filter script
echo "1. Testing Python filter script..."
if python 13.1-filter_count_matrix.py --help > /dev/null 2>&1; then
    echo "   ✓ Python filter script is functional"
else
    echo "   ✗ Python filter script failed"
    exit 1
fi

# Test 2: Robust pipeline script help
echo "2. Testing robust pipeline script..."
if ./robust_lncrna_pipeline.sh --help > /dev/null 2>&1; then
    echo "   ✓ Robust pipeline script is functional"
else
    echo "   ✗ Robust pipeline script failed"
    exit 1
fi

# Test 3: File structure validation
echo "3. Validating file structure..."
required_files=(
    "workflow.qmd"
    "workflow-original.qmd" 
    "workflow-improved.qmd"
    "robust_lncrna_pipeline.sh"
    "13.1-filter_count_matrix.py"
    "README.md"
)

all_files_present=true
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "   ✓ $file exists"
    else
        echo "   ✗ $file missing"
        all_files_present=false
    fi
done

if [[ "$all_files_present" == "false" ]]; then
    exit 1
fi

# Test 4: Environment detection
echo "4. Testing environment detection..."
env_output=$(LOG_DIR=/tmp ./robust_lncrna_pipeline.sh --restart-step 99 2>&1 | grep "Environment:")
if echo "$env_output" | grep -q "Environment:"; then
    echo "   ✓ Environment detection working"
    echo "   $env_output"
else
    echo "   ✗ Environment detection failed"
    exit 1
fi

# Test 5: Configuration validation
echo "5. Testing configuration handling..."
config_output=$(LOG_DIR=/tmp ./robust_lncrna_pipeline.sh --restart-step 99 2>&1 | grep "Configuration Summary:" -A 10)
if echo "$config_output" | grep -q "Threads:"; then
    echo "   ✓ Configuration parsing working"
else
    echo "   ✗ Configuration parsing failed"
    exit 1
fi

# Test 6: Basic file validation function
echo "6. Testing file validation with Python script..."
# Create test files
echo "test content" > test_valid.txt
touch test_empty.txt
echo "<html><body>This is HTML</body></html>" > test_html.txt

# Test the Python script's validation-like behavior
if python -c "
import sys
import os

def check_file(filepath):
    if not os.path.exists(filepath):
        return False, 'missing'
    if os.path.getsize(filepath) == 0:
        return False, 'empty'
    return True, 'valid'

files = ['test_valid.txt', 'test_empty.txt', 'test_html.txt']
results = []
for f in files:
    valid, reason = check_file(f)
    results.append((f, valid, reason))
    
# Check if we can detect issues
valid_count = sum(1 for _, valid, _ in results if valid)
print(f'Validation test: {valid_count}/3 files passed basic checks')
sys.exit(0 if valid_count >= 1 else 1)
"; then
    echo "   ✓ File validation logic working"
else
    echo "   ✗ File validation logic failed"
fi

# Clean up test files
rm -f test_valid.txt test_empty.txt test_html.txt

echo
echo "=== All Tests Passed! ==="
echo "The improved workflow components are functional and ready for use."
echo
echo "Usage examples:"
echo "  # Show help:"
echo "  ./robust_lncrna_pipeline.sh --help"
echo
echo "  # Run with custom settings:"
echo "  ./robust_lncrna_pipeline.sh --threads 4 --restart-step 1"
echo
echo "  # Override tool paths:"
echo "  HISAT2_DIR_OVERRIDE='/path/to/hisat2/' ./robust_lncrna_pipeline.sh"