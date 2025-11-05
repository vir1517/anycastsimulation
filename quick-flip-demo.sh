#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== QUICK ANYCAST FLIP DEMO ==="

test_anycast() {
    echo "Current state:"
    for client in 1 2; do
        echo -n "Client$client: "
        response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
        echo "${response:-NO RESPONSE}"
    done
    echo
}

echo ">>> PHASE 1: Initial state (all servers running)"
test_anycast

echo ">>> PHASE 2: Stopping Server1"
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 2
test_anycast

echo ">>> PHASE 3: Stopping Server3"  
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 2
test_anycast

echo ">>> PHASE 4: Restarting all servers"
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
done
sleep 3
test_anycast

echo "=== DEMO COMPLETE ==="
