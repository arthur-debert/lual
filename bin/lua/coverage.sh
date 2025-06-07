#!/bin/bash

# Clean up previous coverage files
echo "Cleaning up previous coverage files..."
rm -rf coverage/*

# Run tests with coverage
echo "Running tests with coverage..."
busted -c

# Display results
echo "Coverage files generated:"
ls -la coverage/

echo ""
echo "Coverage Summary (sorted by coverage % - highest first):"
echo "----------------------------------------------------------------"
# Extract lines between the dashed lines, sort by coverage percentage (4th column, descending)
sed -n '/^----------------------------------------------------------------$/,/^----------------------------------------------------------------$/p' coverage/luacov.report.out |
    grep "\.lua" |
    sort -k4 -nr
echo "----------------------------------------------------------------"
# Show the total line
grep "^Total" coverage/luacov.report.out
