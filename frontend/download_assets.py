import os
import urllib.request

os.makedirs('assets/sounds', exist_ok=True)

def download_file(url, filename):
    try:
        req = urllib.request.Request(
            url, 
            data=None, 
            headers={
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
        )
        with urllib.request.urlopen(req) as response, open(f'assets/sounds/{filename}', 'wb') as out_file:
            data = response.read()
            out_file.write(data)
        print(f"Downloaded {filename}")
    except Exception as e:
        print(f"Failed to download {filename}: {e}")

download_file('https://actions.google.com/sounds/v1/ui/positive_notification.ogg', 'join.ogg')
download_file('https://actions.google.com/sounds/v1/ui/message_notification.ogg', 'notification.ogg')
