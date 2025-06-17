import requests
import json
import urllib3
from getpass import getpass
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
import time

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ========== CONFIG ==========
PVWA_URL = "https://pvwa.cybermark.lab"
LOGIN_METHODS = ["CyberArk", "LDAP", "RADIUS", "SAML"]
COOKIE_NAME = "ApprendaSession"  # For SAML
# ============================

def saml_login():
    options = Options()
    # Uncomment below to run headless
    # options.add_argument("--headless")
    driver = webdriver.Chrome(options=options)
    print("Opening browser for SAML login...")
    driver.get(f"{PVWA_URL}/PasswordVault")

    input("Complete SAML login & MFA in the browser. Press ENTER once logged in...")

    session_cookie = None
    for cookie in driver.get_cookies():
        if cookie['name'] == COOKIE_NAME:
            session_cookie = cookie['value']
            break

    driver.quit()

    if not session_cookie:
        print(f"[!] Failed to find '{COOKIE_NAME}' cookie. Login may have failed.")
        return None

    print(f"[+] Session cookie acquired: {session_cookie}")
    return {"Cookie": f"{COOKIE_NAME}={session_cookie}"}


def rest_login(auth_type):
    username = input("Username: ")
    password = getpass("Password: ")
    url = f"{PVWA_URL}/PasswordVault/API/Auth/{auth_type}/Logon"

    headers = {"Content-Type": "application/json"}
    body = {
        "username": username,
        "password": password
    }

    response = requests.post(url, headers=headers, json=body, verify=False)
    if response.status_code == 200:
        token = response.text.strip('"')
        print("[+] Successfully logged in!")
        return {"Authorization": f"Bearer {token}"}
    else:
        print(f"[!] Login failed: {response.status_code}")
        print(response.text)
        return None


def choose_auth_method():
    print("Select authentication method:")
    for idx, method in enumerate(LOGIN_METHODS, 1):
        print(f"{idx}. {method}")
    while True:
        choice = input("Enter choice (1-4): ")
        if choice.isdigit() and 1 <= int(choice) <= len(LOGIN_METHODS):
            return LOGIN_METHODS[int(choice) - 1]
        else:
            print("Invalid selection.")


def test_api(headers):
    print("[*] Querying PVWA /api/Accounts...")
    response = requests.get(f"{PVWA_URL}/PasswordVault/api/Accounts", headers=headers, verify=False)
    if response.status_code == 200:
        print("[+] Authenticated API call succeeded.")
        print(json.dumps(response.json(), indent=2))
    else:
        print(f"[!] API call failed: {response.status_code}")
        print(response.text)


def main():
    auth_method = choose_auth_method()
    if auth_method == "SAML":
        headers = saml_login()
    else:
        headers = rest_login(auth_method)

    if headers:
        test_api(headers)
    else:
        print("[!] Authentication failed. Exiting.")

if __name__ == "__main__":
    main()
