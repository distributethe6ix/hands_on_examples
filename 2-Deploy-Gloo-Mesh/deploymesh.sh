export MGMT=mgmt
export CLUSTER1=cluster-1-us-east-1-prod
export CLUSTER2=dl-cluster-1-us-east-1-prod
export GLOO_MESH_VERSION=v1.2.26
export ISTIO_VERSION=1.12.8

echo "Management cluster = $MGMT"
echo "Workload cluster1 = $CLUSTER1"
echo "Workload cluster2 = $CLUSTER2"

# metrics server
kubectl apply --context ${MGMT} -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl apply --context ${CLUSTER1} -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl apply --context ${CLUSTER2} -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install meshctl
curl -sL https://run.solo.io/meshctl/install | sh -
export PATH=$HOME/.gloo-mesh/bin:$PATH

# Install mgmt server
kubectl --context ${MGMT} create ns gloo-mesh
helm upgrade --install gloo-mesh-enterprise gloo-mesh-enterprise/gloo-mesh-enterprise --namespace gloo-mesh --kube-context ${MGMT} --version=${GLOO_MESH_VERSION} --set licenseKey=${GLOO_MESH_LICENSE_KEY} --wait
kubectl --context ${MGMT} -n gloo-mesh rollout status deploy/enterprise-networking
ENDPOINT_GLOO_MESH=""
while [ -z $ENDPOINT_GLOO_MESH ]; do
  echo "Waiting for Gloo Mesh Management IP..."
  ENDPOINT_GLOO_MESH=$(kubectl --context ${MGMT} -n gloo-mesh get svc enterprise-networking -o jsonpath='{.status.loadBalancer.ingress[0].*}')
  [ -z "$ENDPOINT_GLOO_MESH" ] && sleep 10
done
export ENDPOINT_GLOO_MESH=$(kubectl --context ${MGMT} -n gloo-mesh get svc enterprise-networking -o jsonpath='{.status.loadBalancer.ingress[0].*}'):9900
export HOST_GLOO_MESH=$(echo ${ENDPOINT_GLOO_MESH} | cut -d: -f1)
echo "ENDPOINT_GLOO_MESH = ${ENDPOINT_GLOO_MESH}"
echo "HOST_GLOO_MESH = ${HOST_GLOO_MESH}"

# Register cluster
echo "Registering Workload clusters"
meshctl cluster register --mgmt-context=${MGMT} --remote-context=${CLUSTER1} --relay-server-address=${ENDPOINT_GLOO_MESH} enterprise ${CLUSTER1} --cluster-domain cluster.local
meshctl cluster register --mgmt-context=${MGMT} --remote-context=${CLUSTER2} --relay-server-address=${ENDPOINT_GLOO_MESH} enterprise ${CLUSTER2} --cluster-domain cluster.local


# Install rate-limit and extauth gloo-mesh-addon
kubectl --context ${CLUSTER1} create namespace gloo-mesh-addons
kubectl --context ${CLUSTER1} label namespace gloo-mesh-addons istio-injection=enabled
# kubectl --context ${CLUSTER2} create namespace gloo-mesh-addons
# kubectl --context ${CLUSTER2} label namespace gloo-mesh-addons istio-injection=enabled

helm repo add enterprise-agent https://storage.googleapis.com/gloo-mesh-enterprise/enterprise-agent
helm repo update

helm upgrade --install enterprise-agent-addons enterprise-agent/enterprise-agent \
  --kube-context=${CLUSTER1} \
  --version=${GLOO_MESH_VERSION} \
  --namespace gloo-mesh-addons \
  --set enterpriseAgent.enabled=false \
  --set rate-limiter.enabled=false \
  --set ext-auth-service.enabled=true

# helm upgrade --install enterprise-agent-addons enterprise-agent/enterprise-agent \
#   --kube-context=${CLUSTER2} \
#   --version=${GLOO_MESH_VERSION} \
#   --namespace gloo-mesh-addons \
#   --set enterpriseAgent.enabled=false \
#   --set rate-limiter.enabled=false \
#   --set ext-auth-service.enabled=true

# install istio
curl -L https://istio.io/downloadIstio | sh -

kubectl --context ${CLUSTER1} create ns istio-system
kubectl --context ${CLUSTER1} create ns istio-gateways
kubectl --context ${MGMT} create ns istio-gateways # for gloo-mesh gateway config?

kubectl --context ${CLUSTER2} create ns istio-system
kubectl --context ${CLUSTER2} create ns istio-gateways


openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
   -keyout tls.key -out tls.crt -subj "/CN=*"

kubectl -n istio-gateways create secret generic auth-devportal-secret --context $CLUSTER1 \
--from-file=tls.key=tls.key \
--from-file=tls.crt=tls.crt

