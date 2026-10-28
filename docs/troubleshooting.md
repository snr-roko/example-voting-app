# Troubleshooting log

Not a polished guide. This is the order things actually broke and what the fix turned out to be, because the second one took most of a day.

## 1. Node group failed with `NodeCreationFailure`

Terraform applied cleanly. The cluster reported `ACTIVE`. `kubectl get nodes` returned nothing, and the two CoreDNS pods sat in `Pending` because there was nowhere to schedule them.

```
Error: NodeCreationFailure: Instances failed to join the kubernetes cluster
```

### What I ruled out first

I assumed it was networking, so I checked the outside-in path before touching anything inside the node.

| Check | Result |
|---|---|
| Subnet route table | `0.0.0.0/0` to the internet gateway, both subnets associated |
| Public IPs on the instances | yes, both |
| SSM session to the node | worked, so the instance is alive and the agent is running |
| Node user data | valid `nodeadm` `NodeConfig`: correct endpoint, CA present, correct cluster name |
| `systemctl is-active kubelet` | `active` |
| `aws sts get-caller-identity` on the node | `arn:aws:sts::...:assumed-role/example-voting-app-eks-node-role/i-...` |
| Instance profile contents | the expected node role |
| Clock (`date -u`) | correct, so not an expired presigned token |
| `aws eks describe-cluster` from the node | `ACTIVE`, so the node could reach the AWS API |
| `aws-auth` ConfigMap | the node role was mapped to `system:bootstrappers,system:nodes` with `system:node:{{EC2PrivateDNSName}}` |

Everything matched. The role in the token was the role in the ConfigMap.

### The line that actually said something

```
E kubelet_node_status.go:108] "Unable to register node with API server" err="Unauthorized"
E controller.go:208] "Failed to ensure lease exists, will retry" err="Unauthorized"
```

Not a timeout, not a TLS error, not `Forbidden`. The kubelet was reaching the API server and being told it did not know who it was.

That distinction is the useful part. `401` means authentication failed. `403` would have meant the identity was known but not permitted. With the token, the clock, the instance profile and the ConfigMap all verified, the only remaining suspect was the component that does the authenticating: the control plane.

### Root cause

The cluster IAM role had no policies attached at all.

There are two roles in an EKS cluster and I had treated them as one thing:

- `eks_node` — trusted by `ec2.amazonaws.com`. The kubelet uses it. Had four policies.
- `eks_cluster` — trusted by `eks.amazonaws.com`. The control plane uses it to act in my account. Had nothing.

An `aws_eks_cluster` can still reach `ACTIVE` with a permission-less role, because the control plane itself is AWS-managed infrastructure. `ACTIVE` means the API server is up, not that the cluster works. Everything that needs the control plane to act on my behalf fails later and quietly, which is why the symptom appeared 5 minutes into node bootstrap instead of at apply time.

The fix was `AmazonEKSClusterPolicy` on the cluster role, plus `depends_on` so Terraform does not create the cluster in the window before the attachment propagates. IAM is eventually consistent; `AttachRolePolicy` returning success does not mean the policy is readable everywhere yet.

### The second problem hiding behind the first

The node group had no launch template and no explicit security group. That works only because EKS attaches its own cluster security group, which contains a self-referencing allow-all rule, and that rule is the node-to-control-plane path.

The moment you pass your own security groups, EKS stops attaching the cluster one. So the fix had to include the launch template with **both** security groups. Fixing only the IAM policy would have replaced a `401` with a silent timeout, which is harder to read.

### Why the node group had to be replaced

`NodeCreationFailure` is terminal. EKS stops retrying and considers the group dead, so the existing instances would never re-register even with IAM fixed. Node groups also cannot gain a launch template after creation. `terraform apply -replace="aws_eks_node_group.default"` was the only honest option.

Honest caveat: because the policy and the replacement went in the same apply, I cannot prove which single change flipped it. Both were necessary and the group could not be retested without the replacement.

## 2. Trivy failed every build

The scan gate is `CRITICAL,HIGH`, `exit-code 1`, `ignore-unfixed true`. It rejected all three services, each for a different reason. This turned out to be the most useful part of the project.

### vote — findings in packages the app never uses

```
wheel 0.45.1            CVE-2026-24049   HIGH
jaraco.context 5.3.0    CVE-2026-23949   HIGH
```

Both are packaging tools. `gunicorn` does not import either. They were in the image because `python:3.11-slim` ships `pip`, `setuptools` and `wheel` for *building*, and my Dockerfile installed dependencies in the same stage that runs the app.

First attempt was upgrading them (`pip install --upgrade pip setuptools wheel`). That fixed the reported versions but not the class of problem: the count went *up*, because newer pip brings newer vendored libraries, and Trivy reports those too.

The real fix was deleting the package managers from the runtime image:

```dockerfile
RUN python -m pip uninstall -y pip setuptools wheel
```

`urllib3`, `msgpack` and `jaraco` are vendored *inside* pip and setuptools, so removing the parents removes them as well. This is the same lesson as the npm case below: the package manager is a build tool and does not belong in production.

### result and worker — end-of-life base images

The report headers gave it away before reading a single CVE:

```
result  (debian 12.11)   node:18-slim      Node 18 EOL April 2025
worker  (debian 11.9)    dotnet:7.0        .NET 7 EOL May 2024
```

End-of-life base images stop getting security rebuilds. That is why a 2026 build shipped 2024 Debian packages with `+debXuN` patches that existed upstream and had never landed.

Moving to `node:24-slim` and `dotnet:10.0` removed 25 and 53 findings respectively. Not because of a clever fix, but because supported platforms get patched.

### npm's own dependencies

A large part of the Node findings (`tar`, `glob`, `pacote`, `sigstore`, `minimatch`, `ip-address`) were not app dependencies at all. They live in `/usr/local/lib/node_modules/npm`. Same pattern as pip.

Removing npm from the runtime image cleaned all of them. For the dev workflow that used `nodemon`, `node --watch` does the same job with no dependencies.

### `npm ci` failed with `EUSAGE`

```
`npm ci` can only install packages when your package.json and package-lock.json are in sync
```

`npm ci` is strict on purpose: it installs exactly the lockfile and refuses if the manifest disagrees. I had edited `package.json` (express 5, socket.io 4.8) without regenerating the lock, so CI rejected it before installing anything.

Fix is to regenerate the lock, never to hand-edit it:

```shell
docker run --rm -v "$PWD/result:/app" -w /app node:24-slim npm install --package-lock-only
```

### Two findings the lockfile kept

After regenerating, `socket.io-parser 4.2.4` and `ws 8.11.0` were still flagged. Bumping direct dependencies does not move a transitive package while an existing version still satisfies the parent's range.

`overrides` is the right tool:

```json
"overrides": {
  "socket.io-parser": "^4.2.7",
  "ws": "^8.21.0"
}
```

Both are patch-level, and `npm ci` respects overrides, so local and CI resolve identically.

### What I took from it

Trivy reports artifacts, not reachability. A vulnerable `urllib3` inside pip is not a vulnerable application, but it is still a vulnerable artifact, and removing it is cheaper than arguing about it. The scan turned three "working" images into three images I could actually describe.

## 3. Smaller ones, in order

**`Cache export is not supported for the docker driver`.** The GitHub runner's default BuildKit driver cannot export cache to `type=gha`. Adding `docker/setup-buildx-action` switches to the `docker-container` driver, which can. The tempting fix — deleting `cache-to` — makes the error disappear and reinstalls pandas and pip on every run.

**`logging { }` block rejected.** The AWS provider has no `logging` block on `aws_eks_cluster`. It is `enabled_cluster_log_types`.

**`AMI Type AL2_x86_64 is only supported for kubernetes versions 1.32 or earlier`.** Kubernetes 1.37 requires `AL2023_x86_64_STANDARD`.

**`InvalidParameterException: Following required service principals [ec2.amazonaws.com] were not found`.** I had reused the cluster role's trust policy for the node role. Two roles, two principals.

**`kubectl` failing with `no such host` and then `TLS handshake timeout`.** Client-side, both times. A VPN flip breaks DNS for the API endpoint because kubectl resolves it on every call. `no such host` is DNS; `Unauthorized` is the cluster. Different halves of the stack.

**`kubectl get endpointslices db` returning NotFound.** EndpointSlice names are generated (`db-x7k2p`), not inherited from the Service. `kubectl get endpointslices -l kubernetes.io/service-name=db` is the way.

**`helm install` refusing with `invalid ownership metadata`.** Objects from `kubectl apply` have no Helm annotations, and Helm will not silently adopt them. `kubectl delete -f k8s-specifications` first.
