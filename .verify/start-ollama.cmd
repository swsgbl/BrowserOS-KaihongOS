@echo off
set OLLAMA_HOST=0.0.0.0:11436
"G:\AI_MIGRATED\C\Users\hongfu\AppData\Local\Programs\Ollama\ollama.exe" serve > "%~dp0ollama-serve.log" 2>&1
