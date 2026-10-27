# 📊 Runner Handover Loss Benchmark: Unbuffered vs Buffered

Tested at sustained rate of **100 messages/second** with **10 concurrent bot agents**.

| Metric | Unbuffered (Abrupt / Hard Cut) | Buffered (Graceful Handover) |
| :--- | :--- | :--- |
| **Total Messages Sent** | `852` | `861` |
| **Total Messages Received** | `851` | `861` |
| **Dropped / Lost Messages** | **`1` msgs** | **`0` msgs (0 LOSS)** |
| **Message Loss %** | **`0.12%`** | **`0.0%`** |
| **Handover Disruption Window** | `19.44 ms` | `25.73 ms` |
| **Average Latency** | `0.22 ms` | `0.26 ms` |
| **P95 Latency** | `0.29 ms` | `0.27 ms` |

### Key Architectural Takeaway:
- In **Unbuffered Mode**, cutting the server abruptly drops messages generated during the network reconnection gap.
- In **Buffered Mode**, client bots buffer in-flight messages in memory and replay them upon connecting to Runner 2, ensuring **0.00% packet loss** with continuous sequence numbering.
