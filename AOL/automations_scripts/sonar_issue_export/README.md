# README for sonarResults.py

## Overview

`sonarResults.py` is a Python script designed to fetch issues from SonarQube for multiple repositories and update a Google Sheet with the issues categorized by programming language. This tool is useful for tracking and managing code quality issues across different projects.

## Prerequisites

Before running the script, ensure you have the following prerequisites:

1. **Python 3.x**: Make sure Python 3.x is installed on your system. You can download it from [python.org](https://www.python.org/downloads/).

2. **Pip**: Ensure you have pip installed to manage Python packages. It usually comes with Python installations.

3. **Google API Credentials**:

   - You need to set up Google API credentials to access Google Sheets. Follow the instructions on the [Google Developers Console](https://console.developers.google.com/) to create a project and enable the Google Sheets API.
   - Download the `client_secret.json` file and place it in the same directory as the script.

4. **SonarQube Authentication Token**:

   - Obtain a SonarQube authentication token and set it as an environment variable named `SONARQUBE_AUTH_TOKEN` or pass it as a parameter when executing the script.

5. **Python Virtual Environment**:

   - It is recommended to use a virtual environment to manage dependencies. You can create a virtual environment using the following commands:
     ```bash
     python3 -m venv venv
     source venv/bin/activate  # On Windows use `venv\Scripts\activate`
     ```

6. **Required Python Packages**: Install the necessary Python packages using pip:
   ```bash
   pip install requests gspread google-auth google-auth-oauthlib
   ```
   OR
   ```bash
   pip install -r requirements.txt
   ```

## Dependencies

The script requires the following Python packages:

- `requests`: For making HTTP requests to the SonarQube API.
- `gspread`: For interacting with Google Sheets.
- `google-auth`: For handling Google authentication.
- `google-auth-oauthlib`: For OAuth 2.0 authentication with Google services.

## Configuration

The script uses a configuration list to specify the repositories and their corresponding SonarQube project keys. Update the `config` list in the script with your project details.

## Running the Script

To run the script, you can either set environment variables or pass parameters directly. Use the following command with optional arguments:
