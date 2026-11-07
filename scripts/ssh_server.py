#!/usr/bin/env python3
"""
Full-featured SSHv2 Server (Interactive PTY, Exec, SFTP, SCP, Port Forwarding)
using AsyncSSH. Authenticates a target user/password (default: runner / root)
on port 22 cleanly on macOS and Linux.
"""

import argparse
import asyncio
import fcntl
import os
import pty
import pwd
import signal
import struct
import sys
import termios
import asyncssh


def set_winsize(fd: int, width: int, height: int, pixwidth: int = 0, pixheight: int = 0) -> None:
    if width <= 0:
        width = 80
    if height <= 0:
        height = 24
    winsize = struct.pack("HHHH", height, width, pixwidth, pixheight)
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
    except OSError:
        pass


class SimpleAuthSSHServer(asyncssh.SSHServer):
    def __init__(self, allowed_user: str, allowed_pass: str):
        self._allowed_user = allowed_user
        self._allowed_pass = allowed_pass

    def begin_auth(self, username: str) -> bool:
        return True

    def password_auth_supported(self) -> bool:
        return True

    def kbdint_auth_supported(self) -> bool:
        return True

    def get_kbdint_challenge(self, username: str, lang: str, submethods: str):
        return "", "", "", [("Password: ", False)]

    def validate_kbdint_response(self, username: str, responses: list) -> bool:
        if not responses:
            return False
        return username == self._allowed_user and responses[0] == self._allowed_pass

    def validate_password(self, username: str, password: str) -> bool:
        return username == self._allowed_user and password == self._allowed_pass


