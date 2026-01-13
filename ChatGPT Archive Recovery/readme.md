# OpenAI Archive Restore Suite (Userscript)

A comprehensive userscript to recover ChatGPT conversations that are marked as **Archived** in the backend but are **missing** from the official "Archived Chats" UI.

**Version:** 8.3  
**Status:** Working

## ⚠️ Important Disclaimer
* **Not for Deleted Chats:** This tool **cannot** recover conversations that have been permanently deleted. It only fixes visibility issues for chats that still exist in your account database but are hidden from the interface.
* **Use at Your Own Risk:** This script automates calls to OpenAI's internal API. Use responsibly to avoid rate limiting.

---

## Features

* **Token Interception:** Automatically captures your session token when you interact with the site (no manual pasting required).
* **Slash Commands:** Control the script directly from the ChatGPT text input box.
* **Bulk Restore:** Automatically fetches *all* archived conversations and un-archives them sequentially.
* **Targeted Restore:** Paste a list of IDs (from a Data Export or Excel file) to restore specific conversations.
* **Visual Feedback:** Status overlays and toast notifications to track progress.

---

## Installation

1.  **Install a Userscript Manager:**
    * Chrome/Edge: [Tampermonkey](https://chrome.google.com/webstore/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo)
    * Firefox: [Greasemonkey](https://addons.mozilla.org/en-US/firefox/addon/greasemonkey/)
2.  **Create New Script:**
    * Click the Tampermonkey extension icon → **Create a new script**.
3.  **Paste Code:**
    * Delete any default code and paste the **full v8.3 script**.
4.  **Save:**
    * Press `Ctrl+S` or click **File** → **Save**.

---

## Usage Guide

### 1. Initialize & Capture Token
The script needs your authorization token to work. It grabs this automatically when you use ChatGPT normally.

1.  Open [chatgpt.com](https://chatgpt.com).
2.  **Click on any existing chat** in your history or send a simple message (e.g., "Hi").
3.  Look for a green toast notification in the top right: **"Token Captured: Ready for commands."**
4.  *Optional:* Verify status by typing `/token` in the chat box.

### 2. The Commands
Type these commands directly into the main ChatGPT prompt area and press **Enter**.

| Command | Action |
| :--- | :--- |
| `/restore` | **Auto-Scan:** Fetches *all* archived chats from the backend and restores them one by one. |
| `/restore-list` | **Manual Mode:** Opens a modal to paste specific Conversation IDs. |
| `/token` | Checks if the script has successfully captured your auth token. |
| `/restore-help` | Shows a list of available commands. |

---

## Workflows

### Scenario A: "I want to try to restore everything hidden"
1.  Ensure token is captured (see step 1).
2.  Type `/restore` and press **Enter**.
3.  Confirm the prompt.
4.  The script will scan for archived items.
5.  If items are found, a progress overlay will appear. **Do not close the tab** until finished.

### Scenario B: "I have a list of IDs from my Data Export" (Safe Mode)
If you have downloaded your data from OpenAI (`conversations.json`) and identified specific IDs that are missing:

1.  Copy the IDs from your JSON or Excel file.
    * *Note: The script accepts JSON arrays, comma-separated lists, or raw text dumps.*
2.  In ChatGPT, type `/restore-list` and press **Enter**.
3.  Paste your data into the popup modal.
4.  Click **Process List**.
5.  The script will iterate through only those specific IDs.

---

## Troubleshooting

**The commands aren't working:**
* Make sure you are typing in the main prompt box.
* Refresh the page.
* Ensure the script is enabled in Tampermonkey.

**"No token captured yet":**
* The script cannot see your token until a network request is made. Click on a previous conversation in the sidebar to force a network request, then try again.

**Rate Limiting:**
* If you have thousands of chats, OpenAI may rate limit your requests. The script includes a slight delay to mitigate this. If errors occur, refresh and wait a few minutes before continuing.

---

## Privacy Note
This script runs entirely locally in your browser (`client-side`). It intercepts your specific browser session to make calls directly to OpenAI on your behalf. **No data, tokens, or conversation history is sent to any third-party server.**
