# Evidence

Fill this in as you go. Each section should contain the command and its real output, not a description of the output.

Submission date: _fill in_

## 1. Environment rebuilds from code

The cluster was built, torn down to stop the hourly charge, then rebuilt from the same Terraform code with no manual steps.

```shell
cd terraform
terraform apply
```

```
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint = "https://B1FAADB00E52FF0133AABB2A8359C7A1.gr7.us-east-1.eks.amazonaws.com"
cluster_name = "example-voting-app"
connection_info = {
  "cluster_endpoint" = "https://B1FAADB00E52FF0133AABB2A8359C7A1.gr7.us-east-1.eks.amazonaws.com"
  "cluster_name" = "example-voting-app"
  "node_group" = "example-voting-app-node-group"
  "region" = "us-east-1"
  "vpc_id" = "vpc-058a08de831f7b32a"
}
node_group_name = "example-voting-app-node-group"
vpc_id = "vpc-058a08de831f7b32a"
```

The endpoint changed between builds, which is why the kubeconfig has to be regenerated each time:

```shell
aws eks update-kubeconfig --name example-voting-app --region us-east-1
kubectl get nodes -o wide
```

```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-0-0-222.ec2.internal   Ready    <none>   32m   v1.37.1-eks-577a51e
ip-10-0-1-41.ec2.internal    Ready    <none>   32m   v1.37.1-eks-577a51e
```

Both nodes are in different subnets (`10.0.0.0/24` and `10.0.1.0/24`), which is what the node group is supposed to do.

Apply to all-nodes-Ready: roughly 12-15 minutes. The control plane reaches `ACTIVE` well before the node group finishes bootstrapping, and the `AGE` column above includes idle time between the apply and this check.

## 2. One push builds, scans and deploys

Link to a green workflow run: _fill in_

```shell
docker image inspect ghcr.io/snr-roko/example-voting-app-vote:<sha> --format '{{.Id}}'
```

Note the immutable digest of the image that was scanned and deployed: _fill in_

## 3. Deploy

```shell
helm install voting-app helm-charts/voting-app --set imageTag=<sha> --wait --atomic --timeout 5m
```

```
paste helm output, STATUS: deployed
```

```shell
kubectl get pods
```

```
paste five pods Running, all RESTARTS 0
```

Vote cast and visible on the results page: _screenshot or note_

## 4. Rollback drill

### Break it on purpose

```shell
helm upgrade voting-app helm-charts/voting-app --set imageTag=doesnotexist
```

Note what Helm reports (this is the point of the drill):

```
paste STATUS, and kubectl get pods showing ImagePullBackOff
```

### Recover

```shell
helm history voting-app
helm rollback voting-app <previous-revision>
kubectl get pods
```

```
paste helm history with at least two revisions, the rollback message,
and pods returning to Running
```

Confirm the app serves traffic again:

```shell
kubectl port-forward svc/vote 8080:8080
```

_screenshot of http://localhost:8080_

## 5. No secrets in Git

```shell
git ls-files | findstr /i "tfstate tfvars pem key"
```

```
paste output, or state explicitly that it returned nothing
```

## 6. Teardown

```shell
helm uninstall voting-app
cd terraform && terraform destroy
```

```
paste the destroy complete line
```
