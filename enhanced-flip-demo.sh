#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== ENHANCED ANYCAST FLIP DEMO ==="

test_anycast_detailed() {
    echo "=== CURRENT STATE ==="
    
    # Show server status
    echo "Server Status:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
    done
    
    # Test connectivity
    echo -e "\nConnectivity:"
    for client in 1 2; do
        echo "Client$client:"
        responses=()
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
            if [ -n "$response" ]; then
                responses+=("$response")
                echo "  ✅ Request $i: $response"
            else
                responses+=("FAILED")
                echo "  ❌ Request $i: FAILED"
            fi
        done
        
        # Calculate success and unique servers
        success=0
        servers=()
        for response in "${responses[@]}"; do
            if [ "$response" != "FAILED" ]; then
                ((success++))
                server_num=$(echo "$response" | grep -o "Server [0-9]" | cut -d' ' -f2)
                servers["$server_num"]=1
            fi
        done
        
        server_list=$(echo "${!servers[@]}" | tr ' ' ',')
        echo "  📊 Success: $success/5, Servers: ${server_list:-none}"
    done
    echo
}

echo ">>> PHASE 1: INITIAL STATE (All servers running)"
test_anycast_detailed

echo ">>> PHASE 2: STOP SERVER1 (Client1 should failover to Server2)"
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 3
test_anycast_detailed

echo ">>> PHASE 3: STOP SERVER3 (Client2 should failover to Router1)"
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 3
test_anycast_detailed

echo ">>> PHASE 4: RESTART ALL SERVERS"
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
test_anycast_detailed

echo "=== DEMO COMPLETE ==="
