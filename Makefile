# Disable built-in rules.
.SUFFIXES:

# Image URL to use all building/pushing image targets
TAG ?= latest
CONFIG ?= dev
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

build: generate manifests
	go build ./...

# Run tests
test: build
	go test ./... -coverprofile cover.out

pre-commit: codegen test lint

codegen: generate manifests proto config/ci.yaml config/default.yaml config/dev.yaml config/quick-start.yaml docs/EXAMPLES.md

$(GOBIN)/goreman:
	go install github.com/mattn/goreman@v0.3.7

# Run against the configured Kubernetes cluster in ~/.kube/config
start: generate deploy $(GOBIN)/goreman
	goreman -set-ports=false -logtime=false start
wait:
	kubectl -n argo-dataflow-system get pod
	kubectl -n argo-dataflow-system wait pod --all --for=condition=Ready --timeout=2m
logs: $(GOBIN)/stern
	stern -n argo-dataflow-system --tail=3 .

# Install CRDs into a cluster
install:
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall:
	kustomize build config/crd | kubectl delete --ignore-not-found -f -

images: controller runner runtimes

config/dev.yaml:
config/quick-start.yaml:
config/%.yaml: /dev/null
	kustomize build --load_restrictor=none config/$* -o $@

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: install
	kubectl apply --force -f config/$(CONFIG).yaml

undeploy:
	kubectl delete --ignore-not-found -f config/$(CONFIG).yaml

# Generate manifests e.g. CRD, RBAC etc.
.PHONY: manifests
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: docs/EXAMPLES.md
docs/EXAMPLES.md:
	go run ./docs/examples > docs/EXAMPLES.md

# not dependant on api/v1alpha1/generated.proto because it often does not change when this target runs, so results in remakes when they are not needed
proto: api/v1alpha1/generated.pb.go

$(GOBIN)/go-to-protobuf:
	go install k8s.io/code-generator/cmd/go-to-protobuf@v0.19.6

api/v1alpha1/generated.%: $(shell find api/v1alpha1 -type f -name '*.go' -not -name '*generated*' -not -name groupversion_info.go) $(GOBIN)/go-to-protobuf
	[ ! -e api/v1alpha1/groupversion_info.go ] || mv api/v1alpha1/groupversion_info.go api/v1alpha1/groupversion_info.go.0
	go-to-protobuf \
		--go-header-file=./hack/boilerplate.go.txt \
  		--packages=github.com/argoproj-labs/argo-dataflow/api/v1alpha1 \
		--apimachinery-packages=+k8s.io/apimachinery/pkg/util/intstr,+k8s.io/apimachinery/pkg/api/resource,k8s.io/apimachinery/pkg/runtime/schema,+k8s.io/apimachinery/pkg/runtime,k8s.io/apimachinery/pkg/apis/meta/v1,k8s.io/api/core/v1
	mv api/v1alpha1/groupversion_info.go.0 api/v1alpha1/groupversion_info.go
	go mod tidy

lint:
	go mod tidy
	golangci-lint run --fix
	kubectl apply --dry-run=server -f docs/examples

.PHONY: controller
controller: controller-image

.PHONY: runner

runner: runner-image

.PHONY: runtimes
runtimes: go1-16 java16 python3-9

go1-16: go1-16-image
java16: java16-image
python3-9: python3-9-image

%-image:
	docker build . --target $* --tag quay.io/argoproj/dataflow-$*:$(TAG)
scan-%:
	docker scan --severity=high quay.io/argoproj/dataflow-$*:$(TAG)

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.4.1 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

$(GOBIN)/kafka-console-consumer:
	go install github.com/Shopify/sarama/tools/kafka-console-consumer
$(GOBIN)/kafka-console-producer:
	go install github.com/Shopify/sarama/tools/kafka-console-producer

version:=2.3.2
name:=darwin
arch:=amd64

kubebuilder:
	# download the release
	curl -L -O "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v$(version)/kubebuilder_$(version)_$(name)_$(arch).tar.gz"

	# extract the archive
	tar -zxvf kubebuilder_$(version)_$(name)_$(arch).tar.gz
	mv kubebuilder_$(version)_$(name)_$(arch) kubebuilder && sudo mv kubebuilder /usr/local/

config/kafka/dev-small.yaml:
	kustomize build -o config/kafka/dev-small.yaml github.com/Yolean/kubernetes-kafka/variants/dev-small/?ref=v6.0.3

config/nats/single-server-nats.yml:
	curl -o config/nats/single-server-nats.yml https://raw.githubusercontent.com/nats-io/k8s/v0.7.4/nats-server/single-server-nats.yml

config/stan/single-server-stan.yml:
	curl -o config/stan/single-server-stan.yml https://raw.githubusercontent.com/nats-io/k8s/v0.7.4/nats-streaming-server/single-server-stan.yml

nuke: undeploy uninstall
	git clean -fxd
	docker image rm argoproj/dataflow-runner || true
	docker system prune -f

.PHONY: test-examples
test-examples:
	go test -v -tags examples ./docs/examples