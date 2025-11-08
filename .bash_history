sudo docker exec clab-anycast-network-client1 ping -c 2 -W 1 192.168.1.1
EOF

chmod +x simple-working-setup.sh
clear
# Run the simple setup
./simple-working-setup.sh
clear
# Run the simple setup
./simple-working-setup.sh
clear
# Run the simple setup
./simple-working-setup.sh
clear
echo "=== INSTALLING PACKAGES IN ALL CONTAINERS ==="
for container in router1 router2 client1 client2 anycast-server1 anycast-server2 anycast-server3; do     echo "--- Installing in $container ---";     sudo docker exec clab-anycast-network-$container apt-get update;     sudo docker exec clab-anycast-network-$container apt-get install -y iproute2 net-tools iputils-ping curl python3;     echo "✅ $container ready"; done
clear
# The quick-anycast.sh has package installation - let it run that part
echo "=== Running package installation from quick-anycast.sh ==="
./quick-anycast.sh
clear
# Now run the adaptive setup that detects interfaces
./adaptive-anycast-setup.sh
# Or run the route manager
./anycast-route-manager.sh
clear
# Our working demo script should handle everything
./working-flip-demo.sh
clear
# Run just the package installation part of our quick script
echo "=== Installing packages ==="
for container in router1 router2 client1 client2 anycast-server1 anycast-server2 anycast-server3; do     echo "  - $container";     sudo docker exec clab-anycast-network-$container apt-get update > /dev/null 2>&1;     sudo docker exec clab-anycast-network-$container apt-get install -y iproute2 net-tools iputils-ping curl python3 > /dev/null 2>&1; done
clear
# This script detects actual interface names and configures everything
./adaptive-anycast-setup.sh
# Update routes based on current server status
./anycast-route-manager.sh
clear
echo "=== CURRENT NETWORK STATE ==="
for container in router1 router2 client1 client2 anycast-server1 anycast-server2 anycast-server3; do     echo "--- $container ---";     sudo docker exec clab-anycast-network-$container ip -4 addr show;     echo; done
clear
# This script detects actual interface names and configures IPs
./adaptive-anycast-setup.sh
# Run the fixed setup we created earlier
./fixed-anycast-setup.sh
clear
# Test basic connectivity
./anycast-auto-manager.sh test
# Test basic connectivity
./anycast-auto-manager.sh test
# Destroy and recreate everything
sudo containerlab destroy -t anycast-topology.yaml --cleanup
sleep 5
sudo containerlab deploy -t anycast-topology.yaml
sleep 10
# Then run our complete setup
./quick-anycast.sh
clear
sudo docker ps
sudo containerlab deploy -t anycast-topology.yaml
sudo containerlab deploy -t anycast-topology.yaml --reconfigure
clear
ls
containerlab version
sudo docker ps
clear
# Remove all script files but keep containerlab
ubuntu@anycast-vm:~$ rm adaptive-anycast-setup.sh anycast-topology.yaml fixed-anycast-setup.sh quick-test.sh
ubuntu@anycast-vm:~$ rm anycast-auto-manager.sh enhanced-flip-demo.sh quick-anycast.sh simple-working-setup.sh
ubuntu@anycast-vm:~$ rm anycast-route-manager.sh fix-failover.sh quick-flip-demo.sh working-flip-demo.sh
# Remove the containerlab directory (the extracted one, not the binary)
ubuntu@anycast-vm:~$ rm -rf clab-anycast-network/
# Verify what's left
ubuntu@anycast-vm:~$ ls
containerlab  containerlab-linux-amd64
ls
clear
rm adaptive-anycast-setup.sh anycast-topology.yaml fixed-anycast-setup.sh quick-test.sh
rm anycast-auto-manager.sh enhanced-flip-demo.sh quick-anycast.sh simple-working-setup.sh
rm anycast-route-manager.sh fix-failover.sh quick-flip-demo.sh working-flip-demo.sh
rm -rf clab-anycast-network/
ls
clear
sudo docker ps
sudo containerlab deploy -t anycast-topology.yaml
clear
ls
sudo docker ps
clear
ls
clea
clear
mkdir -p ~/anycast-lab
cd ~/anycast-lab
cat > anycast.clab.yml <<'EOF'
name: anycast-network
topology:
  nodes:
    router1:
      kind: linux
      image: frrouting/frr:8.4.2
    router2:
      kind: linux
      image: frrouting/frr:8.4.2
    anycast-server1:
      kind: linux
      image: frrouting/frr:8.4.2
    anycast-server2:
      kind: linux
      image: frrouting/frr:8.4.2
    anycast-server3:
      kind: linux
      image: frrouting/frr:8.4.2
    client1:
      kind: linux
      image: ubuntu:20.04
    client2:
      kind: linux
      image: ubuntu:20.04

  links:
    - endpoints: ["client1:eth1", "router1:eth1"]
    - endpoints: ["client2:eth1", "router2:eth1"]
    - endpoints: ["router1:eth2", "router2:eth2"]
    - endpoints: ["router1:eth3", "anycast-server1:eth1"]
    - endpoints: ["router1:eth4", "anycast-server2:eth1"]
    - endpoints: ["router2:eth3", "anycast-server3:eth1"]
EOF

# 3. show the file you just created
echo "---- anycast.clab.yml ----"
cat anycast.clab.yml
echo "--------------------------"
clear
cd ~/anycast-lab
clear
mkdir -p configs/{router1,router2,anycast-server1,anycast-server2,anycast-server3}
cat > configs/daemons <<'EOF'
zebra=yes
bgpd=yes
ospfd=no
ospf6d=no
ripd=no
ldpd=no
eigrpd=no
EOF

for n in router1 router2 anycast-server1 anycast-server2 anycast-server3; do   cp configs/daemons configs/$n/; done
tree configs
ls -R configs
clear
ls -R configs
clear
ls -R configs
clear
cd ~/anycast-lab
# 1. Create zebra.conf for router1 (defines IPs on its interfaces)
cat > configs/router1/zebra.conf <<'EOF'
!
hostname router1
!
interface eth1
 ip address 10.10.1.1/24
!
interface eth2
 ip address 10.10.12.2/24
!
interface eth3
 ip address 10.10.3.1/24
