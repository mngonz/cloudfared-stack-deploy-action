FROM docker:24-dind

RUN apk add --update --no-cache bash sshpass openssh curl
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/bin/cloudflared
RUN chmod +x /usr/bin/cloudflared

COPY src/main.sh /main.sh

ENTRYPOINT ["bash", "-c", "/main.sh"]