#! /bin/bash

# work around slurm placing scripts in var folder
if [[ $1 == "mode=sbatch" ]]; then
  base=/net/cephfs/home/mathmu/scratch/domain-robustness
else
  script_dir=`dirname "$0"`
  base=$script_dir/..
fi;

mkdir -p $base/shared_models

data=$base/data
scripts=$base/scripts

src=de
trg=en

MOSES=$base/tools/moses-scripts/scripts

bpe_num_operations=32000
bpe_vocab_threshold=10

for domain in all it koran law medical subtitles; do
    echo "domain: $domain"
    data=$base/data/$domain

    # normalize train, dev and test

    for corpus in train dev test; do
      cat $data/$corpus.$src | perl $MOSES/tokenizer/normalize-punctuation.perl > $data/$corpus.normalized.$src
      cat $data/$corpus.$trg | perl $MOSES/tokenizer/normalize-punctuation.perl > $data/$corpus.normalized.$trg
    done

    # tokenize train, dev and test

    for corpus in train dev test; do
      cat $data/$corpus.normalized.$src | perl $MOSES/tokenizer/tokenizer.perl -a -q -l $src > $data/$corpus.tokenized.$src
      cat $data/$corpus.normalized.$trg | perl $MOSES/tokenizer/tokenizer.perl -a -q -l $trg > $data/$corpus.tokenized.$trg
    done

    # clean length and ratio of train (only train!)

    $MOSES/training/clean-corpus-n.perl $data/train.tokenized $src $trg $data/train.tokenized.clean 1 80

    # learn truecase model on train (learn one model for each language)

    $MOSES/recaser/train-truecaser.perl -corpus $data/train.tokenized.clean.$src -model $base/shared_models/truecase-model.$domain.$src
    $MOSES/recaser/train-truecaser.perl -corpus $data/train.tokenized.clean.$trg -model $base/shared_models/truecase-model.$domain.$trg

    # apply truecase model to train, test and dev

    for corpus in train; do
      $MOSES/recaser/truecase.perl -model $base/shared_models/truecase-model.$domain.$src < $data/$corpus.tokenized.clean.$src > $data/$corpus.truecased.$src
      $MOSES/recaser/truecase.perl -model $base/shared_models/truecase-model.$domain.$trg < $data/$corpus.tokenized.clean.$trg > $data/$corpus.truecased.$trg
    done

    for corpus in dev test; do
      $MOSES/recaser/truecase.perl -model $base/shared_models/truecase-model.$domain.$src < $data/$corpus.tokenized.$src > $data/$corpus.truecased.$src
      $MOSES/recaser/truecase.perl -model $base/shared_models/truecase-model.$domain.$trg < $data/$corpus.tokenized.$trg > $data/$corpus.truecased.$trg
    done

done

data=$base/data

# file sizes
for domain in all it koran law medical subtitles; do
    for corpus in train dev test; do
      echo "corpus: "$corpus
      wc -l $data/$domain/$corpus.bpe.$src $data/$domain/$corpus.bpe.$trg
    done
done

# sanity checks

echo "At this point, please check that 1) file sizes are as expected, 2) languages are correct and 3) material is still parallel"
