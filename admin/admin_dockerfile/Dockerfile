# Start from the same base image
FROM alpine:latest

# Install the SSH client and nothing else
RUN apk update && \
    apk add --no-cache openssh-client

# The default command for Alpine is to run a shell, which is perfect.
CMD ["/bin/sh"]