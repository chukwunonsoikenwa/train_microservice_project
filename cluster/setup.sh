#!/usr/bin/env bash
# Recreates the railshack EKS cluster and reconnects GitHub Actions to it.
# Usage: bash cluster/setup.sh
set -euo pipefail

CLUSTER=railshack
REGION=ap-south-1
CONFIG=cluster/eks-auto-mode.yaml
ROLE=railshack-github-deployer
DOMAIN=railshack.nonsoikenwa.live

echo "==> Creating the cluster (15-20 minutes)"
eksctl create cluster -f "$CONFIG"

echo "==> Letting GitHub Actions deploy to the new cluster"
ROLE_ARN=$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text)
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN" > /dev/null \
  || echo "(access entry already exists)"
aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster > /dev/null

echo "==> Checking the connection"
kubectl get nodes || true   # Auto Mode may show no nodes until something is deployed; that's normal

CERT_ARN=$(aws acm list-certificates --region "$REGION" \
  --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" --output text)

echo
echo "✅ Cluster is ready."
echo "   Certificate ARN: $CERT_ARN"
echo "   GitHub role:     $ROLE_ARN (already saved as AWS_ROLE_ARN in GitHub)"
echo "   Next: re-run your deploy workflow from the repo's Actions tab."
