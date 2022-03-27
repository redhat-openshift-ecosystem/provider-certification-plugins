FROM openshift-tests:latest

WORKDIR /ocp-conformance

RUN strip $(which openshift-tests) \
      && strip $(which oc)

#COPY ./parse-tests.py ./parse-tests.py
COPY ./*.sh ./
COPY ./tests ./tests

LABEL io.k8s.display-name="OpenShift Partner Certification Tests" \
      io.k8s.description="OpenShift is a platform for developing, building, and deploying containerized applications." \
      io.openshift.tags="openshift,tests,e2e,partner,certification"

CMD ["./runner.sh"]