kubectl -n istio-gateways create secret generic rni-wf-ui-vg-cert --context $CLUSTER1 \
--from-file=tls.key=tls.key \
--from-file=tls.crt=tls.crt

rm tls.crt tls.key

./istio-${ISTIO_VERSION}/bin/istioctl --context ${CLUSTER1} install -y -f install/istio/operator-${CLUSTER1}.yaml
./istio-${ISTIO_VERSION}/bin/istioctl --context ${CLUSTER2} install -y -f install/istio/operator-${CLUSTER2}.yaml

echo "Deploying Apps"

#creating NS in cluster1
echo "Creating namespaces in ${CLUSTER1}"
kubectl create ns app-gateway --context ${CLUSTER1}
kubectl create ns augment-svc --context ${CLUSTER1}
kubectl create ns core-services --context ${CLUSTER1}
kubectl create ns syndication --context ${CLUSTER1}
kubectl create ns workflow-dev --context ${CLUSTER1}
kubectl create ns thumbnail-svc --context ${CLUSTER1}
kubectl create ns auth-devportal --context ${CLUSTER1}

#creating NS in cluster2
echo "Creating namespaces in ${CLUSTER2}"
kubectl create ns automation --context ${CLUSTER2}
kubectl create ns cdp-common --context ${CLUSTER2}
kubectl create ns condition --context ${CLUSTER2}
kubectl create ns dp-metrics-api --context ${CLUSTER2}
kubectl create ns onboarding --context ${CLUSTER2}
kubectl create ns rmf-wf-rni --context ${CLUSTER2}
kubectl create ns rni-content-optimizer --context ${CLUSTER2}
kubectl create ns segment --context ${CLUSTER2}
kubectl create ns tesla --context ${CLUSTER2}
kubectl create ns virtual-machines --context ${CLUSTER2}

#Label NS in cluster1
echo "Label Namespace in ${CLUSTER1}"
kubectl label ns app-gateway istio-injection=enabled --context ${CLUSTER1}
kubectl label ns augment-svc istio-injection=enabled --context ${CLUSTER1}
kubectl label ns core-services istio-injection=enabled --context ${CLUSTER1}
kubectl label ns syndication istio-injection=enabled --context ${CLUSTER1}
kubectl label ns workflow-dev istio-injection=enabled --context ${CLUSTER1}
kubectl label ns thumbnail-svc istio-injection=enabled --context ${CLUSTER1}

#Label NS in cluster2
echo "Label Namespace in ${CLUSTER1}"
kubectl label ns automation istio-injection=enabled --context ${CLUSTER2}
kubectl label ns cdp-common istio-injection=enabled --context ${CLUSTER2}
kubectl label ns condition istio-injection=enabled --context ${CLUSTER2}
kubectl label ns dp-metrics-api istio-injection=enabled --context ${CLUSTER2}
kubectl label ns onboarding istio-injection=enabled --context ${CLUSTER2}
kubectl label ns rmf-wf-rni istio-injection=enabled --context ${CLUSTER2}
kubectl label ns rni-content-optimizer istio-injection=enabled --context ${CLUSTER2}
kubectl label ns segment istio-injection=enabled --context ${CLUSTER2}
kubectl label ns tesla istio-injection=enabled --context ${CLUSTER2}

# cc apps
kubectl apply --context ${CLUSTER1} -f ./install/cc-apps/${CLUSTER1}
kubectl apply --context ${CLUSTER2} -f ./install/cc-apps/${CLUSTER2}

# monitoring
kubectl apply --context ${CLUSTER1} -f ./istio-${ISTIO_VERSION}/samples/addons
kubectl apply --context ${CLUSTER2} -f ./istio-${ISTIO_VERSION}/samples/addons

