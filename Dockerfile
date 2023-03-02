FROM alpine:3.17.2

ENV TOKEN="" PRODUCT_BUNDLE_IDENTIFIER="" API_URL=""

RUN apk update && apk add --no-cache bash jq curl git

COPY bin /home/polyglot/bin
COPY entrypoint.sh /home/polyglot/entrypoint.sh

WORKDIR /home/polyglot

RUN chmod +x ./entrypoint.sh
ENTRYPOINT ./entrypoint.sh
