FROM alpine:3.17.2

LABEL org.opencontainers.image.source=https://github.com/clickcaramel/PolyglotRocks
LABEL org.opencontainers.image.description="PolyglotRocks is a tool that simplifies the localization process for your iOS mobile app."
LABEL org.opencontainers.image.licenses=Apache-2.0

ENV TOKEN="" PRODUCT_BUNDLE_IDENTIFIER="" API_URL=""

RUN apk update && apk add --no-cache bash jq curl git

COPY bin /home/polyglot/bin
COPY entrypoint.sh /home/polyglot/entrypoint.sh

WORKDIR /home/polyglot

RUN chmod +x ./entrypoint.sh
ENTRYPOINT ./entrypoint.sh
