#!/usr/bin/env python3
import requests
import os
import argparse
from collections import defaultdict
import gspread
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Fetch SonarQube issues and update Google Sheets.')
parser.add_argument('--credentials_file', type=str, help='Path to the Google API credentials file.')
parser.add_argument('--token_file', type=str, help='Path to the token file.')
parser.add_argument('--server_url', type=str, help='SonarQube server URL.')
parser.add_argument('--auth_token', type=str, help='SonarQube authentication token.')
args = parser.parse_args()

# Configuration JSON object for multiple repositories
config = [
    {
        "sonarqube_project_key": "com.aol.obi:mCareNew",
        "git_repo_url": "https://github.com/ms-obi/obi_mcare_be",
        "branch_name": "pipeline"
    },
    {
        "sonarqube_project_key": "com.aol.obi:scs",
        "git_repo_url": "https://git.ouryahoo.com/obi/obi_scs",
        "branch_name": "main"
    },
    {
        "sonarqube_project_key": "com.aol.obi:OBI_CCS_PIPELINE",
        "git_repo_url": "https://git.ouryahoo.com/obi/obi_ccs",
        "branch_name": "main"
    }
    # Add more repositories as needed
]

# Configuration
server_url = args.server_url or os.getenv("SONARQUBE_SERVER_URL", "https://sonar.subscriptions-obi-fe-aws-dev.aws.oath.cloud")
auth_token = args.auth_token or os.getenv("SONARQUBE_AUTH_TOKEN")

if not auth_token:
    raise ValueError("Authentication token not found. Please set the SONARQUBE_AUTH_TOKEN environment variable or pass it as a parameter.")

# Google Sheets setup using OAuth 2.0
SCOPES = ["https://www.googleapis.com/auth/spreadsheets", "https://www.googleapis.com/auth/drive.file"]

creds = None

# Retrieve credentials and token file paths from environment variables or parameters
credentials_file = args.credentials_file or os.getenv("GOOGLE_CREDENTIALS_FILE")
token_file = args.token_file or os.getenv("GOOGLE_TOKEN_FILE")

# Check if the credentials.json file exists
if not os.path.exists(credentials_file):
    raise FileNotFoundError(f"'{credentials_file}' not found. Please create it by following the instructions to set up Google API credentials.")

# The file token.json stores the user's access and refresh tokens, and is
# created automatically when the authorization flow completes for the first time.
if os.path.exists(token_file):
    creds = Credentials.from_authorized_user_file(token_file, SCOPES)

# If there are no (valid) credentials available, let the user log in.
if not creds or not creds.valid:
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    else:
        # Initiate the OAuth2 flow to get new credentials
        flow = InstalledAppFlow.from_client_secrets_file(credentials_file, SCOPES)
        creds = flow.run_local_server(port=0)
    # Save the credentials for the next run
    with open(token_file, 'w') as token:
        token.write(creds.to_json())

gc = gspread.authorize(creds)

