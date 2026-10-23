#!/bin/sh
# Открыть Zumi на телефоне через браузер (телефон и Mac в одной Wi-Fi сети).
cd "$(dirname "$0")"
mkdir -p logs
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
echo ""
echo "=============================================="
echo "  Открой на телефоне в браузере:"
echo "  http://$IP:8080"
echo "  (телефон должен быть в той же Wi-Fi сети)"
echo "  Подожди ~1 минуту, пока соберётся."
echo "  Остановить: Control + C"
echo "=============================================="
echo ""
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 2>&1 | tee logs/run_phone.txt
