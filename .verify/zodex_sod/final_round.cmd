cd /d "D:\BrowserOS - KaihongOS"
del .verify\zodex_sod\curl_out2.txt 2>nul
start /b cmd /c "curl -s -m 60 -X POST "http://127.0.0.1:9222/mcp?token=0jUOmkxENNcNtZsxTd7Ynnbx3AMfiI3L" -H "Content-Type: application/json" --data-binary @.verify\zodex_sod\nav_pay.json > .verify\zodex_sod\curl_out2.txt 2>&1"
ping -n 5 127.0.0.1 >nul
hdc shell uitest uiInput click 1074 640
ping -n 6 127.0.0.1 >nul
hdc shell uitest uiInput click 1074 640
ping -n 8 127.0.0.1 >nul
type .verify\zodex_sod\curl_out2.txt
