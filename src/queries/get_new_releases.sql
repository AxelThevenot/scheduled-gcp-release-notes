SELECT
  product_name,
  ARRAY_AGG(
    STRUCT(
      release_note_type AS `release_note_type`,
      description       AS `description`
    )
  ) AS `release_notes`
FROM `{{ GCP_PROJECT }}.google_cloud_release_notes.release_notes`
WHERE TRUE
  AND _insertion_timestamp >= TIMESTAMP('{{ current_timestamp }}')
  AND release_note_type IN (
    '{{ release_note_types | join("\',\n    \'") }}'
  )
  AND product_name IN (
    '{{ product_names | join("\',\n    \'") }}'
  )
GROUP BY
  product_name
ORDER BY
  product_name
