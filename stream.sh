#!/bin/bash

set -o pipefail

# Default values
DEFAULT_ENV_FILE=".env"
ENV_FILE="$DEFAULT_ENV_FILE" # Default ENV_FILE path
FFMPEG_INPUT_THREADS="${FFMPEG_INPUT_THREADS:-4}"
FFMPEG_OUTPUT_THREADS="${FFMPEG_OUTPUT_THREADS:+"-threads $FFMPEG_OUTPUT_THREADS"}"
FFMPEG_PARAMS="${FFMPEG_PARAMS:-""}"
FFMPEG_VIDEO="${FFMPEG_VIDEO:-"-c:v hevc_vaapi -b:v 8M -rc_mode CBR"}"
FFMPEG_AUDIO="${FFMPEG_AUDIO:-"-c:a libfdk_aac -b:a 128k"}"
FFMPEG_ANALYZE_DURATION="${FFMPEG_ANALYZE_DURATION:-5M}"
FFMPEG_PROBE_SIZE="${FFMPEG_PROBE_SIZE:-50M}"
NDI_SOURCE=""
EXTRA_IPS="${EXTRA_IPS:-}"
VAAPI_DEVICE="${VAAPI_DEVICE:-/dev/dri/renderD128}"
STREAM_TARGET="${STREAM_TARGET:-rtmp://target:port/streamkey}"
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"
CHECK_INTERVAL_DOWN="${CHECK_INTERVAL_DOWN:-30}"
VERBOSE_FLAG="${VERBOSE_FLAG:-info}"
RESTART_FFMPEG="${RESTART_FFMPEG:-false}"
NO_MONITORING="${NO_MONITORING:-false}"
CONTAINER_NAME="${CONTAINER_NAME:-"obs-hw-offload"}"
CHECK_CONTAINER_NAME="${CHECK_CONTAINER_NAME:-"check-obs-hw-offload"}"
DOCKER_IMAGE="pannal/obs-hw-offload"

# Process ID
FFMPEG_PID=""

# Check if running inside a container
if [[ -f /.dockerenv ]]; then
    RUNNING_IN_CONTAINER=true
    FFPROBE_BASE=(ffprobe)
else
    RUNNING_IN_CONTAINER=false
    FFPROBE_BASE=(docker run --rm --name "$CHECK_CONTAINER_NAME" "$DOCKER_IMAGE" ffprobe)
fi

# Usage function
usage() {
    cat <<EOL
Usage: $0 [options]

Options:
  -n, --ndi-source SOURCE       Set the NDI source (always mandatory, should be used together with extra-ips or --network=host in docker).
  -x, --extra-ips IPs           Specify extra IPs for NDI discovery (optional).
  -d, --vaapi-device DEVICE     Specify VAAPI device (default: /dev/dri/renderD128).
  -s, --stream-target TARGET    Set the streaming target URL (default: rtmp://target:port/streamkey).
  -v, --verbose                 Set FFmpeg to verbose output.
  --input-threads NUMBER        How many threads FFmpeg should use for ingesting the source (default: 4). Can also be set to 0 (zero) for all.
  --output-threads NUMBER       How many threads FFmpeg should use for the output (default: all)
  --ffmpeg-video STRING         Specify video-related FFmpeg parameters (default: "-c:v hevc_vaapi -b:v 8M -rc_mode CBR").
  --ffmpeg-audio STRING         Specify audio-related FFmpeg parameters (default: "-c:a libfdk_aac -b:a 128k").
  --ffmpeg-params STRING        Full custom FFmpeg parameters (overrides all other FFmpeg settings).
  --analyzeduration DURATION    Specify analyze duration for input (default: 5M).
  --probesize SIZE              Specify probe size for input (default: 50M).
  --check-interval SECONDS      Set the interval for checking the NDI stream while it's running (default: 5 seconds).
  --check-interval-down SECONDS Set the interval for checking the NDI stream while it's down (default: 30 seconds).
  --no-monitoring               Disable monitoring of NDI streams and just run FFmpeg.
  -r, --restart                 Enable automatic FFmpeg restart when the NDI stream is down.
  -e, --env-file FILE           Specify a custom environment file (default: .env).
  -h, --help                    Display this help message.

Environment Variables:
  The same options can also be specified via environment variables or an environment file.
  Order of precedence: command-line arguments > environment variables > environment file.
EOL
}

# Early processing of ENV_FILE from command-line arguments
for arg in "$@"; do
    case "$arg" in
        -e|--env-file)
            shift
            ENV_FILE="$1"
            shift
            break
            ;;
        --env-file=*)
            ENV_FILE="${arg#*=}"
            shift
            break
            ;;
    esac
