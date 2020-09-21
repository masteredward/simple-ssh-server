FROM alpine:edge
RUN apk add --no-cache openssh-server rsync
RUN ssh-keygen -A && passwd -d root
EXPOSE 22
CMD ["/usr/sbin/sshd", "-De"]