# Anycast Network Simulation Lab

A realistic anycast network simulation using Docker containers and BIRD BGP for demonstrating anycast failover and routing behavior.

## Architecture

- **3 Anycast Nodes** (anycast1, anycast2, anycast3)
  - Each advertises the same IP: 172.20.255.1
  - Running BIRD2 for BGP routing
  - Running Nginx for web service
  
- **1 Client Node**
  - Learns routes via BGP
  - Tests connectivity to anycast IP

## Network Details

- Anycast IP: 172.20.255.1
- Node 1: 172.20.0.11 (AS 65000)
- Node 2: 172.20.0.12 (AS 65000)
- Node 3: 172.20.0.13 (AS 65000)
- Client: 172.20.0.100 (AS 65001)
- Network: 172.20.0.0/16 (Docker bridge)

## Prerequisites

- Multipass VM with Ubuntu
- Docker installed
- At least 4GB RAM, 4 CPUs

## Quick Start

1. Start the demo:
```bash
~/demo-anycast.sh
```

2. Manual failover demo:
```bash
~/manual-failover-demo.sh
```

## Manual Commands

### Check Status
```bash
# Check which nodes are running
docker ps

# Check BGP status
docker exec client birdc show protocols

# Check routes
docker exec client birdc show route for 172.20.255.1

# Test current active node
docker exec client curl -s http://172.20.255.1
```

### Simulate Failures
```bash
# Fail a specific node (BGP crash)
docker exec anycast1 pkill -9 bird

# Hard failure (stop container)
docker stop anycast1

# Remove anycast IP (route withdrawal)
docker exec anycast1 ip addr del 172.20.255.1/32 dev lo
```

### Restore Nodes
```bash
# Restore anycast IP
docker exec anycast1 ip addr add 172.20.255.1/32 dev lo

# Restart BIRD
docker exec anycast1 mkdir -p /run/bird
docker exec -d anycast1 bird -c /etc/bird/bird.conf -d

# Restart Nginx
docker exec anycast1 service nginx start
```

## Monitoring
```bash
# Real-time monitoring
docker exec client tail -f /tmp/monitor.log

# Continuous testing
watch -n 1 'docker exec client curl -s http://172.20.255.1 2>/dev/null'
```

## What This Demonstrates

1. **Anycast Routing**: Multiple nodes advertising the same IP
2. **BGP Failover**: Automatic rerouting when nodes fail
3. **Realistic Simulation**: Full BGP mesh with proper routing protocols
4. **Transparent Failover**: Clients automatically use healthy nodes

## Files

- `Dockerfile` - Container image with BIRD and Nginx
- `demo-anycast.sh` - Automated demonstration script
- `manual-failover-demo.sh` - Interactive failover demonstration

## Future Enhancements

- [ ] Integration with CDN performance testing
- [ ] HTTP caching and mitigation strategies
- [ ] Performance metric collection (FCP, latency)
- [ ] Web UI for visualization

## License

MIT

## Author

Built for IETF Hackathon - Anycast Flip Mitigation Project
