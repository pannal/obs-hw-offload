#!/bin/bash

# Function to print usage
usage() {
    cat <<EOL
Usage: $0 [options]

Options:
  -r, --restart                 Enable restart of FFmpeg if the stream goes down (default: false).
  -t, --timeout TIMEOUT         Set timeout (in seconds) after stopping FFmpeg before restarting (default: 30).
  -c, --check-interval INTERVAL Set check interval (in seconds) between each NDI stream check (default: 5).
  -s, --stream-target TARGET    Set the stream target URL (default: rtmp://fragstore.net:1339/swagger/panni).
  -n, --ndi-source SOURCE       Set the NDI source (mandatory).
  -v, --vaapi-device DEVICE     Set the VAAPI device path (default: /dev/dri/renderD128).
  -x, --extra-ips IPS           Specify extra IPs for the NDI stream (optional).
  -e, --env-file ENV_FILE       Specify an environment file (default: .env).
  -h, --help                    Display this help message.

Environment Variables:
  The same options can also be specified via environment variables or an environment file.
  Order of precedence: command-line arguments > environment variables > environment file.
EOL
}

# Default configuration values
DEFAULT_ENV_FILE=".env"

# Parse command-line arguments
USER_SPECIFIED_ENV_FILE=""
ARGS_PROVIDED=false
while [[ "$#" -gt 0 ]]; do
  ARGS_PROVIDED=true
  case "$1" in
    -e|--env-file) USER_SPECIFIED_ENV_FILE="$2"; shift 2 ;;
    -r|--restart) RESTART=true; shift ;;
    -t|--timeout) TIMEOUT="$2"; shift 2 ;;
    -c|--check-interval) CHECK_INTERVAL="$2"; shift 2 ;;
    -s|--stream-target) STREAM_TARGET="$2"; shift 2 ;;
    -n|--ndi-source) NDI_SOURCE="$2"; shift 2 ;;
    -v|--vaapi-device) VAAPI_DEVICE="$2"; shift 2 ;;
    -x|--extra-ips) EXTRA_IPS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Determine which environment file to use
ENV_FILE="${USER_SPECIFIED_ENV_FILE:-${ENV_FILE:-$DEFAULT_ENV_FILE}}"

# Load environment variables from the file if it exists
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment variables from $ENV_FILE"
    source "$ENV_FILE"
fi

# Default values for optional variables
RESTART="${RESTART:-false}"
TIMEOUT="${TIMEOUT:-30}"  # Timeout in seconds for waiting after stopping FFmpeg before restarting
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"  # Interval in seconds between NDI stream checks
VAAPI_DEVICE="${VAAPI_DEVICE:-/dev/dri/renderD128}"  # Default VAAPI device
EXTRA_IPS="${EXTRA_IPS:-}"  # Optional
STREAM_TARGET="${STREAM_TARGET:-rtmp://domain:port/streamkey}"  # Optional

# Mandatory variable check
if [ -z "$NDI_SOURCE" ]; then
    echo "Error: NDI source is mandatory. Use -n or --ndi-source, set it in $ENV_FILE, or define it as an environment variable."
    usage
    exit 1
fi

# Convert the FFmpeg params environment variable to an array, if set
if [ -n "$FFMPEG_PARAMS" ]; then
    IFS=' ' read -r -a FFMPEG_PARAMS_ARRAY <<< "$FFMPEG_PARAMS"
else
    # Default FFmpeg parameters if not provided via the environment
    FFMPEG_PARAMS_ARRAY=(
        -fflags nobuffer
        -re
        -threads 4
        -hwaccel vaapi
        -vaapi_device "$VAAPI_DEVICE"
        -hwaccel_output_format vaapi
        -f libndi_newtek
        -analyzeduration 5M
        -probesize 50M
        ${EXTRA_IPS:+-extra_ips "$EXTRA_IPS"}
        -i "$NDI_SOURCE"
        -vf 'format=nv12,hwupload'
        -c:v hevc_vaapi
        -maxrate 20M
        -b:v 14M
        -qp 20
        -rc_mode QVBR
        -map 0:0
        -map 0:1
        -c:a libfdk_aac
        -vbr 4
        -v verbose
        -f flv "$STREAM_TARGET"
    )
fi

# Function to start FFmpeg
start_ffmpeg() {
    echo "Starting FFmpeg..."
    ffmpeg "${FFMPEG_PARAMS_ARRAY[@]}" &
    FFMPEG_PID=$!
    echo "FFmpeg is running with PID: $FFMPEG_PID"
}

# Function to monitor the NDI source
monitor_source() {
    while true; do
        ffprobe -f libndi_newtek ${EXTRA_IPS:+-extra_ips "$EXTRA_IPS"} -i "$NDI_SOURCE" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "NDI stream is down."
            kill_ffmpeg
            if [ "$RESTART" = true ]; then
                echo "Waiting for $TIMEOUT seconds before restarting FFmpeg..."
                sleep "$TIMEOUT"
                start_ffmpeg
            else
                echo "Not restarting FFmpeg."
                exit 0
            fi
        fi
        sleep "$CHECK_INTERVAL"
    done
}

# Function to kill FFmpeg
kill_ffmpeg() {
    echo "Stopping FFmpeg..."
    if [ -n "$FFMPEG_PID" ]; then
        kill "$FFMPEG_PID" >/dev/null 2>&1 || echo "No running FFmpeg process to stop."
        wait "$FFMPEG_PID" 2>/dev/null
        FFMPEG_PID=""
    fi
}

# Main execution
if [ "$ARGS_PROVIDED" = false ]; then
    usage
    exit 1
fi

trap 'kill_ffmpeg; exit' SIGINT SIGTERM

# Start FFmpeg and begin monitoring
start_ffmpeg
monitor_source