# Root cert
cat << EOF | kubectl --context ${MGMT} apply -f -
apiVersion: v1
data:
  ca-cert.pem: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUU5VENDQXQyZ0F3SUJBZ0lSQU1uY3U4QkVoZkV1NkZ6R0JjaEczSVV3RFFZSktvWklodmNOQVFFTEJRQXcKRkRFU01CQUdBMVVFQ2hNSloyeHZieTF0WlhOb01CNFhEVEl5TURjeU5qRXpNVFEwT1ZvWERUSXpNRGN5TmpFegpNVFEwT1Zvd0ZERVNNQkFHQTFVRUNoTUpaMnh2YnkxdFpYTm9NSUlDSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DCkFnOEFNSUlDQ2dLQ0FnRUF4YnNCT1QwUDM4NVlvaUY5REZ0RGdOcTlhMHhtMUd2Z0RMMFloOW0xU1A5SmduOVQKbW1Vc1Znck9QTFI1c1VGRWZmdTNnRDRpUGRLNy8vREpDemF5akRVU0JEUVZTamVuTlVlOHF3N1hDcmp0a2VxOApONS9DaElBTzRjODdycU5zeW5xbENHM1hESzhtYTR2Q1RqcmlGOW13eGgxMzJlMk5Ld2crUFV2cU1scVoxWFJJClIwSWJIRDV2MC8wRFVLV0hyb0d1UTJwWWV1a21mNytLRldlZ3BlL3JFQ1BHRXBLUWxVN2V5QkxYTnQ3Ylp2QUIKQmUxYTZaNjlqWWRySDRYUWJKWjlwZmJEWDl1bGhuME9IYWJiU01CVWE5MWszNk4wSWpUNHhWdmVhcFBoaXJZaQpJQ244MldZVU4xYjA0V1dRcUdxc0VKMzNWVzZBREszcFhrTDU4MTdkeDYyclU1UGljcWM2dUtjVWl1SktHU0xTCmJiWTM5TUpnQlovcmdZemtqTkdBZ0tWekV4UFJwbjhIamR5d2xIVWJ5VFZWZkNna3JzZWd5K1pMNHdqODlhSzkKdXh6d1dBM0YyTU9ERXJpNitXVnY0WXlrb2l6QkpCYjR1d1dHSTFFMDlZd09qUnZMOVk3VW9Ka1NEbGFXakJXRQpKUzFmOHVnZEZWSzVTWXMwS1NKc1BuNzRVbWxnbElKUm9wenRhZE0wWCtqVHlxL0NsY29SaVJ6MmpLeDdHcnAyCjlScm1HaGV1bThERm9NNFZicGlaVUMwckdvYThDb3pXTUJoMzVyc2lqQklhQzA0ZlI0OGVNVk1oS3VsY29GWEEKY1RKck9QQXVaaWJ6MFlyWi9PY29hNHFaTURIWDhNdUdNQWUvUVJNVUVJZTRmTkZlNXlHMTY5MUNFOGtDQXdFQQpBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0lFTUE4R0ExVWRFd0VCL3dRRk1BTUJBZjh3SFFZRFZSME9CQllFCkZFUTZmNVhzaUpYcWNzTUdxbkdpZkxVd2VQcCtNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUNBUUFYVXRNZUUwdHoKaXBSYmZSQW5zZjJ2eWlWOHlXeFZIODJSZ3NiY0luYzlyTWJRN0d2TFRLaXNVWmxNMXFGaUNaOTVqOTNJZ3hMUwpteEhjUExhdWtuRUFEK1QwZGd1Zk04eVo5QTlsVjNicXc3QlYrY2dWdVRPQURCbmE4S2ZqVEh1T2dTWkV4L0xjCm5BSGl5OUJDZEZTblM3ZzllRVl4SU54YTV4S0tHek11eTdQQkM2R2dlOWFPK09FVFNZM091Z2oydGQ5bzZhRTcKKzk5cXFZcjVENUZwbGtRemhSNy9sU2dqV0w0OEdabFJ6dERKOTRZcm92S0lURWVZNFJ2eUNYTnB4QWxnZWVTaworaDhYTzJoSzUxYUF6NTlwUWV2NmpwR2NKdFFNay9rV3RiTW4wQ1NLMzdyS0lvK1dsLzAzbC9pd0NJeXVYZzFrCjFMK1NVWTE2WERhd0svazgwRENNNGRLZGRvZ29ZVjZPOTk1TjZzcnp3UXorRjBhYk5IVlNmaWZzQ1ZEOVZkWkUKdzdYZDFtbjRDQStCbVExc3NpdDhlQzlVeHZDRzNGRjhqTGZ6d2pNMUZWVkNTY1g2QWtkZ0JEQnoxcDlQZE1XbwpJT0RIWUdaeTlhNUlqZmQrYTNjTG0vZjBPUmlOVUhVZXdPa2N2KzNsU3FzcHFFVldONmhZRE9leHBMOHBZaUg5CktaR1gvR0hvZkxXNm1IUmlBbzVFQjF2c21vTlpKMDZ0KzhwV1JtQ2tvbUtyZ0VNRVNLVHdZWm1pRU5udFE4Q20KSEJEd21STGZTMWJnbGR2ZXR6MTZtOXRla1ptSFBuTzFuQXlNeDBKYkdJOHh4Z3NTbkdqMW5CdmI5ZnJZbkNIeAovUjB6MjRJUzR5S3ltbkNUY3dFc2tITG12NUhJUk1xVjd3PT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
  ca-key.pem: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlKS3dJQkFBS0NBZ0VBeGJzQk9UMFAzODVZb2lGOURGdERnTnE5YTB4bTFHdmdETDBZaDltMVNQOUpnbjlUCm1tVXNWZ3JPUExSNXNVRkVmZnUzZ0Q0aVBkSzcvL0RKQ3pheWpEVVNCRFFWU2plbk5VZThxdzdYQ3JqdGtlcTgKTjUvQ2hJQU80Yzg3cnFOc3lucWxDRzNYREs4bWE0dkNUanJpRjltd3hoMTMyZTJOS3dnK1BVdnFNbHFaMVhSSQpSMEliSEQ1djAvMERVS1dIcm9HdVEycFlldWttZjcrS0ZXZWdwZS9yRUNQR0VwS1FsVTdleUJMWE50N2JadkFCCkJlMWE2WjY5allkckg0WFFiSlo5cGZiRFg5dWxobjBPSGFiYlNNQlVhOTFrMzZOMElqVDR4VnZlYXBQaGlyWWkKSUNuODJXWVVOMWIwNFdXUXFHcXNFSjMzVlc2QURLM3BYa0w1ODE3ZHg2MnJVNVBpY3FjNnVLY1VpdUpLR1NMUwpiYlkzOU1KZ0JaL3JnWXprak5HQWdLVnpFeFBScG44SGpkeXdsSFVieVRWVmZDZ2tyc2VneStaTDR3ajg5YUs5CnV4endXQTNGMk1PREVyaTYrV1Z2NFl5a29pekJKQmI0dXdXR0kxRTA5WXdPalJ2TDlZN1VvSmtTRGxhV2pCV0UKSlMxZjh1Z2RGVks1U1lzMEtTSnNQbjc0VW1sZ2xJSlJvcHp0YWRNMFgralR5cS9DbGNvUmlSejJqS3g3R3JwMgo5UnJtR2hldW04REZvTTRWYnBpWlVDMHJHb2E4Q296V01CaDM1cnNpakJJYUMwNGZSNDhlTVZNaEt1bGNvRlhBCmNUSnJPUEF1WmliejBZclovT2NvYTRxWk1ESFg4TXVHTUFlL1FSTVVFSWU0Zk5GZTV5RzE2OTFDRThrQ0F3RUEKQVFLQ0FnRUFqYlFLR1hJb1NUVkJFZGc4SExuZTg1NVBkM0VHbEo5R3J2cHBkUnBSc0NHOEZiaVlPcUxkRmtDaQpNcUVJUVQ3TURobHlGWWJ4MVNxTUxzenAxNDU0Z01DYnk4VmpxSStmMWpBMkJzVVkyWWRVUW1sZVArTFBiVk8wCjFxRkVYVkNqYTZ4ZlQxNGdhdWV1K2czcnoxS2xxNEFJRHNNWm5HV0E4T0QwY2N0UTZJdERpZFRPNDdwOVlVMWgKcVNPKzEzSDVmZGRVQXQ1WTBLVDhRVHNNZzNDRGtjZ1J4cnhNZkF6cmJ3Vlo1VHFUWDdCd3ZpR3NLZ3BEUi8vSwpTbjVOQ0FkSEtqcmppeWdBTmxkY0ZialRmKzZQWW1EclgyNEhsN28xUlRwL09qa3ZlV1BIbERnWTFzSWdnZENGCkZtL01DU2hYZGtzVVNzaGFjN0JBTmxZQVU5eGQ4WVhqcGIrMG1iR1lWYUFBT1VoZVVWS2xFOCtLclllMXdQbVAKOE5oYk0yRWl2R2hJQTJhamZMN2pxc2ZLbjU4MTVXQWo4elJqbFdjdjAvc2p3VmtxL0VVRGk5YlVJV0tDYjBENgo4MnJJTzJ4UnVXMndYV1dYMExsOXNndng4RGFUOWN1Nm5UV3JFS2JJTzNwWXp1WDBUUHRDUGxDRllyaUhTT2xBCitvUkN4UEcyalpXNkFIVWJkR1NXRmZqNjZDNWVhZGZqejRJU2ZJckZpaGxuWUp4NDgvcmFsdTVIRUhUc1VzSkIKR3NhZWE1QjNMR2Mrc0lwSzEwV2RpUmpwblZiYXNzck1IVmhsaThEQ0RNM0dFeEZzVmtnZEhFcEp1dGNveGlQSQp1SW1ITE5FVXlMTm5QV3crYmNnTGJ2cG5LSzhqWTAveUtKcFdDeG5WREp6cUJLdHdkaDBDZ2dFQkFNWURGVVUwCmVSMkhrZnF2ZGtuSGlWTXYreURmN3FFZHI2bmxCR05GUU9iOGhtRkxnYWNxd0ZHbWlvOTBpTDVFWHlpWW9sYVYKMm4vbHNrUGhaUjVadjN1WnBtdVgzZWVGM05yMUk1LytxdUd1NEJrYm05M3NGMTJSN3Vsb0dFR0hyekJ2SWRkMgo0RUJ1ZlRxNlFjV05DVVA4REdZZE1rdGlyVzFEL2NhT3lobUp3cG40WGxSMjlXQXA2VU00K3lBYy9rMnpuYURYCnNaYWR4SmdCUm9sN0ZlVUp6ZURQWmlrSFViOEEzNkE4Nk1MUjlnZ1pzZFlLQWJiTHIyaEpCeVp5SlR1VVA2SzkKMEIzenFQMGF4MmdjOEt1TWdOdVltRXJVcG81R2E0TEV6RkVRcVV6a1VvUWY2UUhqRm5TZDcvUGVwMlRVYkFZMgpQMnFpc3BMT0NEY0ltNXNDZ2dFQkFQK2kwRUpma2srcWpjZG1iQnVPc3VhczJlNW1DMGF2ZlB3V3JaOWUvM0MyCmhQOGNCMGU0TTIvamlINWZrRkZ0U2lpRHVPYlZQL1N3b0RLSTNYOE5mTjh5a0xFZDhBMnY3ejJDSDZQaHI4cDIKQUNieHhKRnRrU2IxaXVLLzZJYUZUNnVnSHF3RVl1dDd1RHFHN2V4TzJndzVuRkFzL0VJaUVQWEczR0VyZWxLLwpOWnl1cExXOG9ZTVpHZ1QxNGo1d2RIaEQ1K1dMMnU2c0NZaWNqekRvOEFINVRqMm9TT1lVNjRoVmxPSk8vQnRSCkxoV3R4L2VLRnVXSHFBV0VYZCs4UXV2QVlOUVlGTUp3YzlKdCt0LytQU1pPeFkreVN2QWdQMjUvZGh6ODJHNVcKazFYN0U1Z0VkYjBXcmUyNFdZSTVuaDJicEJFd2ZvbCtPVVNNM2F4RXZtc0NnZ0VCQUkzbnNidXA4azUyVk9pNgpER1N0aWozQ3VnK0NUQ3JNOHBJb0hXL2pOck1UTUY3VDFQUHZVR3B6bHdOZCtZMlp4RFI4eG9LVTNFVWlZUklDCm13d1lONEVseVQxOFZieFJrOGliTzgreW05WW5GRlVLRXpjRXRtNEpZcFdGVXpUTFA0TFBjZ3BQR0VFMHJheUQKeFJVRmtTbFduYkFrcG1HZU16bUdLMzI3NFJ4U1BOTkpTcGp2czhRWjVTQ1cybW5XUFcyRUZxZ3BUQXpydmZOTgpuclp5TG11NURnRlp3UllRTjhaUm92SGNGTmRoenhkWkNyaWc3VCtLVTRmQ0preW9Ld1M2cHF4RHFiMTlYSk1mCk9ON2xOcGxLbFNKTEJvRkNTcWJWMHNDaHR1YzFzSTc1WmlWb0ZQMlVPQWlWRTF6TEtWMjZXanhOYmo5R29BRlQKaEZHa2FwY0NnZ0VCQVAraDBLQ084Y0M0elE2WlhZSXhNTFY4SkhKQm1RVVdkK1dleUFDVy90bTNxMGR3djliNApYSGVIRVBkT21RTFVSMVE4Wktwd2xZUWJIQmRzeGhKSGFwZkgrT2tsQnVpcEJwUjdpeWhXaDNQdWpEaGxqQ3ZoClpVV1FSVko2bGd2dlE3eGNZaytpRTBsb2J0SVlHOVF6QmRrend4eHAzOWhDT0xPT0tOTUNwMUFYNVlUSkgreWMKdE9aa002RENRWHd1K0VsTG5wbnRRUUZyQ0IyVWNaeDNVNHFsdzVma3NRRmo2aVJyY0hiZWhUekw4VW04ZmpzTAoyOW1yemxtMkJDbTRHVE9uTFN6cTU5ZUluRW5Sc1E1Tkx0a2Y3Ry9GMnlwRkZTbHFUTEt3SmI0dzFTVWw3bklXCkE2Y1RCdHF4ZnRDNnpXTE9RVUx2TzVwQ253SHQyNzVwQUFFQ2dnRUJBSzFndUVFU2lxanFzQ0tWWURSSGI0N0oKN1k4cUN0S3BFbWFUcTErZlBjc2pNS014RGpVTzBrQ0tUMnZVdU9WNHdONzlkS1JBM3hXTTFTeG5lbzAwZDhiZApaUkwxeGdrTGlUVDdGdnp4QnN1QjBieHoyUzQ2T0hrVjdJbm5xUHJIWm94REpnUzVXRzVGY3VLa1ByVExMN2pyClg4TFJxQU1td0ZkYzhYc0o1ZkExRm5Vc0ROcmJ4RmxTVnJkbUhVbkJoSG1SSEg1T1ZwdU5oOTUxNVh6NVhwNGEKRWlrRGJuaFUyME95ZnB6OHhzbjg4R2R1aTgvdVp2bDZvTHU0N3RxYkxldFpJcWZPMlhqc3NWZWtMWmdhV2J6UQp3UlZIZ3g0Mk5yQlo0dldEZWZsZkNGMTVyWXVnbEZwZ3YvRjRNaXNFdHQ0NzBZSVpadk5qbUwvREdOOFFpQ1k9Ci0tLS0tRU5EIFJTQSBQUklWQVRFIEtFWS0tLS0tCg==
  cert-chain.pem: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUU5VENDQXQyZ0F3SUJBZ0lSQU1uY3U4QkVoZkV1NkZ6R0JjaEczSVV3RFFZSktvWklodmNOQVFFTEJRQXcKRkRFU01CQUdBMVVFQ2hNSloyeHZieTF0WlhOb01CNFhEVEl5TURjeU5qRXpNVFEwT1ZvWERUSXpNRGN5TmpFegpNVFEwT1Zvd0ZERVNNQkFHQTFVRUNoTUpaMnh2YnkxdFpYTm9NSUlDSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DCkFnOEFNSUlDQ2dLQ0FnRUF4YnNCT1QwUDM4NVlvaUY5REZ0RGdOcTlhMHhtMUd2Z0RMMFloOW0xU1A5SmduOVQKbW1Vc1Znck9QTFI1c1VGRWZmdTNnRDRpUGRLNy8vREpDemF5akRVU0JEUVZTamVuTlVlOHF3N1hDcmp0a2VxOApONS9DaElBTzRjODdycU5zeW5xbENHM1hESzhtYTR2Q1RqcmlGOW13eGgxMzJlMk5Ld2crUFV2cU1scVoxWFJJClIwSWJIRDV2MC8wRFVLV0hyb0d1UTJwWWV1a21mNytLRldlZ3BlL3JFQ1BHRXBLUWxVN2V5QkxYTnQ3Ylp2QUIKQmUxYTZaNjlqWWRySDRYUWJKWjlwZmJEWDl1bGhuME9IYWJiU01CVWE5MWszNk4wSWpUNHhWdmVhcFBoaXJZaQpJQ244MldZVU4xYjA0V1dRcUdxc0VKMzNWVzZBREszcFhrTDU4MTdkeDYyclU1UGljcWM2dUtjVWl1SktHU0xTCmJiWTM5TUpnQlovcmdZemtqTkdBZ0tWekV4UFJwbjhIamR5d2xIVWJ5VFZWZkNna3JzZWd5K1pMNHdqODlhSzkKdXh6d1dBM0YyTU9ERXJpNitXVnY0WXlrb2l6QkpCYjR1d1dHSTFFMDlZd09qUnZMOVk3VW9Ka1NEbGFXakJXRQpKUzFmOHVnZEZWSzVTWXMwS1NKc1BuNzRVbWxnbElKUm9wenRhZE0wWCtqVHlxL0NsY29SaVJ6MmpLeDdHcnAyCjlScm1HaGV1bThERm9NNFZicGlaVUMwckdvYThDb3pXTUJoMzVyc2lqQklhQzA0ZlI0OGVNVk1oS3VsY29GWEEKY1RKck9QQXVaaWJ6MFlyWi9PY29hNHFaTURIWDhNdUdNQWUvUVJNVUVJZTRmTkZlNXlHMTY5MUNFOGtDQXdFQQpBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0lFTUE4R0ExVWRFd0VCL3dRRk1BTUJBZjh3SFFZRFZSME9CQllFCkZFUTZmNVhzaUpYcWNzTUdxbkdpZkxVd2VQcCtNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUNBUUFYVXRNZUUwdHoKaXBSYmZSQW5zZjJ2eWlWOHlXeFZIODJSZ3NiY0luYzlyTWJRN0d2TFRLaXNVWmxNMXFGaUNaOTVqOTNJZ3hMUwpteEhjUExhdWtuRUFEK1QwZGd1Zk04eVo5QTlsVjNicXc3QlYrY2dWdVRPQURCbmE4S2ZqVEh1T2dTWkV4L0xjCm5BSGl5OUJDZEZTblM3ZzllRVl4SU54YTV4S0tHek11eTdQQkM2R2dlOWFPK09FVFNZM091Z2oydGQ5bzZhRTcKKzk5cXFZcjVENUZwbGtRemhSNy9sU2dqV0w0OEdabFJ6dERKOTRZcm92S0lURWVZNFJ2eUNYTnB4QWxnZWVTaworaDhYTzJoSzUxYUF6NTlwUWV2NmpwR2NKdFFNay9rV3RiTW4wQ1NLMzdyS0lvK1dsLzAzbC9pd0NJeXVYZzFrCjFMK1NVWTE2WERhd0svazgwRENNNGRLZGRvZ29ZVjZPOTk1TjZzcnp3UXorRjBhYk5IVlNmaWZzQ1ZEOVZkWkUKdzdYZDFtbjRDQStCbVExc3NpdDhlQzlVeHZDRzNGRjhqTGZ6d2pNMUZWVkNTY1g2QWtkZ0JEQnoxcDlQZE1XbwpJT0RIWUdaeTlhNUlqZmQrYTNjTG0vZjBPUmlOVUhVZXdPa2N2KzNsU3FzcHFFVldONmhZRE9leHBMOHBZaUg5CktaR1gvR0hvZkxXNm1IUmlBbzVFQjF2c21vTlpKMDZ0KzhwV1JtQ2tvbUtyZ0VNRVNLVHdZWm1pRU5udFE4Q20KSEJEd21STGZTMWJnbGR2ZXR6MTZtOXRla1ptSFBuTzFuQXlNeDBKYkdJOHh4Z3NTbkdqMW5CdmI5ZnJZbkNIeAovUjB6MjRJUzR5S3ltbkNUY3dFc2tITG12NUhJUk1xVjd3PT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
  root-cert.pem: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUU5VENDQXQyZ0F3SUJBZ0lSQU1uY3U4QkVoZkV1NkZ6R0JjaEczSVV3RFFZSktvWklodmNOQVFFTEJRQXcKRkRFU01CQUdBMVVFQ2hNSloyeHZieTF0WlhOb01CNFhEVEl5TURjeU5qRXpNVFEwT1ZvWERUSXpNRGN5TmpFegpNVFEwT1Zvd0ZERVNNQkFHQTFVRUNoTUpaMnh2YnkxdFpYTm9NSUlDSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DCkFnOEFNSUlDQ2dLQ0FnRUF4YnNCT1QwUDM4NVlvaUY5REZ0RGdOcTlhMHhtMUd2Z0RMMFloOW0xU1A5SmduOVQKbW1Vc1Znck9QTFI1c1VGRWZmdTNnRDRpUGRLNy8vREpDemF5akRVU0JEUVZTamVuTlVlOHF3N1hDcmp0a2VxOApONS9DaElBTzRjODdycU5zeW5xbENHM1hESzhtYTR2Q1RqcmlGOW13eGgxMzJlMk5Ld2crUFV2cU1scVoxWFJJClIwSWJIRDV2MC8wRFVLV0hyb0d1UTJwWWV1a21mNytLRldlZ3BlL3JFQ1BHRXBLUWxVN2V5QkxYTnQ3Ylp2QUIKQmUxYTZaNjlqWWRySDRYUWJKWjlwZmJEWDl1bGhuME9IYWJiU01CVWE5MWszNk4wSWpUNHhWdmVhcFBoaXJZaQpJQ244MldZVU4xYjA0V1dRcUdxc0VKMzNWVzZBREszcFhrTDU4MTdkeDYyclU1UGljcWM2dUtjVWl1SktHU0xTCmJiWTM5TUpnQlovcmdZemtqTkdBZ0tWekV4UFJwbjhIamR5d2xIVWJ5VFZWZkNna3JzZWd5K1pMNHdqODlhSzkKdXh6d1dBM0YyTU9ERXJpNitXVnY0WXlrb2l6QkpCYjR1d1dHSTFFMDlZd09qUnZMOVk3VW9Ka1NEbGFXakJXRQpKUzFmOHVnZEZWSzVTWXMwS1NKc1BuNzRVbWxnbElKUm9wenRhZE0wWCtqVHlxL0NsY29SaVJ6MmpLeDdHcnAyCjlScm1HaGV1bThERm9NNFZicGlaVUMwckdvYThDb3pXTUJoMzVyc2lqQklhQzA0ZlI0OGVNVk1oS3VsY29GWEEKY1RKck9QQXVaaWJ6MFlyWi9PY29hNHFaTURIWDhNdUdNQWUvUVJNVUVJZTRmTkZlNXlHMTY5MUNFOGtDQXdFQQpBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0lFTUE4R0ExVWRFd0VCL3dRRk1BTUJBZjh3SFFZRFZSME9CQllFCkZFUTZmNVhzaUpYcWNzTUdxbkdpZkxVd2VQcCtNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUNBUUFYVXRNZUUwdHoKaXBSYmZSQW5zZjJ2eWlWOHlXeFZIODJSZ3NiY0luYzlyTWJRN0d2TFRLaXNVWmxNMXFGaUNaOTVqOTNJZ3hMUwpteEhjUExhdWtuRUFEK1QwZGd1Zk04eVo5QTlsVjNicXc3QlYrY2dWdVRPQURCbmE4S2ZqVEh1T2dTWkV4L0xjCm5BSGl5OUJDZEZTblM3ZzllRVl4SU54YTV4S0tHek11eTdQQkM2R2dlOWFPK09FVFNZM091Z2oydGQ5bzZhRTcKKzk5cXFZcjVENUZwbGtRemhSNy9sU2dqV0w0OEdabFJ6dERKOTRZcm92S0lURWVZNFJ2eUNYTnB4QWxnZWVTaworaDhYTzJoSzUxYUF6NTlwUWV2NmpwR2NKdFFNay9rV3RiTW4wQ1NLMzdyS0lvK1dsLzAzbC9pd0NJeXVYZzFrCjFMK1NVWTE2WERhd0svazgwRENNNGRLZGRvZ29ZVjZPOTk1TjZzcnp3UXorRjBhYk5IVlNmaWZzQ1ZEOVZkWkUKdzdYZDFtbjRDQStCbVExc3NpdDhlQzlVeHZDRzNGRjhqTGZ6d2pNMUZWVkNTY1g2QWtkZ0JEQnoxcDlQZE1XbwpJT0RIWUdaeTlhNUlqZmQrYTNjTG0vZjBPUmlOVUhVZXdPa2N2KzNsU3FzcHFFVldONmhZRE9leHBMOHBZaUg5CktaR1gvR0hvZkxXNm1IUmlBbzVFQjF2c21vTlpKMDZ0KzhwV1JtQ2tvbUtyZ0VNRVNLVHdZWm1pRU5udFE4Q20KSEJEd21STGZTMWJnbGR2ZXR6MTZtOXRla1ptSFBuTzFuQXlNeDBKYkdJOHh4Z3NTbkdqMW5CdmI5ZnJZbkNIeAovUjB6MjRJUzR5S3ltbkNUY3dFc2tITG12NUhJUk1xVjd3PT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