!
interface eth4
 ip address 10.10.4.1/24
!
line vty
!
EOF

# 2. Create bgpd.conf for router1 (defines BGP neighbors)
cat > configs/router1/bgpd.conf <<'EOF'
router bgp 65100
 bgp router-id 1.1.1.1

 # Peering with router2 (AS 65200)
 neighbor 10.10.12.1 remote-as 65200

 # Peering with anycast servers (AS 65300)
 neighbor 10.10.3.2 remote-as 65300
 neighbor 10.10.4.2 remote-as 65300

 address-family ipv4 unicast
  neighbor 10.10.12.1 activate
  neighbor 10.10.3.2 activate
  neighbor 10.10.4.2 activate
 exit-address-family
!
line vty
!
EOF

# 3. Verify the files
echo "---- router1 zebra.conf ----"
cat configs/router1/zebra.conf
echo "---- router1 bgpd.conf ----"
cat configs/router1/bgpd.conf
clear
cat > configs/router2/zebra.conf <<'EOF'
!
hostname router2
!
interface eth1
 ip address 10.10.2.1/24
!
interface eth2
 ip address 10.10.12.1/24
!
interface eth3
 ip address 10.10.5.1/24
!
line vty
!
EOF

# 2. Create bgpd.conf for router2
cat > configs/router2/bgpd.conf <<'EOF'
router bgp 65200
 bgp router-id 2.2.2.2

 # Peering with router1 (AS 65100)
 neighbor 10.10.12.2 remote-as 65100

 # Peering with anycast-server3 (AS 65300)
 neighbor 10.10.5.2 remote-as 65300

 address-family ipv4 unicast
  neighbor 10.10.12.2 activate
  neighbor 10.10.5.2 activate
 exit-address-family
!
line vty
!
EOF

clear
echo "---- router2 zebra.conf ----"
cat configs/router2/zebra.conf
echo "---- router2 bgpd.conf ----"
cat configs/router2/bgpd.conf
clear
cat > configs/anycast-server1/zebra.conf <<'EOF'
!
hostname anycast-server1
!
interface eth1
 ip address 10.10.3.2/24
!
ip route 0.0.0.0/0 10.10.3.1
!
line vty
!
EOF

cat > configs/anycast-server1/bgpd.conf <<'EOF'
router bgp 65300
 bgp router-id 3.3.3.3
 neighbor 10.10.3.1 remote-as 65100

 address-family ipv4 unicast
  network 203.0.113.8/32
  neighbor 10.10.3.1 activate
 exit-address-family
!
line vty
!
EOF

cat > configs/anycast-server2/zebra.conf <<'EOF'
!
hostname anycast-server2
!
interface eth1
 ip address 10.10.4.2/24
!
ip route 0.0.0.0/0 10.10.4.1
!
line vty
!
EOF

cat > configs/anycast-server2/bgpd.conf <<'EOF'
router bgp 65300
 bgp router-id 4.4.4.4
 neighbor 10.10.4.1 remote-as 65100

 address-family ipv4 unicast
  network 203.0.113.8/32
  neighbor 10.10.4.1 activate
 exit-address-family
!
line vty
!
EOF

cat > configs/anycast-server3/zebra.conf <<'EOF'
!
hostname anycast-server3
!
interface eth1
 ip address 10.10.5.2/24
!
ip route 0.0.0.0/0 10.10.5.1
!
line vty
!
EOF

cat > configs/anycast-server3/bgpd.conf <<'EOF'
router bgp 65300
 bgp router-id 5.5.5.5
 neighbor 10.10.5.1 remote-as 65200

 address-family ipv4 unicast
  network 203.0.113.8/32
  neighbor 10.10.5.1 activate
 exit-address-family
!
line vty
!
EOF

clear
ls -R configs/anycast-server*
clear
ls -R configs/anycast-server*
clear
cd ~/anycast-lab
# Backup the old topology (just in case)
cp anycast.clab.yml anycast.clab.yml.bak
# Create the updated topology file
cat > anycast.clab.yml <<'EOF'
name: anycast-network
topology:
  nodes:
    router1:
      kind: linux
      image: frrouting/frr:8.4.2
      config: ./configs/router1
    router2:
      kind: linux
      image: frrouting/frr:8.4.2
      config: ./configs/router2
    anycast-server1:
      kind: linux
      image: frrouting/frr:8.4.2
      config: ./configs/anycast-server1
    anycast-server2:
      kind: linux
      image: frrouting/frr:8.4.2
      config: ./configs/anycast-server2
    anycast-server3:
      kind: linux
      image: frrouting/frr:8.4.2
      config: ./configs/anycast-server3
    client1:
      kind: linux
      image: ubuntu:20.04
    client2:
      kind: linux
      image: ubuntu:20.04

  links:
    - endpoints: ["client1:eth1", "router1:eth1"]
    - endpoints: ["client2:eth1", "router2:eth1"]
    - endpoints: ["router1:eth2", "router2:eth2"]
    - endpoints: ["router1:eth3", "anycast-server1:eth1"]
    - endpoints: ["router1:eth4", "anycast-server2:eth1"]
    - endpoints: ["router2:eth3", "anycast-server3:eth1"]
EOF

# Check the file
echo "---- anycast.clab.yml ----"
cat anycast.clab.yml
echo "--------------------------"
clear
cd ~/anycast-lab
# 1. Deploy the topology using your containerlab binary
sudo ~/containerlab-linux-amd64 deploy -t anycast.clab.yml
clear
sudo ~/containerlab-linux-amd64 deploy -t anycast.clab.yml
clear
sudo ~/containerlab-linux-amd64 deploy -t anycast.clab.yml
cd ~
chmod +x containerlab-linux-amd64
./containerlab-linux-amd64 version
clear
rm -f ~/containerlab-linux-amd64
curl -Lo containerlab https://github.com/srl-labs/containerlab/releases/latest/download/containerlab-linux-amd64
chmod +x containerlab
sudo mv containerlab /usr/local/bin/
containerlab version
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo rm -f /usr/local/bin/containerlab
curl -L -o containerlab https://github.com/srl-labs/containerlab/releases/latest/download/containerlab-linux-amd64
ls -lh containerlab
chmod +x containerlab
sudo mv containerlab /usr/local/bin/
containerlab version
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
ping -c 3 google.com
curl -L -o containerlab https://get.containerlab.dev
ls -lh containerlab
chmod +x containerlab
sudo mv containerlab /usr/local/bin/
containerlab version
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo ./containerlab
clear
curl -L -o install.sh https://get.containerlab.dev
chmod +x install.sh
sudo ./install.sh
containerlab version
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo rm -f /usr/local/bin/containerlab
which containerlab
containerlab version
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
cd anycast-lab/
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
mkdir -p ~/anycast-lab/configs/{router1,router2,router3,anycast-server1,anycast-server2,anycast-server3}
cat <<EOF | sudo tee ~/anycast-lab/configs/router1/frr.conf
frr defaults traditional
hostname router1
service integrated-vtysh-config
!
interface eth1
 ip address 10.0.1.1/24
