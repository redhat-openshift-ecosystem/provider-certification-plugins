FROM openshift-tests:latest
LABEL io.k8s.display-name="OpenShift Tests for Partner Certification Tool" \
      io.k8s.description="OpenShift is a platform for developing, building, and deploying containerized applications." \
      io.openshift.tags="openshift,tests,e2e,partner,certification"

WORKDIR /ocp-conformance

COPY ./sonobuoy ./
RUN strip $(which openshift-tests) \
      && strip $(which oc) \
      && strip ./sonobuoy \
      && chmod u+x ./sonobuoy

COPY ./tests ./tests
COPY ./*.sh ./

CMD ["./runner.sh"]
