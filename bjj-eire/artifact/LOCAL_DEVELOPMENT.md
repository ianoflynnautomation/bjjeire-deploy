# Local Kubernetes Development

This guide deploys the BJJ Eire umbrella Helm chart to Minikube using the
local overrides in `values-local.yaml`.

## Prerequisites

- Docker Desktop
- Minikube
- kubectl
- Helm 3
- OpenSSL

The local deployment expects these images:

- `bjj-api:local`
- `bjj-frontend:local`
- `bjj-seeder:local`

Local Kubernetes runs in read-only mode and does not require real Microsoft
Entra ID credentials. `values-local.yaml` supplies non-secret dummy identifiers
because the current API authentication middleware cannot initialize with an
empty client ID. These values cannot authenticate against a real tenant.

The commands below assume the application and deployment repositories are
cloned under the same parent directory:

```text
workspace/
├── BjjEire/
└── bjjeire-deploy/
```

From that parent directory, set reusable repository paths:

```bash
export APP_REPO="$PWD/BjjEire"
export DEPLOY_REPO="$PWD/bjjeire-deploy"
```

## 1. Start Minikube

```bash
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6144 \
  --disk-size=30g

kubectl config use-context minikube
kubectl config current-context
```

Confirm that the current context is `minikube` before continuing. This is
especially important when an AKS context is also configured.

Enable the local ingress controller and metrics API:

```bash
minikube addons enable ingress
minikube addons enable metrics-server
kubectl rollout status deployment/ingress-nginx-controller \
  --namespace ingress-nginx \
  --timeout=5m
```

## 2. Build and Load Local Images

Build each image from its application source repository:

```bash
docker build \
  --file "$APP_REPO/src/BjjEire.Api/Dockerfile" \
  --tag bjj-api:local \
  "$APP_REPO"

docker build \
  --file "$APP_REPO/src/bjjeire-app/Dockerfile" \
  --tag bjj-frontend:local \
  --build-arg VITE_APP_APP_URL=http://localhost:8080 \
  --build-arg VITE_APP_MSAL_CLIENT_ID= \
  --build-arg VITE_APP_MSAL_API_SCOPE= \
  "$APP_REPO"

docker build \
  --file "$APP_REPO/src/BjjEire.Seeder/Dockerfile" \
  --tag bjj-seeder:local \
  "$APP_REPO"
```

The frontend currently continues in anonymous mode when MSAL initialization
fails. For local `npm` development, use blank `VITE_APP_MSAL_CLIENT_ID`,
`VITE_APP_MSAL_TENANT_ID`, and `VITE_APP_MSAL_API_SCOPE` values. The supported
tenant variable is `VITE_APP_MSAL_TENANT_ID`; `VITE_APP_MSAL_AUTHORITY` is
obsolete in the current frontend source.

`VITE_APP_APP_URL` must contain a valid URL at image build time. An empty value
prevents the React application from mounting and leaves only the page
background visible.

Load the images into Minikube:

```bash
minikube image load bjj-api:local
minikube image load bjj-frontend:local
minikube image load bjj-seeder:local
minikube image ls | grep 'bjj-'
```

`values-local.yaml` uses `imagePullPolicy: Never`, so all three images must exist
inside Minikube before the workloads start.

## 3. Create Local Secrets

Create the application namespace and MongoDB password:

```bash
kubectl create namespace bjjeire-app --dry-run=client -o yaml \
  | kubectl apply -f -

kubectl create secret generic bjj-mongodb-root-password \
  --namespace bjjeire-app \
  --from-literal=mongodb-password='local-dev-password' \
  --dry-run=client -o yaml \
  | kubectl apply -f -
```

Create a self-signed certificate for the local ingress hosts:

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /tmp/bjj-local.key \
  -out /tmp/bjj-local.crt \
  -days 365 \
  -subj '/CN=app.bjj.local' \
  -addext 'subjectAltName=DNS:app.bjj.local,DNS:api.bjj.local'

kubectl create secret tls bjj-tls-secret \
  --namespace bjjeire-app \
  --cert=/tmp/bjj-local.crt \
  --key=/tmp/bjj-local.key \
  --dry-run=client -o yaml \
  | kubectl apply -f -
