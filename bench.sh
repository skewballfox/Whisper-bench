#!/usr/bin/bash

top_dir=$(git rev-parse --show-toplevel)
echo $top_dir
model_path=$top_dir/models
data_path=$top_dir/data
results_path=$top_dir/results

mkdir -p $model_path $data_path $results_path/{bench/{md,json},output}/{cpu,gpu} $top_dir/bin
# this is just laziness
rm -r $results_path/output/md

# need a version both whisper and ctranslate2 can use
python_cmd=$(compgen -c python3. | grep -E '^python3.(9|1[0,1])$' | sort -r | head -n 1)
echo $python_cmd

if [[ "$python_cmd" == "" ]]; then
    echo "a compatible python version was not found"
    echo "please install python 3.9, 3.10, or 3.11"
    exit 1
fi

# Clone the repositories if they don't exist

if [ ! -d "original" ]; then
    git clone https://github.com/openai/whisper original
fi

if [ ! -d "ctranslate2" ]; then
    git clone https://github.com/Softcatala/whisper-ctranslate2 ctranslate2
fi

if [ ! -d "burn" ]; then
    git clone https://github.com/Gadersd/whisper-burn burn
fi

if [ ! -d "candle" ]; then
    git clone https://github.com/huggingface/candle.git candle
fi

# if [ ! -d "tract"]; then
#     git clone https://github.com/igor-yusupov/rusty-whisper/
# fi

# # Clone the models if they don't exist
# if [ ! -d "$model_path/whisper-medium.en" ]; then
#     git -C $model_path lfs clone https://huggingface.co/openai/whisper-medium.en
# fi

# if [ ! -d "$model_path/faster-whisper-medium.en" ]; then
#     git -C $model_path lfs clone https://huggingface.co/Systran/faster-whisper-medium.en
# fi

# Clone the data if it doesn't exist
if [ ! -d "$data_path/ami" ]; then
    # curl -X GET \
    #     -o $data_path/ami.tar.gz \
    #     "https://datasets-server.huggingface.co/first-rows?dataset=edinburghcstr%2Fami&config=ihm&split=validation"

    git -C $data_path lfs clone https://huggingface.co/datasets/edinburghcstr/ami
fi

for group in ihm sdm; do
    output_dir="$data_path/ami_unpacked/$group"
    mkdir -p $output_dir
    for file in $data_path/ami/audio/$group/eval/*.tar.gz; do
        dirname=$(basename "${file%.tar.gz}")
        # Check if the file is already unpacked
        if ! [[ -d $output_dir/$dirname ]] || [[ -n "$(find "$output_dir/$dirname" -maxdepth 0 -type d -empty 2>/dev/null)" ]]; then
            # Unpack the tar.gz file into the unpacked directory
            tar -xzf "$file" -C "$output_dir"
        fi
    done
done

# install hyperfine if it doesn't exist
if ! command -v hyperfine &>/dev/null; then
    cargo install hyperfine
fi

# setup the virtual environment for the python packages if they don't exist
venv_check() {
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        deactivate
    fi
}

setup_venv() {
    local project_dir=$1
    venv_check
    if [ ! -d "$project_dir/.venv" ]; then
        $python_cmd -m venv $project_dir/.venv
        source $project_dir/.venv/bin/activate
        pip install $project_dir/.
        deactivate
    fi

}

setup_venv original
setup_venv "ctranslate2"

if [[ -n "$(find "$data_path/samples" -maxdepth 0 -type d -empty 2>/dev/null)" ]]; then
    mkdir -p $data_path/samples

    for audio_file in $(find "$data_path/ami_unpacked/ihm/EN2002a" -maxdepth 1 -type f -name "*.wav" | head -n 10 | tr '\n' ' '); do
        echo "$audio_file"
        SAMPLE_RATE=16000
        #from https://github.com/openai/whisper/blob/main/whisper/audio.py#L45C5-L55C6
        ffmpeg -nostdin -threads 0 -i "$audio_file" -f s16le -ac 1 -acodec pcm_s16le -ar $SAMPLE_RATE $data_path/samples/$(basename "$audio_file")
        #output=$data_path/samples/$(basename "$audio_file")
        #echo $output
        #sox "$audio_file" -r 16000 $output
    done

fi
ihm_files=$(find "$data_path/samples" -maxdepth 1 -type f -name "*.wav" | head -n 10 | tr '\n' ',')
#toss the last comma
ihm_files=${ihm_files::-1}
# ihm_files=$(find "$data_path/ami_unpacked/ihm/EN2002a" -maxdepth 1 -type f -name "*.wav" | head -n 10 | tr '\n' ',') # | sed "s!$data_path/ami_unpacked/ihm/EN2002a/!!g")
# #toss the last comma
# ihm_files=${ihm_files::-1}
#echo $ihm_files

hyperfine_bench() {
    local derby_contender=$(basename $1)
    local command=$2
    local bench_results_path=$results_path/bench/json/$3/$derby_contender.json
    echo $command
    hyperfine --warmup 3 --runs 10 -N \
        --export-json $results_path/bench/json/$device/$derby_contender.json --export-markdown $results_path/bench/md/$device/$derby_contender.md \
        --parameter-list input_file $ihm_files "${command}"
}

bench_python() {
    venv_check
    local project_dir=$1
    local contender=$(basename $project_dir)
    local command=$2
    local model_directory=$3
    local model_name=$4
    local device=$5
    source $project_dir/.venv/bin/activate
    command="python -m $command {input_file} --device cpu --model $model_name --model_dir $model_directory --output_dir $results_path/output/$device/$contender --output_format json 2&>1 >/dev/null"
    hyperfine_bench $project_dir "${command}" $device

}

rust_config() {
    local project_dir=$1
    local binary=$2
    shift 2
    local flags=$@
    cd $project_dir
    cargo build --release
    cp target/release/$binary $top_dir/bin/
    cd $top_dir

}

bench_python "${top_dir}/original" "whisper" "${model_path}" "medium.en" "cpu"
bench_python "${top_dir}/ctranslate2" "whisper-ctranslate2" "${model_path}" "medium.en" "cpu"
#rust_config "${top_dir}/burn" "transcribe" --features wgpu-backend
rust_config "${top_dir}/burn" "/examples/whisper"
#transcribe <model name> <audio file> <lang> <transcription file>
#hyperfine_bench "${top_dir}/burn" "$top_dir/bin/transcribe medium.en {input_file} en $results_path/output/cpu/burn" "cpu"
#where is the model being cached?
hyperfine_bench "${top_dir}/candle" "$top_dir/bin/whisper --model medium.en --language en --input {input_file} --input {input_file}" "cpu"