kind: Secret
metadata:
  # these labels or annotations cause it to get deleted
  # annotations:
  #   parents.networking.mesh.gloo.solo.io: '{"networking.mesh.gloo.solo.io/v1, Kind=VirtualMesh":[{"name":"virtual-mesh","namespace":"gloo-mesh"}]}'
  # labels:
  #   cluster.multicluster.solo.io: ""
  #   owner.networking.mesh.gloo.solo.io: gloo-mesh
  name: virtual-mesh.gloo-mesh
  namespace: gloo-mesh
type: certificates.mesh.gloo.solo.io/generated_signing_cert
EOF

## When testing we need to enable virtualmesh restart of pods and remove auth on virtual gateway for rni

helm template ./install/cc-gloo-mesh-config -f ./install/cc-gloo-mesh-config/values-prod.yaml | kubectl apply --context $MGMT -f -

# Allow Load Testers
cat << EOF | kubectl --context ${MGMT} apply -f -
apiVersion: networking.mesh.gloo.solo.io/v1
kind: AccessPolicy
metadata:
  name: load-generators
  namespace: gloo-mesh
spec:
  sourceSelector:
  - kubeServiceAccountRefs:
      serviceAccounts:
      - name: loadgenerator
        namespace:  workflow-dev
        clusterName: cluster-1-us-east-1-prod
      - name: loadgenerator
        namespace:  app-gateway
        clusterName: cluster-1-us-east-1-prod
      - name: loadgenerator
        namespace:  rmf-wf-rni
        clusterName: dl-cluster-1-us-east-1-prod
      - name: loadgenerator
        namespace:  cdp-common
        clusterName: dl-cluster-1-us-east-1-prod