```

The browser will warn about this self-signed certificate. Use `mkcert` instead
when a locally trusted certificate is required.

## 4. Validate the Chart

Run these commands from this directory:

```bash
cd "$DEPLOY_REPO/bjj-eire/artifact"

helm dependency build .
helm lint . -f values.yaml -f values-local.yaml

helm template bjj-eire . \
  --namespace bjjeire-app \
  -f values.yaml \
  -f values-local.yaml \
  --set-string bjj-api.secrets.mongodbRootPassword.value=bG9jYWwtZGV2LXBhc3N3b3Jk \
  --set-string bjj-mongodb.secrets.mongodbRootPassword.value=bG9jYWwtZGV2LXBhc3N3b3Jk \
  > /tmp/bjj-eire-rendered.yaml
```

The validation overrides contain the base64 representation of
`local-dev-password`. They are required because client-only `helm template`
does not reliably resolve existing cluster secrets.

## 5. Deploy

```bash
helm upgrade --install bjj-eire . \
  --namespace bjjeire-app \
  --create-namespace \
  -f values.yaml \
  -f values-local.yaml \
  --wait \
  --timeout 10m
```

Verify the release:

```bash
helm status bjj-eire --namespace bjjeire-app
kubectl get pods,services,ingresses,pvc --namespace bjjeire-app
kubectl get events --namespace bjjeire-app --sort-by=.lastTimestamp
```

## 6. Access the Application

### macOS with the Docker driver

The Minikube IP shown by ingress is normally inside Docker's private network
and may not be reachable directly from macOS. Use port forwarding:

```bash
kubectl port-forward --namespace bjjeire-app service/bjj-frontend 8080:80
```

Keep that terminal running and open:

- Frontend: `http://localhost:8080`
- Frontend health: `http://localhost:8080/health`
- API through the frontend proxy: `http://localhost:8080/api`

This is the recommended access method for this chart on macOS with the Docker
driver.

### Direct ingress access

On Linux, or with a Minikube driver that exposes its network to the host, get
the Minikube IP:

```bash
minikube ip
```

Add the returned IP to `/etc/hosts`:

```text
<minikube-ip> app.bjj.local api.bjj.local
```

Then open:

- Frontend: `https://app.bjj.local`
- API health: `https://api.bjj.local/health`

`minikube tunnel` is mainly required for `LoadBalancer` services. It does not
always make an ingress address on the Docker network reachable from macOS.

```bash
minikube tunnel
```

## 7. Redeploy Local Changes

Rebuild and reload a changed image:

```bash
docker build \
  --file "$APP_REPO/src/BjjEire.Api/Dockerfile" \
  --tag bjj-api:local \
  "$APP_REPO"
minikube image load bjj-api:local --overwrite
kubectl rollout restart deployment/bjj-api --namespace bjjeire-app
kubectl rollout status deployment/bjj-api --namespace bjjeire-app
```

Use the same process with `bjj-frontend:local` and
`deployment/bjj-frontend` for frontend changes.

After changing chart templates or values, rerun:

```bash
helm upgrade --install bjj-eire . \
  --namespace bjjeire-app \
  -f values.yaml \
  -f values-local.yaml \
  --wait \
  --timeout 10m
```

## 8. Seed Local Data

Local values enable the `bjj-seeder:local` Helm hook. It runs after each
install or upgrade and upserts the JSON data bundled with the seeder image.

After changing seed data, rebuild and reload the image:

```bash
docker build \
  --file "$APP_REPO/src/BjjEire.Seeder/Dockerfile" \
  --tag bjj-seeder:local \
  "$APP_REPO"

minikube image rm bjj-seeder:local 2>/dev/null || true
minikube image load bjj-seeder:local
```

Run the seeder again:

```bash
helm upgrade bjj-eire . \
  --namespace bjjeire-app \
  -f values.yaml \
  -f values-local.yaml \
  --wait \
  --timeout 10m
```

Monitor the hook while it runs:

