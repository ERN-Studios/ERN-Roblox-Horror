"""Walk Level 5's rooms in a running Studio play session that is already IN Level 5 (a fresh session per pass: the
server only moves a checkpoint forward, so a room walked again after a later one is judged from the later one).

    python3 tools/level5_void/qa/walk.py <mode> <speed> <alt> <room> [room ...]

mode: manual (jump 0.2 before each edge), early (1 to 2 studs before it), late (a tap 2.5 studs past it: the jump
assist has to save it), auto (never presses: the touch auto-jump has to do it). speed: 16 or 26. alt: 0 = the main
route, 1.. = that room's n-th second route. A call into Studio may not run long, so the walk runs detached and its
result is read back from a player attribute.
"""
import sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import t

mode, speed, alt = sys.argv[1], sys.argv[2], sys.argv[3]
for sec in sys.argv[4:]:
    print(t.run('Client', 'walk2', SECS='"%s"' % sec, MODE=mode, SPEED=speed, ALT=alt), end=' ', flush=True)
    t0 = time.time()
    while time.time() - t0 < 420:
        time.sleep(5)
        r = t.run('Client', 'poll')
        if r != 'running':
            print(r, flush=True)
            break
    else:
        print('TIMEOUT', flush=True)
