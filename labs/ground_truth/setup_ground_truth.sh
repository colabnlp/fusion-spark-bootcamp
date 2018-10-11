#!/bin/bash

if [ ! -f core-site.xml ]; then
   echo "ERROR: core-site.xml does not exist. Copy core-site.xml.template to core-site.xml and fill in AWS creds"
   exit 1
fi

while [ -h "$SETUP_SCRIPT" ] ; do
  ls=`ls -ld "$SETUP_SCRIPT"`
  # Drop everything prior to ->
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    SETUP_SCRIPT="$link"
  else
    SETUP_SCRIPT=`dirname "$SETUP_SCRIPT"`/"$link"
  fi
done

LABS_TIP=`dirname "$SETUP_SCRIPT"`/../..
LABS_TIP=`cd "$LABS_TIP"; pwd`

source "$LABS_TIP/myenv.sh"

if [ "$FUSION_PASS" == "" ]; then
  echo -e "ERROR: Must provide a valid password for Fusion user: $FUSION_USER"
  exit 1
fi

cp core-site.xml $FUSION_HOME/apps/spark-dist/conf

COLLECTION="groundtruth_demo"
APP_URL="$FUSION_API/apps/$COLLECTION"
PRODUCTS_SPARK_JOB_ID="load_products_spark"
SIGNALS_SPARK_JOB_ID="load_signals_spark"
EXPERIMENT="groundtruth_demo-exp"
GROUND_TRUTH_SPARK_JOB_ID="${EXPERIMENT}-groundTruth-bb-relevance"
RANKING_METRICS_SPARK_JOB_ID="${EXPERIMENT}-rankingMetrics-bb-relevance"

curl -s -u $FUSION_USER:$FUSION_PASS -XPOST -H "Content-type:application/json" -d '{"id":"groundtruth_demo", "name":"groundtruth_demo","description":"dev","properties":{"headerImageName":"headerImage6","tileColor":"apps-darkblue"}}' "$FUSION_API/apps"
echo -e "\nCreated new Fusion app: $COLLECTION"
curl -u $FUSION_USER:$FUSION_PASS "$FUSION_API/apps/$COLLECTION"

# Poll the job status until it is done ...
poll_job_status () {
    if [ -z "$1" ]                           # Is parameter #1 zero length?
    then
      echo "Job ID not passed to function for status check"  # Or no parameter passed.
      exit 1
    fi
    JOB_ID=$1

    echo -e "\nWill poll the $job_id job status for up to 3 minutes to wait for training to complete."
    export PYTHONIOENCODING=utf8
    sleep 10
    COUNTER=0
    MAX_LOOPS=36
    JOB_STATUS=""
    while [  $COUNTER -lt $MAX_LOOPS ]; do
      JOB_STATUS=$(curl -u $FUSION_USER:$FUSION_PASS -s "$FUSION_API/spark/jobs/$JOB_ID" | python -c "import sys, json; print(json.load(sys.stdin)['state'])")
      echo "Job status for $JOB_ID is: ${JOB_STATUS}"
      if [ "running" == ${JOB_STATUS} ] || [ "starting" == ${JOB_STATUS} ]; then
        sleep 10
        let COUNTER=COUNTER+1
      else
        let COUNTER=999
      fi
    done
    if [ "finished" != ${JOB_STATUS} ]; then
      JOB_STATUS_RESP=$(curl -u $FUSION_USER:$FUSION_PASS -s "$FUSION_API/spark/jobs/$JOB_ID")
      echo "Job ${JOB_ID} failed with status ${JOB_STATUS_RESP}. Exiting setup script"
      exit 1
    fi
}

# Create Spark job configurations
echo "Creating Spark job for loading products"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" --data-binary @load_products_spark_job.json \
  "$APP_URL/spark/configurations"

echo "Creating Spark job for loading signals"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" --data-binary @load_signals_spark_job.json \
  "$APP_URL/spark/configurations"

# Run Spark jobs for loading data
echo "Running Spark job ${PRODUCTS_SPARK_JOB_ID}"
curl -u $FUSION_USER:$FUSION_PASS -X POST "$FUSION_API/jobs/spark:$PRODUCTS_SPARK_JOB_ID/actions" -H "Content-type: application/json" \
  -d '{"action": "start", "comment": "Started by script"}'
poll_job_status $PRODUCTS_SPARK_JOB_ID

echo "Running Spark job ${SIGNALS_SPARK_JOB_ID}"
curl -u $FUSION_USER:$FUSION_PASS -X POST "$FUSION_API/jobs/spark:$SIGNALS_SPARK_JOB_ID/actions" -H "Content-type: application/json" \
  -d '{"action": "start", "comment": "Started by script"}'
poll_job_status $SIGNALS_SPARK_JOB_ID

# Run aggregation explicitly
curl -u $FUSION_USER:$FUSION_PASS -X POST "$FUSION_API/jobs/spark:${COLLECTION}_click_signals_aggregation/actions" -H "Content-type: application/json" \
  -d '{"action": "start", "comment": "Started by script"}'
poll_job_status ${COLLECTION}_click_signals_aggregation

# Create pipelines
echo "Creating pipeline with no recs"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" --data-binary @query_pipeline_norecs.json \
  "$APP_URL/query-pipelines"

# Create an experiment and activate it
echo "Creating an experiment"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" --data-binary @experiment.json \
  "$APP_URL/experiments"

echo "Activating experiment"
curl -u $FUSION_USER:$FUSION_PASS -X POST -H "Content-type:application/json" --data-binary @experiment.json \
  "$APP_URL/experiments/${EXPERIMENT}/job"

# Run ground truth, ranking metric jobs
echo "Running Ground Truth Spark job"
curl -u $FUSION_USER:$FUSION_PASS -X POST "$FUSION_API/jobs/spark:${GROUND_TRUTH_SPARK_JOB_ID}/actions" -H "Content-type: application/json" \
  -d '{"action": "start", "comment": "Started by script"}'
poll_job_status ${GROUND_TRUTH_SPARK_JOB_ID}

echo "Running Ranking metrics Spark job"
curl -u $FUSION_USER:$FUSION_PASS -X POST "$FUSION_API/jobs/spark:${RANKING_METRICS_SPARK_JOB_ID}/actions" -H "Content-type: application/json" \
  -d '{"action": "start", "comment": "Started by script"}'
poll_job_status ${RANKING_METRICS_SPARK_JOB_ID}

echo "Stop experiment"
curl -u $FUSION_USER:$FUSION_PASS -X DELETE -H "Content-type:application/json" "$APP_URL/experiments/${EXPERIMENT}/job"
