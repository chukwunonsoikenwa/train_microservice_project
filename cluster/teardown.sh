#!/usr/bin/env bash
# Tears down the railshack EKS cluster so it stops costing money.
# Keeps: ACM certificate, IAM deploy role, OIDC provider, Route 53 zone (all free or ~$0.50/mo).
# Usage: bash cluster/teardown.sh
set -euo pipefail

CLUSTER=railshack
REGION=ap-south-1
CONFIG=cluster/eks-auto-mode.yaml

echo "==> Connecting kubectl to $CLUSTER"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" > /dev/null

echo "==> Uninstalling Helm releases (frees load balancers)"
helm list -A | tail -n +2 | awk '{print $1, $2}' | while read -r name ns; do
  [ -n "$name" ] && helm uninstall "$name" -n "$ns" || true
done

echo "==> Deleting volumes (PVCs) so no EBS disks are left behind"
kubectl delete pvc --all -A --wait=false || true

echo "==> Waiting for AWS load balancers to be removed"
for i in $(seq 1 30); do
  lbs=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  ings=$(kubectl get ingress -A --no-headers 2>/dev/null || true)
  if [ -z "$lbs" ] && [ -z "$ings" ]; then break; fi
  sleep 10
done
sleep 60   # give AWS time to finish deleting load balancers and volumes

echo "==> Deleting the cluster (10-15 minutes)"
eksctl delete cluster -f "$CONFIG" --wait

echo "==> Checking for leftovers (each should be empty)"
echo "Clusters:";       aws eks list-clusters --region "$REGION" --query clusters --output text
echo "Load balancers:"; aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[].LoadBalancerName" --output text
echo "Loose volumes:";  aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query "Volumes[].VolumeId" --output text
echo "NAT gateways:";   aws ec2 describe-nat-gateways --region "$REGION" --filter Name=state,Values=available --query "NatGateways[].NatGatewayId" --output text
echo "✅ Teardown done. Anything listed above is still billing — remove it in the AWS console."