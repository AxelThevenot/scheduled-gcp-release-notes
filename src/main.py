
import os
import json
import yaml
from datetime import datetime, timezone

from jinja2 import Template
from httplib2 import Http
from markdown import markdown
from google.cloud import bigquery

# Retrieve the GCP_PROJECT from the reserved environment variables.
# more: https://cloud.google.com/functions/docs/configuring/env-var#python_37_and_go_111
GCP_PROJECT = os.environ['GCP_PROJECT']

def send_new_release_notes(request) -> tuple:
    '''
    Sends notifications about new GCP releases to a specified Google Chat webhook.

    Args:
        request (flask.Request): HTTP request object.
            args:
                test_timestamp (str, optional): Test timestamp for querying releases.

    Returns:
        tuple: Response from the webhook.
    '''

    test_timestamp = (request.get_json() or {}).get('test_timestamp')
    current_timestamp = test_timestamp or datetime.now(timezone.utc)

    # Set the path to the queries and configurations.
    context_path =  'conf.yaml'
    insert_query_template_path = os.path.join('queries', 'insert_new_releases.sql')
    request_query_template_path = os.path.join('queries', 'get_new_releases.sql')

    # Open those queries as Jinja Templates and open the configurations.
    with open(insert_query_template_path, 'r') as f:
        insert_query_template = Template(f.read())

    with open(request_query_template_path, 'r') as f:
        request_query_template =  Template(f.read())

    with open(context_path, 'r') as f:
        context = yaml.load(f, Loader=yaml.loader.SafeLoader)
        context.update({
            'GCP_PROJECT': GCP_PROJECT,
            'current_timestamp': current_timestamp,
        })

    # Render the queries with the configurations.
    insert_query = insert_query_template.render(**context)
    request_query = request_query_template.render(**context)

    bq_client = bigquery.Client()
    # Merge the full public release note in our dataset.
    _ = bq_client.query(insert_query).result() if not test_timestamp else 'No instert on testing.'
    # Request from the `_insertion_timestamp` the new releases.
    query_result = bq_client.query(request_query).result()

    response = _send_card_to_webhook(context['webhook_url'], query_result)
    return response


def _send_card_to_webhook(
        webhook_url: str,
        releases_notes_query_result: bigquery.table.RowIterator
) -> tuple:
    '''
    Sends a card containing GCP release notes to the specified webhook URL.

    Args:
        webhook_url (str): URL of the Google Chat webhook.
        releases_notes_query_result (bigquery.table.RowIterator): Query result containing release notes.

    Returns:
        tuple: Response from the webhook.
    '''

    def release_note_text(release_note: dict) -> str:
        '''
        Formats a single release note as a Google Chat Card textParagraph.
        https://developers.google.com/chat/api/guides/message-formats/cards

        Args:
            release_note (dict): A dictionary containing release note information.

        Returns:
            str: Formatted Google Chat Card for the release note.
        '''
        release_note_type = release_note['release_note_type'].capitalize()
        release_note_description = markdown(str(release_note['description']))
        return f'<b>{release_note_type}:<b/> {release_note_description}'

    def product_section(product: bigquery.Row) -> dict:
        '''
        Formats a product's release notes as a Google Chat Card Section.

        Args:
            product (bigquery.Row): An object containing product information and release notes.

        Returns:
            dict: Formatted Google Chat Card Section for the product's release notes.
        '''
        product_texts = [release_note_text(release_note) for release_note in product.release_notes]
        product_section = {
            'header': product.product_name,
            'widgets': [{'textParagraph': {'text': '<br><br>'.join(product_texts)}}],
        }
        return product_section

    # Format the release notes as card sections by product.
    releases_sections = [product_section(product) for product in releases_notes_query_result]

    # Do not send an empty card.
    if not releases_sections:
        return None

    # Complete the card and add its footer.
    footer_text = '👉 <a href="https://cloud.google.com/release-notes">GCP Official Release Note</a>'
    footer_section = {
        'header': 'To go Further',
        'widgets': [{ 'textParagraph': {'text': footer_text}}],
    }

    card = {
        'cards': [{
            'header': {'title': 'Daily GCP Release Note'},
            'sections': releases_sections + [footer_section],
        }]
    }

    # Of course, sends the card to the webhook then.
    response = Http().request(
        uri=webhook_url,
        method='POST',
        headers={'Content-Type': 'application/json; charset=UTF-8'},
        body=json.dumps(card),
    )
    return response