```bash
kubectl get jobs,pods --namespace bjjeire-app \
  --selector app.kubernetes.io/component=seeder

kubectl logs --namespace bjjeire-app \
  --selector app.kubernetes.io/component=seeder \
  --all-containers
```

Successful jobs are deleted automatically by the Helm hook policy. The seeder
uses upserts, so rerunning it updates matching records instead of duplicating
them.

## 9. Troubleshooting

```bash
kubectl get pods --namespace bjjeire-app
kubectl describe pod --namespace bjjeire-app <pod-name>
kubectl logs --namespace bjjeire-app deployment/bjj-api --tail=200
kubectl logs --namespace bjjeire-app deployment/bjj-frontend --tail=200
kubectl logs --namespace ingress-nginx deployment/ingress-nginx-controller
kubectl get endpoints --namespace bjjeire-app
kubectl top pods --namespace bjjeire-app
helm status bjj-eire --namespace bjjeire-app
helm history bjj-eire --namespace bjjeire-app
helm get values bjj-eire --namespace bjjeire-app
helm get manifest bjj-eire --namespace bjjeire-app
```

Common failures:

- `ErrImageNeverPull`: build and load the missing `:local` image.
- `ImagePullBackOff` for MongoDB: confirm Docker and internet access.
- API template failure: confirm `bjj-mongodb-root-password` exists.
- Pending MongoDB pod: inspect the PVC and the `standard` storage class.
- Ingress returns 404: verify the ingress controller and `/etc/hosts`.

## 10. Local Observability

Use the included observability profiles instead of copying the production
resource sizes into Minikube.

- `light` is recommended for normal development. It installs Prometheus,
  Alertmanager, Grafana, kube-state-metrics, the BJJ API dashboard, and local
  alert rules.
- `full` adds Loki, Tempo, and an OpenTelemetry Collector. The collector
  receives application OTLP telemetry and collects container logs from the
  Minikube node.

The light profile is suitable for a 6 GiB Minikube cluster. Allocate at least
8 GiB to Minikube before using the full profile; Docker Desktop must have more
memory assigned than Minikube requests.

Install the recommended light profile:

```bash
./observability/install.sh light
```

Install the full metrics, logs, and traces profile:

```bash
./observability/install.sh full
```

The installer refuses to run unless the active Kubernetes context is
`minikube`. Chart versions are pinned in `observability/install.sh` so local
upgrades are deliberate and reproducible. Observability-only app upgrades skip
the seeder hook because telemetry configuration does not require reseeding.

Access Grafana:

```bash
kubectl port-forward \
  --namespace observability \
  service/monitoring-grafana \
  3000:80
```

Open `http://localhost:3000` and sign in with `admin` / `admin`. The local
password is intentionally development-only.

Access Prometheus and Alertmanager in separate terminals:

```bash
kubectl port-forward \
  --namespace observability \
  service/monitoring-kube-prometheus-prometheus \
  9090:9090

kubectl port-forward \
  --namespace observability \
  service/monitoring-kube-prometheus-alertmanager \
  9093:9093
```

Verify discovery, rules, and telemetry:

```bash
./observability/install.sh status

kubectl get servicemonitor,prometheusrule --all-namespaces
kubectl logs --namespace observability daemonset/otel-collector --tail=100
kubectl top pods --namespace observability
```

Switching back to light mode removes Loki, Tempo, and the collector and clears
the API OTLP endpoint:

```bash
./observability/install.sh light
```

Remove the local observability namespace and restore the application to its
normal local values:

```bash
./observability/install.sh cleanup
```

For local Flux reconciliation tests, keep these values in a dedicated local
GitOps overlay and reference the same pinned chart versions. Do not modify the
production base with Minikube resource limits, local Grafana credentials, or
ephemeral storage settings.

## 11. Cleanup

Remove only the Helm release:

```bash
helm uninstall bjj-eire --namespace bjjeire-app
```

Remove the namespace and its persistent MongoDB data:

```bash
kubectl delete namespace bjjeire-app
```

Stop the cluster while preserving its state:

```bash
minikube stop
```

Delete the cluster completely:

```bash
minikube delete
```
