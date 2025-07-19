#!/bin/bash
set -euo pipefail

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Disable ALL Terraform locking
export TF_CLI_ARGS="-lock=false"
export TF_CLI_ARGS_init="-lock=false"
export TF_CLI_ARGS_plan="-lock=false"
export TF_CLI_ARGS_apply="-lock=false"
export TF_CLI_ARGS_destroy="-lock=false"

LAST_PATHS_FILE=".last_tf_paths"
projects=()
selected_projects=()

# 🔍 Project detection
function detect_tf_projects() {
  echo -e "\n${CYAN}📦 Scanning for Terraform projects...${NC}"
  projects=()
  
  while IFS= read -r -d '' dir; do
    if ls "$dir"/*.tf &>/dev/null || [[ "$dir" == "." && $(ls *.tf 2>/dev/null | wc -l) -gt 0 ]]; then
      [[ "$dir" == "." ]] && projects+=(".") || projects+=("$dir")
    fi
  done < <(find . -mindepth 1 -maxdepth 3 -type f -name "*.tf" -exec dirname {} \; | sort -u | tr '\n' '\0')

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No valid Terraform projects found${NC}"
    exit 1
  fi

  echo -e "\n${GREEN}📂 Detected Terraform projects:${NC}"
  for i in "${!projects[@]}"; do
    printf "${BLUE}%3d.${NC} %s\n" "$((i + 1))" "$([[ "${projects[$i]}" == "." ]] && echo "./" || echo "${projects[$i]}")"
  done
}

# 🚀 Enhanced execution with proper numbering and error output
function run_terraform() {
  local path="$1"
  local action="$2"
  local counter="$3"
  local display_path="$([[ "$path" == "." ]] && echo "./" || echo "$path")"
  
  echo -ne "${counter}. ${display_path}"
  
  pushd "$path" >/dev/null || { echo -e " ${RED}❌ Can't enter directory${NC}"; return 1; }

  # 1. INIT
  echo -ne " [init..."
  local start=$(date +%s)
  if terraform init -input=false -no-color &>init.log; then
    local duration=$(( $(date +%s) - start ))
    printf " ${GREEN}OK${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
  else
    local duration=$(( $(date +%s) - start ))
    printf " ${RED}FAIL${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
    echo -e "${YELLOW}Init logs:${NC}"
    cat init.log
    popd >/dev/null
    return 1
  fi

  if [[ "$action" == "apply" ]]; then
    # 2. PLAN
    echo -ne " [plan..."
    start=$(date +%s)
    if terraform plan -input=false -no-color -out=tfplan &>plan.log; then
      duration=$(( $(date +%s) - start ))
      printf " ${GREEN}OK${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
    else
      duration=$(( $(date +%s) - start ))
      printf " ${RED}FAIL${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
      echo -e "${YELLOW}Plan error:${NC}"
      grep -A 5 -B 5 "Error:" plan.log || cat plan.log
      popd >/dev/null
      return 1
    fi

    # 3. APPLY
    echo -ne " [apply..."
    start=$(date +%s)
    if terraform apply -input=false -no-color tfplan &>apply.log; then
      duration=$(( $(date +%s) - start ))
      printf " ${GREEN}DONE${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
    else
      duration=$(( $(date +%s) - start ))
      printf " ${RED}FAIL${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
      echo -e "${YELLOW}Apply error:${NC}"
      grep -A 5 -B 5 "Error:" apply.log || cat apply.log
      popd >/dev/null
      return 1
    fi
  else
    # DESTROY FLOW
    echo -ne " [check..."
    start=$(date +%s)
    local resources=$(terraform state list 2>/dev/null | wc -l)
    duration=$(( $(date +%s) - start ))
    printf " ${YELLOW}%d resources${NC} (%02dm%02ds)]" "$resources" $((duration/60)) $((duration%60))

    if [[ $resources -eq 0 ]]; then
      printf " ${YELLOW}SKIPPED${NC}\n"
      popd >/dev/null
      return 0
    fi

    echo -ne " [destroy..."
    start=$(date +%s)
    if terraform destroy -auto-approve -input=false -no-color &>destroy.log; then
      duration=$(( $(date +%s) - start ))
      printf " ${GREEN}DONE${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
    else
      duration=$(( $(date +%s) - start ))
      printf " ${RED}FAIL${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
      
      # Recovery attempt
      echo -ne " [retry..."
      start=$(date +%s)
      terraform force-unlock -force $(terraform state list 2>/dev/null | head -1)
      if terraform destroy -auto-approve -input=false -no-color &>/dev/null; then
        duration=$(( $(date +%s) - start ))
        printf " ${GREEN}DONE${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
      else
        duration=$(( $(date +%s) - start ))
        printf " ${RED}FAIL${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
        popd >/dev/null
        return 1
      fi
    fi
  fi

  popd >/dev/null
  return 0
}

# 🌱 Main Execution
clear
echo -e "${GREEN}🌱 Terraform Automation Script${NC}"
echo -e "${BLUE}--------------------------------${NC}"
echo -e "1. ${CYAN}Apply${NC} (create/modify infrastructure)"
echo -e "2. ${RED}Destroy${NC} (tear down infrastructure)"
echo -ne "\n${YELLOW}➡️ Select operation (1-2): ${NC}"
read -r choice

case "$choice" in
  1|2)
    detect_tf_projects
    echo -e "\n${YELLOW}🧮 Enter project numbers (e.g., 1 3 5) or 'all': ${NC}"
    read -r order
    
    if [[ "$order" == "all" ]]; then
      selected_projects=("${projects[@]}")
    else
      for i in $order; do
        selected_projects+=("${projects[$((i-1))]}")
      done
    fi

    echo -e "\n${CYAN}➡️ Will execute:${NC}"
    for i in "${!selected_projects[@]}"; do
      printf "${YELLOW}%3d.${NC} %s\n" "$((i+1))" "$([[ "${selected_projects[$i]}" == "." ]] && echo "./" || echo "${selected_projects[$i]}")"
    done

    echo -ne "\n${GREEN}✅ Confirm? (y/n): ${NC}"
    read -r confirm
    [[ "$confirm" == "y" ]] || { echo -e "${RED}❌ Aborted.${NC}"; exit 1; }

    # Execute with proper numbering
    for i in "${!selected_projects[@]}"; do
      if ! run_terraform "${selected_projects[$i]}" "$([[ "$choice" == "1" ]] && echo "apply" || echo "destroy")" "$((i+1))"; then
        echo -e "\n${RED}⛔ Operation failed on ${selected_projects[$i]}${NC}"
        echo -e "${YELLOW}Investigate the error above before continuing.${NC}"
        exit 1
      fi
    done

    [[ "$choice" == "1" ]] && printf "%s\n" "${selected_projects[@]}" > "$LAST_PATHS_FILE"
    ;;
  *)
    echo -e "${RED}❌ Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

echo -e "\n${GREEN}🎉 All operations completed successfully!${NC}"