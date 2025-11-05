#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== WORKING ANYCAST FLIP DEMO ==="

show_status() {
    echo "=== SYSTEM STATUS ==="
    echo "Servers:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
    done
}

test_connectivity() {
    echo -e "\n=== CONNECTIVITY TEST ==="
    for client in 1 2; do
        echo "Client$client:"
        success=0
        servers_reached=()
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
            if [ -n "$response" ]; then
                echo "  ✅ $response"
                ((success++))
                # Extract server number
                server_num=$(echo "$response" | grep -o "Server [0-9]" | cut -d' ' -f2)
                servers_reached["$server_num"]=1
            else
                echo "  ❌ FAILED"
            fi
        done
        server_list=$(echo "${!servers_reached[@]}" | tr ' ' ',')
        echo "  📊 Success: $success/5, Servers: ${server_list:-none}"
    done
}

# PHASE 1: Initial setup
echo ">>> PHASE 1: INITIAL SETUP"
./anycast-route-manager.sh
show_status
test_connectivity

# PHASE 2: Stop Server1 - should failover to Server2
echo -e "\n>>> PHASE 2: STOP SERVER1 (Testing failover to Server2)"
echo "Stopping Server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 2
./anycast-route-manager.sh
show_status
test_connectivity

# PHASE 3: Stop Server3 - should failover to Router1 (Server2)
echo -e "\n>>> PHASE 3: STOP SERVER3 (Testing cross-router failover)"
echo "Stopping Server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 2
./anycast-route-manager.sh
show_status
test_connectivity

# PHASE 4: Restore all servers
echo -e "\n>>> PHASE 4: RESTORE ALL SERVERS"
echo "Starting all servers..."
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
./anycast-route-manager.sh
show_status
test_connectivity

echo -e "\n=== DEMO COMPLETE ==="
