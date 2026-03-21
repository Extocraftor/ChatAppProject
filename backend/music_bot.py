from __future__ import annotations

import asyncio
import fractions
import inspect
import json
import logging
import os
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Awaitable, Callable, Deque
from urllib.parse import urlparse

import websockets
from aiortc import RTCConfiguration, RTCIceServer, RTCPeerConnection, RTCSessionDescription
from aiortc.contrib.media import MediaPlayer, MediaRelay
from aiortc.mediastreams import AUDIO_PTIME, AudioStreamTrack, MediaStreamError
from aiortc.sdp import candidate_from_sdp
from av import AudioFrame
from websockets.exceptions import ConnectionClosed
from yt_dlp import DownloadError, YoutubeDL


logger = logging.getLogger("music_bot")

TextAnnouncer = Callable[[int, str], Awaitable[None]]
SessionClosedCallback = Callable[[int, "MusicVoiceSession"], Awaitable[None] | None]

DEFAULT_RTC_CONFIGURATION = RTCConfiguration(
    iceServers=[RTCIceServer(urls="stun:stun.l.google.com:19302")]
)


class MusicBotError(Exception):
    pass


@dataclass(slots=True)
class ResolvedMedia:
    original_url: str
    stream_url: str
    title: str
    webpage_url: str
    duration_seconds: int | None = None
    is_live: bool = False
    headers: dict[str, str] = field(default_factory=dict)


@dataclass(slots=True)
class QueueEntry:
    original_url: str
    title: str
    requested_by_username: str
    text_channel_id: int


class SilenceAudioStreamTrack(AudioStreamTrack):
    def __init__(self, sample_rate: int = 48_000, layout: str = "stereo") -> None:
        super().__init__()
        self._sample_rate = sample_rate
        self._layout = layout

    async def recv(self) -> AudioFrame:
        if self.readyState != "live":
            raise MediaStreamError

        samples = int(AUDIO_PTIME * self._sample_rate)

        if hasattr(self, "_timestamp"):
            self._timestamp += samples
            wait = self._start + (self._timestamp / self._sample_rate) - time.time()
            await asyncio.sleep(max(wait, 0))
        else:
            self._start = time.time()
            self._timestamp = 0

        frame = AudioFrame(format="s16", layout=self._layout, samples=samples)
        for plane in frame.planes:
            plane.update(bytes(plane.buffer_size))

        frame.pts = self._timestamp
        frame.sample_rate = self._sample_rate
        frame.time_base = fractions.Fraction(1, self._sample_rate)
        return frame


class SwitchingAudioTrack(AudioStreamTrack):
    def __init__(self) -> None:
        super().__init__()
        self._silence_track = SilenceAudioStreamTrack()
        self._source_track: AudioStreamTrack = self._silence_track
        self._source_finished_callback: Callable[[], None] | None = None

    def use_silence(self) -> None:
        self._source_track = self._silence_track
        self._source_finished_callback = None

    def set_source(
        self,
        track: AudioStreamTrack,
        *,
        on_finished: Callable[[], None] | None = None,
    ) -> None:
        self._source_track = track
        self._source_finished_callback = on_finished

    async def recv(self) -> AudioFrame:
        while self.readyState == "live":
            source_track = self._source_track
            callback = self._source_finished_callback
            try:
                return await source_track.recv()
            except MediaStreamError:
                if source_track is self._source_track:
                    self.use_silence()
                    if callback is not None:
                        callback()
                continue
            except Exception:
                logger.exception("audio source failed")
                if source_track is self._source_track:
                    self.use_silence()
                    if callback is not None:
                        callback()
                continue

        raise MediaStreamError

    def stop(self) -> None:
        self._silence_track.stop()
        super().stop()


