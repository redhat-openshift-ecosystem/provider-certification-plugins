FROM openshift-tests:latest

WORKDIR /ocp-conformance

#COPY ./parse-tests.py ./parse-tests.py
COPY ./run.sh ./run.sh
COPY ./report-progress.sh ./report-progress.sh
COPY ./tests ./tests

LABEL io.k8s.display-name="OpenShift Partner Certification Tests" \
      io.k8s.description="OpenShift is a platform for developing, building, and deploying containerized applications." \
      io.openshift.tags="openshift,tests,e2e,partner,certification"

#ENTRYPOINT ["./run.sh"]
