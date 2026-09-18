# https://developers.home-assistant.io/docs/apps/configuration#app-dockerfile
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.23
FROM ${BUILD_FROM}

RUN apk add --no-cache nginx

COPY run.sh /
RUN chmod a+x /run.sh

LABEL \
    org.opencontainers.image.title="Home Assistant App: Port Redirect" \
    org.opencontainers.image.description="Answers on Home Assistant's previous HTTP port with permanent redirects to its new one." \
    org.opencontainers.image.source="https://github.com/megakid/ha-app-port-redirect" \
    org.opencontainers.image.licenses="MIT"

CMD [ "/run.sh" ]