class MusicVoiceSession:
    def __init__(
        self,
        *,
        voice_channel_id: int,
        bot_user_id: int,
        bot_username: str,
        signal_base_ws_url: str,
        announce: TextAnnouncer,
        on_closed: SessionClosedCallback,
    ) -> None:
        self.voice_channel_id = voice_channel_id
        self.bot_user_id = bot_user_id
        self.bot_username = bot_username
        self._signal_base_ws_url = signal_base_ws_url.rstrip("/")
        self._announce = announce
        self._on_closed = on_closed

        self._signal_ws = None
        self._reader_task: asyncio.Task[None] | None = None
        self._worker_task: asyncio.Task[None] | None = None
        self._connect_lock = asyncio.Lock()

        self._queue: Deque[QueueEntry] = deque()
        self._participants: dict[int, str] = {}
        self._peer_connections: dict[int, RTCPeerConnection] = {}
        self._pending_remote_ice: dict[int, list[dict[str, object]]] = {}
        self._remote_description_ready_users: set[int] = set()
        self._connected_peers: set[int] = set()
        self._peer_connected_event = asyncio.Event()

        self._audio_bridge = SwitchingAudioTrack()
        self._audio_relay = MediaRelay()

        self._current_item: QueueEntry | None = None
        self._current_player: MediaPlayer | None = None
        self._current_player_audio = None
        self._current_track_done: asyncio.Event | None = None

        self._last_text_channel_id: int | None = None
        self._closing = False
        self._closed = False
        self._stop_requested = False

    @property
    def signal_url(self) -> str:
        return (
            f"{self._signal_base_ws_url}/voice/"
            f"{self.voice_channel_id}/{self.bot_user_id}"
        )

    @property
    def queue_size(self) -> int:
        return len(self._queue)

    @property
    def is_playing(self) -> bool:
        return self._current_item is not None

    async def enqueue(
        self,
        *,
        url: str,
        requested_by_username: str,
        text_channel_id: int,
    ) -> None:
        self._assert_open()
        self._last_text_channel_id = text_channel_id

        metadata = await asyncio.to_thread(resolve_media, url)
        await self.ensure_connected()

        queue_entry = QueueEntry(
            original_url=url,
            title=metadata.title,
            requested_by_username=requested_by_username,
            text_channel_id=text_channel_id,
        )
        self._queue.append(queue_entry)
        self._stop_requested = False

        if self._worker_task is None or self._worker_task.done():
            self._worker_task = asyncio.create_task(
                self._playback_loop(),
                name=f"music-playback-{self.voice_channel_id}",
            )

        await self._announce(
            text_channel_id,
            (
                f"Queued: {metadata.title}"
                f" (requested by {requested_by_username})."
            ),
        )

    async def skip(self, text_channel_id: int) -> None:
        self._last_text_channel_id = text_channel_id

        if self._current_item is None:
            if self._queue:
                skipped = self._queue.popleft()
                await self._announce(
                    text_channel_id,
                    f"Removed from queue: {skipped.title}.",
                )
            else:
                await self._announce(text_channel_id, "Nothing is currently playing.")
            return

        current_title = self._current_item.title
        await self._announce(text_channel_id, f"Skipped: {current_title}.")
        await self._finish_current_track()

    async def stop(self, text_channel_id: int, *, reason: str | None = None) -> None:
        self._last_text_channel_id = text_channel_id

        if self._current_item is None and not self._queue:
            await self._announce(text_channel_id, "Nothing is currently playing.")
            return

        self._queue.clear()
        self._stop_requested = True
        await self._announce(
            text_channel_id,
            reason or "Stopped playback and leaving the voice channel.",
        )

        if self._current_item is not None:
            await self._finish_current_track()
            return

        await self.close()

    async def ensure_connected(self) -> None:
        self._assert_open()

        if self._reader_task is not None and not self._reader_task.done():
            return

        async with self._connect_lock:
            if self._reader_task is not None and not self._reader_task.done():
                return

            logger.info(
                "music session connecting voice_channel=%s url=%s",
                self.voice_channel_id,
                self.signal_url,
            )
            self._signal_ws = await websockets.connect(
                self.signal_url,
                open_timeout=10,
                ping_interval=20,
                ping_timeout=20,
                close_timeout=5,
                max_size=1_048_576,
            )
            self._reader_task = asyncio.create_task(
                self._read_signaling_loop(),
                name=f"music-signal-{self.voice_channel_id}",
            )

    async def close(self) -> None:
        if self._closed or self._closing:
            return

        self._closing = True

        reader_task = self._reader_task
        self._reader_task = None

        signal_ws = self._signal_ws
        self._signal_ws = None

        worker_task = self._worker_task
        self._worker_task = None

        if worker_task is not None and worker_task is not asyncio.current_task():
            worker_task.cancel()
            try:
                await worker_task
            except asyncio.CancelledError:
                pass
            except Exception:
                logger.exception("music playback task shutdown failed")

        await self._stop_current_source()

        if signal_ws is not None:
            try:
                await signal_ws.close()
            except Exception:
                logger.exception("music websocket close failed")

        if reader_task is not None and reader_task is not asyncio.current_task():
            try:
                await reader_task
            except Exception:
                pass

        for remote_user_id in list(self._peer_connections.keys()):
            await self._close_peer_connection(remote_user_id)

        self._participants.clear()
        self._pending_remote_ice.clear()
        self._remote_description_ready_users.clear()
        self._connected_peers.clear()
        self._peer_connected_event.clear()
        self._queue.clear()
        self._audio_bridge.stop()

        self._closing = False
        self._closed = True

        callback_result = self._on_closed(self.voice_channel_id, self)
        if inspect.isawaitable(callback_result):
            await callback_result

    async def _playback_loop(self) -> None:
        try:
            while not self._closing:
                if not self._queue:
                    break

                queue_entry = self._queue.popleft()
                self._current_item = queue_entry
                self._current_track_done = asyncio.Event()

                try:
                    await self.ensure_connected()
                    await self._wait_for_peer_connection()

                    resolved = await asyncio.to_thread(
                        resolve_media,
                        queue_entry.original_url,
                    )
                    player = MediaPlayer(
                        resolved.stream_url,
                        options=build_ffmpeg_options(resolved),
                        timeout=20,
                    )
                    audio_track = player.audio
                    if audio_track is None:
                        raise MusicBotError("The link did not provide any playable audio.")

                    self._current_player = player
                    self._current_player_audio = audio_track
                    self._audio_bridge.set_source(
                        audio_track,
                        on_finished=self._mark_current_track_complete,
                    )

                    duration_label = format_duration(resolved.duration_seconds)
                    source_suffix = " (live)" if resolved.is_live else ""
                    duration_suffix = (
                        f" [{duration_label}]"
                        if duration_label is not None and not resolved.is_live
                        else ""
                    )
                    await self._announce(
                        queue_entry.text_channel_id,
                        (
                            f"Now playing: {resolved.title}{source_suffix}{duration_suffix}"
                            f" (requested by {queue_entry.requested_by_username})."
                        ),
                    )

                    await self._current_track_done.wait()
                except asyncio.CancelledError:
                    raise
                except MusicBotError as exc:
                    await self._announce(
                        queue_entry.text_channel_id,
                        f"Unable to play {queue_entry.title}: {exc}",
                    )
                except Exception as exc:
                    logger.exception(
                        "music playback failed voice_channel=%s title=%s",
                        self.voice_channel_id,
                        queue_entry.title,
                    )
                    await self._announce(
                        queue_entry.text_channel_id,
                        f"Playback failed for {queue_entry.title}: {exc}",
                    )
                finally:
                    await self._stop_current_source()
                    self._current_item = None
                    self._current_track_done = None

            if not self._closing:
                if not self._stop_requested and self._last_text_channel_id is not None:
                    await self._announce(
                        self._last_text_channel_id,
                        "Queue finished. Leaving the voice channel.",
                    )
                await self.close()
        except asyncio.CancelledError:
            raise

    async def _read_signaling_loop(self) -> None:
        signal_ws = self._signal_ws
        if signal_ws is None:
            return

        disconnect_error: Exception | None = None

        try:
            async for raw_message in signal_ws:
                if isinstance(raw_message, bytes):
                    continue
                await self._handle_signal_payload(raw_message)
        except ConnectionClosed:
            pass
        except Exception as exc:
            disconnect_error = exc
            logger.exception(
                "music signaling loop crashed voice_channel=%s",
                self.voice_channel_id,
            )
        finally:
            if self._signal_ws is signal_ws:
                self._signal_ws = None

            if not self._closing:
                text_channel_id = self._last_text_channel_id
                if text_channel_id is not None:
                    if disconnect_error is None:
                        await self._announce(
                            text_channel_id,
                            "The music bot lost its voice connection and stopped playback.",
                        )
                    else:
                        await self._announce(
                            text_channel_id,
                            "The music bot hit a voice connection error and stopped playback.",
                        )
                await self.close()

    async def _handle_signal_payload(self, raw_message: str) -> None:
        try:
            payload = json.loads(raw_message)
        except json.JSONDecodeError:
            return

        payload_type = payload.get("type")

        if payload_type == "voice_state":
            participants = payload.get("participants") or []
            if not isinstance(participants, list):
                return

            self._participants.clear()
            for participant in participants:
                if not isinstance(participant, dict):
                    continue
                user_id = participant.get("user_id")
                username = participant.get("username")
                if isinstance(user_id, int) and isinstance(username, str):
                    self._participants[user_id] = username
            return

        if payload_type == "participant_joined":
            user_id = payload.get("user_id")
            username = payload.get("username")
            if not isinstance(user_id, int) or user_id == self.bot_user_id:
                return

            if isinstance(username, str):
                self._participants[user_id] = username
            else:
                self._participants[user_id] = f"User #{user_id}"

            await self._create_offer_for_user(user_id)
            return

        if payload_type == "participant_left":
            user_id = payload.get("user_id")
            if not isinstance(user_id, int):
                return

            self._participants.pop(user_id, None)
            await self._close_peer_connection(user_id)

            if not self._human_participants():
                text_channel_id = self._last_text_channel_id
                if text_channel_id is not None:
                    await self.stop(
                        text_channel_id,
                        reason="Everyone left the voice channel, so the bot is leaving too.",
                    )
            return

        if payload_type == "offer":
            await self._handle_offer(payload)
            return

        if payload_type == "answer":
            await self._handle_answer(payload)
            return

        if payload_type == "ice_candidate":
            await self._handle_remote_ice_candidate(payload)
            return

    async def _ensure_peer_connection(self, remote_user_id: int) -> RTCPeerConnection:
        existing = self._peer_connections.get(remote_user_id)
        if existing is not None:
            return existing

        peer_connection = RTCPeerConnection(DEFAULT_RTC_CONFIGURATION)
        peer_connection.addTrack(self._audio_relay.subscribe(self._audio_bridge))

        @peer_connection.on("icecandidate")
        async def on_icecandidate(candidate) -> None:
            if candidate is None or candidate.candidate is None:
                return

            await self._send_signal(
                {
                    "type": "ice_candidate",
                    "target_user_id": remote_user_id,
                    "candidate": {
                        "candidate": candidate.candidate,
                        "sdpMid": candidate.sdpMid,
                        "sdpMLineIndex": candidate.sdpMLineIndex,
                    },
                }
            )

        @peer_connection.on("connectionstatechange")
        async def on_connectionstatechange() -> None:
            state = peer_connection.connectionState
            if state == "connected":
                self._connected_peers.add(remote_user_id)
                self._peer_connected_event.set()
                return

            if state in {"failed", "closed"}:
                await self._close_peer_connection(remote_user_id)

        self._peer_connections[remote_user_id] = peer_connection
        return peer_connection

    async def _create_offer_for_user(self, remote_user_id: int) -> None:
        if remote_user_id == self.bot_user_id or self._closing:
            return

        peer_connection = await self._ensure_peer_connection(remote_user_id)
        self._remote_description_ready_users.discard(remote_user_id)

        offer = await peer_connection.createOffer()
        await peer_connection.setLocalDescription(offer)
        await self._send_signal(
            {
                "type": "offer",
                "target_user_id": remote_user_id,
                "sdp": {
                    "sdp": offer.sdp,
                    "type": offer.type,
                },
            }
        )

    async def _handle_offer(self, payload: dict[str, object]) -> None:
        from_user_id = payload.get("from_user_id")
        sdp_data = payload.get("sdp")
        if not isinstance(from_user_id, int) or not isinstance(sdp_data, dict):
            return

        remote_sdp = sdp_data.get("sdp")
        remote_type = sdp_data.get("type")
        if not isinstance(remote_sdp, str) or not isinstance(remote_type, str):
            return

        peer_connection = await self._ensure_peer_connection(from_user_id)
        await peer_connection.setRemoteDescription(
            RTCSessionDescription(sdp=remote_sdp, type=remote_type)
        )
        self._remote_description_ready_users.add(from_user_id)
        await self._flush_remote_ice_candidates(from_user_id)

        answer = await peer_connection.createAnswer()
        await peer_connection.setLocalDescription(answer)
        await self._send_signal(
            {
                "type": "answer",
                "target_user_id": from_user_id,
                "sdp": {
                    "sdp": answer.sdp,
                    "type": answer.type,
                },
            }
        )

    async def _handle_answer(self, payload: dict[str, object]) -> None:
        from_user_id = payload.get("from_user_id")
        sdp_data = payload.get("sdp")
        if not isinstance(from_user_id, int) or not isinstance(sdp_data, dict):
            return

        remote_sdp = sdp_data.get("sdp")
        remote_type = sdp_data.get("type")
        if not isinstance(remote_sdp, str) or not isinstance(remote_type, str):
            return

        peer_connection = self._peer_connections.get(from_user_id)
        if peer_connection is None:
            return

        await peer_connection.setRemoteDescription(
            RTCSessionDescription(sdp=remote_sdp, type=remote_type)
        )
        self._remote_description_ready_users.add(from_user_id)
        await self._flush_remote_ice_candidates(from_user_id)

    async def _handle_remote_ice_candidate(self, payload: dict[str, object]) -> None:
        from_user_id = payload.get("from_user_id")
        candidate_data = payload.get("candidate")
        if not isinstance(from_user_id, int) or not isinstance(candidate_data, dict):
            return

        candidate_sdp = candidate_data.get("candidate")
        if not isinstance(candidate_sdp, str) or not candidate_sdp:
            return

        if from_user_id not in self._remote_description_ready_users:
            self._pending_remote_ice.setdefault(from_user_id, []).append(candidate_data)
            return

        peer_connection = await self._ensure_peer_connection(from_user_id)
        await peer_connection.addIceCandidate(parse_ice_candidate(candidate_data))

    async def _flush_remote_ice_candidates(self, remote_user_id: int) -> None:
        pending_candidates = self._pending_remote_ice.pop(remote_user_id, [])
        if not pending_candidates:
            return

        peer_connection = await self._ensure_peer_connection(remote_user_id)
        for candidate_data in pending_candidates:
            try:
                await peer_connection.addIceCandidate(parse_ice_candidate(candidate_data))
            except Exception:
                logger.exception(
                    "music failed to add queued ice candidate voice_channel=%s user=%s",
                    self.voice_channel_id,
                    remote_user_id,
                )

    async def _close_peer_connection(self, remote_user_id: int) -> None:
        peer_connection = self._peer_connections.pop(remote_user_id, None)
        self._pending_remote_ice.pop(remote_user_id, None)
        self._remote_description_ready_users.discard(remote_user_id)
        self._connected_peers.discard(remote_user_id)
        if not self._connected_peers:
            self._peer_connected_event.clear()

        if peer_connection is not None:
            try:
                await peer_connection.close()
            except Exception:
                logger.exception(
                    "music failed to close peer voice_channel=%s user=%s",
                    self.voice_channel_id,
                    remote_user_id,
                )

    async def _send_signal(self, payload: dict[str, object]) -> None:
        signal_ws = self._signal_ws
        if signal_ws is None:
            raise MusicBotError("The bot is not connected to voice signaling.")

        await signal_ws.send(json.dumps(payload))

    async def _wait_for_peer_connection(self) -> None:
        if self._connected_peers or not self._human_participants():
            return

        self._peer_connected_event.clear()
        try:
            await asyncio.wait_for(self._peer_connected_event.wait(), timeout=2.0)
        except asyncio.TimeoutError:
            pass

    async def _finish_current_track(self) -> None:
        self._mark_current_track_complete()
        await self._stop_current_source()

    async def _stop_current_source(self) -> None:
        player = self._current_player
        audio_track = self._current_player_audio
        self._current_player = None
        self._current_player_audio = None
        self._audio_bridge.use_silence()

        if audio_track is not None:
            try:
                audio_track.stop()
            except Exception:
                logger.exception("music failed to stop audio track")

        if player is not None and player.video is not None:
            try:
                player.video.stop()
            except Exception:
                logger.exception("music failed to stop video track")

    def _mark_current_track_complete(self) -> None:
        if self._current_track_done is not None and not self._current_track_done.is_set():
            self._current_track_done.set()

    def _human_participants(self) -> list[int]:
        return [
            user_id
            for user_id in self._participants
            if user_id != self.bot_user_id
        ]

    def _assert_open(self) -> None:
        if self._closed or self._closing:
            raise MusicBotError("The music session is shutting down.")


