"""
High-throughput async WebSocket message server for bots with state export/import
and graceful handover capability.
"""
import asyncio
import json
import logging
import time
from typing import Dict, Set, Optional
import websockets
from scripts.handoff.protocol import ChatMessage, StateSnapshot, SequenceTracker

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("MessageServer")

class MessageServer:
    def __init__(self, server_id: str, host: str = "0.0.0.0", port: int = 8765):
        self.server_id = server_id
        self.host = host
        self.port = port
        self.clients: Set[websockets.WebSocketServerProtocol] = set()
        self.bot_clients: Dict[str, websockets.WebSocketServerProtocol] = {}
        self.tracker = SequenceTracker()
        self.running = False
        self.start_time = 0.0
        self.total_received = 0
        self.recent_count = 0
        self.current_mps = 0.0
        self.server = None
        self._rate_task: Optional[asyncio.Task] = None
        self.handover_target: Optional[str] = None

    async def start(self):
        self.running = True
        self.start_time = time.time()
        self.server = await websockets.serve(
            self.handle_connection,
            self.host,
            self.port,
            ping_interval=20,
            ping_timeout=20,
            max_size=10 * 1024 * 1024
        )
        self._rate_task = asyncio.create_task(self._rate_monitor())
        logger.info(f"[{self.server_id}] Server started on {self.host}:{self.port}")

    async def _rate_monitor(self):
        last_t = time.time()
        while self.running:
            await asyncio.sleep(1.0)
            now = time.time()
            dt = now - last_t
            if dt > 0:
                self.current_mps = self.recent_count / dt
                self.recent_count = 0
                last_t = now
                if self.total_received > 0:
                    logger.info(
                        f"[{self.server_id}] Rate: {self.current_mps:.1f} msgs/s | "
                        f"Total: {self.total_received} | Active Bots: {len(self.bot_clients)}"
                    )

    async def handle_connection(self, websocket: websockets.WebSocketServerProtocol):
        self.clients.add(websocket)
        bot_id = None
        try:
            async for raw_msg in websocket:
                try:
                    data = json.loads(raw_msg)
                except Exception:
                    continue

                msg_type = data.get("type", "CHAT")

                if msg_type == "REGISTER_BOT":
                    bot_id = data.get("bot_id", f"bot-{len(self.bot_clients)+1}")
                    self.bot_clients[bot_id] = websocket
                    await websocket.send(json.dumps({
                        "type": "REGISTER_ACK",
                        "server_id": self.server_id,
                        "bot_id": bot_id
                    }))

                elif msg_type == "CHAT":
                    msg = ChatMessage(
                        seq=data["seq"],
                        sender=data["sender"],
                        recipient=data.get("recipient", "all"),
                        timestamp=data["timestamp"],
                        payload=data.get("payload", "")
                    )
                    self.total_received += 1
                    self.recent_count += 1
                    self.tracker.record_message(msg, self.server_id)

                    # Broadcast to other bots if recipient is 'all'
                    if len(self.bot_clients) > 1 and data.get("broadcast", False):
                        broadcast_data = json.dumps({"type": "INCOMING_CHAT", "msg": data})
                        recipients = [
                            ws for b_id, ws in self.bot_clients.items()
                            if ws != websocket
                        ]
                        if recipients:
                            await asyncio.gather(
                                *(ws.send(broadcast_data) for ws in recipients),
                                return_exceptions=True
                            )

                elif msg_type == "GET_STATUS":
                    await websocket.send(json.dumps({
                        "type": "STATUS_RESPONSE",
                        "server_id": self.server_id,
                        "total_received": self.total_received,
                        "highest_seq": self.tracker.highest_seq,
                        "active_bots": len(self.bot_clients),
                        "mps": self.current_mps,
                        "uptime": round(time.time() - self.start_time, 2)
                    }))

                elif msg_type == "EXPORT_STATE":
                    snapshot = StateSnapshot(
                        server_id=self.server_id,
                        last_seq=self.tracker.highest_seq,
                        total_received=self.total_received,
                        active_bots=list(self.bot_clients.keys()),
                        start_time=self.start_time,
                        snapshot_time=time.time(),
                        received_seqs=list(self.tracker.received_seqs)
                    )
                    await websocket.send(json.dumps({
                        "type": "STATE_EXPORT_RESPONSE",
                        "snapshot": asdict(snapshot)
                    }))

                elif msg_type == "IMPORT_STATE":
                    snap_data = data.get("snapshot", {})
                    prev_seqs = snap_data.get("received_seqs", [])
                    prev_id = snap_data.get("server_id", "runner-1")
                    for s in prev_seqs:
                        self.tracker.received_seqs.add(s)
                    if prev_id == "runner-1":
                        self.tracker.server1_count = len(prev_seqs)
                    self.tracker.highest_seq = max(self.tracker.highest_seq, snap_data.get("last_seq", 0))
                    logger.info(f"[{self.server_id}] Imported state from {prev_id}: {len(prev_seqs)} prior messages.")
                    await websocket.send(json.dumps({
                        "type": "STATE_IMPORT_ACK",
                        "imported_count": len(prev_seqs)
                    }))

                elif msg_type == "INITIATE_HANDOVER":
                    target_url = data.get("target_url")
                    self.handover_target = target_url
                    logger.warning(f"[{self.server_id}] INITIATING HANDOVER TO: {target_url}")
                    handover_payload = json.dumps({
                        "type": "HANDOVER_REDIRECT",
                        "target_url": target_url,
                        "drain_time_ms": data.get("drain_time_ms", 100)
                    })
                    if self.bot_clients:
                        await asyncio.gather(
                            *(ws.send(handover_payload) for ws in self.bot_clients.values()),
                            return_exceptions=True
                        )
                    await websocket.send(json.dumps({
                        "type": "HANDOVER_ACK",
                        "bots_notified": len(self.bot_clients)
                    }))

        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.clients.discard(websocket)
            if bot_id and bot_id in self.bot_clients:
                del self.bot_clients[bot_id]

    async def initiate_handover(self, target_url: str):
        self.handover_target = target_url
        logger.warning(f"[{self.server_id}] Broadcasting HANDOVER_REDIRECT to {len(self.bot_clients)} bots -> {target_url}")
        payload = json.dumps({
            "type": "HANDOVER_REDIRECT",
            "target_url": target_url
        })
        if self.bot_clients:
            await asyncio.gather(
                *(ws.send(payload) for ws in list(self.bot_clients.values())),
                return_exceptions=True
            )

    async def stop(self):
        self.running = False
        if self._rate_task:
            self._rate_task.cancel()
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        logger.info(f"[{self.server_id}] Stopped. Total messages processed: {self.total_received}")
