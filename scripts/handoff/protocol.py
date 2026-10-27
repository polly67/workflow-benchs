"""
Data models and sequence loss tracker for high-speed bot chat and runner handoff.
"""
import time
import json
from dataclasses import dataclass, field, asdict
from typing import List, Dict, Optional, Set

@dataclass
class ChatMessage:
    seq: int
    sender: str
    recipient: str
    timestamp: float
    payload: str

    def to_json(self) -> str:
        return json.dumps(asdict(self))

    @staticmethod
    def from_json(data: str) -> "ChatMessage":
        d = json.loads(data)
        return ChatMessage(
            seq=d["seq"],
            sender=d["sender"],
            recipient=d.get("recipient", "all"),
            timestamp=d["timestamp"],
            payload=d.get("payload", "")
        )

@dataclass
class StateSnapshot:
    server_id: str
    last_seq: int
    total_received: int
    active_bots: List[str]
    start_time: float
    snapshot_time: float
    received_seqs: List[int] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps(asdict(self))

    @staticmethod
    def from_json(data: str) -> "StateSnapshot":
        d = json.loads(data)
        return StateSnapshot(**d)

@dataclass
class LossAnalysis:
    total_sent: int
    total_received_s1: int
    total_received_s2: int
    total_received: int
    lost_count: int
    loss_percentage: float
    missing_seq_ranges: List[str]
    handover_disruption_ms: float
    throughput_s1_mps: float
    throughput_s2_mps: float
    avg_latency_ms: float
    p95_latency_ms: float

class SequenceTracker:
    def __init__(self):
        self.received_seqs: Set[int] = set()
        self.highest_seq: int = 0
        self.lowest_seq: Optional[int] = None
        self.latencies_ms: List[float] = []
        self.timestamps: List[float] = []
        self.server1_count: int = 0
        self.server2_count: int = 0
        self.last_s1_time: Optional[float] = None
        self.first_s2_time: Optional[float] = None

    def record_message(self, msg: ChatMessage, server_id: str):
        now = time.time()
        self.received_seqs.add(msg.seq)
        if self.lowest_seq is None or msg.seq < self.lowest_seq:
            self.lowest_seq = msg.seq
        if msg.seq > self.highest_seq:
            self.highest_seq = msg.seq

        lat = max(0.0, (now - msg.timestamp) * 1000.0)
        self.latencies_ms.append(lat)
        self.timestamps.append(now)

        if server_id == "runner-1":
            self.server1_count += 1
            self.last_s1_time = now
        else:
            self.server2_count += 1
            if self.first_s2_time is None:
                self.first_s2_time = now

    def analyze_loss(self, total_sent: int, start_seq: int = 1) -> LossAnalysis:
        end_seq = max(total_sent, self.highest_seq)
        missing_seqs = [s for s in range(start_seq, end_seq + 1) if s not in self.received_seqs]
        lost_count = len(missing_seqs)
        loss_pct = (lost_count / total_sent * 100.0) if total_sent > 0 else 0.0

        # Group missing seqs into compact ranges e.g. "101-145"
        ranges = []
        if missing_seqs:
            r_start = missing_seqs[0]
            r_prev = missing_seqs[0]
            for s in missing_seqs[1:]:
                if s == r_prev + 1:
                    r_prev = s
                else:
                    ranges.append(f"{r_start}-{r_prev}" if r_start != r_prev else f"{r_start}")
                    r_start = s
                    r_prev = s
            ranges.append(f"{r_start}-{r_prev}" if r_start != r_prev else f"{r_start}")

        disruption_ms = 0.0
        if self.last_s1_time and self.first_s2_time:
            disruption_ms = max(0.0, (self.first_s2_time - self.last_s1_time) * 1000.0)

        avg_lat = sum(self.latencies_ms) / len(self.latencies_ms) if self.latencies_ms else 0.0
        sorted_lat = sorted(self.latencies_ms) if self.latencies_ms else [0.0]
        p95_idx = int(len(sorted_lat) * 0.95)
        p95_lat = sorted_lat[min(p95_idx, len(sorted_lat) - 1)]

        return LossAnalysis(
            total_sent=total_sent,
            total_received_s1=self.server1_count,
            total_received_s2=self.server2_count,
            total_received=len(self.received_seqs),
            lost_count=lost_count,
            loss_percentage=round(loss_pct, 2),
            missing_seq_ranges=ranges[:10] + (["..."] if len(ranges) > 10 else []),
            handover_disruption_ms=round(disruption_ms, 2),
            throughput_s1_mps=0.0,
            throughput_s2_mps=0.0,
            avg_latency_ms=round(avg_lat, 2),
            p95_latency_ms=round(p95_lat, 2)
        )
