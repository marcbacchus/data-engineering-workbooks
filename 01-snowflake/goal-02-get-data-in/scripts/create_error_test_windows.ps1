# ══════════════════════════════════════════════════════════════
# SNOWFLAKE ENGINEERING WORKBOOK
# Goal 2 : Get Data In — Sub-task 2.4 : Handle load errors
# Script  : create_error_test_windows.ps1
# Platform: Windows (PowerShell)
# ──────────────────────────────────────────────────────────────
# WHAT THIS DOES:
#   Creates a deliberately broken CSV file for error handling
#   exercises, then uploads it to your Snowflake stage via SnowSQL.
#
# HOW TO RUN:
#   Open PowerShell and run:
#   cd C:\Users\YourName\projects\data-engineering-workbooks
#   .\01-snowflake\goal-02-get-data-in\scripts\create_error_test_windows.ps1
#
#   If you get an execution policy error, run first:
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#
# PREREQUISITES:
#   · SnowSQL installed and configured (snowsql -c workbook works)
#   · ECOMMERCE_RAW_STAGE exists in Snowflake
# ══════════════════════════════════════════════════════════════

Write-Host "Creating broken CSV file for error handling exercises..."

# Create the broken CSV file in C:\Temp
# Row 2: NOT_A_NUMBER in the price column (FLOAT) — type mismatch
# Row 3: NOT_A_DATE in the created_at column (DATE) — type mismatch
# Rows 1, 4, 5: valid rows that should load successfully

$csvPath = "C:\Temp\error_test.csv"

# Create C:\Temp if it does not exist
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
    Write-Host "Created C:\Temp directory"
}

# Write the CSV content
@"
id,name,price,created_at
1,Widget A,19.99,2024-01-15
2,Widget B,NOT_A_NUMBER,2024-01-16
3,Widget C,29.99,NOT_A_DATE
4,Widget D,39.99,2024-01-18
5,Widget E,49.99,2024-01-19
"@ | Set-Content -Path $csvPath -Encoding UTF8

Write-Host "File created at $csvPath"
Write-Host ""
Write-Host "Contents:"
Get-Content $csvPath
Write-Host ""

# Upload to Snowflake stage via SnowSQL
Write-Host "Uploading to Snowflake stage..."
snowsql -c workbook -q "PUT file://C:/Temp/error_test.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"

Write-Host ""
Write-Host "Done. Return to Snowsight and continue with Step 2."
Write-Host "Verify the file is staged with:"
Write-Host "  LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*error_test.*';"
