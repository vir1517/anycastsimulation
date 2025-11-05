#!/bin/bash

ANYCAST_IP="10.0.0.100"

case "$1" in
    "start")
        echo "Starting server $2..."
        sudo docker exec -d clab-anycast-network-anycast-server$2 python3 -c "
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
        sleep 2
        ./anycast-route-manager.sh
        ;;
    "stop")
        echo "Stopping server $2..."
        sudo docker exec clab-anycast-network-anycast-server$2 pkill -f "python3"
        sleep 2
        ./anycast-route-manager.sh
        ;;
    "status")
        echo "=== ANYCAST STATUS ==="
        for server in 1 2 3; do
            status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
            echo "Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
        done
        echo -e "\n=== ROUTES ==="
        echo "Router1:"
        sudo docker exec clab-anycast-network-router1 ip route show | grep $ANYCAST_IP || echo "  No routes"
        echo "Router2:"
        sudo docker exec clab-anycast-network-router2 ip route show | grep $ANYCAST_IP || echo "  No routes"
        ;;
    "test")
        echo "=== ANYCAST TEST ==="
        for client in 1 2; do
            echo "Client$client:"
            for i in {1..3}; do
                response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
                echo "  $([ -n "$response" ] && echo "✅ $response" || echo "❌ FAILED")"
            done
        done
        ;;
    "demo")
        ./working-flip-demo.sh
        ;;
    "monitor")
        echo "Starting anycast monitor (Ctrl+C to stop)..."
        while true; do
            clear
            ./anycast-auto-manager.sh status
            echo -e "\nPress Ctrl+C to stop monitoring"
            sleep 5
        done
        ;;
    *)
        echo "Usage: $0 {start|stop <server_num>|status|test|demo|monitor}"
        echo ""
        echo "Examples:"
        echo "  $0 status          - Show server status and routes"
        echo "  $0 test            - Test anycast connectivity"
        echo "  $0 stop 1          - Stop server 1 and update routes"
        echo "  $0 start 1         - Start server 1 and update routes" 
        echo "  $0 demo            - Run complete flip demo"
        echo "  $0 monitor         - Continuous monitoring"
        ;;
esac
