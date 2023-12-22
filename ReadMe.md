# Whisper-Bench

An in progress benchmark to compare various Whisper implementations in terms of performance and accuracy.
Right now, the only thing it will benchmark is your network connection, so I'd advise checking back later.

## Setting up

At the time of writing, here are the things you need pre-installed:
- rustc, cargo
- git
- a version of python between 3.9 and 3.11
- ffmpeg

hyperfine is used to run the benchmarks, and is installed automatically by the setup script if it is not already installed.

## data used

currently the audio data downloaded is the complete ami dataset, I'm looking for a smaller dataset that can be used for evalutation and hopefully doesn't require transcoding to be usable by all implementations.

## Running the benchmarks

TODO

## Adding a new implementation

TODO

