FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git jq procps \
    && rm -rf /var/lib/apt/lists/* \
    && printf 'nightshift compatibility fixture\n' >/etc/nightshift-devcontainer-fixture

USER vscode
