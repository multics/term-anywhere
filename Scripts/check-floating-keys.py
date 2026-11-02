#!/usr/bin/env python3
"""Verify floating-key sequences on an isolated tmux server, without user sessions."""
import fcntl
import os
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time

with tempfile.TemporaryDirectory(prefix='term-floating-keys-') as folder:
    command = ['tmux', '-S', folder + '/tmux.sock']
    def tmux(*args):
        return subprocess.check_output(command + list(args), text=True).strip()
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 0, 0))
    attached = None
    try:
        tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'keys')
        cases = [('Up', '\x1b[A'), ('Down', '\x1b[B'), ('Right', '\x1b[C'), ('Left', '\x1b[D'),
                 ('S-Up', '\x1b[1;2A'), ('S-Down', '\x1b[1;2B'),
                 ('S-Right', '\x1b[1;2C'), ('S-Left', '\x1b[1;2D'), ('Escape', '\x1b')]
        for key, _ in cases:
            tmux('bind-key', '-n', key, 'set-option', '-g', '@floating-key', key)
        attached = subprocess.Popen(command + ['attach', '-t', 'keys'], stdin=slave, stdout=slave, stderr=slave,
                                    env={**os.environ, 'TERM': 'xterm-256color'}, start_new_session=True)
        for key, sequence in cases:
            tmux('set-option', '-g', '@floating-key', 'waiting')
            os.write(master, sequence.encode())
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                if select.select([master], [], [], .03)[0]:
                    os.read(master, 65536)
                if tmux('show-option', '-gv', '@floating-key') == key:
                    break
            assert tmux('show-option', '-gv', '@floating-key') == key, key
            print('TMUX_FLOATING_KEY_OK', key)
    finally:
        subprocess.run(command + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if attached:
            attached.wait(timeout=5)
        os.close(master)
        os.close(slave)
