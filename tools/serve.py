#!/usr/bin/env python3
"""Run a simple HTTP server to view the MotorCursor Visualizer locally."""

import http.server
import socketserver
import webbrowser
import sys
from pathlib import Path

PORT = 8000
DIRECTORY = Path(__file__).resolve().parent.parent

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DIRECTORY), **kwargs)

    def log_message(self, format, *args):
        # Silence default request logging to keep console clean
        pass

def main():
    # Ensure port is free
    socketserver.TCPServer.allow_reuse_address = True
    
    try:
        with socketserver.TCPServer(("", PORT), CustomHandler) as httpd:
            url = f"http://localhost:{PORT}/visualizer.html"
            print("=" * 70)
            print(" 🚀 MOTORCURSOR TELEMETRY VISUALIZER SERVER")
            print("=" * 70)
            print(f" Сервер запущен в директории: {DIRECTORY}")
            print(f" Адрес для открытия в браузере: \033[1;36m{url}\033[0m")
            print("=" * 70)
            print(" Ссылка кликабельна! Зажмите Ctrl и кликните по ссылке выше.")
            print(" Для остановки сервера нажмите Ctrl + C")
            print("=" * 70)
            
            # Automatically try to open the browser
            try:
                webbrowser.open(url)
            except Exception:
                pass
                
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n Сервер успешно остановлен. До свидания!")
        sys.exit(0)
    except OSError as e:
        print(f"Ошибка: Не удалось занять порт {PORT}. Возможно, он уже используется другим процессом.")
        print(f"Детали: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
