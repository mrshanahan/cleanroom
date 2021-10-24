#!/bin/bash

PROGRAM=$(basename "$0")

printerr() {
    echo "${PROGRAM}: error: ${1}" >&2
}

printwarn() {
    echo "${PROGRAM}: warn: ${1}" >&2
}

usage() {
    echo "usage: ${PROGRAM} [list|new|remove] [<options>] <arguments>" >&2
}

assert() {
    if $1; then
        printerr "$2"
        exit 1
    fi
}

if [[ "$VAGRANT_TMP" == "" ]]
then
    #VAGRANT_TMP="/tmp/vagrant"
    VAGRANT_TMP=~/.cleanroom
fi

if [[ ! -d "$VAGRANT_TMP" ]]
then
    mkdir -p "$VAGRANT_TMP"
    if [[ $? != 0 ]]
    then
        printerr "failed to create Vagrant temp directory '$VAGRANT_TMP'"
        exit 1
    fi
fi

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    arg="$1"

    case $arg in
        # TODO: help should be contextual to commands
        help|-h|--help)
            usage
            exit 0
            ;;
        list|ls)
            if [[ "$COMMAND" != "" ]]; then
                printerr "too many commands (got '$1', already had '$COMMAND')"
                usage
                exit 1
            fi
            COMMAND="list"
            shift
            ;;
        new)
            if [[ "$COMMAND" != "" ]]; then
                printerr "too many commands (got '$1', already had '$COMMAND')"
                usage
                exit 1
            fi
            COMMAND="new"
            shift
            ;;
        remove|rm)
            if [[ "$COMMAND" != "" ]]; then
                printerr "too many commands (got '$1', already had '$COMMAND')"
                usage
                exit 1
            fi
            COMMAND="remove"
            shift
            ;;
        *)
            if [[ "$COMMAND" == "" ]]; then
                printerr "expected command (got '$1')"
                usage
                exit 1
            fi
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

escape_path() {
    patt='s/\([\\()\/]\)/\\\\\1/g'
    echo "$1" | sed -e "$patt"
}

case $COMMAND in
    list)
        ENVS=($(ls -1tr "$VAGRANT_TMP"))
        OUT_LINES=()
        WARN=0
        for x in "${ENVS[@]}"
        do
            METADATA_PATH="${VAGRANT_TMP}/${x}/metadata"
            SOURCE_PATH="<?>"
            if [[ ! -f "$METADATA_PATH" ]]
            then
                printwarn "could not find metadata file for ${x}"
                WARN=1
            else
                SOURCE_PATH="$(cat "$METADATA_PATH")"
            fi
            OUT_LINES+=("${x} ${SOURCE_PATH}")
        done
        if [[ $WARN -gt 0 ]]
        then
            echo "" >&2
        fi
        for line in "${OUT_LINES[@]}"
        do
            echo "$line"
        done
        ;;
    new)
        FILE=${POSITIONAL[0]}
        if [[ "$FILE" == "" ]]; then
            printerr "must provide file argument to new command"
            usage
            exit 1
        elif [[ ! -f "$FILE" ]]; then
            printerr "could not find file '$FILE'; ensure it exists & is a normal file type"
            usage
            exit 1
        fi

        SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
        TEMPLATE="${SCRIPT_DIR}/Vagrantfile.template"
        TMP_NAME=$(echo $RANDOM | md5sum | head -c 20)
        TMP_DIR="${VAGRANT_TMP}/${TMP_NAME}"
        mkdir -p "$TMP_DIR"
        TEMPLATE_TARGET="${TMP_DIR}/Vagrantfile"
        METADATA_TARGET="${TMP_DIR}/metadata"

        DATA_FILE="$(realpath "$FILE")"
        DATA_FILENAME="$(basename "$DATA_FILE")"
        DATA_FILEEXT="${DATA_FILENAME##*.}"
        TEMPLATE_PATTS="s/{{ data_file }}/$(escape_path "${DATA_FILE}")/g"
        TEMPLATE_PATTS="${TEMPLATE_PATTS}\ns/{{ data_filename }}/file.${DATA_FILEEXT}/g"
        cat "$TEMPLATE" | sed -f <(echo -e "$TEMPLATE_PATTS") >"$TEMPLATE_TARGET"
        echo "$DATA_FILE" >"$METADATA_TARGET"
        echo "Vagrant directory is: ${TMP_DIR}"

        OLD_DIR=$(pwd)
        cd "$TMP_DIR"
        vagrant up
        if [[ $? -gt 0 ]]; then
            vagrant destroy --force
            cd "$OLD_DIR"
            rm -rf "$TMP_DIR"
        fi
        ;;
    remove)
        set -- $POSITIONAL
        HAD_ERROR=0
        while [[ $# -gt 0 ]]; do
            arg="$1"
            NUM_MATCHING=$(ls -1 "${VAGRANT_TMP}" | grep --color=NEVER "^${arg}" | wc -l)
            if [[ $NUM_MATCHING == 1 ]]; then
                MATCHING=$(ls -1 "${VAGRANT_TMP}" | grep --color=NEVER "^${arg}")
                REMOVE_PATH="${VAGRANT_TMP}/${MATCHING}"
                OLD_DIR=$(pwd)
                cd "$REMOVE_PATH"
                vagrant destroy --force
                cd "$OLD_DIR"
                rm -rf "$REMOVE_PATH"
            elif [[ $NUM_MATCHING -gt 1 ]]; then
                printerr "ambiguous id '${arg}'; matches ${NUM_MATCHING} entries:"
                ls -1 "${VAGRANT_TMP}" | grep --color=NEVER "^${arg}" >&2
                HAD_ERROR=1
            else
                printerr "could not find cleanroom '${arg}'"
                HAD_ERROR=1
            fi
            shift
        done
        exit $HAD_ERROR
        ;;
esac

