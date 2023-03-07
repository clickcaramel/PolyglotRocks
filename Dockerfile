FROM alpine:3.17.2

ENV TOKEN="" PRODUCT_BUNDLE_IDENTIFIER="" API_URL=""

RUN apk update && apk add --no-cache bash curl git

COPY bin /home/polyglot/bin
COPY entrypoint.sh /home/polyglot/entrypoint.sh

RUN chmod +x /home/polyglot/entrypoint.sh
ENTRYPOINT ["/bin/bash", "/home/polyglot/entrypoint.sh"]