!
interface eth2
 ip address 10.0.2.1/24
!
router bgp 65001
 bgp router-id 1.1.1.1
 neighbor 10.0.2.2 remote-as 65002
 network 10.0.1.0/24
!
line vty
EOF

cat <<EOF | sudo tee ~/anycast-lab/configs/router2/frr.conf
frr defaults traditional
hostname router2
service integrated-vtysh-config
!
interface eth1
 ip address 10.0.3.1/24
!
interface eth2
 ip address 10.0.2.2/24
!
interface eth3
 ip address 10.0.4.2/24
!
router bgp 65002
 bgp router-id 2.2.2.2
 neighbor 10.0.2.1 remote-as 65001
 neighbor 10.0.4.3 remote-as 65003
 network 10.0.3.0/24
EOF

cat <<EOF | sudo tee ~/anycast-lab/configs/router3/frr.conf
frr defaults traditional
hostname router3
service integrated-vtysh-config
!
interface eth1
 ip address 10.0.4.3/24
!
router bgp 65003
 bgp router-id 3.3.3.3
 neighbor 10.0.4.2 remote-as 65002
 network 10.0.4.0/24
EOF

cat <<EOF | sudo tee ~/anycast-lab/configs/anycast-server1/frr.conf
frr defaults traditional
hostname anycast-server1
service integrated-vtysh-config
!
interface eth1
 ip address 192.0.2.1/32
!
router bgp 65010
 bgp router-id 10.10.10.1
 neighbor 10.0.1.1 remote-as 65001
 network 192.0.2.1/32
EOF

cat <<EOF | sudo tee ~/anycast-lab/configs/anycast-server2/frr.conf
frr defaults traditional
hostname anycast-server2
service integrated-vtysh-config
!
interface eth1
 ip address 192.0.2.1/32
!
router bgp 65010
 bgp router-id 10.10.10.2
 neighbor 10.0.3.1 remote-as 65002
 network 192.0.2.1/32
EOF

cat <<EOF | sudo tee ~/anycast-lab/configs/anycast-server3/frr.conf
frr defaults traditional
hostname anycast-server3
service integrated-vtysh-config
!
interface eth1
 ip address 192.0.2.1/32
!
router bgp 65010
 bgp router-id 10.10.10.3
 neighbor 10.0.4.3 remote-as 65003
 network 192.0.2.1/32
EOF

