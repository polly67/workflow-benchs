"""
High-speed bot cluster generating 100 msgs/second with handover handling and loss tracking.
"""
import asyncio
import collections
import json
import logging
import random
import time
from typing import Dict, List, Optional
import websockets
from scripts.handoff.protocol import ChatMessage

logger = logging.getLogger("BotCluster")

CHAT_TEMPLATES = [
    "Runner health check status nominal.",
    "Database replication block synced at offset {seq}.",
    "Compute node CPU load stable at 4.2%.",
    "Telemetry packet {seq} validated.",
    "KV store consensus heart-beat acknowledged.",
    "Cache hit ratio 99.4% on shard {shard}.",
    "Dispatching job block {seq} to worker pool.",
    "Network egress packet verified."
]

class BotAgent:
    def __init__(
        self,
        bot_id: str,
        initial_url: str,
        buffer_mode: str = "buffered", # "buffered" or "unbuffered"
        cluster = None
    ):
        self.bot_id = bot_id
        self.current_url = initial_url
        self.target_url: Optional[str] = None
        self.buffer_mode = buffer_mode
        self.cluster = cluster
        self.ws: Optional[websockets.WebSocketClientProtocol] = None
        self.is_connected = False
        self.is_handing_over = False
        self.buffer = collections.deque()
        self.running = False
        self.send_task: Optional[asyncio.Task] = None
        self.recv_task: Optional[asyncio.Task] = None
        self.handover_start = 0.0
        self.handover_end = 0.0

    async def start(self):
        self.running = True
        await self._connect(self.current_url)
        self.recv_task = asyncio.create_task(self._receive_loop())

    async def _connect(self, url: str):
        try:
            self.ws = await websockets.connect(url, ping_interval=10, ping_timeout=10)
            self.current_url = url
            self.is_connected = True
            await self.ws.send(json.dumps({
                "type": "REGISTER_BOT",
                "bot_id": self.bot_id
            }))
            # If buffered and we reconnected, flush buffer
            if self.buffer:
                count = len(self.buffer)
                while self.buffer:
                    msg = self.buffer.popleft()
                    await self.ws.send(msg.to_json())
                logger.info(f"[{self.bot_id}] Flushed {count} buffered messages to {url}")
        except Exception as e:
            self.is_connected = False
            logger.debug(f"[{self.bot_id}] Connect to {url} failed: {e}")

    async def _receive_loop(self):
        while self.running:
            if not self.ws or self.ws.closed:
                await asyncio.sleep(0.05)
                continue
            try:
                raw = await self.ws.recv()
                data = json.loads(raw)
                msg_type = data.get("type")
                if msg_type == "HANDOVER_REDIRECT":
                    new_target = data.get("target_url")
                    logger.warning(f"[{self.bot_id}] Received HANDOVER_REDIRECT -> {new_target}")
                    asyncio.create_task(self.migrate_to(new_target))
            except (websockets.exceptions.ConnectionClosed, asyncio.CancelledError):
                break
            except Exception:
                await asyncio.sleep(0.05)

    async def migrate_to(self, new_url: str):
        if self.is_handing_over:
            return
        self.is_handing_over = True
        self.handover_start = time.time()
        self.is_connected = False

        old_ws = self.ws
        self.ws = None
        if old_ws:
            try:
                await old_ws.close()
            except Exception:
                pass

        # Retry loop to connect to Runner 2
        connected = False
        attempts = 0
        while self.running and not connected and attempts < 100:
            attempts += 1
            try:
                self.ws = await websockets.connect(new_url, ping_interval=10, ping_timeout=10)
                self.current_url = new_url
                self.is_connected = True
                connected = True
                await self.ws.send(json.dumps({
                    "type": "REGISTER_BOT",
                    "bot_id": self.bot_id
                }))
                self.handover_end = time.time()
                dur_ms = (self.handover_end - self.handover_start) * 1000.0
                logger.info(f"[{self.bot_id}] Handover complete to {new_url} in {dur_ms:.1f}ms")

                # Flush buffer if in buffered mode
                if self.buffer_mode == "buffered" and self.buffer:
                    count = len(self.buffer)
                    while self.buffer:
                        msg = self.buffer.popleft()
                        await self.ws.send(msg.to_json())
                    logger.info(f"[{self.bot_id}] Flushed {count} buffered messages after handover.")
            except Exception as e:
                await asyncio.sleep(0.05)

        self.is_handing_over = False

    async def send_message(self, msg: ChatMessage):
        if self.is_connected and self.ws and not self.ws.closed:
            try:
                await self.ws.send(msg.to_json())
                return True
            except Exception:
                self.is_connected = False
                if self.buffer_mode == "buffered":
                    self.buffer.appendleft(msg)
                    if self.cluster:
                        self.cluster.buffered_count += 1
                    return True

        # If disconnected / in handover
        if self.buffer_mode == "buffered":
            self.buffer.append(msg)
            if self.cluster:
                self.cluster.buffered_count += 1
            return True
        else:
            # Unbuffered mode: message is dropped
            if self.cluster:
                self.cluster.dropped_count += 1
            return False

    async def stop(self):
        self.running = False
        if self.recv_task:
            self.recv_task.cancel()
        if self.ws:
            await self.ws.close()

