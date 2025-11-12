# Start from the Kali base image
FROM kalilinux/kali-last-release

# Install the SSH client and nothing else
RUN apt update && \
    apt -y install kali-linux-headless && \
    apt -y install wget

# The default command for Alpine is to run a shell, which is perfect.
CMD ["/bin/sh"]