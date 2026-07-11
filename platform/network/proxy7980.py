#!/usr/bin/env python3
"""
Dynamic forward proxy on port 7980.
Automatically reads macOS system proxy settings for each connection.
"""
import socket
import threading
import subprocess
import re
import select
import sys
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[
        logging.FileHandler('/tmp/proxy7980.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
log = logging.getLogger(__name__)

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 7980
BUFFER = 65536


def get_mac_proxy():
    """Read current macOS proxy settings via scutil --proxy"""
    try:
        out = subprocess.check_output(['scutil', '--proxy'], text=True)

        # SOCKS proxy (preferred, handles all protocols)
        if re.search(r'SOCKSEnable\s*:\s*1', out):
            h = re.search(r'SOCKSProxy\s*:\s*(\S+)', out)
            p = re.search(r'SOCKSPort\s*:\s*(\d+)', out)
            if h and p:
                return ('socks5', h.group(1), int(p.group(1)))

        # HTTP proxy fallback
        if re.search(r'HTTPEnable\s*:\s*1', out):
            h = re.search(r'HTTPProxy\s*:\s*(\S+)', out)
            p = re.search(r'HTTPPort\s*:\s*(\d+)', out)
            if h and p:
                return ('http', h.group(1), int(p.group(1)))

        # HTTPS proxy fallback
        if re.search(r'HTTPSEnable\s*:\s*1', out):
            h = re.search(r'HTTPSProxy\s*:\s*(\S+)', out)
            p = re.search(r'HTTPSPort\s*:\s*(\d+)', out)
            if h and p:
                return ('http', h.group(1), int(p.group(1)))
    except Exception as e:
        log.warning(f'Failed to read proxy settings: {e}')
    return None


def connect_via_socks5(proxy_host, proxy_port, target_host, target_port):
    """Connect to target through SOCKS5 proxy"""
    s = socket.create_connection((proxy_host, proxy_port), timeout=10)
    # SOCKS5 handshake: no auth
    s.sendall(b'\x05\x01\x00')
    resp = s.recv(2)
    if resp != b'\x05\x00':
        raise ConnectionError(f'SOCKS5 auth failed: {resp!r}')

    # SOCKS5 connect request
    host_bytes = target_host.encode()
    req = (b'\x05\x01\x00\x03' +
           bytes([len(host_bytes)]) + host_bytes +
           target_port.to_bytes(2, 'big'))
    s.sendall(req)
    resp = s.recv(10)
    if len(resp) < 2 or resp[1] != 0x00:
        raise ConnectionError(f'SOCKS5 connect failed: {resp!r}')
    return s


def connect_via_http_proxy(proxy_host, proxy_port, target_host, target_port):
    """Connect to target through HTTP CONNECT proxy"""
    s = socket.create_connection((proxy_host, proxy_port), timeout=10)
    req = f'CONNECT {target_host}:{target_port} HTTP/1.1\r\nHost: {target_host}:{target_port}\r\n\r\n'
    s.sendall(req.encode())
    resp = b''
    while b'\r\n\r\n' not in resp:
        chunk = s.recv(4096)
        if not chunk:
            break
        resp += chunk
    if b' 200' not in resp.split(b'\r\n')[0]:
        raise ConnectionError(f'HTTP CONNECT failed: {resp[:100]!r}')
    return s


def connect_direct(target_host, target_port):
    return socket.create_connection((target_host, target_port), timeout=10)


def relay(src, dst):
    """Bidirectional relay between two sockets"""
    try:
        while True:
            r, _, _ = select.select([src, dst], [], [], 60)
            if not r:
                break
            for s in r:
                data = s.recv(BUFFER)
                if not data:
                    return
                other = dst if s is src else src
                other.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.close()
            except Exception:
                pass


def handle_https_connect(client, method, path, version):
    """Handle CONNECT tunneling (HTTPS)"""
    host, _, port = path.rpartition(':')
    port = int(port) if port else 443

    proxy = get_mac_proxy()
    try:
        if proxy:
            ptype, ph, pp = proxy
            log.info(f'CONNECT {host}:{port} via {ptype} {ph}:{pp}')
            if ptype == 'socks5':
                remote = connect_via_socks5(ph, pp, host, port)
            else:
                remote = connect_via_http_proxy(ph, pp, host, port)
        else:
            log.info(f'CONNECT {host}:{port} direct')
            remote = connect_direct(host, port)
    except Exception as e:
        log.warning(f'CONNECT {host}:{port} failed: {e}')
        client.sendall(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
        client.close()
        return

    client.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
    relay(client, remote)


def handle_http_request(client, method, path, version, headers, body):
    """Handle plain HTTP request (forward to upstream proxy or direct)"""
    # Extract host/port from path or Host header
    if path.startswith('http://'):
        url = path[7:]
        slash = url.find('/')
        hostport = url[:slash] if slash != -1 else url
        path_only = url[slash:] if slash != -1 else '/'
    else:
        hostport = headers.get('host', '')
        path_only = path

    if ':' in hostport:
        host, port = hostport.rsplit(':', 1)
        port = int(port)
    else:
        host = hostport
        port = 80

    proxy = get_mac_proxy()
    try:
        if proxy:
            ptype, ph, pp = proxy
            log.info(f'{method} {host}:{port} via {ptype} {ph}:{pp}')
            if ptype == 'socks5':
                remote = connect_via_socks5(ph, pp, host, port)
                # Send original request
                req_line = f'{method} {path_only} {version}\r\n'
                hdr_str = ''.join(f'{k}: {v}\r\n' for k, v in headers.items())
                remote.sendall((req_line + hdr_str + '\r\n').encode() + body)
            else:
                # Send to HTTP proxy as-is (with full URL)
                remote = socket.create_connection((ph, pp), timeout=10)
                req_line = f'{method} http://{hostport}{path_only} {version}\r\n'
                hdr_str = ''.join(f'{k}: {v}\r\n' for k, v in headers.items())
                remote.sendall((req_line + hdr_str + '\r\n').encode() + body)
        else:
            log.info(f'{method} {host}:{port} direct')
            remote = connect_direct(host, port)
            req_line = f'{method} {path_only} {version}\r\n'
            hdr_str = ''.join(f'{k}: {v}\r\n' for k, v in headers.items())
            remote.sendall((req_line + hdr_str + '\r\n').encode() + body)
    except Exception as e:
        log.warning(f'{method} {host}:{port} failed: {e}')
        client.sendall(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
        client.close()
        return

    relay(client, remote)


def handle_client(client, addr):
    try:
        data = b''
        while b'\r\n\r\n' not in data:
            chunk = client.recv(4096)
            if not chunk:
                return
            data += chunk

        header_part, _, body = data.partition(b'\r\n\r\n')
        lines = header_part.decode(errors='replace').split('\r\n')
        request_line = lines[0]
        parts = request_line.split(' ', 2)
        if len(parts) < 3:
            return
        method, path, version = parts

        headers = {}
        for line in lines[1:]:
            if ': ' in line:
                k, _, v = line.partition(': ')
                headers[k.lower()] = v

        if method == 'CONNECT':
            handle_https_connect(client, method, path, version)
        else:
            handle_http_request(client, method, path, version, headers, body)
    except Exception as e:
        log.debug(f'handle_client error from {addr}: {e}')
    finally:
        try:
            client.close()
        except Exception:
            pass


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(128)
    log.info(f'Proxy listening on {LISTEN_HOST}:{LISTEN_PORT}')

    proxy = get_mac_proxy()
    if proxy:
        log.info(f'Current upstream proxy: {proxy[0]} {proxy[1]}:{proxy[2]}')
    else:
        log.info('No upstream proxy detected, will connect directly')

    while True:
        try:
            client, addr = server.accept()
            t = threading.Thread(target=handle_client, args=(client, addr), daemon=True)
            t.start()
        except KeyboardInterrupt:
            log.info('Shutting down')
            break
        except Exception as e:
            log.error(f'Accept error: {e}')


if __name__ == '__main__':
    main()