class BotCluster:
    def __init__(
        self,
        server_url: str,
        num_bots: int = 10,
        target_rate: float = 100.0,
        buffer_mode: str = "buffered"
    ):
        self.server_url = server_url
        self.num_bots = num_bots
        self.target_rate = target_rate
        self.buffer_mode = buffer_mode
        self.bots: List[BotAgent] = []
        self.current_seq = 0
        self.total_sent = 0
        self.buffered_count = 0
        self.dropped_count = 0
        self.running = False
        self._traffic_task: Optional[asyncio.Task] = None

    async def start(self):
        self.running = True
        logger.info(
            f"Spawning {self.num_bots} bots targeting {self.target_rate} msgs/sec "
            f"[Mode: {self.buffer_mode.upper()}] to {self.server_url}"
        )
        for i in range(1, self.num_bots + 1):
            bot = BotAgent(
                bot_id=f"bot-{i:02d}",
                initial_url=self.server_url,
                buffer_mode=self.buffer_mode,
                cluster=self
            )
            self.bots.append(bot)
            await bot.start()

        # Wait for connections to establish
        await asyncio.sleep(0.2)
        self._traffic_task = asyncio.create_task(self._generate_traffic())

    async def _generate_traffic(self):
        try:
            logger.info(f"BotCluster traffic generator started for {len(self.bots)} bots at {self.target_rate} mps")
            dt = 1.0 / self.target_rate
            start_time = time.perf_counter()
            bot_idx = 0
            all_bot_ids = [b.bot_id for b in self.bots]

            while self.running:
                self.current_seq += 1
                seq = self.current_seq
                self.total_sent += 1

                sender_bot = self.bots[bot_idx % len(self.bots)]
                bot_idx += 1
                recip = random.choice([b for b in all_bot_ids if b != sender_bot.bot_id] or ["all"])
                template = random.choice(CHAT_TEMPLATES)
                payload = template.format(seq=seq, shard=random.randint(1, 16))

                msg = ChatMessage(
                    seq=seq,
                    sender=sender_bot.bot_id,
                    recipient=recip,
                    timestamp=time.time(),
                    payload=payload
                )

                sent = await sender_bot.send_message(msg)
                if seq == 1:
                    logger.info(f"BotCluster successfully transmitted initial message seq=1 (status: {sent})")

                # Precise pacer
                target_t = start_time + self.total_sent * dt
                now = time.perf_counter()
                if target_t > now:
                    await asyncio.sleep(target_t - now)
        except Exception as e:
            logger.exception(f"Unhandled exception in _generate_traffic: {e}")

    async def trigger_handover(self, new_url: str):
        logger.warning(f"[BotCluster] Manually triggering migration of all bots to {new_url}")
        await asyncio.gather(*(bot.migrate_to(new_url) for bot in self.bots))

    async def stop(self):
        self.running = False
        if self._traffic_task:
            self._traffic_task.cancel()
        
        # Flush any remaining buffers
        if self.buffer_mode == "buffered":
            for bot in self.bots:
                if bot.buffer and bot.ws and not bot.ws.closed:
                    while bot.buffer:
                        msg = bot.buffer.popleft()
                        try:
                            await bot.ws.send(msg.to_json())
                        except Exception:
                            break

        for bot in self.bots:
            await bot.stop()
        logger.info(
            f"[BotCluster] Stopped. Total Sent: {self.total_sent} | "
            f"Buffered: {self.buffered_count} | Dropped: {self.dropped_count}"
        )
