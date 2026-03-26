# Music Bot Fix Plan

**Generated:** 2026-03-25  
**Source:** `1774443730865_music_bot_implementation_attempt_combined.txt`

---

## Root Problems Diagnosed

Before the fix plan, here are the concrete bugs causing failures:

**Bug 1 — `_send_music_bot_notice` has swapped arguments.**
The function calls `manager.broadcast(json_string, channel_id)`, but `ConnectionManager.broadcast` expects `(channel_id, message)` — the same convention used by `VoiceConnectionManager.broadcast`. The arguments are reversed, so music bot notices are never delivered to text chat.

**Bug 2 — Audio proxy URL has a broken `base_url`.**
`base_url = str(websocket.url.replace(path="", scheme=...))` — `Starlette.URL.replace` does not accept a `path=""` kwarg; it either throws or produces a malformed URL. If it silently fails, `final_stream_url` stays as the raw yt-dlp signed CDN URL, which Flutter's `audioplayers` `UrlSource` cannot play directly from mobile.

**Bug 3 — The audio proxy opens two separate `httpx` clients.**
The HEAD probe and the streaming GET use different `AsyncClient` instances, losing session continuity. The stream also omits the `Referer` header required by YouTube's CDN, causing 403 errors. There is also no `Range` header passthrough, so `audioplayers` cannot seek.

**Bug 4 — Music bot notices never reach text chat (Bug 1), so users get no feedback.**
The `music_play` event is sent correctly on the voice WebSocket, but the user sees nothing in the chat UI because Bug 1 silently drops the `music_bot_notice`.

**Bug 5 — Spotify search doesn't work.**
`ytsearch1:<spotify_url>` passes the full Spotify URL as a YouTube search query, returning unrelated results. The intent (evidenced by `spotipy` in `requirements.txt` but unused) was to resolve the Spotify track to `"Artist - Title"` first, then search YouTube.

---

## Detailed Fix Plan

### Phase 1 — Fix `_send_music_bot_notice` (argument order)

**File:** `backend/main.py`

The `ConnectionManager.broadcast` signature follows the same `(channel_id, message)` convention as the voice manager. Fix the argument order:

```python
# BEFORE (broken)
async def _send_music_bot_notice(channel_id: int, content: str) -> None:
    await manager.broadcast(
        json.dumps({
            "type": "music_bot_notice",
            "content": content,
        }),
        channel_id,
    )

# AFTER (fixed)
async def _send_music_bot_notice(channel_id: int, content: str) -> None:
    await manager.broadcast(
        channel_id,                          # ← channel_id FIRST
        json.dumps({
            "type": "music_bot_notice",
            "content": content,
        }),
    )
```

> **Action:** Audit the full `ConnectionManager.broadcast` signature and ensure all callers are consistent with the argument order.

---

### Phase 2 — Fix `base_url` construction

**File:** `backend/main.py`

Replace the broken `websocket.url.replace(...)` call with a correct manual construction:

```python
# BEFORE (broken)
base_url = str(websocket.url.replace(path="", scheme="https" if websocket.url.is_secure else "http"))

# AFTER (fixed)
ws_url = websocket.url
scheme = "https" if ws_url.scheme in ("wss", "https") else "http"
base_url = f"{scheme}://{ws_url.hostname}"
if ws_url.port and ws_url.port not in (80, 443):
    base_url += f":{ws_url.port}"
```

This produces a clean `https://extochatapp.onrender.com` that the proxy URL can be correctly appended to.

---

### Phase 3 — Fix the audio proxy

**File:** `backend/main.py`

The current proxy has three problems: two separate `httpx` clients, missing `Referer` header, and no `Range` passthrough. Replace the entire endpoint:

```python
@app.get("/audio-proxy")
async def audio_proxy(request: Request, url: str):
    target_url = urllib.parse.unquote(url)
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "audio/*,*/*;q=0.8",
        "Referer": "https://www.youtube.com/",  # Required for YouTube CDN
    }

    # Passthrough Range header so audioplayers can seek
    range_header = request.headers.get("range")
    if range_header:
        headers["Range"] = range_header

    async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
        response_headers = {"Accept-Ranges": "bytes"}
        content_type = "audio/mpeg"

        # HEAD probe — same client, same session
        try:
            probe = await client.head(target_url, headers=headers, timeout=10.0)
            if probe.is_success:
                content_type = probe.headers.get("content-type", content_type)
                for h in ("content-length", "accept-ranges", "cache-control", "etag"):
                    if v := probe.headers.get(h):
                        response_headers[h.title()] = v
        except Exception:
            pass  # Proceed without metadata; stream will still work

        async def stream_audio():
            async with client.stream("GET", target_url, headers=headers) as resp:
                async for chunk in resp.aiter_bytes(chunk_size=65536):
                    yield chunk

        return StreamingResponse(
            stream_audio(),
            media_type=content_type,
            headers=response_headers,
        )
```

> **Key changes:**  
> - Single `AsyncClient` shared between HEAD and GET  
> - `Referer: https://www.youtube.com/` added  
> - `Range` header forwarded from the incoming Flutter request  
> - `chunk_size=65536` for efficient streaming  

