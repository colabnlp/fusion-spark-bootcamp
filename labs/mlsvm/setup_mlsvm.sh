#!/bin/bash
set -e

SCRIPT_HOME="$(dirname "${BASH_SOURCE-$0}")"
LABS_TIP=${SCRIPT_HOME}/../..
LABS_TIP=`cd "$LABS_TIP"; pwd`

source "$LABS_TIP/myenv.sh"
cd ${SCRIPT_HOME}

if [ "$FUSION_PASS" == "" ]; then
  echo -e "ERROR: Must provide a valid password for Fusion user: $FUSION_USER"
  exit 1
fi

COLL=socialdata
echo "Creating the $COLL collection in Fusion"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" -d '{"id":"socialdata","solrParams":{"replicationFactor":1,"numShards":2,"maxShardsPerNode":2},"type":"DATA"}' \
  "$FUSION_API/apps/$BOOTCAMP/collections"

curl -u $FUSION_USER:$FUSION_PASS -X PUT -H "Content-type:application/json" -d @$COLL-default.json $FUSION_API/apps/$BOOTCAMP/index-pipelines/$COLL-default
curl -u $FUSION_USER:$FUSION_PASS -X PUT -H "Content-type:application/zip" -H "fusion-blob-modelType:spark-mllib" --data-binary @mllib-svm-sentiment.zip "$FUSION_API/apps/$BOOTCAMP/blobs/tweets_sentiment_svm?resourceType=model:ml-model"
curl -u $FUSION_USER:$FUSION_PASS -X PUT  $FUSION_API/apps/$BOOTCAMP/index-pipelines/$COLL-default/refresh

curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/vnd.lucidworks-document" -d '[
  {
    "id":"tweets-1",
    "fields": [
      { "name": "ts", "value": "2016-02-24T00:10:01Z" },
      { "name": "tweet_txt", "value": "I am really upset, angry, and unhappy about this election season! :-(" }
    ]
  }
]' "$FUSION_API/apps/$BOOTCAMP/index-pipelines/$COLL-default/collections/$COLL/index?echo=true"

curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/vnd.lucidworks-document" -d '[
  {
    "id":"tweets-2",
    "fields": [
      { "name": "ts", "value": "2016-02-24T00:10:01Z" },
      { "name": "tweet_txt", "value": "I am super excited that spring is finally here, yay! #happy" }
    ]
  }
]' "$FUSION_API/apps/$BOOTCAMP/index-pipelines/$COLL-default/collections/$COLL/index?echo=true"