EOF

cat << EOF | kubectl --context ${MGMT} apply -f -
apiVersion: networking.mesh.gloo.solo.io/v1
kind: TrafficPolicy
metadata:
  namespace: gloo-mesh
  name: auth-devportal-tls-disable
spec:
  sourceSelector:
  - kubeWorkloadMatcher:
      namespaces:
      - istio-gateways
  destinationSelector:
  - kubeServiceRefs:
      services:
        - clusterName: cluster-1-us-east-1-prod
          name: auth-devportal
          namespace: auth-devportal
  policy:
    mtls:
      istio:
        tlsMode: DISABLE
EOF

cat << EOF | kubectl --context ${CLUSTER1} apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: custom-external-svc
  namespace: core-services
spec:
  exportTo:
  - .
  host: www.google.com
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: SIMPLE
EOF

cat << EOF | kubectl --context ${CLUSTER1} apply -f -
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: custom-external-svc
  namespace: core-services
spec:
  exportTo:
  - .
  hosts:
  - www.google.com
  location: MESH_EXTERNAL
  ports:
  - name: http-port
    number: 80
    protocol: HTTP
  - name: https-port
    number: 443
    protocol: HTTPS
  resolution: DNS
EOF
Footer
© 2022 GitHub, Inc.
Footer navigation
Terms
Privacy
Security
Status
Docs