clear
ls -R ~/anycast-lab/configs
clear
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
ls -R ~/anycast-lab/configs
clear
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo systemctl restart docker
sudo systemctl status docker
clear
sudo su
clerar
clear
root@anycast-vm:/home/ubuntu/anycast-lab# ls -ld /proc /proc/0 || echo "No /proc/0"
ls: cannot access '/proc/0': No such file or directory
dr-xr-xr-x 185 root root 0 Nov  7 19:38 /proc
No /proc/0
root@anycast-vm:/home/ubuntu/anycast-lab# 
clear
ls -ld /proc /proc/0 || echo "No /proc/0"
clear
sudo containerlab destroy -t /home/ubuntu/anycast-lab/anycast.clab.yml
sudo systemctl restart docker
sudo containerlab deploy -t /home/ubuntu/anycast-lab/anycast.clab.yml
clear
sudo containerlab destroy -t /home/ubuntu/anycast-lab/anycast.clab.yml
sudo systemctl restart docker
sudo containerlab deploy -t /home/ubuntu/anycast-lab/anycast.clab.yml
clear
sudo containerlab destroy -t /home/ubuntu/anycast-lab/anycast.clab.yml
sudo systemctl restart docker
sudo containerlab deploy -t /home/ubuntu/anycast-lab/anycast.clab.yml
clear
sudo docker ps -a
sudo docker logs clab-anycast-lab-anycast-server1 | head -40
sudo docker logs clab-anycast-lab-router3 | head -40
clear
sudo containerlab destroy -t ~/anycast-lab/anycast.clab.yml
sudo docker pull --platform linux/amd64 frrouting/frr:8.4.2
clear
uname -m
sudo docker pull --platform linux/arm64 frrouting/frr:10.1
clear
sudo docker pull ghcr.io/srl-labs/frr:10.1
sudo docker pull ghcr.io/srl-labs/frr:10.0
clear
sudo docker pull quay.io/frrouting/frr:10.0-arm64
git clone https://github.com/FRRouting/frr.git
cd frr
docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
cd ~/anycast-lab/frr/docker
ls
find ~/anycast-lab/frr/docker -maxdepth 2 -name "Dockerfile"
cd ~/anycast-lab/frr/docker/ubuntu22-ci
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
nano Dockerfile
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
cd ~/anycast-lab/frr
ls bootstrap.sh
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
cd docker/ubuntu22-ci/Dockerfile
clear
cd ~/anycast-lab/frr/docker/ubuntu22-ci
sudo nano Dockerfile
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
cd ~/anycast-lab/frr
ls bootstrap.sh
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
cd ~/anycast-lab/frr/docker/ubuntu22-ci
sudo nano Dockerfile
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
cd ~/anycast-lab/frr/docker/ubuntu22-ci
nano Dockerfile
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
cd ~/anycast-lab/frr/docker/ubuntu22-ci
nano Dockerfile
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
sudo docker images
sudo docker run -it --rm --name frr-test --privileged frr-arm64:local bash
clea
clear
sudo containerlab destroy -t ~/anycast-lab/anycast.clab.yml
sudo systemctl restart docker
nano ~/anycast-lab/anycast.clab.yml
sudo docker system prune -af
clear
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab destroy -t ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
nano ~/anycast-lab/anycast.clab.yml
sudo containerlab destroy -t ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
nano ~/anycast-lab/anycast.clab.yml
cd ~/anycast-lab/frr
sudo containerlab destroy -t ~/anycast-lab/anycast.clab.yml
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
mkdir -p ~/anycast-lab/configs
echo "hostname r1
service integrated-vtysh-config
log file /var/log/frr.log" > ~/anycast-lab/configs/r1.conf
echo "hostname r2
service integrated-vtysh-config
log file /var/log/frr.log" > ~/anycast-lab/configs/r2.conf
echo "hostname r3
service integrated-vtysh-config
log file /var/log/frr.log" > ~/anycast-lab/configs/r3.conf
echo "hostname anycast1
service integrated-vtysh-config
log file /var/log/frr.log" > ~/anycast-lab/configs/anycast1.conf
echo "hostname anycast2
service integrated-vtysh-config
log file /var/log/frr.log" > ~/anycast-lab/configs/anycast2.conf
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
sudo docker images
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
sudo docker images
clear
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo docker run -it frr-arm64:local /bin/bash
clear
sudo docker rmi frr-arm64:local
sudo docker ps -a | grep frr-arm64
sudo docker rm -f $(sudo docker ps -aq --filter ancestor=frr-arm64:local)
sudo docker rmi frr-arm64:local
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
sudo docker run -it frr-arm64:local /bin/bash
ls /usr/lib/frr/
clear
nano ~/anycast-lab/frr/docker/ubuntu22-ci/Dockerfile
sudo docker rm -f $(sudo docker ps -aq --filter ancestor=frr-arm64:local)
sudo docker rmi -f frr-arm64:local
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
sudo docker run -it frr-arm64:local /bin/bash
clear
sudo containerlab deploy -t ~/anycast-lab/anycast.clab.yml
clear
sudo docker run -it frr-arm64:local /bin/bash
cd ~/anycast-lab/frr
clear
nano Dockerfile
ls
nano Dockerfile
clear
cd ~/anycast-lab/frr
nano Dockerfile
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
nano Dockerfile
sudo docker system df
sudo docker container prune -f
sudo docker image prune -f
sudo docker image prune -a -f
sudo docker builder prune -a -f
sudo docker network prune -f
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local .
clear
sudo docker stop $(sudo docker ps -aq) 2>/dev/null
sudo docker rm $(sudo docker ps -aq) 2>/dev/null
sudo docker system prune -a --volumes -f
df -h /
clear
cd ~/anycast-lab/frr/docker/ubuntu22-ci
sudo nano Dockerfile
cd ..
clear
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
sudo docker run -it frr-arm64:local /bin/bash
clear
sudo docker exec -it dc866442da44 /bin/bash
nano docker/
nano dockerfile
clear
ls
nano Dockerfile 
clear
sudo docker ps -aq | xargs -r sudo docker stop
sudo docker ps -aq | xargs -r sudo docker rm
sudo docker images -aq | xargs -r sudo docker rmi -f
sudo docker builder prune -af
sudo docker volume prune -f
clear
sudo docker build -t frr-arm64:local .
clear
cd ~/anycast-lab/frr
sudo rm -f docker/ubuntu22-ci/Dockerfile
sudo nano docker/ubuntu22-ci/Dockerfile
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
clear
cd ~/anycast-lab/frr
sudo rm -f docker/ubuntu22-ci/Dockerfile
sudo nano docker/ubuntu22-ci/Dockerfile
sudo docker system prune -a --volumes -f
sudo docker builder prune -a -f
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
sudo docker run -it frr-arm64:local /bin/bash
cd ~/anycast-lab/frr
sudo docker buildx build --platform linux/arm64 -t frr-arm64:local -f docker/ubuntu22-ci/Dockerfile .
ls
cd ~
ls
sudo rm -rf anycast-lab/
sudo rm -rf install.sh 
clear
ls
sudo apt clean
sudo apt autoremove -y
df -h
clear
df -h
# 1️⃣ Remove apt package cache
sudo apt clean
sudo apt autoclean
# 2️⃣ Remove old dependencies that aren’t needed
sudo apt autoremove -y
# 3️⃣ Clean temporary files
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
# 4️⃣ Remove leftover Docker images, containers, and build caches
sudo docker system prune -a -f --volumes
# 5️⃣ Remove any previous FRR build files if present
sudo rm -rf ~/anycast-lab/frr
sudo rm -rf ~/frr
clear
du -h ~ | sort -hr | head -20
clear
sudo apt update
clear
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER
newgrp docker
docker --version
clear
docker network create --subnet=172.20.0.0/16 anycast-net
docker network ls
docker network inspect anycast-net
clear
mkdir ~/anycast-lab
cd ~/anycast-lab
cat > Dockerfile << 'EOF'
FROM ubuntu:22.04

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install BIRD and useful tools
RUN apt-get update && \
    apt-get install -y bird2 iputils-ping iproute2 tcpdump net-tools curl nginx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create directory for BIRD config
RUN mkdir -p /etc/bird

# Expose BGP port
EXPOSE 179

# Keep container running
CMD ["tail", "-f", "/dev/null"]
EOF

clear
docker build -t anycast-bird .
clear
docker run -d   --name anycast1   --network anycast-net   --ip 172.20.0.11   --cap-add NET_ADMIN   --privileged   anycast-bird
# Create anycast node 2
docker run -d   --name anycast2   --network anycast-net   --ip 172.20.0.12   --cap-add NET_ADMIN   --privileged   anycast-bird
# Create anycast node 3
docker run -d   --name anycast3   --network anycast-net   --ip 172.20.0.13   --cap-add NET_ADMIN   --privileged   anycast-bird
# Create a client for testing
docker run -d   --name client   --network anycast-net   --ip 172.20.0.100   --cap-add NET_ADMIN   anycast-bird
clear
docker ps
docker exec anycast1 ip addr add 172.20.255.1/32 dev lo
# Add anycast IP to anycast2
docker exec anycast2 ip addr add 172.20.255.1/32 dev lo
# Add anycast IP to anycast3
docker exec anycast3 ip addr add 172.20.255.1/32 dev lo
docker exec anycast1 ip addr show lo
clear
docker exec anycast1 bash -c 'cat > /etc/bird/bird.conf << "EOF"
log syslog all;

