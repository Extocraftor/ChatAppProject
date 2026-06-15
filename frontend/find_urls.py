import urllib.request

def try_urls(prefix, suffixes):
    for s in suffixes:
        url = f"https://www.myinstants.com/media/sounds/{prefix}{s}.mp3"
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            urllib.request.urlopen(req)
            print(f"FOUND: {url}")
            return url
        except Exception:
            pass
    print(f"NOT FOUND for prefix {prefix}")

try_urls('discord', ['-join', '-join-sound', 'join', '-channel-join', '-user-join', '-connected'])
try_urls('discord', ['-leave', '-leave-sound', 'leave', '-channel-leave', '-user-leave', '-disconnected'])
