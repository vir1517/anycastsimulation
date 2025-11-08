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
