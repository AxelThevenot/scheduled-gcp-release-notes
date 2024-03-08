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
    --gen2 \
    --project=${project_id} \
    --region=us-central1 \
    --trigger-http \
    --runtime=python312 \
    --set-env-vars GCP_PROJECT=${project_id} \
    --source=./src \
    --entry-point=send_new_release_notes

# Create the SA
gcloud iam service-accounts create release-note-scheduler \
    --project=${project_id} \
    --display-name "Release Note GCP Scheduler"

gcloud projects add-iam-policy-binding ${project_id} \
    --member=serviceAccount:release-note-scheduler@${project_id}.iam.gserviceaccount.com \
    --role=roles/cloudfunctions.invoker

gcloud projects add-iam-policy-binding ${project_id} \
    --member=serviceAccount:release-note-scheduler@${project_id}.iam.gserviceaccount.com \
    --role=roles/run.invoker

# Create the Cloud Scheduler trigger.
gcloud scheduler jobs create http google-cloud-release-notes-schedule \
    --project=${project_id} \
    --location=us-central1 \
    --schedule="${schedule}" \
    --uri=https://us-central1-${project_id}.cloudfunctions.net/google-cloud-release-notes-function \
    --oidc-service-account-email=release-note-scheduler@${project_id}.iam.gserviceaccount.com \
    --oidc-token-audience=https://us-central1-${project_id}.cloudfunctions.net/google-cloud-release-notes-function \
    --http-method=POST \
    --headers="Content-Type=application/json" \
    --message-body="{}" \
    --time-zone=${time_zone}


# Force run the Cloud Scheduler to initialize the table.
gcloud scheduler jobs run google-cloud-release-notes-schedule --location=us-central1 --project=${project_id}
