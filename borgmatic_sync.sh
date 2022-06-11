#!/bin/bash

usage() {
     echo "usage: $(basename "$0") [options] --repo BORG_REPO_PATH --cloud-dest CLOUD_DEST

     Run borgmatic and upload to remote

     Examples:
          $(basename "$0") --repo /mnt/user/borg-repo
          $(basename "$0") --config appdata --repo /mnt/user/borg-repo

     Options:
          -b, --borgmatic-container CONTAINER_NAME name of borgmatic container
                                                   (default=\"borgmatic\")
          -c, --config CONFIG_SUBDIRECTORY         config subdirectory
          -d, --cloud-dest CLOUD_DEST              Rclone cloud destination
          -D, --dont-restart-containers            Skip stop/start of containers
          -e, --healthcheck HEALTHCHECK_URL        URL to healthcheck service
          -h, --help                               show this help text
          -k, --keep-alive CONTAINER_NAME          name of container to keep alive.
                                                   can be used multiple times.
          -r, --repo BORG_REPO_PATH                host repository location"
}

required_arg() {
     if [ -z "$1" ]; then
          echo "Missing required argument"
          exit 1
     fi
}

is_running() {
     local process="$1"

     pgrep "$process" >/dev/null
}

ping_healthcheck() {
     local healthcheck_url="$1"
     local status=${2:-"success"}

     echo "Sending healtcheck ping to $healthcheck_url with status: $2"
     curl -m 10 --retry 5 "$healthcheck_url/$status"
}

containers_to_stop() {
     local return_var="$1"
     local keep_alive_containers="$2"

     echo "Getting running container ids"
     eval "$return_var=\"$(docker ps -a |
          grep -ve "$keep_alive_containers" |
          awk 'NR>1 {print $1}')\""
}

docker_stop() {
     echo "Stopping Docker containers"
     local container_name

     for container_id in "$@"; do
          container_name="$(docker inspect "$container_id" --format {{.Name}})"
          echo "Stopping $container_id ${container_name:1}"
          docker stop "$container_id" >/dev/null
     done
}

main() {
     borg_repo=''
     borgmatic_container_name=''
     borgmatic_verbosityopt=''
     cloud_dest=''
     config=''
     configopt=''
     dryrunopt=''
     healthcheck_url=''
     keep_alive_containers=''
     perform_healthcheck=''
     perform_sync=''
     rclone_verbosityopt=''
     restart_containers=''
     verbosity=''
     while [[ "$#" -gt 0 ]]; do
          case $1 in
          -b | --borgmatic-container)
               borgmatic_container_name="$2"
               shift
               ;;
          -C | --dont-restart-containers)
               restart_containers="false"
               ;;
          -c | --config)
               config="/etc/borgmatic.d/$2"
               configopt="--config $config"
               shift
               ;;
          -d | --cloud-dest)
               cloud_dest="$2"
               shift
               ;;
          -e | --healthcheck)
               healthcheck_url="$2"
               shift
               ;;
          -k | --keep-alive)
               if [ -n "$keep_alive_containers" ]; then
                    keep_alive_containers="$keep_alive_containers\|$2"
               else
                    keep_alive_containers="$2"
               fi
               shift
               ;;
          -n | --dry-run)
               dryrunopt="--dry-run"
               ;;
          -r | --repo)
               borg_repo="$2"
               shift
               ;;
          -S | --dont-sync)
               perform_sync="false"
               ;;
          -v | --verbosity)
               verbosity="$2"
               borgmatic_verbosityopt="--verbosity $verbosity"
               rclone_verbosityopt="--verbose"
               shift
               ;;
          -H | --dont-healthcheck)
               perform_healthcheck="false"
               ;;
          -h | --help)
               usage
               exit 0
               ;;
          *)
               echo "Unexpected argument ($1)"
               usage
               exit 1
               ;;
          esac
          shift
     done

     # Defaults
     borgmatic_container_name=${borgmatic_container_name:-"borgmatic"}
     keep_alive_containers=${keep_alive_containers:-"borgmatic"}

     required_arg "$borg_repo"
     required_arg "$cloud_dest"

     restart_containers=${restart_containers:-"true"}
     if [ -n "$dryrunopt" ]; then
          restart_containers="false"
     fi

     perform_sync=${perform_sync:-"true"}
     if [ -z $dryrunopt ] && [ -n "$cloud_dest" ]; then
          perform_sync="true"
     else
          perform_sync="false"
     fi

     perform_healthcheck=${perform_healthcheck:-"true"}
     if [ -z $dryrunopt ] && [ $perform_sync == "true" ]; then
          perform_healthcheck="true"
     else
          perform_healthcheck="false"
     fi

     # Exit if Rclone already running
     # This section must go before any other section to ensure that
     # Borg backup is not executed while Rclone is running, otherwise
     # you may end with mismatched files between the host and remote
     if is_running rclone; then
          echo "RClone already running, exiting"
          exit 1
     else
          echo "Rclone not running, continuing"
     fi

     # Check if Borgmatic is running
     # if [ -z "$(docker ps | grep $borgmatic_container_name)" ]; then
     #      echo "Borgmatic container not running"
     #      exit 1
     #      if [ $perform_healthcheck == "true" ]; then
     #           ping_healthcheck "$healthcheck_url" fail
     #      fi
     # fi


     # Stop running Docker containers except for Borgmatic
     container_ids=''
     keep_alive_containers="$borgmatic_container_name\|$keep_alive_containers"
     containers_to_stop container_ids "$keep_alive_containers"

     if [ $restart_containers == "true" ]; then
          docker_stop "$container_ids"
     fi

     # Borg backup
     echo "Running borgmatic"
     borgmatic_command="borgmatic \
          $configopt \
          $borgmatic_verbosityopt \
          $dryrunopt"
     docker exec borgmatic sh -c "$borgmatic_command"
     docker_exit_status=$?
     [ $docker_exit_status -ne 0 ] && exit $docker_exit_status

     # Start previously running Docker containers
     if [ $restart_containers == "true" ]; then
          nohup docker start "$container_ids" >/dev/null &
     fi

     # Rclone sync
     if [ $perform_sync == "true" ]; then
          echo "Starting Rclone sync"
          rclone sync \
               --drive-use-trash=false \
               $rclone_verbosityopt \
               $dryrunopt \
               "$borg_repo" \
               "$cloud_dest"
          rclone_status=$?

          # Rclone healthcheck
          if [ $perform_healthcheck == "true" ]; then
               if [ $rclone_status -eq 0 ]; then
                    ping_healthcheck "$healthcheck_url"
               else
                    echo "Rclone exit status != 0, not sending healthceck ping"
               fi
          else
               echo "Skipping healthcheck ping (no healthcheck url provided)"
          fi
     else
          echo "Skipping sync"
     fi

     echo "$(basename "$0") done"
     exit $rclone_status
}

main "$@"