for repo_config in config:
    project_key = repo_config.get("sonarqube_project_key")
    git_repo_url = repo_config.get("git_repo_url")
    branch_name = repo_config.get("branch_name")

    if not project_key or not git_repo_url or not branch_name:
        raise ValueError("Configuration for SonarQube project key, Git repository URL, or branch name is missing.")

    # Open or create the Google Sheet
    spreadsheet_title = project_key + " SonarQube Issues"
    try:
        spreadsheet = gc.open(spreadsheet_title)
    except gspread.exceptions.SpreadsheetNotFound:
        spreadsheet = gc.create(spreadsheet_title)

    # Fetch issues
    issues_by_language = defaultdict(list)
    page = 1
    total_issues_fetched = 0
    max_issues = 10000  # Set a limit to avoid exceeding SonarQube's limit

    while total_issues_fetched < max_issues:
        # Prepare request parameters
        params = {
            "componentKeys": project_key,
            "statuses": "OPEN,CONFIRMED,REOPENED",
            "facets": "languages",
            "ps": 500,
            "p": page,
            "s": "FILE_LINE",
            "severities": "CRITICAL,BLOCKER"  # Filter for CRITICAL and BLOCKER severities
        }
        
        # Make the request
        response = requests.get(
            f"{server_url}/api/issues/search",
            params=params,
            auth=(auth_token, '')  # Use Basic Auth with username as auth_token and password as blank
        )
        
        # Print request and response headers
        print("Request Headers:", response.request.url)
        print("Response Headers:", response.headers)
        
        try:
            response.raise_for_status()  # Ensure we catch HTTP errors
        except requests.exceptions.HTTPError as e:
            print(f"HTTP error occurred: {e}")  # Print the HTTP error
            print(f"Response content: {response.content}")  # Print the response content for more details
            break  # Exit the loop or handle the error as needed

        data = response.json()
        issues = data.get("issues", [])
        facets = data.get("facets", [])
        
        # Extract language information from facets
        language_map = {}
        for facet in facets:
            if facet.get("property") == "languages":
                for value in facet.get("values", []):
                    language_map[value["val"]] = value["val"]

        for issue in issues:
            # Attempt to get language from the issue, fallback to rule-based extraction
            language = issue.get("language", "unknown")
            if language == "unknown":
                rule = issue.get("rule", "")
                if ":" in rule:
                    language = rule.split(":")[0]
            language = language_map.get(language, language)  # Use language map if available
            issues_by_language[language].append(issue)
        
        total_issues_fetched += len(issues)
        
        if not issues or total_issues_fetched >= max_issues:
            break
        page += 1

    # Update Google Sheets with a tab for each language
    fieldnames = ["key", "severity", "type", "rule", "message", "status", "line", "component", "git_url"]

    for language, issues in issues_by_language.items():
        # Create or select the worksheet for the language
        try:
            worksheet = spreadsheet.worksheet(language)
        except gspread.exceptions.WorksheetNotFound:
            worksheet = spreadsheet.add_worksheet(title=language, rows="5000", cols="9")
            worksheet.append_row(fieldnames)

        existing_records = worksheet.get_all_records()
        existing_records_dict = {record['key']: record for record in existing_records}

        current_keys = set()
        updates = []
        new_record_start_index = len(existing_records) + 2  # Start index for new records

        for issue in issues:
            issue_data = {field: issue.get(field, '') for field in fieldnames[:-1]}  # Exclude git_url for now
            key = issue_data['key']
            current_keys.add(key)
            
            # Generate Git URL for the issue
            component = issue_data.get('component', '')
            line = issue_data.get('line', '')
            # Extract the file path from the component
            file_path = component.split(':', 2)[-1]
            git_url = f"{git_repo_url}/blob/{branch_name}/{file_path}#L{line}"
            issue_data['git_url'] = git_url
            
            if key in existing_records_dict:
                # Update existing record, preserving user-added fields
                row_index = existing_records.index(existing_records_dict[key]) + 2  # +2 to account for header and 0-index
                existing_row = existing_records_dict[key]  # Use the dictionary to get the existing row
                updated_row = [issue_data.get(field, existing_row.get(field, '')) for field in fieldnames]
                updates.append({
                    "range": f'A{row_index}:I{row_index}',
                    "values": [updated_row]
                })
            else:
                # Add new record, only SonarQube fields
                new_row = [issue_data.get(field, '') for field in fieldnames]
                updates.append({
                    "range": f'A{new_record_start_index}:I{new_record_start_index}',
                    "values": [new_row]
                })
                new_record_start_index += 1  # Increment for the next new record

        # Perform batch update
        if updates:
            worksheet.batch_update(updates)

        # Mark resolved issues
        for record in existing_records:
            if record['key'] not in current_keys:
                row_index = existing_records.index(record) + 2
                worksheet.update_cell(row_index, fieldnames.index('status') + 1, 'RESOLVED')
