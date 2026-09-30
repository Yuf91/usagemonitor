#!/usr/bin/env python3
"""Read-only protocol diagnostic. Does not print credentials or account identifiers."""
import json, os, select, shutil, subprocess, sys, time
codex = shutil.which('codex') or sys.exit('codex CLI not found on PATH')
p = subprocess.Popen([codex, 'app-server', '--listen', 'stdio://'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
buffer = b''
def send(obj):
    p.stdin.write(json.dumps(obj).encode() + b'\n'); p.stdin.flush()
def receive(expected):
    global buffer
    end = time.monotonic() + 25
    while time.monotonic() < end:
        while b'\n' in buffer:
            line, buffer = buffer.split(b'\n', 1)
            message = json.loads(line)
            if message.get('id') == expected:
                if 'error' in message:
                    raise RuntimeError('RPC error code: ' + str(message['error'].get('code')))
                return message['result']
        if select.select([p.stdout], [], [], 0.5)[0]:
            chunk = os.read(p.stdout.fileno(), 8192)
            if not chunk: raise RuntimeError('Server exited')
            buffer += chunk
    raise TimeoutError('Codex read timed out')
try:
    send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'ai_usage_bar', 'version': '1.0.0'}}})
    receive(1)
    send({'method': 'initialized', 'params': {}})
    send({'id': 2, 'method': 'account/rateLimits/read'})
    result = receive(2)
    buckets = result.get('rateLimitsByLimitId') or {'codex': result.get('rateLimits')}
    for name, bucket in buckets.items():
        if not bucket: continue
        for window in ('primary', 'secondary'):
            value = bucket.get(window)
            if value: print(name, window, {k: value.get(k) for k in ('usedPercent', 'windowDurationMins', 'resetsAt')})
finally:
    p.terminate()
    try: p.wait(timeout=2)
    except subprocess.TimeoutExpired: p.kill(); p.wait()
