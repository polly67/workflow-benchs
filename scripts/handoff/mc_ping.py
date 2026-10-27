import socket
import struct
import json
import time

def encode_varint(val: int) -> bytes:
    total = b""
    while True:
        byte = val & 0x7F
        val >>= 7
        if val != 0:
            byte |= 0x80
        total += struct.pack("!B", byte)
        if val == 0:
            break
    return total

def read_varint(sock: socket.socket) -> int:
    result = 0
    shift = 0
    while True:
        b = sock.recv(1)
        if not b:
            raise ConnectionError("Socket closed prematurely while reading VarInt")
        byte_val = b[0]
        result |= (byte_val & 0x7F) << shift
        if not (byte_val & 0x80):
            break
        shift += 7
        if shift >= 35:
            raise ValueError("VarInt too large")
    return result

def ping_minecraft_server(host: str = "127.0.0.1", port: int = 25565, timeout: float = 3.0) -> dict:
    start_time = time.perf_counter()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    
    try:
        sock.connect((host, port))
        
        # 1. Handshake Packet (ID 0x00, protocol -1, host, port, state 1)
        host_bytes = host.encode('utf-8')
        handshake_payload = (
            encode_varint(0x00) +
            encode_varint(765) +
            encode_varint(len(host_bytes)) + host_bytes +
            struct.pack("!H", port) +
            encode_varint(1)
        )
        handshake_packet = encode_varint(len(handshake_payload)) + handshake_payload
        sock.sendall(handshake_packet)
        
        # 2. Status Request Packet (ID 0x00)
        request_payload = encode_varint(0x00)
        request_packet = encode_varint(len(request_payload)) + request_payload
        sock.sendall(request_packet)
        
        # 3. Read Response
        packet_len = read_varint(sock)
        packet_id = read_varint(sock)
        if packet_id != 0x00:
            raise ValueError(f"Expected packet ID 0x00, got {packet_id}")
            
        json_len = read_varint(sock)
        data = bytearray()
        while len(data) < json_len:
            chunk = sock.recv(min(4096, json_len - len(data)))
            if not chunk:
                break
            data.extend(chunk)
            
        latency_ms = (time.perf_counter() - start_time) * 1000
        
        status_data = json.loads(data.decode('utf-8'))
        status_data["latency_ms"] = round(latency_ms, 2)
        return status_data
    finally:
        sock.close()

if __name__ == "__main__":
    import sys
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 25565
    try:
        res = ping_minecraft_server(host, port)
        print("Success:")
        print(json.dumps(res, indent=2))
    except Exception as e:
        print(f"Error pinging {host}:{port}: {e}")
