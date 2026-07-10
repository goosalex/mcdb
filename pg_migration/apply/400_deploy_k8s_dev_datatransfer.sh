#!/usr/bin/env bash

# Exit on error, undefined variables, and propagate pipe failures
set -euo pipefail

# Set directory for K8s manifest files
K8S_DIR="${PANTA_HOME}/osdb/mcdb/pg_migration/k8s/dev"

echo "=== Starting deployment to Kubernetes ==="

# Function to check if kubectl is available
check_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
  fi

  # Check if connected to a cluster
  if ! kubectl config view --minify &> /dev/null; then
    echo "Error: Not connected to a Kubernetes cluster"
    exit 1
  fi
  echo "kubectl is available and connected to a cluster"
  echo "Current context: $(kubectl config current-context)"
  echo "Current namespace: $(kubectl config view --minify --output 'jsonpath={..namespace}')"
}

# Function to apply resources matching a pattern
apply_resources() {
  local pattern=$1
  local description=$2

  echo "=== Deploying $description ==="

  # Find files matching the pattern
  files=$(find "${K8S_DIR}" -name "${pattern}" -type f | sort)

  if [ -z "$files" ]; then
    echo "No $description found to deploy"
    return 0
  fi

  # Apply each file
  for file in $files; do
    echo "Applying $file"
    kubectl apply -f "$file"

    # Small delay to avoid overwhelming the API server
    sleep 1
  done

  echo "=== Finished deploying $description ==="
}

# Function to wait for a job to complete successfully
wait_for_job() {
  local job_name=$1
  local namespace
  namespace=$(kubectl config view --minify --output 'jsonpath={..namespace}')

  if [ -z "$namespace" ]; then
    namespace="default"
  fi

  echo "Waiting for job $job_name to complete..."

  # Initial timeout for job to appear
  timeout=50
  while [ $timeout -gt 0 ]; do
    if kubectl get job "$job_name" -n "$namespace" &> /dev/null; then
      break
    fi
    sleep 2
    ((timeout-=2))
    echo -n "."
  done

  if [ $timeout -le 0 ]; then
    echo "Error: Timed out waiting for job $job_name to appear"
    return 1
  fi

  echo ""

  # Wait for job completion with a longer timeout
  timeout=3600  # 60 minutes
  while [ $timeout -gt 0 ]; do
    # Check job status
    status=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
    failed=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.failed}')

    if [ "$status" == "True" ]; then
      echo "Job $job_name completed successfully"
      return 0
    elif [ "$failed" ] && [ "$failed" -gt 0 ]; then
      echo "Error: Job $job_name failed"
      kubectl logs job/"$job_name" -n "$namespace"
      return 1
    fi

    sleep 5
    ((timeout-=5))

    # Print progress every 30 seconds
    if [ $((timeout % 30)) -eq 0 ]; then
      echo "Still waiting for job $job_name to complete... ($(($timeout/60)) minutes remaining)"
    fi
  done

  echo "Error: Timed out waiting for job $job_name to complete"
  return 1
}

# Function to deploy jobs sequentially
deploy_jobs() {
  echo "=== Deploying Jobs Sequentially ==="

  # Find job files
  job_files=$(find "${K8S_DIR}" -name "[0-9]*.job.yaml" -type f | sort)

  if [ -z "$job_files" ]; then
    echo "No jobs found to deploy"
    return 0
  fi

  # Apply each job and wait for completion
  for job_file in $job_files; do
    job_name=$(basename "$job_file" .job.yaml)

    # Extract job name from the file content using grep and awk
    job_name=$(grep "job-name:" "$job_file" | awk '{print $2}' || echo "$job_name")

    # Ensure job name is not empty
    if [ -z "$job_name" ]; then
      echo "Error: Could not determine job name from file $job_file"
      continue
    fi
    # if ENV RARIABLE RUNALL is set, delete the job if it already exists


    # if there is already a job defined with the same name, print its age
    existing_job=$(kubectl get job "$job_name" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)
    if [ -n "$existing_job" ]; then
      if [[ "${DELETEALL:-}" == "true" ]]; then
        echo "Deleting existing job $job_name as DELETEALL is set to true"
        kubectl delete job "$job_name" || true
      else
        echo "Job $job_name already exists, started: ${existing_job}"
        # Ask user if they want to delete the existing job
        read -p "Do you want to delete the existing job $job_name and redeploy it? (y/n): " delete_existing
        if [[ "$delete_existing" =~ ^[Yy]$ ]]; then
          echo "Deleting existing job $job_name"
          kubectl delete job "$job_name" || true
        else
          echo "Skipping deployment of job $job_name"
          continue
        fi
      fi
    fi


    echo "Deploying job: $job_name"

    kubectl apply -f "$job_file"

    if ! wait_for_job "$job_name"; then
      echo "Error: Failed to deploy job $job_name. Aborting remaining deployments."
      exit 1
    fi

    echo "Job $job_name completed successfully"
  done

  echo "=== All jobs deployed and completed successfully ==="
}

# Main deployment logic
main() {
  check_kubectl

  # Deploy resources in order
  apply_resources "*.configMap.yaml" "ConfigMaps"
  apply_resources "*.persistentVolumeClaim.yaml" "PersistentVolumeClaims"
  apply_resources "*.externalSecret.yaml" "ExternalSecrets"

  # Deploy jobs sequentially, waiting for each to complete
  deploy_jobs

  echo "=== Deployment completed successfully ==="
}

# Run the main function
main