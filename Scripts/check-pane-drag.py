#!/usr/bin/env python3
"""Check mouse-drag resizing on an isolated local tmux server and PTY."""
import os, pty, fcntl, termios, struct, subprocess, tempfile, time, select, shutil
socket_dir = tempfile.mkdtemp(prefix='term-pane-drag-')
socket = socket_dir + '/tmux.sock'
cmd = ['tmux', '-S', socket]
def tmux(*args):
    return subprocess.check_output(cmd + list(args), text=True).strip()
def drain():
    deadline = time.monotonic() + .25
    while time.monotonic() < deadline:
        if select.select([master], [], [], .03)[0]:
            try: os.read(master, 65536)
            except OSError: break
def send(text):
    os.write(master, text.encode()); drain()
def drag(x, y, nx, ny, pane, dimension):
    before = int(tmux('display', '-p', '-t', pane, dimension))
    delta = nx - x if nx != x else ny - y
    halfway = int(delta / 2)
    send(f'\x1b[<0;{x};{y}M')
    mx, my = (x + halfway, y) if nx != x else (x, y + halfway)
    send(f'\x1b[<32;{mx};{my}M')
    assert int(tmux('display', '-p', '-t', pane, dimension)) == before + halfway
    send(f'\x1b[<32;{nx};{ny}M')
    assert int(tmux('display', '-p', '-t', pane, dimension)) == before + delta
    print('TMUX_CONTINUOUS_MOVEMENT_BEFORE_RELEASE_OK')
    send(f'\x1b[<0;{nx};{ny}m')
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 0, 0))
process = None
try:
    tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'check', '-x', '100', '-y', '30')
    tmux('set', '-g', 'mouse', 'on')
    process = subprocess.Popen(cmd + ['attach', '-t', 'check'], stdin=slave, stdout=slave, stderr=slave,
                               env={**os.environ, 'TERM': 'xterm-256color'}, start_new_session=True)
    drain()
    first = tmux('display', '-p', '-t', 'check:', '#{pane_id}')
    second = tmux('split-window', '-h', '-d', '-t', first, '-P', '-F', '#{pane_id}')
    drain()
    x = int(tmux('display', '-p', '-t', second, '#{pane_left}'))
    before = int(tmux('display', '-p', '-t', first, '#{pane_width}'))
    drag(x, 5, x + 7, 5, first, '#{pane_width}')
    after = int(tmux('display', '-p', '-t', first, '#{pane_width}'))
    assert after == before + 7, (before, after)
    assert tmux('display', '-p', '-t', first, '#{pane_in_mode}') == '0'
    assert tmux('display', '-p', '-t', second, '#{pane_in_mode}') == '0'
    print('TMUX_HORIZONTAL_BORDER_DRAG_OK', before, after)
    # A released button must not keep resizing on later motion.
    send(f'\x1b[<32;{x + 10};5M')
    assert int(tmux('display', '-p', '-t', first, '#{pane_width}')) == after
    print('TMUX_RELEASE_STOPS_RESIZING_OK')
    tmux('kill-pane', '-t', second)
    second = tmux('split-window', '-v', '-d', '-t', first, '-P', '-F', '#{pane_id}')
    drain()
    y = int(tmux('display', '-p', '-t', second, '#{pane_top}'))
    before = int(tmux('display', '-p', '-t', first, '#{pane_height}'))
    drag(5, y, 5, y + 4, first, '#{pane_height}')
    after = int(tmux('display', '-p', '-t', first, '#{pane_height}'))
    assert after == before + 4, (before, after)
    assert tmux('display', '-p', '-t', first, '#{pane_in_mode}') == '0'
    assert tmux('display', '-p', '-t', second, '#{pane_in_mode}') == '0'
    print('TMUX_VERTICAL_BORDER_DRAG_OK', before, after)
    print('TMUX_BORDER_DRAG_DOES_NOT_SELECT_TEXT_OK')
finally:
    subprocess.run(cmd + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if process: process.wait(timeout=5)
    os.close(master); os.close(slave)
    shutil.rmtree(socket_dir)
