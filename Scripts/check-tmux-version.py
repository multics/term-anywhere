#!/usr/bin/env python3
"""Reproduce late tmux identity input and verify optional-response omission.

The hosted SwiftTerm test checks that the app emits the corresponding bytes.
This fixture checks their effect in an isolated real tmux client after timeout.
"""
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
from pathlib import Path


def check(omit_version):
    with tempfile.TemporaryDirectory(prefix='term-version-') as folder:
        command = ['tmux', '-S', folder + '/sock']
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 0, 0))
        attached = None
        capture = Path(folder) / 'input'
        try:
            subprocess.check_call(command + [
                '-f', '/dev/null', 'new-session', '-d', '-s', 'probe',
                'stty raw -echo; cat > ' + shlex.quote(str(capture)),
            ])
            attached = subprocess.Popen(
                command + ['attach', '-t', 'probe'], stdin=slave, stdout=slave, stderr=slave,
                env={**os.environ, 'TERM': 'xterm-256color'}, start_new_session=True,
            )
            output = b''
            deadline = time.monotonic() + 9
            while time.monotonic() < deadline:
                if select.select([master], [], [], .05)[0]:
                    output += os.read(master, 65536)
            assert b'\x1b[>q' in output or b'\x1b[>0q' in output, 'tmux did not request identity'
            reply = b'\x1bP>|SwiftTerm 1.20.0:\x1b\\'
            if not omit_version:
                os.write(master, reply)
            os.write(master, b'ordinary-input')
            expected = (b'' if omit_version else reply) + b'ordinary-input'
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                data = capture.read_bytes()
                if data == expected:
                    break
                time.sleep(.03)
            assert data == expected, repr(data)
            print('TMUX_VERSION_OMITTED_OK' if omit_version else 'TMUX_LATE_VERSION_LEAK_REPRODUCED')
        finally:
            subprocess.run(command + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.close(master)
            os.close(slave)
            if attached:
                try:
                    attached.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    attached.terminate()
                    attached.wait(timeout=3)


check(False)
check(True)
