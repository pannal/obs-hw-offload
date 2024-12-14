#!/bin/bash
SH_VERSION=0.0.4b
echo "stream.sh, version ${SH_VERSION}"

set -o pipefail

# Default values
ENV_FILE="${ENV_FILE:-".env"}" # Default ENV_FILE path
FFMPEG_INPUT_THREADS="${FFMPEG_INPUT_THREADS:-4}"
FFMPEG_OUTPUT_THREADS="${FFMPEG_OUTPUT_THREADS:+"-threads $FFMPEG_OUTPUT_THREADS"}"
FFMPEG_PARAMS="${FFMPEG_PARAMS:-""}"
VIDEO_CODEC="${VIDEO_CODEC:-"hevc_vaapi"}"
VIDEO_BITRATE="${VIDEO_BITRATE:-"8M"}"
FFMPEG_NATIVE_FRAMERATE="${FFMPEG_NATIVE_FRAMERATE:-}"
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

# Enhanced logging function
log() {
    local level="${1^^}"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[${level}] ${timestamp}: ${message}" >&2
}

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
  -c, --video-codec STRING      Set video codec (default: hevc_vaapi).
  -b, --video-bitrate STRING    Set video bitrate (default: 8M).
  -nf, --native-framerate       Read input at the native frame rate (set FFmpeg "-re" parameter).
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
  Order of precedence: command-line arguments > environment file > environment variables.

  Variables: ENV_FILE, FFMPEG_INPUT_THREADS, FFMPEG_OUTPUT_THREADS, FFMPEG_PARAMS, VIDEO_CODEC, VIDEO_BITRATE,
             FFMPEG_NATIVE_FRAMERATE, FFMPEG_VIDEO, FFMPEG_AUDIO, FFMPEG_ANALYZE_DURATION, FFMPEG_PROBE_SIZE, NDI_SOURCE,
             EXTRA_IPS, VAAPI_DEVICE, STREAM_TARGET, CHECK_INTERVAL, CHECK_INTERVAL_DOWN, VERBOSE_FLAG, RESTART_FFMPEG,
             NO_MONITORING, CONTAINER_NAME, CHECK_CONTAINER_NAME, DOCKER_IMAGE
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

# Create a function to load and validate configuration
load_configuration() {
    # Load environment file if exists
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Loading environment variables from $ENV_FILE"
        set -o allexport
        source "$ENV_FILE"
        set +o allexport
    fi

    # Set default values with more explicit fallback
    NDI_SOURCE="${NDI_SOURCE:?Error: NDI source must be set}"
    STREAM_TARGET="${STREAM_TARGET:?Error: Stream target must be set}"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -n|--ndi-source) NDI_SOURCE="$2"; shift 2 ;;
        -x|--extra-ips) EXTRA_IPS="$2"; shift 2 ;;
        -d|--vaapi-device) VAAPI_DEVICE="$2"; shift 2 ;;
        -s|--stream-target) STREAM_TARGET="$2"; shift 2 ;;
        -v|--verbose) VERBOSE_FLAG="verbose"; shift ;;
        -c|--video-codec) VIDEO_CODEC="$2"; shift 2 ;;
        -b|--video-bitrate) VIDEO_BITRATE="$2"; shift 2 ;;
        -nf|--native-framerate) FFMPEG_NATIVE_FRAMERATE="-re"; shift ;;
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
        *) log "ERROR" "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Validate input parameters
validate_inputs() {
    # Check numeric inputs
    [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || {
        log "ERROR" "Error: Check interval must be a non-negative integer" >&2
        exit 1
    }
    [[ "$CHECK_INTERVAL_DOWN" =~ ^[0-9]+$ ]] || {
        log "ERROR" "Error: Check interval down must be a non-negative integer" >&2
        exit 1
    }
}

# Construct FFMPEG_VIDEO dynamically
if [[ -z "$FFMPEG_VIDEO" ]]; then
    FFMPEG_VIDEO="-c:v ${VIDEO_CODEC} -b:v ${VIDEO_BITRATE} -rc_mode CBR"
fi

# Function to monitor the NDI stream
monitor_ndi_stream() {
    while true; do
        if [[ -n "$NDI_SOURCE" ]]; then
            # invoke FFprobe
            "${FFPROBE_BASE[@]}" -f libndi_newtek ${EXTRA_IPS:+-extra_ips "$EXTRA_IPS"} -i "$NDI_SOURCE" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                log "INFO" "NDI stream is down."
                kill_ffmpeg
                if [[ ! "$RESTART_FFMPEG" == "true" ]]; then
                    log "INFO" "Not restarting FFmpeg."
                    exit 0
                fi
                log "INFO" "Waiting for NDI stream"
                USE_CHECK_INTERVAL=${CHECK_INTERVAL_DOWN}
            else
                # NDI stream is (still) up, run FFmpeg immediately if requested and not already running
                if [[ -z "$FFMPEG_PID" || ( -n "$FFMPEG_PID" && "$(ps --pid "$FFMPEG_PID" > /dev/null 2>&1)" -ne 0 ) ]]; then
                    log "INFO" "NDI stream is up, starting immediately."
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
            log "INFO" "Killing FFmpeg process (PID: $FFMPEG_PID)..."
            kill -9 "$FFMPEG_PID" >/dev/null 2>&1 || log "ERROR" "No running FFmpeg process to stop."
            wait "$FFMPEG_PID" 2>/dev/null
        else
            log "INFO" "Killing Docker container ($CONTAINER_NAME, $FFMPEG_PID)..."
            docker kill "$CONTAINER_NAME" >/dev/null 2>&1 || log "ERROR"  "No running container to stop."
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi
        FFMPEG_PID=""
    fi
}

build_ffmpeg_command() {
    if [[ -n "$FFMPEG_PARAMS" ]]; then
        echo "ffmpeg $FFMPEG_PARAMS"
        return
    fi

    local base_command="ffmpeg \
        -fflags nobuffer $FFMPEG_NATIVE_FRAMERATE -threads \"$FFMPEG_INPUT_THREADS\" \
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

    echo "$base_command"
}

run_ffmpeg() {
    local command=$(build_ffmpeg_command)

    if [[ "$NO_MONITORING" == "true" ]]; then
        eval "$command"
    else
        eval "$command &"
        FFMPEG_PID=$!
    fi
}

run_docker_ffmpeg() {
    local ffmpeg_command=$(build_ffmpeg_command)

    local docker_command=("docker" "run" "--tty" "--init" "--rm" "--name" "$CONTAINER_NAME"
        "--device" "$VAAPI_DEVICE:$VAAPI_DEVICE"
        "$DOCKER_IMAGE" "bash" "-c" "$ffmpeg_command")

    if [[ "$NO_MONITORING" == "true" ]]; then
        "${docker_command[@]}"
    else
        "${docker_command[@]}" &
        FFMPEG_PID=$!
    fi
}


# Wrapper function to either start FFmpeg directly or inside Docker
start_ffmpeg() {
    if $RUNNING_IN_CONTAINER; then
        run_ffmpeg
    else
        run_docker_ffmpeg
    fi
}

main() {
    # Load and validate configuration
    load_configuration

    # Validate inputs
    validate_inputs

    # Set up signal handling
    trap 'kill_ffmpeg; exit' SIGINT SIGTERM

    # Run monitoring or direct startup
    if [[ "$NO_MONITORING" == "false" ]]; then
        monitor_ndi_stream
    else
        start_ffmpeg
    fi
}

# Call main function with all arguments
main "$@"