---

### Phase 4 — Fix Spotify resolution

**File:** `backend/main.py`

Replace the broken `ytsearch1:<spotify_url>` with actual Spotify metadata lookup using `spotipy` (already in `requirements.txt`):

```python
import spotipy
from spotipy.oauth2 import SpotifyClientCredentials

def _resolve_spotify_to_search_query(spotify_url: str) -> str:
    """Convert a Spotify track URL to 'Artist - Title' for YouTube search."""
    client_id = os.getenv("SPOTIFY_CLIENT_ID", "").strip()
    client_secret = os.getenv("SPOTIFY_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        raise MusicExtractionError(
            "Spotify links require SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET env vars."
        )
    sp = spotipy.Spotify(
        auth_manager=SpotifyClientCredentials(
            client_id=client_id,
            client_secret=client_secret,
        )
    )
    match = SPOTIFY_URL_PATTERN.match(spotify_url)
    track_id = match.group("id")
    track = sp.track(track_id)
    artist = track["artists"][0]["name"]
    title = track["name"]
    return f"ytsearch1:{artist} - {title}"
```

Then in `_handle_music_play_command`, replace the Spotify branch:

```python
# BEFORE (broken — passes raw Spotify URL as a search term)
if is_spotify:
    extraction_url = f"ytsearch1:{raw_url}"

# AFTER (fixed — resolves to "Artist - Title" first)
if is_spotify:
    extraction_url = _resolve_spotify_to_search_query(raw_url)
```

> **New env vars required:** `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET`  
> Get these from the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) by creating a free app.

---

### Phase 5 — Frontend: verify `_appendLocalSystemMessage` triggers a UI rebuild

**File:** `frontend/lib/providers/app_state.dart`

The method adds to the `messages` list but must call `notifyListeners()` so the widget tree rebuilds. Verify and fix:

```dart
// BEFORE (may be missing notifyListeners)
void _appendLocalSystemMessage(String content) {
  messages.add(
    Message(
      id: _nextLocalMessageId--,
      userId: 0,
      username: "Music Bot",
      content: content,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    ),
  );
}

// AFTER (guaranteed rebuild)
void _appendLocalSystemMessage(String content) {
  messages.add(
    Message(
      id: _nextLocalMessageId--,
      userId: 0,
      username: "Music Bot",
      content: content,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    ),
  );
  notifyListeners(); // ← ensure the chat list widget rebuilds
}
```

---

### Phase 6 — Frontend: verify HTTPS for mobile playback

**File:** `frontend/lib/providers/app_state.dart`

`UrlSource(streamUrl)` with a proxied backend URL works, but iOS ATS blocks plain `http://` URLs. Since the backend is on Render (`https://extochatapp.onrender.com`), the proxy URL will be HTTPS as long as Phase 2's `base_url` fix is applied correctly.

Additionally, surface `voiceError` in the UI so the user sees playback failures. If it isn't already displayed, add a visible error widget wherever voice state is shown:

```dart
if (appState.voiceError != null)
  Text(
    appState.voiceError!,
    style: const TextStyle(color: Colors.red),
  ),
```

---

### Phase 7 — yt-dlp YouTube bot-check mitigation (deployment)

**Environment:** Render dashboard

On a hosted server, anonymous yt-dlp calls to YouTube will almost always hit bot-check errors. The cookie strategy in the code is correct but requires setup:

1. **Export YouTube cookies** from a logged-in browser using the "Get cookies.txt LOCALLY" browser extension. Save in Netscape format.
2. **Base64-encode the file:**
   ```bash
   base64 -w 0 cookies.txt
   ```
3. **Set the environment variable** in your Render dashboard:
   ```
   MUSIC_BOT_YTDLP_COOKIES_B64=<base64 output>
   ```
4. **Enable the tuned extractor:**
   ```
   MUSIC_BOT_YTDLP_ENABLE_TUNED_EXTRACTOR=1
   ```
5. **Redeploy** the backend service.

> **Note:** YouTube signed cookie tokens expire. If extraction starts failing again after working, re-export and update `MUSIC_BOT_YTDLP_COOKIES_B64`.

---

## Summary Checklist

| # | Fix | File | Impact |
|---|-----|------|--------|
| 1 | Swap `manager.broadcast` argument order in `_send_music_bot_notice` | `main.py` | Music bot notices appear in chat |
| 2 | Rewrite `base_url` construction from `websocket.url` | `main.py` | Proxy URL is valid |
| 3 | Single `httpx` client + `Referer` header + `Range` passthrough in `/audio-proxy` | `main.py` | Audio actually streams and seeks |
| 4 | Use `spotipy` to resolve Spotify → `"Artist - Title"` before yt search | `main.py` | Spotify links work |
| 5 | Add `notifyListeners()` in `_appendLocalSystemMessage` | `app_state.dart` | Chat UI rebuilds on bot messages |
| 6 | Verify `music_play` stream URL is `https://` on mobile, surface `voiceError` | `app_state.dart` | iOS/Android playback unblocked |
| 7 | Set `MUSIC_BOT_YTDLP_COOKIES_B64` env var on Render | Deployment | YouTube extraction works in prod |
