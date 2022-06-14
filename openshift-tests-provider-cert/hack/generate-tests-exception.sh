#!/usr/bin/env bash

#
# Provider certification tests generator.
#

set -o pipefail
set -o nounset
set -o errexit

echo "> Running Tests Exception Generator..."

cat <<EOF > "$(dirname "$0")/../tests/e2e-level-validated-exception.txt"
"[sig-cli] oc builds complex build start-build [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc builds complex build start-build [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc builds complex build webhooks CRUD [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc builds get buildconfig [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc builds new-build [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc builds patch buildconfig [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc can run inside of a busybox container [Suite:openshift/conformance/parallel]"
"[sig-cli] oc debug deployment configs from a build [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-cli] oc debug ensure it works with image streams [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs  should adhere to Three Laws of Controllers [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs adoption will orphan all RCs and adopt them back when recreated [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs rolled back should rollback to an older deployment [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs should respect image stream tag reference policy resolve the image pull spec [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs when changing image change trigger should successfully trigger from an updated image [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs when tagging images should successfully tag the deployed image [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs with custom deployments should run the custom deployment steps [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs with failing hook should get all logs from retried hooks [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs with minimum ready seconds set should not transition the deployment to Complete before satisfied [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs with test deployments should run a deployment to completion and then scale to zero [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:DeploymentConfig] deploymentconfigs won't deploy RC with unresolved images when patched with empty image [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-apps][Feature:Jobs] Users should be able to create and run a job in a user project [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-devex] check registry.redhat.io is available and samples operator can import sample imagestreams run sample related validations [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-devex][Feature:OpenShiftControllerManager] TestAutomaticCreationOfPullSecrets [Suite:openshift/conformance/parallel]"
"[sig-devex][Feature:OpenShiftControllerManager] TestDockercfgTokenDeletedController [Suite:openshift/conformance/parallel]"
"[sig-devex][Feature:Templates] templateinstance readiness test  should report failed soon after an annotated objects has failed [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-devex][Feature:Templates] templateinstance readiness test  should report ready soon after all annotated objects are ready [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
"[sig-instrumentation][sig-builds][Feature:Builds] Prometheus when installed on the cluster should start and expose a secured proxy and verify build metrics [Skipped:Disconnected] [Suite:openshift/conformance/parallel]"
EOF

echo "> Tests Generator Exception Done."
