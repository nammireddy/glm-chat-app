# GLM Chat Application — root Makefile
# Delegates lint / test / build to each service subdirectory and the frontend.
#
# Usage:
#   make lint    — run linters across all services
#   make test    — run unit + property tests across all services
#   make build   — build Docker images for all services
#   make clean   — remove build artefacts

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ─── Service directories ──────────────────────────────────────────────────────
PYTHON_SERVICES := \
	services/chat-service \
	services/inference-service \
	services/rag-service \
	services/embedding-service \
	services/confidence-scorer

FRONTEND_DIR := frontend

# ─── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo "GLM Chat Application — available targets:"
	@echo ""
	@echo "  lint      Run linters for all Python services and the frontend"
	@echo "  test      Run unit + property tests for all services"
	@echo "  build     Build Docker images for all services"
	@echo "  clean     Remove build artefacts and cached files"
	@echo ""

# ─── Lint ─────────────────────────────────────────────────────────────────────
.PHONY: lint lint-python lint-frontend lint-terraform

lint: lint-python lint-frontend lint-terraform

lint-python:
	@echo "==> Linting Python services..."
	@for svc in $(PYTHON_SERVICES); do \
		if [ -f "$$svc/pyproject.toml" ] || [ -f "$$svc/setup.py" ] || [ -f "$$svc/requirements.txt" ]; then \
			echo "  -> $$svc"; \
			cd $$svc && \
			python -m ruff check . && \
			python -m mypy . --ignore-missing-imports || true; \
			cd -; \
		else \
			echo "  -> $$svc (no Python project file yet, skipping)"; \
		fi \
	done

lint-frontend:
	@echo "==> Linting frontend..."
	@if [ -f "$(FRONTEND_DIR)/package.json" ]; then \
		cd $(FRONTEND_DIR) && npm run lint; \
	else \
		echo "  -> frontend (no package.json yet, skipping)"; \
	fi

lint-terraform:
	@echo "==> Linting Terraform..."
	@if command -v tflint &>/dev/null; then \
		find infra/terraform -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do \
			echo "  -> $$dir"; \
			tflint --chdir $$dir; \
		done; \
	else \
		echo "  -> tflint not found, running terraform validate instead"; \
		find infra/terraform -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do \
			echo "  -> $$dir"; \
			cd $$dir && terraform validate && cd -; \
		done; \
	fi

# ─── Test ─────────────────────────────────────────────────────────────────────
.PHONY: test test-python test-frontend

test: test-python test-frontend

test-python:
	@echo "==> Running Python tests..."
	@for svc in $(PYTHON_SERVICES); do \
		if [ -d "$$svc/tests" ]; then \
			echo "  -> $$svc"; \
			cd $$svc && python -m pytest tests/ -v --tb=short; \
			cd -; \
		else \
			echo "  -> $$svc (no tests/ directory yet, skipping)"; \
		fi \
	done

test-frontend:
	@echo "==> Running frontend tests..."
	@if [ -f "$(FRONTEND_DIR)/package.json" ]; then \
		cd $(FRONTEND_DIR) && npm run test -- --run; \
	else \
		echo "  -> frontend (no package.json yet, skipping)"; \
	fi

# ─── Build ────────────────────────────────────────────────────────────────────
.PHONY: build build-services build-frontend

build: build-services build-frontend

build-services:
	@echo "==> Building service Docker images..."
	@for svc in $(PYTHON_SERVICES); do \
		if [ -f "$$svc/Dockerfile" ]; then \
			svc_name=$$(basename $$svc); \
			echo "  -> Building $$svc_name"; \
			docker build -t glm-chat/$$svc_name:local $$svc; \
		else \
			echo "  -> $$svc (no Dockerfile yet, skipping)"; \
		fi \
	done

build-frontend:
	@echo "==> Building frontend Docker image..."
	@if [ -f "$(FRONTEND_DIR)/Dockerfile" ]; then \
		docker build -t glm-chat/frontend:local $(FRONTEND_DIR); \
	else \
		echo "  -> frontend (no Dockerfile yet, skipping)"; \
	fi

# ─── Clean ────────────────────────────────────────────────────────────────────
.PHONY: clean

clean:
	@echo "==> Cleaning build artefacts..."
	@find . -type d -name "__pycache__" -not -path "./.kiro/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -not -path "./.kiro/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "*.egg-info" -not -path "./.kiro/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".mypy_cache" -not -path "./.kiro/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -not -path "./.kiro/*" -delete 2>/dev/null || true
	@[ -d "$(FRONTEND_DIR)/dist" ] && rm -rf $(FRONTEND_DIR)/dist || true
	@[ -d "$(FRONTEND_DIR)/node_modules" ] && echo "  -> run 'rm -rf $(FRONTEND_DIR)/node_modules' manually if needed" || true
	@echo "Done."
