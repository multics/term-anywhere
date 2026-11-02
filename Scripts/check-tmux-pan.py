#!/usr/bin/env python3
"""Check per-client tmux viewport movement on an isolated server and two PTYs."""
import fcntl
import os
import pty
import select
import shlex
import struct
import subprocess
import tempfile
import termios
import time

with tempfile.TemporaryDirectory(prefix='term-pan-') as folder:
    command = ['tmux', '-S', folder + '/tmux.sock']
    clients = []
    def tmux(*args):
        return subprocess.check_output(command + list(args), text=True).strip()
    def drain():
        for process, master, slave in clients:
            while select.select([master], [], [], 0)[0]:
                os.read(master, 65536)
    def state(tty):
        return tmux('display-message', '-c', tty, '-p',
                    '#{window_offset_x}|#{window_width}|#{window_height}')
    def expect(tty, value):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            drain()
            if state(tty) == value:
                return
            time.sleep(.02)
        raise AssertionError((tty, state(tty), value))
    try:
        tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'wide', '-x', '200', '-y', '25')
        tmux('set-option', '-w', '-t', 'wide:', 'window-size', 'manual')
        tmux('set-option', '-t', 'wide', 'status', 'off')
        for width in (200, 80):
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 25, width, 0, 0))
            preamble = "printf '\\033]777;term-anywhere-test;%s\\007' \"$(tty)\"; exec "
            process = subprocess.Popen(['/bin/sh', '-c', preamble + shlex.join(command + ['attach', '-t', 'wide'])],
                                       stdin=slave, stdout=slave, stderr=slave,
                                       env={**os.environ, 'TERM': 'xterm-256color'}, start_new_session=True)
            clients.append((process, master, slave))
            output = b''
            deadline = time.monotonic() + 3
            marker = ('\x1b]777;term-anywhere-test;' + os.ttyname(slave) + '\x07').encode()
            while marker not in output and time.monotonic() < deadline:
                if select.select([master], [], [], .05)[0]:
                    output += os.read(master, 65536)
            assert marker in output, 'PTY identity handshake missing'
        desktop, mobile = [os.ttyname(item[2]) for item in clients]
        deadline = time.monotonic() + 3
        while len(tmux('list-clients').splitlines()) != 2 and time.monotonic() < deadline:
            drain(); time.sleep(.02)
        tmux('refresh-client', '-t', mobile, '-L', '999')
        expect(mobile, '0|200|25')
        baseline = state(desktop)
        for direction, count, offset in [('R', 20, 20), ('R', 15, 35), ('L', 10, 25), ('R', 999, 120), ('L', 999, 0)]:
            tmux('refresh-client', '-t', mobile, '-' + direction, str(count))
            expect(mobile, f'{offset}|200|25')
            assert state(desktop) == baseline, 'Desktop viewport changed'
            print('TMUX_PAN_OK', direction, count, 'offset', offset)
        tmux('refresh-client', '-t', mobile, '-c')
        expect(mobile, '0|200|25')
        assert state(desktop) == baseline
        print('TMUX_PAN_OK cursor follow; window size and desktop viewport unchanged')
    finally:
        subprocess.run(command + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for process, master, slave in clients:
            os.close(master); os.close(slave)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
