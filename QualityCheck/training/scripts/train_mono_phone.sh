#!/bin/bash -eu
#
# Copyright 2016 The Eyra Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# File author/s:
#     Robert Kjaran <robert@kjaran.com>
#     Matthias Petursson <oldschool01123@gmail.com> (the adding of the last couple of lines mostly)

# Generic LVCSR built using open/freely accessible data
# Prepares data for Marosijo module, outfile: local/marosijo.tgz. 

# For the Cleanup module, you have to uncomment stage 3 and run
# the last couple of lines.

nj=7
stage=0

LEXICON_PATH=$1
PHONEME_PATH=$2
model_path=$3

LANGDIR="data/lang"

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

if [ $stage -le 0 ]; then
    echo "Converting corpus to datadir"

    echo "Extracting features"
    steps/make_mfcc.sh \
        --nj $nj       \
        --mfcc-config conf/mfcc.conf \
        --cmd "$train_cmd"           \
        data/all exp/make_mfcc mfcc || utils/fix_data_dir.sh data/all

    steps/compute_cmvn_stats.sh \
        data/all exp/make_mfcc mfcc

    utils/fix_data_dir.sh \
        data/all

    ln -s all data/train
fi

if [ $stage -le 1 ]; then
    echo "Lang preparation"

    DICTDIR="data/local/dict"
    mkdir -p $DICTDIR
    touch $DICTDIR/extra_questions.txt
    echo "sil" > $DICTDIR/optional_silence.txt
    echo -e "sil\nspn" > $DICTDIR/silence_phones.txt
    cut -f 1 $PHONEME_PATH > $DICTDIR/nonsilence_phones.txt
    cp $LEXICON_PATH $DICTDIR/lexicon.txt
    echo -e '<UNK>\tspn' >> $DICTDIR/lexicon.txt

    utils/prepare_lang.sh \
        $DICTDIR "<UNK>" data/local/lang $LANGDIR

    utils/validate_lang.pl $LANGDIR || { echo "lang dir invalid" && exit 1; }
fi

if [ $stage -le 2 ]; then
    echo "Training mono system"
    steps/train_mono.sh    \
        --nj $nj           \
        --cmd "$train_cmd" \
        --totgauss 4000    \
        data/train         \
        data/lang          \
        exp/mono
fi


if [ $stage -le 3 ]; then
    #Fix for error: "chain-est-phone-lm: error while loading shared libraries: libcublas.so.8.0: cannot open shared object file: No such file or directory"
    module load cuda/8.0
    module load kaldi

    ./local/lang_add_phones.sh data/local/dict/lexiconp.txt data/lang data/newlang
    ./local/make_phone_bigram_fst.sh exp/mono data/newlang local/my_phone_fst
    ./local/prepare_model_folder.sh data/newlang exp/mono local/my_phone_fst 16000 "$LEXICON_PATH" $model_path

fi