def make_process_handler(shell_path: str, base_env: dict):
    async def handle_process(process: asyncssh.SSHServerProcess) -> None:
        env = dict(base_env)
        for k, v in process.env.items():
            ks = k.decode("utf-8", errors="ignore") if isinstance(k, bytes) else str(k)
            vs = v.decode("utf-8", errors="ignore") if isinstance(v, bytes) else str(v)
            env[ks] = vs

        term_type = process.get_terminal_type()
        cmd = process.command
        if isinstance(cmd, bytes):
            cmd = cmd.decode("utf-8", errors="replace")

        # Case 1: Non-PTY command execution (`ssh runner@host "cmd"`)
        if term_type is None and cmd is not None:
            proc = await asyncio.create_subprocess_exec(
                shell_path, "-l", "-c", cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=env.get("HOME", "/"),
                env=env,
            )

            async def pump_in():
                try:
                    while not process.stdin.at_eof():
                        data = await process.stdin.read(4096)
                        if not data:
                            break
                        proc.stdin.write(data)
                        await proc.stdin.drain()
                except Exception:
                    pass
                finally:
                    try:
                        proc.stdin.close()
                    except Exception:
                        pass

            async def pump_out(reader, writer):
                try:
                    while True:
                        data = await reader.read(4096)
                        if not data:
                            break
                        writer.write(data)
                except Exception:
                    pass

            in_task = asyncio.create_task(pump_in())
            out_task = asyncio.create_task(pump_out(proc.stdout, process.stdout))
            err_task = asyncio.create_task(pump_out(proc.stderr, process.stderr))
            rc = await proc.wait()
            in_task.cancel()
            await asyncio.gather(out_task, err_task, return_exceptions=True)
            process.exit(rc)
            return

        # Case 2: Interactive PTY shell (or `ssh -t runner@host "cmd"`)
        env["TERM"] = term_type or "xterm-256color"
        master_fd, slave_fd = pty.openpty()
        try:
            w, h, pw, ph = process.get_terminal_size()
            set_winsize(master_fd, w, h, pw, ph)
        except Exception:
            set_winsize(master_fd, 80, 24)

        def child_setup():
            os.setsid()
            try:
                fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
            except OSError:
                pass

        args = [shell_path, "-l"]
        if cmd is not None:
            args.extend(["-c", cmd])

        proc = await asyncio.create_subprocess_exec(
            *args,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            cwd=env.get("HOME", "/"),
            env=env,
            preexec_fn=child_setup,
        )
        os.close(slave_fd)

        loop = asyncio.get_running_loop()

        def on_pty_readable():
            try:
                data = os.read(master_fd, 8192)
                if data:
                    process.stdout.write(data)
                else:
                    loop.remove_reader(master_fd)
            except OSError:
                try:
                    loop.remove_reader(master_fd)
                except Exception:
                    pass

        loop.add_reader(master_fd, on_pty_readable)

        async def read_ssh_stdin():
            while True:
                try:
                    data = await process.stdin.read(4096)
                    if not data:
                        try:
                            os.write(master_fd, b"\x04")
                        except OSError:
                            pass
                        break
                    os.write(master_fd, data)
                except asyncssh.TerminalSizeChanged as exc:
                    set_winsize(master_fd, exc.width, exc.height, exc.pixwidth, exc.pixheight)
                    if proc.returncode is None:
                        try:
                            proc.send_signal(signal.SIGWINCH)
                        except ProcessLookupError:
                            pass
                except asyncssh.BreakReceived:
                    if proc.returncode is None:
                        try:
                            os.killpg(os.getpgid(proc.pid), signal.SIGINT)
                        except Exception:
                            pass
                except Exception:
                    break

        stdin_task = asyncio.create_task(read_ssh_stdin())
        try:
            rc = await proc.wait()
            await asyncio.sleep(0.05)
        finally:
            stdin_task.cancel()
            try:
                loop.remove_reader(master_fd)
            except Exception:
                pass
            try:
                os.close(master_fd)
            except OSError:
                pass
            if proc.returncode is None:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGHUP)
                except Exception:
                    try:
                        proc.terminate()
                    except Exception:
                        pass

        process.exit(rc if rc is not None else 0)

    return handle_process


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", type=str, default="runner")
    parser.add_argument("--password", type=str, default="root")
    parser.add_argument("--run-as", type=str, default="runner")
    parser.add_argument("--host-key", type=str, default="/tmp/asyncssh_host_ed25519")
    args = parser.parse_args()

    if not os.path.exists(args.host_key):
        key = asyncssh.generate_private_key("ssh-ed25519")
        key.write_private_key(args.host_key)
        os.chmod(args.host_key, 0o600)

    pw_entry = pwd.getpwnam(args.run_as)
    shell_path = pw_entry.pw_shell if os.path.exists(pw_entry.pw_shell) else (
        "/bin/zsh" if os.path.exists("/bin/zsh") else "/bin/bash"
    )
    if os.path.exists("/bin/zsh") and sys.platform == "darwin":
        shell_path = "/bin/zsh"

    base_env = {
        "HOME": pw_entry.pw_dir,
        "USER": pw_entry.pw_name,
        "LOGNAME": pw_entry.pw_name,
        "SHELL": shell_path,
        "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
    }

    server = await asyncssh.create_server(
        lambda: SimpleAuthSSHServer(args.user, args.password),
        host="",
        port=args.port,
        server_host_keys=[args.host_key],
        process_factory=make_process_handler(shell_path, base_env),
        encoding=None,
        sftp_factory=True,
        allow_scp=True,
    )

    if os.geteuid() == 0 and pw_entry.pw_uid != 0:
        os.chown(args.host_key, pw_entry.pw_uid, pw_entry.pw_gid)
        os.initgroups(pw_entry.pw_name, pw_entry.pw_gid)
        os.setgid(pw_entry.pw_gid)
        os.setuid(pw_entry.pw_uid)
        os.environ["HOME"] = pw_entry.pw_dir
        os.environ["USER"] = pw_entry.pw_name

    print(f"AsyncSSH server listening on port {args.port} (auth user='{args.user}', shell={shell_path})", flush=True)
    await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())