done

# Load environment variables from the specified environment file, if it exists
if [[ -f "$ENV_FILE" ]]; then
    echo "Loading environment variables from $ENV_FILE"
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
else
    if [[ "$ENV_FILE" != "$DEFAULT_ENV_FILE" ]]; then
        echo "Error: Specified environment file $ENV_FILE not found."
        exit 1
    fi
fi

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -n|--ndi-source) NDI_SOURCE="$2"; shift 2 ;;
        -x|--extra-ips) EXTRA_IPS="$2"; shift 2 ;;
        -d|--vaapi-device) VAAPI_DEVICE="$2"; shift 2 ;;
        -s|--stream-target) STREAM_TARGET="$2"; shift 2 ;;
        -v|--verbose) VERBOSE_FLAG="verbose"; shift ;;
        --input-threads) FFMPEG_INPUT_THREADS="$2"; shift 2 ;;
        --output-threads) FFMPEG_OUTPUT_THREADS="-threads $2"; shift 2 ;;
        --ffmpeg-video) FFMPEG_VIDEO="$2"; shift 2 ;;
        --ffmpeg-audio) FFMPEG_AUDIO="$2"; shift 2 ;;
        --ffmpeg-params) FFMPEG_PARAMS="$2"; shift 2 ;;
        --analyzeduration) FFMPEG_ANALYZE_DURATION="$2"; shift 2 ;;
        --probesize) FFMPEG_PROBE_SIZE="$2"; shift 2 ;;
        --check-interval) CHECK_INTERVAL="$2"; shift 2 ;;
        --check-interval-down) CHECK_INTERVAL_DOWN="$2"; shift 2 ;;
        --no-monitoring) NO_MONITORING="true"; shift ;;
        -r|--restart) RESTART_FFMPEG="true"; shift ;;
        -e|--env-file) shift ;; # Already processed early, skip
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Ensure NDI_SOURCE is set
if [[ -z "$NDI_SOURCE" ]]; then
    echo "Error: NDI source is mandatory."
    usage
    exit 1
fi

# Function to monitor the NDI stream
monitor_ndi_stream() {
    while true; do
        if [[ -n "$NDI_SOURCE" ]]; then
            # invoke FFprobe
            "${FFPROBE_BASE[@]}" -f libndi_newtek ${EXTRA_IPS:+-extra_ips "$EXTRA_IPS"} -i "$NDI_SOURCE" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "NDI stream is down."
                kill_ffmpeg
                if [[ ! "$RESTART_FFMPEG" == "true" ]]; then
                    echo "Not restarting FFmpeg."
                    exit 0
                fi
                echo "Waiting for NDI stream"
                USE_CHECK_INTERVAL=${CHECK_INTERVAL_DOWN}
            else
                # NDI stream is (still) up, run FFmpeg immediately if requested and not already running
                if [[ -z "$FFMPEG_PID" || ( -n "$FFMPEG_PID" && "$(ps --pid "$FFMPEG_PID" > /dev/null 2>&1)" -ne 0 ) ]]; then
                    echo "NDI stream is up, starting immediately."
                    start_ffmpeg
                    USE_CHECK_INTERVAL=${CHECK_INTERVAL}
                fi
            fi
            sleep "$USE_CHECK_INTERVAL"
        else
            return 0
        fi
    done
}

