DECLARE max_timestamp TIMESTAMP;  -- Only used for first init.
SET max_timestamp = (
  SELECT
    MAX(_insertion_timestamp)
  FROM `{{ GCP_PROJECT }}.google_cloud_release_notes.release_notes`
);

MERGE `{{ GCP_PROJECT }}.google_cloud_release_notes.release_notes` T
USING (
  SELECT
    description,
    release_note_type,
    published_at,
    CAST(product_id AS STRING) AS `product_id`,  -- As STRING for convenience.
    product_name,
    product_version_name,
    IF(  -- First init with the real `published_at`.
      max_timestamp IS NULL,
      TIMESTAMP(published_at),
      CURRENT_TIMESTAMP()
    )                          AS `_insertion_timestamp`,
  FROM `bigquery-public-data.google_cloud_release_notes.release_notes`
) S
ON TRUE
  AND S.description          IS NOT DISTINCT FROM T.description
  AND S.release_note_type    IS NOT DISTINCT FROM T.release_note_type
  AND S.published_at         IS NOT DISTINCT FROM T.published_at
  AND S.product_id           IS NOT DISTINCT FROM T.product_id
  AND S.product_name         IS NOT DISTINCT FROM T.product_name
  AND S.product_version_name IS NOT DISTINCT FROM T.product_version_name
WHEN NOT MATCHED BY TARGET THEN
  INSERT ROW
;
