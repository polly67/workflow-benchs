"""
Coordination module for inter-runner signaling, GitHub workflow dispatch,
and Cloudflare tunnel provisioning.
"""
import asyncio
import json
import logging
import os
import re
import subprocess
import time
from typing import Optional, Dict, Any
import requests

logger = logging.getLogger("Coordinator")

GITHUB_API_URL = "https://api.github.com"
DEFAULT_REPO = "Xincs-Lab/workflow-benchs"
DEFAULT_WORKFLOW = "runner-handoff.yml"

class TunnelManager:
    def __init__(self, local_port: int = 8765):
        self.local_port = local_port
        self.process: Optional[subprocess.Popen] = None
        self.public_url: Optional[str] = None

    def start(self, timeout: int = 15) -> str:
        logger.info(f"Starting cloudflared tunnel for localhost:{self.local_port}...")
        self.process = subprocess.Popen(
            ["cloudflared", "tunnel", "--url", f"http://127.0.0.1:{self.local_port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        start_t = time.time()
        while time.time() - start_t < timeout:
            line = self.process.stderr.readline()
            if not line and self.process.poll() is not None:
                break
            m = re.search(r"https://[a-zA-Z0-9\-]+\.trycloudflare\.com", line)
            if m:
                http_url = m.group(0)
                # Convert to WSS
                self.public_url = http_url.replace("https://", "wss://")
                logger.info(f"Cloudflare Tunnel active: {self.public_url}")
                return self.public_url

        raise RuntimeError("Failed to obtain Cloudflare tunnel URL within timeout.")

    def stop(self):
        if self.process:
            logger.info("Stopping Cloudflare tunnel...")
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except Exception:
                self.process.kill()
            self.process = None


class InterRunnerCoordinator:
    def __init__(
        self,
        session_id: str,
        github_token: Optional[str] = None,
        repo: str = DEFAULT_REPO
    ):
        self.session_id = session_id
        self.channel = f"whyno-handoff-{session_id}"
        self.ntfy_url = f"https://ntfy.sh/{self.channel}"
        self.github_token = github_token or os.environ.get("GITHUB_TOKEN")
        self.repo = repo

    def publish_signal(self, event_type: str, payload: Dict[str, Any]):
        data = {"event": event_type, "session_id": self.session_id, "timestamp": time.time(), **payload}
        try:
            resp = requests.post(self.ntfy_url, data=json.dumps(data), timeout=5)
            if resp.status_code == 200:
                logger.info(f"Published signal [{event_type}] to {self.channel}")
            else:
                logger.warning(f"Publish failed: {resp.status_code}")
        except Exception as e:
            logger.error(f"Error publishing signal: {e}")

    def poll_for_signal(self, event_type: str, timeout: int = 180, poll_interval: float = 2.0) -> Optional[Dict[str, Any]]:
        logger.info(f"Waiting for signal [{event_type}] on channel {self.channel} (timeout: {timeout}s)...")
        start_t = time.time()
        seen_ids = set()

        while time.time() - start_t < timeout:
            try:
                resp = requests.get(f"{self.ntfy_url}/json?poll=1", timeout=5)
                if resp.status_code == 200:
                    for line in resp.text.strip().split("\n"):
                        if not line:
                            continue
                        try:
                            item = json.loads(line)
                            msg_id = item.get("id")
                            if msg_id in seen_ids:
                                continue
                            seen_ids.add(msg_id)

                            raw_msg = item.get("message", "{}")
                            payload = json.loads(raw_msg)
                            if payload.get("event") == event_type and payload.get("session_id") == self.session_id:
                                logger.info(f"Received expected signal [{event_type}]: {payload}")
                                return payload
                        except Exception:
                            continue
            except Exception as e:
                logger.debug(f"Poll check error: {e}")

            time.sleep(poll_interval)

        logger.error(f"Timed out waiting for signal [{event_type}] after {timeout}s")
        return None

    def trigger_runner_2(self, workflow_name: str = DEFAULT_WORKFLOW, role: str = "runner2") -> bool:
        if not self.github_token:
            logger.error("No GITHUB_TOKEN available to dispatch Runner 2 workflow.")
            return False

        url = f"{GITHUB_API_URL}/repos/{self.repo}/actions/workflows/{workflow_name}/dispatches"
        headers = {
            "Authorization": f"token {self.github_token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json"
        }
        body = {
            "ref": "main",
            "inputs": {
                "role": role,
                "session_id": self.session_id
            }
        }
        try:
            logger.info(f"Dispatching workflow {workflow_name} to provision Runner 2...")
            resp = requests.post(url, headers=headers, json=body, timeout=10)
            if resp.status_code in (200, 204):
                logger.info("Successfully dispatched Runner 2 workflow!")
                return True
            else:
                logger.error(f"Failed to dispatch Runner 2: {resp.status_code} {resp.text}")
                return False
        except Exception as e:
            logger.error(f"Exception dispatching Runner 2: {e}")
            return False