router id 172.20.0.11;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer2 {
  local as 65000;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}
EOF'
# Start BIRD on anycast1
docker exec anycast1 bird -c /etc/bird/bird.conf
clear
docker exec anycast1 mkdir -p /run/bird
docker exec anycast2 mkdir -p /run/bird
docker exec anycast3 mkdir -p /run/bird
# Now start BIRD on anycast1
docker exec anycast1 bird -c /etc/bird/bird.conf
# Start BIRD on anycast2
docker exec anycast2 bird -c /etc/bird/bird.conf
# Start BIRD on anycast3
docker exec anycast3 bird -c /etc/bird/bird.conf
docker exec anycast1 birdc show protocols
clear
docker exec anycast1 birdc show protocols
# Check BGP details
docker exec anycast1 birdc show protocols all peer2
# Check the routing table on anycast1
docker exec anycast1 birdc show route
clear
docker exec anycast1 birdc show protocols
# Check BGP details
docker exec anycast1 birdc show protocols all peer2
# Check the routing table on anycast1
docker exec anycast1 birdc show route
clear
docker exec anycast2 ps aux | grep bird
docker exec anycast3 ps aux | grep bird
docker exec anycast2 bird -c /etc/bird/bird.conf
docker exec anycast3 bird -c /etc/bird/bird.conf
sleep 5
docker exec anycast1 birdc show protocols
docker exec anycast1 pkill bird
docker exec anycast2 pkill bird
docker exec anycast3 pkill bird
sleep 2
docker exec -d anycast1 bird -c /etc/bird/bird.conf -d
docker exec -d anycast2 bird -c /etc/bird/bird.conf -d
docker exec -d anycast3 bird -c /etc/bird/bird.conf -d
sleep 5
docker exec anycast1 birdc show protocols
docker exec anycast1 netstat -tln | grep 179
clear
docker exec anycast2 netstat -tln | grep 179
docker exec anycast3 netstat -tln | grep 179
docker exec anycast2 netstat -tln | grep 179
clear
docker exec anycast2 netstat -tln | grep 179
docker exec anycast3 netstat -tln | grep 179
docker exec anycast1 ping -c 2 172.20.0.12
docker exec anycast1 ping -c 2 172.20.0.13
docker exec anycast2 birdc show protocols all peer1
clear
docker exec anycast2 ps aux | grep bird
docker exec anycast3 ps aux | grep bird
docker exec anycast2 bird -p -c /etc/bird/bird.conf
docker exec anycast2 cat /etc/bird/bird.conf
clear
# Check if BIRD processes are running
docker exec anycast2 ps aux | grep bird
docker exec anycast3 ps aux | grep bird
# Check BIRD configuration is valid on anycast2
docker exec anycast2 bird -p -c /etc/bird/bird.conf
# If there are errors, let's view the config file
docker exec anycast2 cat /etc/bird/bird.conf
clear
docker exec anycast1 pkill -9 bird
docker exec anycast2 pkill -9 bird
docker exec anycast3 pkill -9 bird
sleep 2
docker exec anycast1 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.11;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer2 {
  local as 65000;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}
EOF'
# Verify it was written correctly
docker exec anycast1 cat /etc/bird/bird.conf
clear
docker exec anycast2 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.12;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer1 {
  local as 65000;
  neighbor 172.20.0.11 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}
EOF'
# Configure anycast3
docker exec anycast3 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.13;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer1 {
  local as 65000;
  neighbor 172.20.0.11 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer2 {
  local as 65000;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export all;
  };
}
EOF'
# Verify anycast2 config
docker exec anycast2 cat /etc/bird/bird.conf
clear
docker exec -d anycast1 bird -c /etc/bird/bird.conf -d
docker exec -d anycast2 bird -c /etc/bird/bird.conf -d
docker exec -d anycast3 bird -c /etc/bird/bird.conf -d
sleep 5
docker exec anycast1 birdc show protocols
docker exec anycast2 netstat -tln | grep 179
docker exec anycast3 netstat -tln | grep 179
clear
docker exec anycast1 birdc show route all
docker exec anycast1 ip route show
docker exec client ping -c 4 172.20.255.1
docker exec client traceroute -n 172.20.255.1
clear
docker exec anycast1 service nginx start
docker exec anycast2 service nginx start
docker exec anycast3 service nginx start
docker exec anycast1 bash -c 'echo "Response from ANYCAST NODE 1 (172.20.0.11)" > /var/www/html/index.html'
docker exec anycast2 bash -c 'echo "Response from ANYCAST NODE 2 (172.20.0.12)" > /var/www/html/index.html'
docker exec anycast3 bash -c 'echo "Response from ANYCAST NODE 3 (172.20.0.13)" > /var/www/html/index.html'
docker exec client curl http://172.20.255.1
clear
docker exec anycast3 birdc configure soft
docker exec anycast3 birdc disable static1
docker exec client curl http://172.20.255.1
docker exec anycast1 birdc show route all for 172.20.255.1
clear
docker exec anycast3 ip addr del 172.20.255.1/32 dev lo
sleep 3
docker exec client curl http://172.20.255.1
docker exec anycast1 birdc show route for 172.20.255.1
docker exec client ip route show
docker exec client bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.100;

protocol device {
  scan time 10;
}

protocol kernel {
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp anycast1 {
  local as 65001;
  neighbor 172.20.0.11 as 65000;
  ipv4 {
    import all;
    export none;
  };
}

protocol bgp anycast2 {
  local as 65001;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export none;
  };
}

protocol bgp anycast3 {
  local as 65001;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export none;
  };
}
EOF'
clear
docker exec client mkdir -p /run/bird
docker exec -d client bird -c /etc/bird/bird.conf -d
sleep 5
docker exec client birdc show protocols
clear
docker exec anycast1 bash -c 'cat >> /etc/bird/bird.conf <<EOF

