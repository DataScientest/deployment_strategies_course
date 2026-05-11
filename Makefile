.PHONY: install run status sample-request sample-shadow-request build-image build-v1 build-v2 build-v2-buggy load-v1 load-v2 load-v2-buggy kind-create kind-delete apply-namespace apply-services apply-shadow-base apply-shadow-ingress cleanup-shadow apply-canary update-canary-to-v2 cleanup-canary apply-bluegreen update-bluegreen-to-v2 cleanup-bluegreen apply-analysis-template apply-servicemonitor apply-analysis-rollout update-analysis-to-v2-buggy shadow-file canary-file bluegreen-file analysis-file

install:
	uv python install 3.11
	uv venv --python 3.11
	uv pip install --python .venv/bin/python -r service/requirements.txt

run:
	cd service && ../.venv/bin/python -m uvicorn app:app --reload --host 0.0.0.0 --port 8000

status:
	cd service && ../.venv/bin/python -m pytest -q tests/test_app.py

sample-request:
	curl -s -X POST http://127.0.0.1:8000/predict -H "Content-Type: application/json" -d '{"amount":1499.0,"merchant_category":"travel","hour_of_day":2,"country":"FR","is_international":true,"device_risk_score":0.91}'

sample-shadow-request:
	curl -s -X POST http://127.0.0.1:8081/predict -H "Host: fraud.local" -H "Content-Type: application/json" -d '{"amount":1499.0,"merchant_category":"travel","hour_of_day":2,"country":"FR","is_international":true,"device_risk_score":0.91}'

build-image:
	docker build -t fraud-scoring:v1 service

build-v1:
	docker build -t fraud-scoring:v1 service

build-v2:
	docker build -t fraud-scoring:v2 service

build-v2-buggy:
	docker build -t fraud-scoring:v2-buggy service

load-v1:
	kind load docker-image fraud-scoring:v1 --name argocd-ml

load-v2:
	kind load docker-image fraud-scoring:v2 --name argocd-ml

load-v2-buggy:
	kind load docker-image fraud-scoring:v2-buggy --name argocd-ml

kind-create:
	kind create cluster --name argocd-ml --config scripts/kind-config.yaml

kind-delete:
	kind delete cluster --name argocd-ml

apply-namespace:
	kubectl apply -f k8s/namespace.yaml

apply-services:
	kubectl apply -f k8s/services/

apply-shadow-base:
	kubectl apply -f k8s/deployments/fraud-v1.yaml && kubectl apply -f k8s/deployments/fraud-v2.yaml

apply-shadow-ingress:
	kubectl apply -f k8s/ingress/shadow-ingress.yaml

cleanup-shadow:
	kubectl delete -f k8s/ingress/shadow-ingress.yaml --ignore-not-found=true && kubectl delete -f k8s/deployments/fraud-v1.yaml --ignore-not-found=true && kubectl delete -f k8s/deployments/fraud-v2.yaml --ignore-not-found=true

apply-canary:
	kubectl apply -f k8s/rollouts/canary-rollout.yaml

update-canary-to-v2:
	kubectl patch rollout fraud-rollout -n fraud-detection --type merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"fraud-api","image":"fraud-scoring:v2","env":[{"name":"MODEL_VERSION","value":"v2"}]}]}}}}'

cleanup-canary:
	kubectl delete rollout fraud-rollout -n fraud-detection --ignore-not-found=true

apply-bluegreen:
	kubectl apply -f k8s/rollouts/bluegreen-rollout.yaml

update-bluegreen-to-v2:
	kubectl patch rollout fraud-bluegreen -n fraud-detection --type merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"fraud-api","image":"fraud-scoring:v2","env":[{"name":"MODEL_VERSION","value":"v2"}]}]}}}}'

cleanup-bluegreen:
	kubectl delete rollout fraud-bluegreen -n fraud-detection --ignore-not-found=true

apply-analysis-template:
	kubectl apply -f k8s/analysis/prometheus-analysis-template.yaml

apply-servicemonitor:
	kubectl apply -f k8s/analysis/fraud-servicemonitor.yaml

apply-analysis-rollout:
	kubectl apply -f k8s/rollouts/canary-rollout-with-analysis.yaml

update-analysis-to-v2-buggy:
	kubectl patch rollout fraud-rollout-analysis -n fraud-detection --type merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"fraud-api","image":"fraud-scoring:v2-buggy","env":[{"name":"MODEL_VERSION","value":"v2-buggy"}]}]}}}}'

shadow-file:
	python3 -m pathlib k8s/ingress/shadow-ingress.yaml

canary-file:
	python3 -m pathlib k8s/rollouts/canary-rollout.yaml

bluegreen-file:
	python3 -m pathlib k8s/rollouts/bluegreen-rollout.yaml

analysis-file:
	python3 -m pathlib k8s/analysis/prometheus-analysis-template.yaml