class MusicBotManager:
    def __init__(
        self,
        *,
        bot_user_id: int,
        bot_username: str,
        signal_base_ws_url: str,
        announce: TextAnnouncer,
    ) -> None:
        self.bot_user_id = bot_user_id
        self.bot_username = bot_username
        self._signal_base_ws_url = signal_base_ws_url
        self._announce = announce
        self._sessions: dict[int, MusicVoiceSession] = {}
        self._lock = asyncio.Lock()

    async def enqueue(
        self,
        *,
        voice_channel_id: int,
        text_channel_id: int,
        url: str,
        requested_by_username: str,
    ) -> None:
        session, created = await self._get_or_create_session(voice_channel_id)
        try:
            await session.enqueue(
                url=url,
                requested_by_username=requested_by_username,
                text_channel_id=text_channel_id,
            )
        except Exception:
            if created:
                await session.close()
            raise

    async def skip(self, *, voice_channel_id: int, text_channel_id: int) -> None:
        session = self._sessions.get(voice_channel_id)
        if session is None:
            await self._announce(text_channel_id, "Nothing is currently playing.")
            return
        await session.skip(text_channel_id)

    async def stop(self, *, voice_channel_id: int, text_channel_id: int) -> None:
        session = self._sessions.get(voice_channel_id)
        if session is None:
            await self._announce(text_channel_id, "Nothing is currently playing.")
            return
        await session.stop(text_channel_id)

    async def describe_queue(
        self,
        *,
        voice_channel_id: int,
        text_channel_id: int,
    ) -> None:
        session = self._sessions.get(voice_channel_id)
        if session is None or (not session.is_playing and session.queue_size == 0):
            await self._announce(text_channel_id, "The queue is empty.")
            return

        lines: list[str] = []
        if session.is_playing and session._current_item is not None:
            lines.append(f"Now playing: {session._current_item.title}")

        if session.queue_size:
            queued_titles = list(session._queue)[:5]
            for index, item in enumerate(queued_titles, start=1):
                lines.append(f"{index}. {item.title}")
            if session.queue_size > 5:
                lines.append(f"...and {session.queue_size - 5} more.")

        await self._announce(text_channel_id, "Queue:\n" + "\n".join(lines))

    async def _get_or_create_session(
        self,
        voice_channel_id: int,
    ) -> tuple[MusicVoiceSession, bool]:
        async with self._lock:
            existing = self._sessions.get(voice_channel_id)
            if existing is not None:
                return existing, False

            session = MusicVoiceSession(
                voice_channel_id=voice_channel_id,
                bot_user_id=self.bot_user_id,
                bot_username=self.bot_username,
                signal_base_ws_url=self._signal_base_ws_url,
                announce=self._announce,
                on_closed=self._handle_session_closed,
            )
            self._sessions[voice_channel_id] = session
            return session, True

    async def _handle_session_closed(
        self,
        voice_channel_id: int,
        session: MusicVoiceSession,
    ) -> None:
        async with self._lock:
            current = self._sessions.get(voice_channel_id)
            if current is session:
                self._sessions.pop(voice_channel_id, None)


def build_default_signal_base_ws_url() -> str:
    configured = os.getenv("MUSIC_BOT_SIGNAL_BASE_WS_URL")
    if configured:
        return configured.rstrip("/")

    host = os.getenv("MUSIC_BOT_SIGNAL_HOST", "127.0.0.1")
    port = int(os.getenv("PORT", os.getenv("UVICORN_PORT", "8000")))
    return f"ws://{host}:{port}/ws"


def resolve_media(url: str) -> ResolvedMedia:
    url = normalize_media_url(url)
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise MusicBotError("The play command needs a full http or https URL.")

    ydl_options = {
        "format": "bestaudio/best",
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
        "skip_download": True,
        "socket_timeout": 15,
    }

    try:
        with YoutubeDL(ydl_options) as ydl:
            info = ydl.extract_info(url, download=False)
    except DownloadError as exc:
        if is_youtube_host(parsed.netloc):
            raise MusicBotError(
                "Unable to extract audio from that YouTube URL: "
                f"{summarize_download_error(exc)}"
            ) from exc
        return ResolvedMedia(
            original_url=url,
            stream_url=url,
            title=best_effort_title_from_url(url),
            webpage_url=url,
        )
    except Exception as exc:
        raise MusicBotError(f"Unable to resolve that link: {exc}") from exc

    if info is None:
        raise MusicBotError("The link could not be resolved.")

    if isinstance(info, dict) and "entries" in info:
        entries = [entry for entry in info.get("entries") or [] if entry]
        if not entries:
            raise MusicBotError("The link did not contain any playable entries.")
        info = entries[0]

    if not isinstance(info, dict):
        raise MusicBotError("The link returned an unsupported media payload.")

    title = (
        info.get("title")
        or info.get("fulltitle")
        or info.get("webpage_url")
        or best_effort_title_from_url(url)
    )
    webpage_url = info.get("webpage_url") or url
    duration_seconds = safe_int(info.get("duration"))
    is_live = bool(info.get("is_live"))
    headers = {
        str(key): str(value)
        for key, value in (info.get("http_headers") or {}).items()
        if value is not None
    }

    stream_url = extract_stream_url(info)
    if not stream_url:
        raise MusicBotError("The link did not expose a playable audio stream.")

    return ResolvedMedia(
        original_url=url,
        stream_url=stream_url,
        title=str(title),
        webpage_url=str(webpage_url),
        duration_seconds=duration_seconds,
        is_live=is_live,
        headers=headers,
    )


