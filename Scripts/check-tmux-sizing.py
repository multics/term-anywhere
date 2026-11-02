#!/usr/bin/env python3
"""Check migration and desktop/mobile focus switching on an isolated tmux server."""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

with tempfile.TemporaryDirectory(prefix='term-fit-') as folder:
    command = ['tmux', '-S', folder + '/tmux.sock']
    clients = []
    def tmux(*args):
        return subprocess.check_output(command + list(args), text=True).strip()
    def drain():
        for process, master, slave in clients:
            while select.select([master], [], [], 0)[0]:
                try:
                    if not os.read(master, 65536): break
                except OSError: break
    def dimensions(target='fit:'):
        return tmux('display-message', '-p', '-t', target, '#{window_width}|#{window_height}|#{window-size}')
    def expect(width, height, policy="latest"):
        expected = f'{width}|{height}|{policy}'
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            drain()
            if dimensions() == expected: return
            time.sleep(.02)
        raise AssertionError((dimensions(), expected))
    def attach(width, height):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', height, width, 0, 0))
        process = subprocess.Popen(command + ['attach', '-t', 'fit'], stdin=slave, stdout=slave, stderr=slave,
                                   env={**os.environ, 'TERM': 'xterm-256color'}, start_new_session=True)
        clients.append((process, master, slave))
        return process, slave
    try:
        tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'fit', '-x', '200', '-y', '40')
        tmux('set-option', '-t', 'fit', 'status', 'off')
        tmux('set-option', '-w', '-t', 'fit:', 'window-size', 'manual')
        tmux('new-session', '-d', '-s', 'unrelated', '-x', '180', '-y', '35')
        tmux('set-option', '-w', '-t', 'unrelated:', 'window-size', 'manual')
        untouched = dimensions('unrelated:')
        tmux('set-hook', '-g', 'session-window-changed', 'set-option -g @existing_hook yes')
        # Match the app: preserve inherited callbacks before creating a local array.
        tmux('set-hook', '-t', 'fit', 'session-window-changed[0]', 'set-option -g @existing_hook yes')
        tmux('set-hook', '-a', '-t', 'fit', 'session-window-changed',
             "set-option -w window-size smallest")
        desktop, _ = attach(200, 40)
        ipad, ipad_slave = attach(100, 30)
        tmux('set-option', '-w', '-t', 'fit:', 'window-size', 'smallest')
        expect(100, 30, 'smallest')
        os.write(clients[0][1], b'\x1b[I')
        time.sleep(.05); drain()
        expect(100, 30, 'smallest')
        print('REPRODUCED smallest keeps desktop at mobile size')
        tmux('set-hook', '-t', 'fit', 'session-window-changed[1]', 'set-option -w window-size latest')
        tmux('set-option', '-w', '-t', 'fit:', 'window-size', 'latest')
        os.write(clients[1][1], b'\x1b[I')
        expect(100, 30)
        print('TMUX_FIT_OK desktop + iPad = 100x30')
        phone, phone_slave = attach(70, 24)
        expect(70, 24)
        print('TMUX_FIT_OK iPhone attaches = 70x24')
        os.write(clients[0][1], b'\x1b[I')
        time.sleep(.1); drain()
        expect(200, 40)
        print('TMUX_LATEST_OK desktop focus restores 200x40 while mobile remains attached')
        os.write(clients[0][1], b'\x1b[D')
        expect(200, 40)
        print('DESKTOP_INPUT', dimensions())
        os.write(clients[2][1], b'\x1b[I')
        time.sleep(.1); drain()
        expect(70, 24)
        print('TMUX_LATEST_OK phone focus restores 70x24 without typing')
        os.write(clients[1][1], b'\x1b[D')
        expect(100, 30)

        tmux('detach-client', '-t', os.ttyname(phone_slave))
        expect(100, 30)
        print('TMUX_FIT_OK iPhone detaches = 100x30')
        fcntl.ioctl(ipad_slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 120, 0, 0))
        ipad.send_signal(signal.SIGWINCH)
        expect(120, 32)
        print('TMUX_FIT_OK iPad bounds change = 120x32')
        first = tmux('display-message', '-p', '-t', 'fit:', '#{window_id}')
        tmux('new-window', '-t', 'fit')
        expect(120, 32)
        assert tmux('show-option', '-gv', '@existing_hook') == 'yes'
        tmux('select-window', '-t', first)
        expect(120, 32)
        assert dimensions('unrelated:') == untouched
        print('TMUX_FIT_OK new/switch windows fit; existing hooks and unrelated session preserved')
        tmux('detach-client', '-t', os.ttyname(ipad_slave))
        expect(200, 40)
        print('TMUX_FIT_OK mobile clients leave = desktop 200x40')
    finally:
        subprocess.run(command + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for process, master, slave in clients:
            os.close(master); os.close(slave)
            try: process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.terminate(); process.wait(timeout=5)
