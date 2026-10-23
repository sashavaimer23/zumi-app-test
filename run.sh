#!/bin/sh
# Запуск Zumi в Chrome. Ошибки сохраняются в папку logs/, чтобы их можно было прочитать.
cd "$(dirname "$0")"
mkdir -p logs
echo "1/3  Скачиваю библиотеки..."
flutter pub get > logs/pub.txt 2>&1 || { echo "Ошибка на шаге pub get — напиши Claude"; exit 1; }
echo "2/3  Проверяю код..."
flutter analyze --no-fatal-infos --no-fatal-warnings > logs/analyze.txt 2>&1
if grep -q " error " logs/analyze.txt; then
  echo "В коде есть ошибки — напиши Claude «проверь логи»"
  exit 1
fi
echo "3/3  Запускаю в Chrome..."
flutter run -d chrome 2>&1 | tee logs/run.txt