def extract_stream_url(info: dict[str, object]) -> str | None:
    direct_url = info.get("url")
    if isinstance(direct_url, str) and direct_url:
        return direct_url

    requested_formats = info.get("requested_formats")
    if isinstance(requested_formats, list):
        for media_format in requested_formats:
            if not isinstance(media_format, dict):
                continue
            if not format_has_audio(media_format):
                continue
            format_url = media_format.get("url")
            if isinstance(format_url, str) and format_url:
                return format_url

    formats = info.get("formats")
    if isinstance(formats, list):
        audio_formats: list[dict[str, object]] = []
        for media_format in formats:
            if not isinstance(media_format, dict):
                continue
            if not format_has_audio(media_format):
                continue
            format_url = media_format.get("url")
            if isinstance(format_url, str) and format_url:
                audio_formats.append(media_format)

        if audio_formats:
            best_audio = max(audio_formats, key=format_sort_key)
            format_url = best_audio.get("url")
            if isinstance(format_url, str) and format_url:
                return format_url

    return None


def normalize_media_url(url: str) -> str:
    normalized = url.strip()
    normalized = normalized.strip("<>")
    normalized = normalized.strip("\"'")
    if "://" in normalized:
        return normalized

    possible_host = normalized.split("/", 1)[0].lower()
    if is_youtube_host(possible_host):
        return f"https://{normalized}"

    return normalized


