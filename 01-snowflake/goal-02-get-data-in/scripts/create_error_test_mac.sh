#!/bin/bash
# ══════════════════════════════════════════════════════════════
# SNOWFLAKE ENGINEERING WORKBOOK
# Goal 2 : Get Data In — Sub-task 2.4 : Handle load errors
# Script  : create_error_test_mac.sh
# Platform: Mac / Linux
# ──────────────────────────────────────────────────────────────
# WHAT THIS DOES:
#   Creates a deliberately broken CSV file for error handling
#   exercises, then uploads it to your Snowflake stage via SnowSQL.
#
# HOW TO RUN:
#   cd ~/projects/data-engineering-workbooks
#   bash 01-snowflake/goal-02-get-data-in/scripts/create_error_test_mac.sh
#
# PREREQUISITES:
#   · SnowSQL installed and configured (snowsql -c workbook works)
#   · ECOMMERCE_RAW_STAGE exists in Snowflake
# ══════════════════════════════════════════════════════════════

echo "Creating broken CSV file for error handling exercises..."

# Create the broken CSV file
# Row 2: NOT_A_NUMBER in the price column (FLOAT) — type mismatch
# Row 3: NOT_A_DATE in the created_at column (DATE) — type mismatch
# Rows 1, 4, 5: valid rows that should load successfully
cat > /tmp/error_test.csv << 'CSVEOF'
id,name,price,created_at
1,Widget A,19.99,2024-01-15
2,Widget B,NOT_A_NUMBER,2024-01-16
3,Widget C,29.99,NOT_A_DATE
4,Widget D,39.99,2024-01-18
5,Widget E,49.99,2024-01-19
CSVEOF

echo "File created at /tmp/error_test.csv"
echo ""
echo "Contents:"
cat /tmp/error_test.csv
echo ""

# Upload to Snowflake stage via SnowSQL
echo "Uploading to Snowflake stage..."
snowsql -c workbook -q "PUT file:///tmp/error_test.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"

echo ""
echo "Done. Return to Snowsight and continue with Step 2."
echo "Verify the file is staged with:"
echo "  LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*error_test.*';"