protocol bgp client {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'
# Update anycast2
docker exec anycast2 bash -c 'cat >> /etc/bird/bird.conf <<EOF

protocol bgp client {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'
# Update anycast3
docker exec anycast3 bash -c 'cat >> /etc/bird/bird.conf <<EOF

protocol bgp client {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'
# Reconfigure BIRD on all nodes
docker exec anycast1 birdc configure
docker exec anycast2 birdc configure
docker exec anycast3 birdc configure
# Wait for BGP to establish
sleep 5
clear
"client" is a reserved keyword in BIRD. Let's use a different name:
bash# Fix anycast1
docker exec anycast1 bash -c 'cat > /etc/bird/bird.conf <<EOFlog syslog all;

router id 172.20.0.11;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer2 {
  local as 65000;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp client_peer {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'

# Fix anycast2
docker exec anycast2 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.12;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer1 {
  local as 65000;
  neighbor 172.20.0.11 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp client_peer {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'


exit
clear

clear
# Fix anycast1
docker exec anycast1 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.11;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer2 {
  local as 65000;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp client_peer {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'
# Fix anycast2
docker exec anycast2 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.12;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer1 {
  local as 65000;
  neighbor 172.20.0.11 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer3 {
  local as 65000;
  neighbor 172.20.0.13 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp client_peer {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'
# Fix anycast3 (remember to add back the loopback IP first!)
docker exec anycast3 ip addr add 172.20.255.1/32 dev lo
docker exec anycast3 bash -c 'cat > /etc/bird/bird.conf <<EOF
log syslog all;

router id 172.20.0.13;

protocol device {
  scan time 10;
}

protocol direct {
  ipv4;
  interface "lo";
}

protocol kernel {
  ipv4 {
    export all;
  };
}

protocol static {
  ipv4;
  route 172.20.255.1/32 via "lo";
}

protocol bgp peer1 {
  local as 65000;
  neighbor 172.20.0.11 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp peer2 {
  local as 65000;
  neighbor 172.20.0.12 as 65000;
  ipv4 {
    import all;
    export all;
  };
}

protocol bgp client_peer {
  local as 65000;
  neighbor 172.20.0.100 as 65001;
  ipv4 {
    import none;
    export all;
  };
}
EOF'
# Reconfigure all nodes
docker exec anycast1 birdc configure
docker exec anycast2 birdc configure
docker exec anycast3 birdc configure
# Wait for BGP
sleep 5
# Check client status
docker exec client birdc show protocols
clear
# Check the client's routing table - it should now have the anycast route
docker exec client ip route show
# Check which routes the client learned
docker exec client birdc show route
# Now test the web service - which node responds?
docker exec client curl http://172.20.255.1
clear
# Check the client's routing table - it should now have the anycast route
docker exec client ip route show
# Check which routes the client learned
docker exec client birdc show route
# Now test the web service - which node responds?
docker exec client curl http://172.20.255.1
clear
docker stop anycast1
sleep 10
docker exec client curl http://172.20.255.1
docker exec client birdc show route for 172.20.255.1
clear
docker start anycast1
sleep 10
docker exec client curl http://172.20.255.1
docker exec client birdc show route for 172.20.255.1
docker exec anycast1 service nginx stop
docker exec client curl http://172.20.255.1
docker exec anycast1 ip addr del 172.20.255.1/32 dev lo
sleep 5
docker exec client curl http://172.20.255.1
clear
# Check if BIRD is running on anycast1
docker exec anycast1 ps aux | grep bird
# Check BGP status on anycast1
docker exec anycast1 birdc show protocols
# Check if the loopback IP exists
docker exec anycast1 ip addr show lo
# Let's manually add it back and reconfigure
docker exec anycast1 ip addr add 172.20.255.1/32 dev lo
# Start nginx again
docker exec anycast1 service nginx start
# Wait for BGP to converge
sleep 5
# Check client's routes
docker exec client birdc show route for 172.20.255.1
# Test which node responds
docker exec client curl http://172.20.255.1
clear
docker exec anycast1 mkdir -p /run/bird
docker exec -d anycast1 bird -c /etc/bird/bird.conf -d
sleep 5
docker exec anycast1 birdc show protocols
docker exec client birdc show route for 172.20.255.1
docker exec client curl http://172.20.255.1
docker exec anycast1 iptables -A INPUT -p tcp --dport 179 -j DROP
docker exec anycast1 iptables -A OUTPUT -p tcp --sport 179 -j DROP
clear
docker exec anycast1 pkill -9 bird
# Wait for BGP hold timer to expire on the client side
sleep 10
docker exec client birdc show protocols
docker exec client birdc show route for 172.20.255.1
docker exec client curl http://172.20.255.1
clear
docker exec client bash -c 'cat > /tmp/monitor.sh <<EOF
#!/bin/bash
while true; do
  echo "\$(date +%T) - \$(curl -s http://172.20.255.1)"
  sleep 1
done
EOF'
docker exec client chmod +x /tmp/monitor.sh
docker exec -d client bash /tmp/monitor.sh > /tmp/monitor.log 2>&1
sleep 5
docker exec client tail -20 /tmp/monitor.log
clear
docker exec -d client bash -c 'while true; do echo "$(date +%T) - $(curl -s http://172.20.255.1)" >> /tmp/monitor.log 2>&1; sleep 1; done'
sleep 5
docker exec client tail -10 /tmp/monitor.log
clear
docker exec anycast2 ip addr del 172.20.255.1/32 dev lo
sleep 10
docker exec client tail -30 /tmp/monitor.log
docker exec client birdc show route for 172.20.255.1
clear
docker exec anycast2 birdc disable static1
sleep 5
docker exec client tail -20 /tmp/monitor.log
docker exec client birdc show route for 172.20.255.1
docker exec client curl http://172.20.255.1
clear
docker exec anycast2 pkill -9 bird
sleep 10
docker exec client tail -20 /tmp/monitor.log
docker exec client birdc show route for 172.20.255.1
docker exec client curl http://172.20.255.1
clear
l
cd anycast-lab/
clear
ls
cat > ~/demo-anycast.sh << 'SCRIPT'
#!/bin/bash

echo "========================================="
echo "ANYCAST NETWORK DEMONSTRATION"
echo "========================================="
echo ""

# Function to wait with progress
wait_with_progress() {
  local duration=$1
  local message=$2
  echo -n "$message"
  for i in $(seq 1 $duration); do
    echo -n "."
    sleep 1
  done
  echo " Done!"
}

echo "Step 1: Starting containers..."
docker start anycast1 anycast2 anycast3 client > /dev/null 2>&1
wait_with_progress 2 "Waiting for containers"

echo ""
echo "Step 2: Starting BIRD (BGP daemon) on all nodes..."
docker exec anycast1 mkdir -p /run/bird 2>/dev/null
docker exec anycast2 mkdir -p /run/bird 2>/dev/null
docker exec anycast3 mkdir -p /run/bird 2>/dev/null
docker exec client mkdir -p /run/bird 2>/dev/null

docker exec -d anycast1 bird -c /etc/bird/bird.conf -d 2>/dev/null
docker exec -d anycast2 bird -c /etc/bird/bird.conf -d 2>/dev/null
docker exec -d anycast3 bird -c /etc/bird/bird.conf -d 2>/dev/null
docker exec -d client bird -c /etc/bird/bird.conf -d 2>/dev/null

wait_with_progress 10 "Waiting for BGP to establish"

echo ""
echo "Step 3: Configuring anycast IPs..."
docker exec anycast1 ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
docker exec anycast2 ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
docker exec anycast3 ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true

echo ""
echo "Step 4: Starting web services..."
docker exec anycast1 service nginx start 2>&1 | grep -v "already"
docker exec anycast2 service nginx start 2>&1 | grep -v "already"
docker exec anycast3 service nginx start 2>&1 | grep -v "already"

echo ""
echo "========================================="
echo "NETWORK ARCHITECTURE"
echo "========================================="
echo "Anycast IP: 172.20.255.1 (advertised by all 3 nodes)"
echo "Node 1: 172.20.0.11"
echo "Node 2: 172.20.0.12"
echo "Node 3: 172.20.0.13"
echo "Client: 172.20.0.100"
echo ""

echo "========================================="
echo "BGP ROUTING STATUS"
echo "========================================="
docker exec client birdc show protocols
echo ""

echo "All routes to anycast IP (showing redundancy):"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "========================================="
echo "CURRENT ACTIVE NODE"
echo "========================================="
echo "Testing which node is currently serving traffic:"
RESPONSE=$(docker exec client curl -s http://172.20.255.1)
echo "$RESPONSE"
echo ""

echo "========================================="
echo "STARTING REAL-TIME MONITORING"
echo "========================================="
docker exec client rm -f /tmp/monitor.log 2>/dev/null
docker exec -d client bash -c 'while true; do echo "$(date +%T) - $(curl -s http://172.20.255.1 2>/dev/null)"; sleep 1; done >> /tmp/monitor.log 2>&1'

wait_with_progress 5 "Collecting baseline traffic"
echo ""
echo "Last 5 requests:"
docker exec client tail -5 /tmp/monitor.log
echo ""

read -p "Press ENTER to simulate node failure and watch anycast flip..."

echo ""
echo "========================================="
echo "SIMULATING NODE FAILURE"
echo "========================================="

# Determine active node and fail it
ACTIVE_NODE=$(echo "$RESPONSE" | grep -oP 'NODE \K[0-9]')
echo "Failing Node $ACTIVE_NODE (killing BGP daemon)..."

if [ "$ACTIVE_NODE" == "1" ]; then
  docker exec anycast1 pkill -9 bird
elif [ "$ACTIVE_NODE" == "2" ]; then
  docker exec anycast2 pkill -9 bird
else
  docker exec anycast3 pkill -9 bird
fi

wait_with_progress 10 "Waiting for BGP reconvergence"

echo ""
echo "========================================="
echo "ANYCAST FLIP DETECTED!"
echo "========================================="
echo "Traffic flow during and after failure:"
docker exec client tail -20 /tmp/monitor.log
echo ""

echo "New routing table (failed node removed):"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "========================================="
echo "DEMONSTRATION COMPLETE"
echo "========================================="
echo ""
echo "To continue monitoring: docker exec client tail -f /tmp/monitor.log"
echo "To check BGP status: docker exec client birdc show protocols"
echo "To restore failed node: See restoration commands in README"
SCRIPT

chmod +x ~/demo-anycast.sh
clear
cd ~/anycast-lab
~/demo-anycast.sh
clear
ls
cd ..
ls
nano demo-anycast.sh 
clear
echo "Testing which node is currently serving traffic:"
RESPONSE=$(docker exec client curl -s http://172.20.255.1)
echo "$RESPONSE"
clear
great the demo script works, now actually comes the main part, i am building this project for a IETF hackathon and my problem statement is anycast flipping and cdn user experiencez
clear
RESPONSE=$(docker exec client curl -s http://172.20.255.1)
echo "$RESPONSE"
docker exec anycast2 pkill -9 bird
docker exec client bash -c 'for i in {1..15}; do echo "$(date +%T) - $(curl -s http://172.20.255.1 2>/dev/null || echo FAILED)"; sleep 1; done'
clear
cat > ~/manual-failover-demo.sh << 'SCRIPT'
#!/bin/bash

echo "=== MANUAL FAILOVER DEMONSTRATION ==="
echo ""

# Show current state
echo "Current active node:"
CURRENT=$(docker exec client curl -s http://172.20.255.1)
echo "$CURRENT"
CURRENT_NODE=$(echo "$CURRENT" | grep -oP 'NODE \K[0-9]')
echo ""

# Show all routes
echo "All available routes:"
docker exec client birdc show route for 172.20.255.1
echo ""

read -p "Press ENTER to fail Node $CURRENT_NODE..."

# Fail current node
echo "Failing Node $CURRENT_NODE..."
docker exec anycast${CURRENT_NODE} pkill -9 bird
echo ""

# Show real-time failover
echo "Watching failover (15 seconds):"
docker exec client bash -c 'for i in {1..15}; do echo "$(date +%T) - $(curl -s http://172.20.255.1 2>/dev/null || echo FAILED)"; sleep 1; done'
echo ""

# Show new state
echo "New active node:"
NEW=$(docker exec client curl -s http://172.20.255.1)
echo "$NEW"
NEW_NODE=$(echo "$NEW" | grep -oP 'NODE \K[0-9]')
echo ""

echo "Updated routing table:"
docker exec client birdc show route for 172.20.255.1
echo ""

read -p "Press ENTER to restore Node $CURRENT_NODE and bring it back online..."

# Restore failed node
echo "Restoring Node $CURRENT_NODE..."
docker exec anycast${CURRENT_NODE} ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
docker exec anycast${CURRENT_NODE} mkdir -p /run/bird
docker exec -d anycast${CURRENT_NODE} bird -c /etc/bird/bird.conf -d
docker exec anycast${CURRENT_NODE} service nginx start 2>&1 | grep -v "already"
echo ""

echo "Waiting for BGP to establish..."
sleep 8
echo ""

echo "BGP Status:"
docker exec client birdc show protocols | grep anycast
echo ""

echo "All routes now available:"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "Testing which node serves traffic now:"
for i in {1..5}; do
  docker exec client curl -s http://172.20.255.1
  sleep 1
done
echo ""

echo "=== DEMONSTRATION COMPLETE ==="
SCRIPT

chmod +x ~/manual-failover-demo.sh
clear
~/manual-failover-demo.sh
clea
clear
cat > ~/manual-failover-demo.sh << 'SCRIPT'
#!/bin/bash

echo "=== MANUAL FAILOVER DEMONSTRATION ==="
echo ""

# Function to check which nodes have BIRD running
check_active_nodes() {
  ACTIVE_NODES=""
  for i in 1 2 3; do
    if docker exec anycast${i} pgrep bird > /dev/null 2>&1; then
      ACTIVE_NODES="$ACTIVE_NODES $i"
    fi
  done
  echo "$ACTIVE_NODES"
}

# Function to restore a node
restore_node() {
  local NODE=$1
  echo "Restoring Node $NODE..."
  docker exec anycast${NODE} ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
  docker exec anycast${NODE} mkdir -p /run/bird 2>/dev/null
  docker exec -d anycast${NODE} bird -c /etc/bird/bird.conf -d 2>/dev/null
  docker exec anycast${NODE} service nginx start 2>&1 | grep -v "already"
}

# Check current state
echo "Checking system state..."
ACTIVE_NODES=$(check_active_nodes)
echo "Active nodes (with BIRD running):$ACTIVE_NODES"
echo ""

# Show current active node
echo "Current active node:"
CURRENT=$(docker exec client curl -s http://172.20.255.1 2>/dev/null)
if [ -z "$CURRENT" ]; then
  echo "ERROR: No node is responding! Need to restore at least one node."
  echo ""
  echo "Available restore commands:"
  echo "  Node 1: restore_node 1"
  echo "  Node 2: restore_node 2"
  echo "  Node 3: restore_node 3"
  echo ""
  read -p "Which node to restore? (1/2/3): " RESTORE_CHOICE
  restore_node $RESTORE_CHOICE
  echo ""
  echo "Waiting for BGP..."
  sleep 8
  CURRENT=$(docker exec client curl -s http://172.20.255.1)
fi

echo "$CURRENT"
CURRENT_NODE=$(echo "$CURRENT" | grep -oP 'NODE \K[0-9]')
echo ""

# Show all routes
echo "All available routes:"
docker exec client birdc show route for 172.20.255.1
echo ""

read -p "Press ENTER to fail Node $CURRENT_NODE..."

# Fail current node
echo ""
echo "Failing Node $CURRENT_NODE..."
docker exec anycast${CURRENT_NODE} pkill -9 bird
echo ""

# Show real-time failover
echo "Watching failover (15 seconds):"
docker exec client bash -c 'for i in {1..15}; do RESP=$(curl -s http://172.20.255.1 2>/dev/null); if [ -z "$RESP" ]; then echo "$(date +%T) - FAILED/SWITCHING..."; else echo "$(date +%T) - $RESP"; fi; sleep 1; done'
echo ""

# Show new state
echo "New active node:"
NEW=$(docker exec client curl -s http://172.20.255.1 2>/dev/null)
if [ -z "$NEW" ]; then
  echo "ERROR: No nodes left! All nodes are down."
  echo "Need to restore at least one node manually."
  exit 1
fi
echo "$NEW"
NEW_NODE=$(echo "$NEW" | grep -oP 'NODE \K[0-9]')
echo ""

echo "Updated routing table:"
docker exec client birdc show route for 172.20.255.1
echo ""

# Check which nodes are down
echo "Checking for failed nodes..."
FAILED_NODES=""
for i in 1 2 3; do
  if ! docker exec anycast${i} pgrep bird > /dev/null 2>&1; then
    FAILED_NODES="$FAILED_NODES $i"
  fi
done

if [ -z "$FAILED_NODES" ]; then
  echo "All nodes are running. Demonstration complete!"
  exit 0
fi

echo "Failed nodes:$FAILED_NODES"
echo ""

read -p "Press ENTER to restore failed node(s) and bring them back online..."

# Restore all failed nodes
for NODE in $FAILED_NODES; do
  echo ""
  restore_node $NODE
done

echo ""
echo "Waiting for BGP to establish..."
sleep 10
echo ""

echo "BGP Status:"
docker exec client birdc show protocols | grep anycast
echo ""

echo "All routes now available:"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "Testing traffic distribution (may stay on current node or switch based on routing):"
for i in {1..8}; do
  docker exec client curl -s http://172.20.255.1
  sleep 1
done
echo ""

echo "Final system state:"
ACTIVE_NODES=$(check_active_nodes)
echo "Active nodes:$ACTIVE_NODES"
echo ""

echo "=== DEMONSTRATION COMPLETE ==="
echo ""
echo "Quick commands for manual testing:"
echo "  - Fail a node: docker exec anycastX pkill -9 bird"
echo "  - Check status: docker exec client curl -s http://172.20.255.1"
echo "  - View routes: docker exec client birdc show route for 172.20.255.1"
SCRIPT

chmod +x ~/manual-failover-demo.sh
clear
~/manual-failover-demo.sh
ls
~/demo-anycast.sh 
~/manual-failover-demo.sh 
docker exec client birdc show route for 172.20.255.1
clear
