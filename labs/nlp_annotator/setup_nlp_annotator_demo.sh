#!/bin/bash

SCRIPT_HOME="$(dirname "${BASH_SOURCE-$0}")"
LABS_TIP=${SCRIPT_HOME}/../..
LABS_TIP=`cd "$LABS_TIP"; pwd`

source "$LABS_TIP/myenv.sh"
check_for_core_site
cd ${SCRIPT_HOME}

if [ "$FUSION_PASS" == "" ]; then
  echo -e "ERROR: Must provide a valid password for Fusion user: $FUSION_USER"
  exit 1
fi

COLLECTION=nlp_annotator_demo
INDEX_PIPELINE=nlp_annotation_extraction
JOB_ID=nlp_annotation_extraction


echo -e "\nCreating new Fusion collection $COLLECTION in the $BOOTCAMP app ..."
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" -d '{"id":"nlp_annotator_demo","solrParams":{"replicationFactor":1,"numShards":4,"maxShardsPerNode":4},"type":"DATA"}' \
  "$FUSION_API/apps/$BOOTCAMP/collections?defaultFeatures=false"

echo -e "\nDownloading pretrained models from JohnSnow Lab into Fusion Blob store ..."
curl -o sparknlpNERDLModel.zip https://s3.amazonaws.com/auxdata.johnsnowlabs.com/public/models/ner_precise_en_1.7.0_2_1539623388047.zip
curl -u $FUSION_USER:$FUSION_PASS -X PUT -H "Content-type:application/zip" --data-binary @sparknlpNERDLModel.zip "$FUSION_API/apps/$BOOTCAMP/blobs/sparknlpNERDLModel.zip?resourceType=model:spark-nlp"
rm sparknlpNERDLModel.zip

curl -o sparknlpPOSModel.zip https://s3.amazonaws.com/auxdata.johnsnowlabs.com/public/models/pos_fast_en_1.6.1_2_1533853928168.zip
curl -u $FUSION_USER:$FUSION_PASS -X PUT -H "Content-type:application/zip" --data-binary @sparknlpPOSModel.zip "$FUSION_API/apps/$BOOTCAMP/blobs/sparknlpPOSModel.zip?resourceType=model:spark-nlp"
rm sparknlpPOSModel.zip

echo -e "\nCreating Spark job for NLP annotation extraction bootcamp lab"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" --data-binary @ner_extraction_job.json \
    "$FUSION_API/apps/$BOOTCAMP/spark/configurations"

curl -u $FUSION_USER:$FUSION_PASS -X PUT -H "Content-type:application/json" -d @insure_index_pipeline.json $FUSION_API/apps/$BOOTCAMP/index-pipelines/$INDEX_PIPELINE
curl -u $FUSION_USER:$FUSION_PASS -X PUT  $FUSION_API/apps/$BOOTCAMP/index-pipelines/$INDEX_PIPELINE/refresh

echo -e "\n Spark job created"

# Run Spark jobs for loading data
echo "Running Spark job ${JOB_ID}"
curl -u $FUSION_USER:$FUSION_PASS -X POST "$FUSION_API/jobs/spark:$JOB_ID/actions" -H "Content-type: application/json" \
  -d '{"action": "start", "comment": "Started by script"}'
poll_job_status $JOB_ID