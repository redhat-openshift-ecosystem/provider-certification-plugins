# Base image
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as ubi-base
RUN microdnf install yum \
  && yum -y update-minimal --security --sec-severity=Important --sec-severity=Critical

# Layering Tools image
FROM quay.io/ocp-cert/tools:latest as tools

# Plugin container image
FROM ubi-base
LABEL io.k8s.display-name="OpenShift Tests for Provider Certification Plugin" \
      io.k8s.description="OpenShift is a platform for developing, building, and deploying containerized applications." \
      io.openshift.tags="openshift,tests,e2e,partner,certification,plugin"
COPY --from=tools /tools/sonobuoy /usr/bin/
COPY --from=tools /tools/oc /usr/bin/
COPY --from=tools /tools/jq /usr/bin/

#TODO: embeed the nc on tools layer (build it statically)
RUN yum install -y netcat \
  && yum clean all \
  && microdnf clean all

RUN ln -svf /usr/bin/oc /usr/bin/kubectl

WORKDIR /plugin

COPY ./tests ./tests
COPY ./*.sh ./

CMD ["./runner.sh"]