# Function to kill FFmpeg or Docker container
kill_ffmpeg() {
    if [[ -n "$FFMPEG_PID" && "$(ps --pid "$FFMPEG_PID" > /dev/null 2>&1)" -eq 0 ]]; then
        if $RUNNING_IN_CONTAINER; then
            echo "Killing FFmpeg process (PID: $FFMPEG_PID)..."
            kill "$FFMPEG_PID" >/dev/null 2>&1 || echo "No running FFmpeg process to stop."
            wait "$FFMPEG_PID" 2>/dev/null
        else
            echo "Killing Docker container ($CONTAINER_NAME, $FFMPEG_PID)..."
            docker kill "$CONTAINER_NAME" >/dev/null 2>&1 || echo "No running container to stop."
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi
        FFMPEG_PID=""
    fi
}

# Function to run FFmpeg directly
run_ffmpeg() {
    if [[ -n "$FFMPEG_PARAMS" ]]; then
        ffmpeg "$FFMPEG_PARAMS" &
    else
        ffmpeg \
            -fflags nobuffer -threads "$FFMPEG_INPUT_THREADS" \
            -hwaccel vaapi -vaapi_device "$VAAPI_DEVICE" -hwaccel_output_format vaapi \
            -f libndi_newtek -analyzeduration "$FFMPEG_ANALYZE_DURATION" -probesize "$FFMPEG_PROBE_SIZE" \
            ${EXTRA_IPS:+-extra_ips "$EXTRA_IPS"} \
            -i "$NDI_SOURCE" \
            $FFMPEG_OUTPUT_THREADS \
            -vf 'format=nv12,hwupload' \
            $FFMPEG_VIDEO \
            $FFMPEG_AUDIO \
            -v $VERBOSE_FLAG \
            -f flv "$STREAM_TARGET" &
    fi
    FFMPEG_PID=$!
}

# Function to run FFmpeg inside Docker
run_docker_ffmpeg() {
    local ffmpeg_command
    if [[ -n "$FFMPEG_PARAMS" ]]; then
        ffmpeg_command="ffmpeg $FFMPEG_PARAMS"
    else
        ffmpeg_command="ffmpeg \
            -fflags nobuffer -threads \"$FFMPEG_INPUT_THREADS\" \
            -hwaccel vaapi -vaapi_device \"$VAAPI_DEVICE\" -hwaccel_output_format vaapi \
            -f libndi_newtek -analyzeduration \"$FFMPEG_ANALYZE_DURATION\" -probesize \"$FFMPEG_PROBE_SIZE\" \
            ${EXTRA_IPS:+-extra_ips \"$EXTRA_IPS\"} \
            -i \"$NDI_SOURCE\" \
            $FFMPEG_OUTPUT_THREADS \
            -vf 'format=nv12,hwupload' \
            $FFMPEG_VIDEO \
            $FFMPEG_AUDIO \
            -v $VERBOSE_FLAG \
            -f flv \"$STREAM_TARGET\""
    fi

    docker run --tty --init --rm --name "$CONTAINER_NAME" \
        --device "$VAAPI_DEVICE:$VAAPI_DEVICE" \
        "$DOCKER_IMAGE" bash -c "$ffmpeg_command" &
    FFMPEG_PID=$!
}

# Wrapper function to either start FFmpeg directly or inside Docker
start_ffmpeg() {
    if $RUNNING_IN_CONTAINER; then
        run_ffmpeg
    else
        run_docker_ffmpeg
    fi
}

trap 'kill_ffmpeg; exit' SIGINT SIGTERM

# Start FFmpeg and begin monitoring
#start_ffmpeg

if [[ "$NO_MONITORING" == "false" ]]; then
    monitor_ndi_stream
else
    start_ffmpeg
fi
