# Deploying BGP on Cilium with FRR
This folder provides configurations required to get FRR up and running with BGP along with Cilium.

## Prerequsites
- kubectl
- helm
- cilium cli
- Docker
- kind
- FRR running in docker

## Instructions

1. First clone the repo to the environment where you'll provision a KinD cluster. You may need to update the `ciliumpeerpolicy-gr.yaml` to ensure it matches your Neighbors.
2. Once all prerequisites are met, you can proceed to install your kind cluster. You can do this from file 
