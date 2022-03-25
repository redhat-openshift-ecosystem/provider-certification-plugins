FROM openshift-tests:latest

WORKDIR /ocp-conformance

# remove unused image stuffs
RUN rm -rf /usr/share/doc/git \
    /usr/share/man \
    /usr/share/hwdata

COPY ./parse-tests.py ./parse-tests.py
COPY ./run.sh ./run.sh
COPY ./report-progress.sh ./report-progress.sh
COPY ./tests ./tests

# do we need sonobuoy inside that image?
#ADD https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.56.3/sonobuoy_0.56.3_linux_amd64.tar.gz sonobuoy.tar.gz
#RUN tar -C /usr/bin/ -xzf sonobuoy.tar.gz sonobuoy && rm sonobuoy.tar.gz

#LABEL io.k8s.display-name="OpenShift End-to-End Tests" \
#      io.k8s.description="OpenShift is a platform for developing, building, and deploying containerized applications." \
#      io.openshift.tags="openshift,tests,e2e"

#ENTRYPOINT ["./run.sh"]
