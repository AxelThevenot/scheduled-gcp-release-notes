#!/bin/bash

if [ $# -ne 3 ] ; then
    echo "You must provide a project ID. Example: '${0} project_id schedule time_zone'"
    exit 1
else
    project_id=$1
    schedule=$2
    time_zone=$3
fi

# Create BigQuery dataset.
bq --location=US mk \
    --dataset \
    ${project_id}:google_cloud_release_notes

# Create BigQuery Table.
bq --project_id=${project_id} mk \
   --table \
   google_cloud_release_notes.release_notes \
   ./schemas/release_notes.json

# Create Cloud Function.
gcloud functions deploy google-cloud-release-notes-function \
    --project=${project_id} \
    --region=us-central1 \
    --trigger-http \
    --runtime=python37 \
    --source=./src \
    --entry-point=send_new_release_notes

# Create the Cloud Scheduler trigger.
gcloud scheduler jobs create http google-cloud-release-notes-schedule \
    --location=us-central1 \
    --schedule="${schedule}" \
    --uri=https://us-central1-${project_id}.cloudfunctions.net/google-cloud-release-notes-function \
    --http-method=POST \
    --time-zone=${time_zone}


# Force run the Cloud Scheduler to initialize the table.
gcloud scheduler jobs run google-cloud-release-notes-schedule --location=us-central1
