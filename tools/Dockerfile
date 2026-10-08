# Test runner image: kcov (coverage) + bats-core with helper libraries + jq, git, make.
FROM bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f AS bats

FROM kcov/kcov:latest@sha256:481289ae32e55e5b733019515acd10948a4f76dfed381765577db909664fc603
RUN apt-get update \
  && apt-get install -y --no-install-recommends jq git make \
  && rm -rf /var/lib/apt/lists/*
COPY --from=bats /opt/bats /opt/bats
COPY --from=bats /usr/lib/bats /usr/lib/bats
RUN ln -s /opt/bats/bin/bats /usr/local/bin/bats \
  && git config --system --add safe.directory '*'
ENV BATS_LIB_PATH=/usr/lib/bats
ENTRYPOINT []