def is_youtube_host(host: str) -> bool:
    normalized_host = host.strip().lower()
    if not normalized_host:
        return False

    if ":" in normalized_host:
        normalized_host = normalized_host.split(":", 1)[0]

    return normalized_host in {
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtu.be",
    }


def summarize_download_error(exc: DownloadError) -> str:
    message = str(exc).strip()
    if message.startswith("ERROR: "):
        message = message[len("ERROR: ") :]
    message = " ".join(message.split())
    return message or "unknown extractor error"


def format_has_audio(media_format: dict[str, object]) -> bool:
    acodec = media_format.get("acodec")
    return isinstance(acodec, str) and acodec != "none"


def format_sort_key(media_format: dict[str, object]) -> tuple[int, int, int]:
    abr = safe_int(media_format.get("abr")) or 0
    asr = safe_int(media_format.get("asr")) or 0
    quality = safe_int(media_format.get("quality")) or 0
    return abr, asr, quality


def safe_int(value: object) -> int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(float(value))
        except ValueError:
            return None
    return None


def best_effort_title_from_url(url: str) -> str:
    parsed = urlparse(url)
    tail = parsed.path.rsplit("/", 1)[-1].strip()
    if tail:
        return tail
    return url


def parse_ice_candidate(candidate_data: dict[str, object]):
    candidate_sdp = candidate_data.get("candidate")
    if not isinstance(candidate_sdp, str) or not candidate_sdp:
        raise MusicBotError("Received an invalid ICE candidate.")

    stripped_sdp = candidate_sdp
    if stripped_sdp.startswith("candidate:"):
        stripped_sdp = stripped_sdp[len("candidate:") :]

    candidate = candidate_from_sdp(stripped_sdp)

    sdp_mid = candidate_data.get("sdpMid")
    if isinstance(sdp_mid, str):
        candidate.sdpMid = sdp_mid

    sdp_mline_index = safe_int(candidate_data.get("sdpMLineIndex"))
    if sdp_mline_index is not None:
        candidate.sdpMLineIndex = sdp_mline_index

    return candidate


def build_ffmpeg_options(media: ResolvedMedia) -> dict[str, str]:
    options = {
        "vn": "1",
        "reconnect": "1",
        "reconnect_streamed": "1",
        "reconnect_delay_max": "5",
        "rw_timeout": "15000000",
    }

    headers = format_ffmpeg_headers(media.headers)
    if headers:
        options["headers"] = headers

    return options


def format_ffmpeg_headers(headers: dict[str, str]) -> str | None:
    if not headers:
        return None

    lines = [f"{key}: {value}" for key, value in headers.items() if value]
    if not lines:
        return None
    return "\r\n".join(lines) + "\r\n"


def format_duration(duration_seconds: int | None) -> str | None:
    if duration_seconds is None or duration_seconds <= 0:
        return None

    minutes, seconds = divmod(duration_seconds, 60)
    hours, minutes = divmod(minutes, 60)

    if hours:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes}:{seconds:02d}"
