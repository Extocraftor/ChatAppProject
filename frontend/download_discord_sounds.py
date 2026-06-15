import os
import urllib.request

def download(url, filename):
    try:
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0'}
        )
        with urllib.request.urlopen(req) as response, open(filename, 'wb') as f:
            f.write(response.read())
        print(f"Success: {filename}")
    except Exception as e:
        print(f"Failed: {filename} - {e}")

download('https://www.myinstants.com/media/sounds/discord-join.mp3', 'assets/sounds/discord-join.mp3')
download('https://www.myinstants.com/media/sounds/discord-leave.mp3', 'assets/sounds/discord-leave.mp3')
