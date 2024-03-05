#
## Base image
#
FROM quay.io/fedora/fedora-minimal:40 as base

# gcompat: allow to run glibc programs (oc and jq)
# sononbuoy is already built with musl
RUN microdnf update -y \
    && microdnf install -y bash curl grep tar xz gzip git diff util-linux python3-six \
    && git config --system user.name opct \
    && git config --system user.email opct@test.dev \
    && microdnf clean all

#
# Clients image builder
#
FROM base as clientsbuilder
WORKDIR /clients
ARG JQ_URL=TBD
ARG JQ_BIN=TBD
ARG CAMGI_URL=TBD
ARG CAMGI_TAR=TBD
ARG OC_URL=TBD
ARG OC_TAR=TBD
ARG YQ_URL=TBD
ARG YQ_BIN=TBD

ADD ${OC_URL} ./
ADD ${JQ_URL} ./
ADD ${YQ_URL} ./
ADD ${CAMGI_URL} ./
RUN microdnf install -y binutils \
    && microdnf clean all \
    && tar xvfz ${OC_TAR} \
    && rm -f ${OC_TAR} kubectl README.md \
    && tar xvf ${CAMGI_TAR} && rm ${CAMGI_TAR} \
    && strip oc && strip camgi \
    && mv ${JQ_BIN} jq && strip jq \
    && mv ${YQ_BIN} yq && strip yq \
    && chmod +x jq yq oc camgi

# Final image
FROM base
ARG QUAY_EXPIRATION=never
ARG TARGETARCH
ARG TARGETPLATFORM
ARG TARGETOS
LABEL io.k8s.display-name="OPCT Clients" \
        io.k8s.description="OPCT Clients is the base image for most of OPCT plugins." \
        io.openshift.tags="openshift,tests,e2e,partner,conformance,tools" \
        quay.expires-after=${QUAY_EXPIRATION} \
        architecture=$TARGETARCH \
        platform=$TARGETPLATFORM \
        os=$TARGETOS

WORKDIR /clients
COPY --from=clientsbuilder /clients/oc /usr/bin/oc
COPY --from=clientsbuilder /clients/jq /usr/bin/jq
COPY --from=clientsbuilder /clients/yq /usr/bin/yq
COPY --from=clientsbuilder /clients/camgi /usr/bin/camgi
RUN ln -svf /usr/bin/oc /usr/bin/kubectl
