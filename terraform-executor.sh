#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FOLDER_A="consumer-EP"
FOLDER_B="provider-EPS"

PATH_A="$SCRIPT_DIR/$FOLDER_A"
PATH_B="$SCRIPT_DIR/$FOLDER_B"

[[ ! -d "$PATH_A" ]] && { echo -e "${RED}❌ Folder not found: $PATH_A${NC}"; exit 1; }
[[ ! -d "$PATH_B" ]] && { echo -e "${RED}❌ Folder not found: $PATH_B${NC}"; exit 1; }

# Init with fallback
terraform_init_with_fallback() {
  local dir=$1
  echo -e "${BLUE}👉 Initializing Terraform in >>>>>>>> $dir${NC}"
  cd "$dir"
  if ! terraform init -input=false > /dev/null; then
    echo -e "${YELLOW}⚠️ Init failed, retrying with -upgrade...${NC}"
    terraform init -input=false -upgrade > /dev/null || {
      echo -e "${RED}❌ terraform init failed even with -upgrade${NC}"
      exit 1
    }
  fi
  cd "$SCRIPT_DIR"
}

# Plan and apply
terraform_plan_and_apply() {
  local dir=$1
  local extra_var=$2
  echo -e "${YELLOW}💡 Planning Terraform for >>>>>>>> $dir${NC}"
  cd "$dir"
  if terraform plan $extra_var; then
    echo -e "${GREEN}✅ Plan successful — applying...${NC}"
    terraform apply -auto-approve $extra_var
  else
    echo -e "${RED}❌ terraform plan failed. Exiting.${NC}"
    exit 1
  fi
  cd "$SCRIPT_DIR"
}

# Main menu
echo -e "${BOLD}What do you want to do?${NC}"
echo "1) Terraform Apply"
echo "2) Terraform Destroy"
read -rp "Enter choice (1 or 2): " ACTION

# ---------------------- APPLY ---------------------
if [[ "$ACTION" == "1" ]]; then
  echo
  read -rp "Does consumer-EP need an output from provider-EPS? (type -y to confirm): " CONFIRM
  [[ "$CONFIRM" != "-y" ]] && { echo -e "${RED}❌ Dependency not confirmed. Exiting.${NC}"; exit 1; }

  echo -e "${BLUE}🔧 Step 1: Init & Apply provider-EPS${NC}"
  terraform_init_with_fallback "$PATH_B"
  terraform_plan_and_apply "$PATH_B"

  echo -e "${BLUE}🔍 Step 2: Capturing output from provider-EPS...${NC}"
  cd "$PATH_B"
  OUTPUT_VALUE=$(terraform output -raw endpoint_service_name)
  cd "$SCRIPT_DIR"
  echo -e "${GREEN}✅ Captured endpoint_service_name: $OUTPUT_VALUE${NC}"

  echo -e "${BLUE}🔧 Step 3: Init & Apply consumer-EP${NC}"
  terraform_init_with_fallback "$PATH_A"
  terraform_plan_and_apply "$PATH_A" "-var=endpoint_service_name=$OUTPUT_VALUE"

  echo -e "${GREEN}${BOLD}🎉 Apply process complete for both modules!${NC}"

# ---------------------- DESTROY ---------------------
elif [[ "$ACTION" == "2" ]]; then
  echo -e "${RED}🔥 Destroying Terraform resources in >>>>>>>> $PATH_A${NC}"
  cd "$PATH_A"
  terraform destroy -auto-approve -var=endpoint_service_name="x" || true
  cd "$SCRIPT_DIR"

  echo -e "${RED}🔥 Destroying Terraform resources in >>>>>>>> $PATH_B (1st pass)${NC}"
  cd "$PATH_B"
  terraform destroy -auto-approve || true
  cd "$SCRIPT_DIR"

  echo -e "${RED}🔥 Final cleanup of >>>>>>>> $PATH_B (2nd pass)${NC}"
  cd "$PATH_B"
  terraform destroy -auto-approve || true
  cd "$SCRIPT_DIR"

  echo -e "${GREEN}${BOLD}✅ Destroy process complete for both modules!${NC}"

else
  echo -e "${RED}❌ Invalid choice. Exiting.${NC}"
  exit 1
fi

