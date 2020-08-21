NAME ?= summerwind/actions-runner-controller
VERSION ?= latest

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
test: generate fmt vet manifests
	go test ./... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	go run ./main.go

# Install CRDs into a cluster
install: manifests
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests
	kustomize build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	cd config/manager && kustomize edit set image controller=${NAME}:${VERSION}
	kustomize build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths="./..."

# Build the docker image
docker-build: test
	docker build . -t ${NAME}:${VERSION}

# Push the docker image
docker-push:
	docker push ${NAME}:${VERSION}

# Generate the release manifest file
release: manifests
	cd config/manager && kustomize edit set image controller=${NAME}:${VERSION}
	mkdir -p release
	kustomize build config/default > release/actions-runner-controller.yaml

	# build helm charts	
	# copy controller manifest to helm templates
	cp -v release/actions-runner-controller.yaml charts/actions-runner-controller/templates

	ls release
	ls charts
	ls charts/actions-runner-controller
	ls charts/actions-runner-controller/templates

	# remove first 7 lines that create namespace
	sed -i '1,7d' charts/actions-runner-controller/templates/actions-runner-controller.yaml 
	# package helm .tgz and put it into the release dir
	helm package charts/actions-runner-controller --app-version ${VERSION} -d release

	# package actions-runner-deployment and put it into the release dir
	helm package charts/actions-runner-deployment --app-version ${VERSION} -d release

# Upload release file to GitHub.
github-release: release
	ghr ${VERSION} release/

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.4 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif
